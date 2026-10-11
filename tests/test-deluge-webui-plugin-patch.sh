#!/bin/bash
# Regression test for the deluge WebUI plugin name lookup patch in build/root/install.sh.
#
# Arch's deluge package applies upstream commit dab761f3 (importlib plugin loader), which
# registers web plugins as 'WebPlugin.<lowercase snake case name>', but leaves
# deluge/ui/web/pluginmanager.py looking up 'WebPlugin.<original name>'. Every mixed case
# built-in plugin (Label, Scheduler, Blocklist, Extractor, AutoAdd, YaRSS2) then logs
# 'contains no WebUI code' and loses its web UI. install.sh normalises the three lookups.
#
# Usage: tests/test-deluge-webui-plugin-patch.sh [path/to/install.sh]

set -uo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
install_sh=${1:-"${repo_root}/build/root/install.sh"}

BEGIN_MARKER='# deluge plugin webui patch - begin'
END_MARKER='# deluge plugin webui patch - end'
RAW_LOOKUP="component.get('WebPlugin.' + name)"
NORMALISED_LOOKUP="component.get('WebPlugin.' + name.lower().replace('-', '_').replace(' ', '_'))"

work_dir=$(mktemp -d)
trap 'rm -rf "${work_dir}"' EXIT

failures=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; failures=$((failures + 1)); }

# Write a minimal replica of the three WebPlugin lookups in deluge/ui/web/pluginmanager.py
# (deluge 2.2.0 lines 63, 91 and 140).
write_fixture() { # $1 = target file, $2 = broken|upstream-fixed
	local target=$1 state=$2 expr
	case "${state}" in
	broken) expr='name' ;;
	upstream-fixed) expr='_plugin_rpc_name(name)' ;;
	*)
		echo "unknown fixture state '${state}'" >&2
		exit 2
		;;
	esac
	mkdir -p -- "$(dirname -- "${target}")"
	cat > "${target}" <<EOF
"""Minimal replica of the three WebPlugin lookups in the deluge web plugin manager."""


def disable_plugin(self, name):
    try:
        plugin = component.get('WebPlugin.' + ${expr})
    except KeyError:
        log.debug('%s plugin contains no WebUI code, ignoring WebUI disable call.', name)
        return


def enable_plugin(self, name):
    try:
        plugin = component.get('WebPlugin.' + ${expr})
    except KeyError:
        log.info('%s plugin contains no WebUI code, ignoring WebUI enable call.', name)
        return


def get_plugin_resources(self, name):
    try:
        plugin = component.get('WebPlugin.' + ${expr})
    except KeyError:
        log.info('Plugin has no web ui')
        return
EOF
}

# Resolve every web plugin lookup in a pluginmanager.py replica for the mixed case plugin
# name 'Label' and fail unless it matches the component key WebPluginBase registers.
write_behaviour_checker() { # $1 = target script
	cat > "$1" <<'EOF'
import re
import sys


def _plugin_rpc_name(plugin_name):
    return plugin_name.lower().replace('-', '_').replace(' ', '_')


path = sys.argv[1]
with open(path, encoding='utf-8') as handle:
    text = handle.read()

expressions = [e.strip() for e in re.findall(r"component\.get\('WebPlugin\.' \+ (.*)\)$", text, re.M)]
if len(expressions) != 3:
    print(f'expected 3 web plugin lookups, found {len(expressions)}')
    sys.exit(2)

# 'Label' is why this bug bites: WebPluginBase registers the normalised name.
registry = {'WebPlugin.label': object()}
resolved = [
    'WebPlugin.' + str(eval(expression, {'name': 'Label', '_plugin_rpc_name': _plugin_rpc_name}))
    for expression in expressions
]

print('resolved: ' + ', '.join(resolved))
missing = [key for key in resolved if key not in registry]
if missing:
    print('not registered: ' + ', '.join(missing))
    sys.exit(1)
sys.exit(0)
EOF
}

if [[ ! -f "${install_sh}" ]]; then
	echo "install.sh not found: ${install_sh}" >&2
	exit 2
fi

block="${work_dir}/patch-block.sh"
awk -v b="${BEGIN_MARKER}" -v e="${END_MARKER}" '$0 == b, $0 == e' "${install_sh}" > "${block}"

if [[ ! -s "${block}" ]]; then
	fail "install.sh has no deluge plugin webui patch block (expected '${BEGIN_MARKER}' ... '${END_MARKER}')"
else
	pass "install.sh declares the deluge plugin webui patch block"

	site_packages="${work_dir}/site-packages"
	target="${site_packages}/deluge/ui/web/pluginmanager.py"
	write_fixture "${target}" broken
	cp "${target}" "${work_dir}/broken.orig"

	if DELUGE_SITE_PACKAGES="${site_packages}" bash "${block}" > "${work_dir}/patch.out" 2>&1; then
		pass "patch block runs against a deluge site-packages tree"
	else
		fail "patch block exited non-zero: $(cat "${work_dir}/patch.out")"
	fi

	remaining_raw=$(grep -cF "${RAW_LOOKUP}" "${target}" || true)
	normalised=$(grep -cF "${NORMALISED_LOOKUP}" "${target}" || true)
	if [[ "${remaining_raw}" == "0" && "${normalised}" == "3" ]]; then
		pass "all three web plugin lookups are normalised (raw=${remaining_raw}, normalised=${normalised})"
	else
		fail "expected 0 raw and 3 normalised lookups, got raw=${remaining_raw}, normalised=${normalised}"
	fi

	changed=$(diff "${work_dir}/broken.orig" "${target}" | grep -c '^<' || true)
	if [[ "${changed}" == "3" ]]; then
		pass "exactly three lines changed"
	else
		fail "expected exactly 3 changed lines, got ${changed}"
	fi

	before=$(sha256sum "${target}")
	DELUGE_SITE_PACKAGES="${site_packages}" bash "${block}" > /dev/null 2>&1
	after=$(sha256sum "${target}")
	if [[ "${before}" == "${after}" ]]; then
		pass "patch is idempotent"
	else
		fail "second patch run changed the file"
	fi

	fixed_site_packages="${work_dir}/fixed-site-packages"
	fixed_target="${fixed_site_packages}/deluge/ui/web/pluginmanager.py"
	write_fixture "${fixed_target}" upstream-fixed
	cp "${fixed_target}" "${work_dir}/upstream-fixed.orig"
	DELUGE_SITE_PACKAGES="${fixed_site_packages}" bash "${block}" > /dev/null 2>&1
	if diff -q "${work_dir}/upstream-fixed.orig" "${fixed_target}" > /dev/null; then
		pass "an already-fixed upstream file is left untouched"
	else
		fail "an already-fixed upstream file was modified"
	fi

	checker="${work_dir}/check_lookup.py"
	write_behaviour_checker "${checker}"
	if python3 "${checker}" "${work_dir}/broken.orig" > /dev/null 2>&1; then
		fail "behaviour check passed on the unpatched file, so it does not detect the bug"
	else
		pass "behaviour check fails on the unpatched file (the assertion is meaningful)"
	fi
	if python3 "${checker}" "${target}" > "${work_dir}/behaviour.out" 2>&1; then
		pass "mixed case plugin 'Label' resolves to the registered web plugin key"
	else
		fail "behaviour check failed on the patched file: $(cat "${work_dir}/behaviour.out")"
	fi
fi

echo
if [[ "${failures}" -eq 0 ]]; then
	echo "All checks passed."
else
	echo "${failures} check(s) failed." >&2
fi
exit "${failures}"
