#!/bin/bash
# Regression test for the deluge WebUI plugin name lookup patch in build/root/install.sh.
#
# Arch's deluge package applies upstream commit dab761f3 (importlib plugin loader), which
# registers web plugins as 'WebPlugin.<lowercase snake case name>', but leaves
# deluge/ui/web/pluginmanager.py looking up 'WebPlugin.<original name>'. Mixed case plugin
# names then fail that lookup and the plugin logs 'contains no WebUI code' and loses its web
# UI - the built-ins (Label, Scheduler, Blocklist, Extractor, AutoAdd) plus third party
# plugins such as YaRSS2. install.sh normalises the three lookups to match.
#
# This file is mirrored on the libtorrentv1 branch - the workflow-test job diffs the two
# copies, so keep them in sync.
#
# Usage: tests/test-deluge-webui-plugin-patch.sh [path/to/install.sh]

set -uo pipefail

for required_tool in awk bash diff find grep id python3 sha256sum; do
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

# Write a replica deluge site-packages tree: three WebPlugin lookups in the web plugin
# manager (deluge 2.2.0 lines 63, 91 and 140) plus the plugin base that decides whether the
# installed loader normalises component names. $2 selects the lookup shape, $3 the loader.
write_fixture() { # $1 = site-packages root, $2 = broken|upstream-fixed|unrecognised|mixed, $3 = importlib|legacy
	local root=$1 state=$2 loader=${3:-importlib}
	local pluginmanager="${root}/deluge/ui/web/pluginmanager.py"
	local pluginbase="${root}/deluge/plugins/pluginbase.py"
	local lookups
	case "${state}" in
	broken)
		lookups=("'WebPlugin.' + name" "'WebPlugin.' + name" "'WebPlugin.' + name")
		;;
	upstream-fixed)
		lookups=(
			"'WebPlugin.' + _plugin_rpc_name(name)"
			"'WebPlugin.' + _plugin_rpc_name(name)"
			"'WebPlugin.' + _plugin_rpc_name(name)"
		)
		;;
	unrecognised)
		lookups=("'WebPlugin.%s' % name" "'WebPlugin.%s' % name" "'WebPlugin.%s' % name")
		;;
	mixed)
		lookups=(
			"'WebPlugin.' + name.lower().replace('-', '_').replace(' ', '_')"
			"'WebPlugin.%s' % name"
			"'WebPlugin.%s' % name"
		)
		;;
	*)
		echo "unknown fixture state '${state}'" >&2
		exit 2
		;;
	esac
	mkdir -p -- "$(dirname -- "${pluginmanager}")" "$(dirname -- "${pluginbase}")"
	cat > "${pluginmanager}" <<EOF
"""Minimal replica of the three WebPlugin lookups in the deluge web plugin manager."""


def disable_plugin(self, name):
    try:
        plugin = component.get(${lookups[0]})
    except KeyError:
        log.debug('%s plugin contains no WebUI code, ignoring WebUI disable call.', name)
        return


def enable_plugin(self, name):
    try:
        plugin = component.get(${lookups[1]})
    except KeyError:
        log.info('%s plugin contains no WebUI code, ignoring WebUI enable call.', name)
        return


def get_plugin_resources(self, name):
    try:
        plugin = component.get(${lookups[2]})
    except KeyError:
        log.info('Plugin has no web ui')
        return
EOF
	if [[ "${loader}" == "importlib" ]]; then
		# the normalising helper the importlib backport adds
		cat > "${pluginbase}" <<'EOF'
def _plugin_rpc_name(plugin_name):
    return plugin_name.lower().replace('-', '_').replace(' ', '_')
EOF
	else
		# the pre-backport loader: registration keeps the plugin's own case
		cat > "${pluginbase}" <<'EOF'
class WebPluginBase:
    def __init__(self, plugin_name):
        super().__init__('WebPlugin.' + plugin_name)
EOF
	fi
}

# Resolve every web plugin lookup in a pluginmanager.py replica and fail unless it matches
# the component key the normalising loader registers. The expected keys are literals fixed
# here, deliberately NOT derived from the formula the shipped patch uses - a wrong
# normalisation contract must fail here rather than agree with itself.
write_behaviour_checker() { # $1 = target script
	cat > "$1" <<'EOF'
import re
import sys


def _plugin_rpc_name(plugin_name):
    return plugin_name.lower().replace('-', '_').replace(' ', '_')


# 'Label' is why this bug bites; the other names exercise lower casing and both
# punctuation replacements.
SAMPLES = [
    ('Label', 'WebPlugin.label'),
    ('Auto Add', 'WebPlugin.auto_add'),
    ('Foo Bar-Baz', 'WebPlugin.foo_bar_baz'),
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

# double quoted variants are the same expression, so compare on normalised quoting
unexpected = [e for e in expressions if e.replace('"', "'") not in ALLOWED]
if unexpected:
    print(f'unexpected lookup expression(s): {unexpected!r}')
    sys.exit(2)

mismatches = []
for expression in expressions:
    for plugin_name, expected in SAMPLES:
        namespace = {'__builtins__': {}, 'name': plugin_name, '_plugin_rpc_name': _plugin_rpc_name}
        resolved = 'WebPlugin.' + str(eval(expression, namespace))
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
run_block() { # $1 = deluge site-packages root (may contain a glob), $2 = output file
	DELUGE_SITE_PACKAGES="$1" bash -e "${block}" > "$2" 2>&1
}

if [[ ! -s "${block}" ]]; then
	fail "install.sh has no deluge plugin webui patch block (expected '${BEGIN_MARKER}' ... '${END_MARKER}')"
else
	pass "install.sh declares the deluge plugin webui patch block"

	site_packages="${work_dir}/site-packages"
	target="${site_packages}/deluge/ui/web/pluginmanager.py"
	write_fixture "${site_packages}" broken
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
		fail "second patch run: exit=${repeat_rc}, file changed=$([[ "${before}" == "${after}" ]] && echo no || echo yes)"
	fi

	fixed_site_packages="${work_dir}/fixed-site-packages"
	fixed_target="${fixed_site_packages}/deluge/ui/web/pluginmanager.py"
	write_fixture "${fixed_site_packages}" upstream-fixed
	cp "${fixed_target}" "${work_dir}/upstream-fixed.orig"
	run_block "${fixed_site_packages}" "${work_dir}/fixed.out"
	fixed_rc=$?
	unchanged=no
	diff -q "${work_dir}/upstream-fixed.orig" "${fixed_target}" > /dev/null && unchanged=yes
	if [[ "${fixed_rc}" -eq 0 && "${unchanged}" == "yes" ]] \
		&& grep -q 'already normalised' "${work_dir}/fixed.out" \
		&& ! grep -q '\[warn\]' "${work_dir}/fixed.out"; then
		pass "an already-fixed upstream file is left untouched and reported as already normalised"
	else
		fail "already-fixed file: exit=${fixed_rc}, unchanged=${unchanged}, output=$(cat "${work_dir}/fixed.out")"
	fi

	empty_site_packages="${work_dir}/empty-site-packages"
	mkdir -p "${empty_site_packages}"
	run_block "${empty_site_packages}" "${work_dir}/empty.out"
	empty_rc=$?
	created=$(find "${empty_site_packages}" -mindepth 1 -print -quit)
	if [[ "${empty_rc}" -eq 0 && -z "${created}" ]] && grep -q 'patch not applied' "${work_dir}/empty.out"; then
		pass "absent deluge tree is a no-op that warns (exit 0, nothing created)"
	else
		fail "absent deluge tree: exit=${empty_rc}, created='${created}', output=$(cat "${work_dir}/empty.out")"
	fi

	unexpected_site_packages="${work_dir}/unexpected-site-packages"
	unexpected_target="${unexpected_site_packages}/deluge/ui/web/pluginmanager.py"
	write_fixture "${unexpected_site_packages}" unrecognised
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

	mixed_site_packages="${work_dir}/mixed-site-packages"
	mixed_target="${mixed_site_packages}/deluge/ui/web/pluginmanager.py"
	write_fixture "${mixed_site_packages}" mixed
	cp "${mixed_target}" "${work_dir}/mixed.orig"
	run_block "${mixed_site_packages}" "${work_dir}/mixed.out"
	mixed_rc=$?
	if [[ "${mixed_rc}" -eq 0 ]] \
		&& diff -q "${work_dir}/mixed.orig" "${mixed_target}" > /dev/null \
		&& grep -q 'only 1/3 normalised' "${work_dir}/mixed.out"; then
		pass "a partially normalised file warns and is left untouched"
	else
		fail "partially normalised file: exit=${mixed_rc}, output=$(cat "${work_dir}/mixed.out")"
	fi

	# without the importlib backport the loader keeps the plugin's own case, so rewriting the
	# lookup would invert a working state - the block must refuse to patch
	legacy_site_packages="${work_dir}/legacy-site-packages"
	legacy_target="${legacy_site_packages}/deluge/ui/web/pluginmanager.py"
	write_fixture "${legacy_site_packages}" broken legacy
	cp "${legacy_target}" "${work_dir}/legacy.orig"
	run_block "${legacy_site_packages}" "${work_dir}/legacy.out"
	legacy_rc=$?
	if [[ "${legacy_rc}" -eq 0 ]] \
		&& diff -q "${work_dir}/legacy.orig" "${legacy_target}" > /dev/null \
		&& grep -q 'does not normalise plugin component names' "${work_dir}/legacy.out"; then
		pass "a deluge without the importlib backport is left unchanged (no inverted patch)"
	else
		fail "legacy loader: exit=${legacy_rc}, output=$(cat "${work_dir}/legacy.out")"
	fi

	# the shipped default is a glob, so exercise the multi match path
	multi_root="${work_dir}/multi"
	write_fixture "${multi_root}/python3.13" broken
	write_fixture "${multi_root}/python3.14" broken
	run_block "${multi_root}/python3*" "${work_dir}/multi.out"
	multi_rc=$?
	multi_ok=0
	for multi_file in "${multi_root}"/python3.*/deluge/ui/web/pluginmanager.py; do
		multi_raw=$(grep -cF "${RAW_LOOKUP}" "${multi_file}" || true)
		multi_normalised=$(grep -cF "${NORMALISED_LOOKUP}" "${multi_file}" || true)
		[[ "${multi_raw}" == "0" && "${multi_normalised}" == "3" ]] && multi_ok=$((multi_ok + 1))
	done
	if [[ "${multi_rc}" -eq 0 && "${multi_ok}" -eq 2 ]]; then
		pass "a glob site-packages override patches every matched tree (2/2)"
	else
		fail "glob override: exit=${multi_rc}, patched=${multi_ok}/2, output=$(cat "${work_dir}/multi.out")"
	fi

	# a sed that cannot write must abort the build rather than report success
	readonly_site_packages="${work_dir}/readonly-site-packages"
	write_fixture "${readonly_site_packages}" broken
	readonly_dir="${readonly_site_packages}/deluge/ui/web"
	if [[ "$(id -u)" -eq 0 ]]; then
		echo "SKIP: cannot enforce a read-only directory when running as root" >&2
	else
		chmod 500 "${readonly_dir}"
		run_block "${readonly_site_packages}" "${work_dir}/readonly.out"
		readonly_rc=$?
		chmod 755 "${readonly_dir}"
		if [[ "${readonly_rc}" -ne 0 ]] && grep -q '\[crit\] Failed to patch' "${work_dir}/readonly.out"; then
			pass "an unwritable target aborts the build with a crit message"
		else
			fail "unwritable target: exit=${readonly_rc}, output=$(cat "${work_dir}/readonly.out")"
		fi
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
