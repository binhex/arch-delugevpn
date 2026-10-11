#!/bin/bash
# Regression test for the deluge WebUI plugin name lookup patch in build/root/install.sh.
#
# Arch's deluge package applies upstream commit dab761f3 (importlib plugin loader), which
# registers web plugins as 'WebPlugin.<lowercase snake case name>', but leaves
# deluge/ui/web/pluginmanager.py looking up 'WebPlugin.<original name>'. Every mixed case
# built-in plugin (Label, Scheduler, Blocklist, Extractor, AutoAdd, YaRSS2) then logs
# 'contains no WebUI code' and loses its web UI. install.sh normalises the three lookups.
#
# This file is mirrored on the libtorrentv1 branch - the workflow-test job diffs the two
# copies, so keep them in sync.
#
# Usage: tests/test-deluge-webui-plugin-patch.sh [path/to/install.sh]

set -uo pipefail

for required_tool in awk bash diff find grep python3 sha256sum; do
	if ! command -v "${required_tool}" > /dev/null 2>&1; then
		echo "required tool not available: ${required_tool}" >&2
		exit 2
	fi
done

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
# (deluge 2.2.0 lines 63, 91 and 140). $2 selects the lookup shape under test.
write_fixture() { # $1 = target file, $2 = broken|upstream-fixed|unrecognised
	local target=$1 state=$2 lookup
	case "${state}" in
	broken) lookup="'WebPlugin.' + name" ;;
	upstream-fixed) lookup="'WebPlugin.' + _plugin_rpc_name(name)" ;;
	unrecognised) lookup="'WebPlugin.%s' % name" ;;
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
        plugin = component.get(${lookup})
    except KeyError:
        log.debug('%s plugin contains no WebUI code, ignoring WebUI disable call.', name)
        return


def enable_plugin(self, name):
    try:
        plugin = component.get(${lookup})
    except KeyError:
        log.info('%s plugin contains no WebUI code, ignoring WebUI enable call.', name)
        return


def get_plugin_resources(self, name):
    try:
        plugin = component.get(${lookup})
    except KeyError:
        log.info('Plugin has no web ui')
        return
EOF
}

# Resolve every web plugin lookup in a pluginmanager.py replica and fail unless it matches
# the component key WebPluginBase registers. The expected keys below are hard coded literals,
# deliberately NOT derived from the formula the shipped patch uses - a wrong normalisation
# contract must fail here rather than agree with itself.
write_behaviour_checker() { # $1 = target script
	cat > "$1" <<'EOF'
import re
import sys


def _plugin_rpc_name(plugin_name):
    return plugin_name.lower().replace('-', '_').replace(' ', '_')


# 'Label' is why this bug bites; the punctuation cases pin the replace() chain.
SAMPLES = [
    ('Label', 'WebPlugin.label'),
    ('Auto Add', 'WebPlugin.auto_add'),
    ('YaRSS2', 'WebPlugin.yarss2'),
    ('Blocklist', 'WebPlugin.blocklist'),
]

# Only these lookup expressions may be evaluated - no arbitrary code from the target file.
ALLOWED = [
    'name',
    "name.lower().replace('-', '_').replace(' ', '_')",
    '_plugin_rpc_name(name)',
]

path = sys.argv[1]
with open(path, encoding='utf-8') as handle:
    text = handle.read()

expressions = [e.strip() for e in re.findall(r"component\.get\('WebPlugin\.' \+ (.*)\)$", text, re.M)]
if len(expressions) != 3:
    print(f'expected 3 web plugin lookups, found {len(expressions)}')
    sys.exit(2)

unexpected = [expression for expression in expressions if expression not in ALLOWED]
if unexpected:
    print(f'unexpected lookup expression(s): {unexpected!r}')
    sys.exit(2)

mismatches = []
for expression in expressions:
    for plugin_name, expected in SAMPLES:
        resolved = 'WebPlugin.' + str(
            eval(expression, {'name': plugin_name, '_plugin_rpc_name': _plugin_rpc_name})
        )
        if resolved != expected:
            mismatches.append(f'{plugin_name}: expected {expected}, resolved {resolved}')

print(f'checked {len(expressions)} lookups x {len(SAMPLES)} plugin names')
if mismatches:
    print('mismatches:')
    for mismatch in mismatches:
        print('  ' + mismatch)
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

# install.sh runs under 'set -e', so run the extracted block the same way and always keep
# its exit status - a block that starts failing must not silently PASS here.
run_block() { # $1 = deluge site-packages root, $2 = output file
	DELUGE_SITE_PACKAGES="$1" bash -e "${block}" > "$2" 2>&1
}

if [[ ! -s "${block}" ]]; then
	fail "install.sh has no deluge plugin webui patch block (expected '${BEGIN_MARKER}' ... '${END_MARKER}')"
else
	pass "install.sh declares the deluge plugin webui patch block"

	site_packages="${work_dir}/site-packages"
	target="${site_packages}/deluge/ui/web/pluginmanager.py"
	write_fixture "${target}" broken
	cp "${target}" "${work_dir}/broken.orig"

	run_block "${site_packages}" "${work_dir}/patch.out"
	patch_rc=$?
	if [[ "${patch_rc}" -eq 0 ]]; then
		pass "patch block runs against a deluge site-packages tree"
	else
		fail "patch block exited ${patch_rc}: $(cat "${work_dir}/patch.out")"
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

	# counts alone would stay green if sed mangled the line, so parse the patched file
	if python3 -c 'import ast, sys; ast.parse(open(sys.argv[1], encoding="utf-8").read())' "${target}" 2> "${work_dir}/ast.out"; then
		pass "patched file still parses as python"
	else
		fail "patched file failed to parse: $(cat "${work_dir}/ast.out")"
	fi

	before=$(sha256sum "${target}")
	run_block "${site_packages}" "${work_dir}/repeat.out"
	repeat_rc=$?
	after=$(sha256sum "${target}")
	if [[ "${repeat_rc}" -eq 0 && "${before}" == "${after}" ]]; then
		pass "patch is idempotent (second run exits 0 and changes nothing)"
	else
		fail "second patch run: exit=${repeat_rc}, changed=$([[ "${before}" == "${after}" ]] && echo no || echo yes)"
	fi

	fixed_site_packages="${work_dir}/fixed-site-packages"
	fixed_target="${fixed_site_packages}/deluge/ui/web/pluginmanager.py"
	write_fixture "${fixed_target}" upstream-fixed
	cp "${fixed_target}" "${work_dir}/upstream-fixed.orig"
	run_block "${fixed_site_packages}" "${work_dir}/fixed.out"
	fixed_rc=$?
	if [[ "${fixed_rc}" -eq 0 ]] && diff -q "${work_dir}/upstream-fixed.orig" "${fixed_target}" > /dev/null; then
		pass "an already-fixed upstream file is left untouched"
	else
		fail "already-fixed file: exit=${fixed_rc}, modified=$([[ ! -s "${work_dir}/fixed.out" ]] && echo no || echo check)"
	fi

	empty_site_packages="${work_dir}/empty-site-packages"
	mkdir -p "${empty_site_packages}"
	run_block "${empty_site_packages}" "${work_dir}/empty.out"
	empty_rc=$?
	created=$(find "${empty_site_packages}" -mindepth 1 -print -quit)
	if [[ "${empty_rc}" -eq 0 && -z "${created}" ]]; then
		pass "absent deluge tree is a safe no-op (exit 0, nothing created)"
	else
		fail "absent deluge tree: exit=${empty_rc}, created='${created}', output=$(cat "${work_dir}/empty.out")"
	fi

	# an unrecognised layout must be reported, not silently treated as already patched
	unexpected_site_packages="${work_dir}/unexpected-site-packages"
	unexpected_target="${unexpected_site_packages}/deluge/ui/web/pluginmanager.py"
	write_fixture "${unexpected_target}" unrecognised
	cp "${unexpected_target}" "${work_dir}/unexpected.orig"
	run_block "${unexpected_site_packages}" "${work_dir}/unexpected.out"
	unexpected_rc=$?
	if [[ "${unexpected_rc}" -eq 0 ]] \
		&& diff -q "${work_dir}/unexpected.orig" "${unexpected_target}" > /dev/null \
		&& grep -q 'patch not applied' "${work_dir}/unexpected.out"; then
		pass "unrecognised lookup layout warns and is left untouched"
	else
		fail "unrecognised layout: exit=${unexpected_rc}, output=$(cat "${work_dir}/unexpected.out")"
	fi

	checker="${work_dir}/check_lookup.py"
	write_behaviour_checker "${checker}"
	if python3 "${checker}" "${work_dir}/broken.orig" > /dev/null 2>&1; then
		fail "behaviour check passed on the unpatched file, so it does not detect the bug"
	else
		pass "behaviour check fails on the unpatched file (the assertion is meaningful)"
	fi
	if python3 "${checker}" "${target}" > "${work_dir}/behaviour.out" 2>&1; then
		pass "mixed case plugin names resolve to the registered web plugin keys"
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
