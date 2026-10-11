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
# fixed umask so a demoted user can always read the extracted block and the fixtures
umask 022
# set to 0 by the recursive negative controls below so they cannot re-enter themselves
suite_controls=${DELUGE_PATCH_SUITE_CONTROLS:-1}

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
# world traversable so the read-only case below can still drop privileges and read the block
chmod 755 "${work_dir}"
trap 'rm -rf "${work_dir}"' EXIT

failures=0
skipped=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; failures=$((failures + 1)); }
skip() { echo "SKIP: $1" >&2; skipped=$((skipped + 1)); }

# Write a replica deluge site-packages tree: three WebPlugin lookups in the web plugin
# manager (deluge 2.2.0 lines 63, 91 and 140) plus the plugin base that decides whether the
# installed loader normalises component names. $2 selects the lookup shape, $3 the loader.
write_fixture() { # $1 = site-packages root, $2 = lookup shape, $3 = loader
	# lookup shapes: broken, upstream-fixed, unrecognised, mixed, partially-raw, double-quoted,
	#                mixed-quoting, no-lookup
	# loaders: importlib, legacy, helper-but-legacy, unrecognised-registration,
	#          normalised-without-helper
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
	partially-raw)
		lookups=("'WebPlugin.' + name" "'WebPlugin.' + name" "'WebPlugin.%s' % name")
		;;
	double-quoted)
		lookups=('"WebPlugin." + name' '"WebPlugin." + name' '"WebPlugin." + name')
		;;
	mixed-quoting)
		lookups=("'WebPlugin.' + name" "'WebPlugin.' + name" '"WebPlugin." + name')
		;;
	no-lookup)
		lookups=("component['WebPlugin.'] + name" "component['WebPlugin.'] + name" "component['WebPlugin.'] + name")
		;;
	double-quoted-normalised)
		lookups=(
			'"WebPlugin." + name.lower().replace("-", "_").replace(" ", "_")'
			'"WebPlugin." + name.lower().replace("-", "_").replace(" ", "_")'
			'"WebPlugin." + name.lower().replace("-", "_").replace(" ", "_")'
		)
		;;
	mixed-normalised)
		lookups=(
			"'WebPlugin.' + name"
			'"WebPlugin." + name.lower().replace("-", "_").replace(" ", "_")'
			'"WebPlugin." + name.lower().replace("-", "_").replace(" ", "_")'
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
	case "${loader}" in
	importlib)
		# the importlib backport: helper defined and a normalised registration
		cat > "${pluginbase}" <<'EOF'
def _plugin_rpc_name(plugin_name):
    return plugin_name.lower().replace('-', '_').replace(' ', '_')


class WebPluginBase:
    def __init__(self, plugin_name):
        name = _plugin_rpc_name(plugin_name)
        super().__init__('WebPlugin.' + name)
EOF
		;;
	legacy)
		# the pre-backport loader: no helper, registration keeps the plugin's own case
		cat > "${pluginbase}" <<'EOF'
class WebPluginBase:
    def __init__(self, plugin_name):
        super().__init__('WebPlugin.' + plugin_name)
EOF
		;;
	helper-but-legacy)
		# the helper exists but the web plugin base still registers the raw name
		cat > "${pluginbase}" <<'EOF'
def _plugin_rpc_name(plugin_name):
    return plugin_name.lower().replace('-', '_').replace(' ', '_')


class WebPluginBase:
    def __init__(self, plugin_name):
        super().__init__('WebPlugin.' + plugin_name)
EOF
		;;
	unrecognised-registration)
		# no WebPlugin registration line at all
		cat > "${pluginbase}" <<'EOF'
class WebPluginBase:
    def __init__(self, plugin_name):
        super().__init__(plugin_name)
EOF
		;;
	normalised-without-helper)
		# a normalised registration but none of the helper the block probes for
		cat > "${pluginbase}" <<'EOF'
class WebPluginBase:
    def __init__(self, plugin_name):
        name = plugin_name.lower().replace('-', '_').replace(' ', '_')
        super().__init__('WebPlugin.' + name)
EOF
		;;
	helper-unused)
		# the helper exists but the registration normalises on its own, so naming the helper
		# must not be accepted as proof that the loader uses it
		cat > "${pluginbase}" <<'EOF'
def _plugin_rpc_name(plugin_name):
    return plugin_name.lower().replace('-', '_').replace(' ', '_')


class WebPluginBase:
    def __init__(self, plugin_name):
        name = plugin_name.lower()
        super().__init__('WebPlugin.' + name)
EOF
		;;
	*)
		echo "unknown fixture loader '${loader}'" >&2
		exit 2
		;;
	esac
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

expressions = [e.strip() for e in re.findall(r"component\.get\(['\"]WebPlugin\.['\"]\s*\+\s*(.*)\)$", text, re.M)]
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
        # __builtins__ is stripped: an allowed expression must not need a builtin
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
# fail closed: awk's range operator prints to EOF when the end marker is missing, which
# would feed real install steps (chmod, sed, cleanup) into run_block
awk -v b="${BEGIN_MARKER}" -v e="${END_MARKER}" \
	'$0 == b { started = 1 } started { print } started && $0 == e { closed = 1; exit } END { exit !(started && closed) }' \
	"${install_sh}" > "${block}" || block_rc=$?
block_rc=${block_rc:-0}

# install.sh runs under 'set -e', so run the extracted block the same way and always keep
# its exit status - a block that starts failing must not silently PASS here.
run_block() { # $1 = deluge site-packages root (may contain a glob), $2 = output file
	DELUGE_SITE_PACKAGES="$1" bash -e "${block}" > "$2" 2>&1
}

if [[ "${block_rc}" -ne 0 || ! -s "${block}" ]]; then
	fail "install.sh has no complete deluge plugin webui patch block (expected '${BEGIN_MARKER}' ... '${END_MARKER}')"
else
	pass "install.sh declares the deluge plugin webui patch block"

	begin_markers=$(grep -cF "${BEGIN_MARKER}" "${install_sh}" || true)
	end_markers=$(grep -cF "${END_MARKER}" "${install_sh}" || true)
	if [[ "${begin_markers}" == "1" && "${end_markers}" == "1" ]]; then
		pass "install.sh declares exactly one begin and one end marker"
	else
		fail "expected one of each marker in install.sh, got begin=${begin_markers}, end=${end_markers}"
	fi

	site_packages="${work_dir}/site-packages"
	target="${site_packages}/deluge/ui/web/pluginmanager.py"
	write_fixture "${site_packages}" broken
	cp "${target}" "${work_dir}/broken.orig"

	run_block "${site_packages}" "${work_dir}/patch.out"
	patch_rc=$?
	if [[ "${patch_rc}" -eq 0 ]] && grep -q '\[info\] Patched deluge WebUI plugin name lookup' "${work_dir}/patch.out"; then
		pass "patch block runs against a deluge site-packages tree and reports the patch"
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
		&& grep -q 'only 0/3 normalised' "${work_dir}/unexpected.out"; then
		pass "unrecognised lookup layout warns stating the count and is left untouched"
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
		&& grep -q 'registration uses the raw plugin name' "${work_dir}/legacy.out"; then
		pass "a deluge without the importlib backport is left unchanged (no inverted patch)"
	else
		fail "legacy loader: exit=${legacy_rc}, output=$(cat "${work_dir}/legacy.out")"
	fi

	# a raw lookup alongside an unrecognised one: sed runs, so the remaining shortfall is fatal
	raw_mixed_site_packages="${work_dir}/partially-raw-site-packages"
	raw_mixed_target="${raw_mixed_site_packages}/deluge/ui/web/pluginmanager.py"
	write_fixture "${raw_mixed_site_packages}" partially-raw
	run_block "${raw_mixed_site_packages}" "${work_dir}/partially-raw.out"
	raw_mixed_rc=$?
	raw_mixed_normalised=$(grep -cF "${NORMALISED_LOOKUP}" "${raw_mixed_target}" || true)
	if [[ "${raw_mixed_rc}" -ne 0 && "${raw_mixed_normalised}" == "2" ]] \
		&& grep -q 'only 2/3 normalised' "${work_dir}/partially-raw.out"; then
		pass "a partial substitution aborts the build instead of reporting success"
	else
		fail "partial substitution: exit=${raw_mixed_rc}, normalised=${raw_mixed_normalised}, output=$(cat "${work_dir}/partially-raw.out")"
	fi

	# a sed that exits 0 without writing must be caught by the post-sed raw check
	shim_dir="${work_dir}/shim-bin"
	mkdir -p "${shim_dir}"
	printf '#!/bin/bash\nexit 0\n' > "${shim_dir}/sed"
	chmod +x "${shim_dir}/sed"
	shim_site_packages="${work_dir}/shim-site-packages"
	write_fixture "${shim_site_packages}" broken
	PATH="${shim_dir}:${PATH}" DELUGE_SITE_PACKAGES="${shim_site_packages}" \
		bash -e "${block}" > "${work_dir}/shim.out" 2>&1
	shim_rc=$?
	if [[ "${shim_rc}" -ne 0 ]] && grep -q 'raw lookup still present' "${work_dir}/shim.out"; then
		pass "a sed that exits 0 without substituting is caught and aborts the build"
	else
		fail "no-op sed shim: exit=${shim_rc}, output=$(cat "${work_dir}/shim.out")"
	fi

	# deterministic coverage of the sed failure branch, independent of host DAC
	fail_shim_dir="${work_dir}/fail-shim-bin"
	mkdir -p "${fail_shim_dir}"
	printf '#!/bin/bash\nexit 4\n' > "${fail_shim_dir}/sed"
	chmod +x "${fail_shim_dir}/sed"
	fail_shim_site_packages="${work_dir}/fail-shim-site-packages"
	write_fixture "${fail_shim_site_packages}" broken
	PATH="${fail_shim_dir}:${PATH}" DELUGE_SITE_PACKAGES="${fail_shim_site_packages}" \
		bash -e "${block}" > "${work_dir}/fail-shim.out" 2>&1
	fail_shim_rc=$?
	if [[ "${fail_shim_rc}" -ne 0 ]] && grep -q '\[crit\] Failed to patch' "${work_dir}/fail-shim.out"; then
		pass "a failing sed aborts the build with a crit message (deterministic)"
	else
		fail "failing sed shim: exit=${fail_shim_rc}, output=$(cat "${work_dir}/fail-shim.out")"
	fi

	# a lookup shape the block cannot recognise at all is reported, not silently accepted
	double_site_packages="${work_dir}/double-quoted-site-packages"
	double_target="${double_site_packages}/deluge/ui/web/pluginmanager.py"
	write_fixture "${double_site_packages}" double-quoted
	cp "${double_target}" "${work_dir}/double-quoted.orig"
	run_block "${double_site_packages}" "${work_dir}/double-quoted-site.out"
	double_rc=$?
	if [[ "${double_rc}" -eq 0 ]] \
		&& diff -q "${work_dir}/double-quoted.orig" "${double_target}" > /dev/null \
		&& grep -q 'only 0/3 normalised' "${work_dir}/double-quoted-site.out"; then
		pass "a double quoted lookup is counted and reported as unmatched, left untouched"
	else
		fail "unmatched lookup shape: exit=${double_rc}, output=$(cat "${work_dir}/double-quoted-site.out")"
	fi

	# a file with no readable WebPlugin lookup at all is reported, not silently accepted
	nolookup_site_packages="${work_dir}/no-lookup-site-packages"
	nolookup_target="${nolookup_site_packages}/deluge/ui/web/pluginmanager.py"
	write_fixture "${nolookup_site_packages}" no-lookup
	cp "${nolookup_target}" "${work_dir}/no-lookup.orig"
	run_block "${nolookup_site_packages}" "${work_dir}/no-lookup.out"
	nolookup_rc=$?
	if [[ "${nolookup_rc}" -eq 0 ]] \
		&& diff -q "${work_dir}/no-lookup.orig" "${nolookup_target}" > /dev/null \
		&& grep -q 'no lookup matching' "${work_dir}/no-lookup.out"; then
		pass "a file with no recognised WebPlugin lookup is reported and left untouched"
	else
		fail "no lookup: exit=${nolookup_rc}, output=$(cat "${work_dir}/no-lookup.out")"
	fi

	# mixed quoting must never be reported as fully patched while a raw lookup remains
	mixedq_site_packages="${work_dir}/mixed-quoting-site-packages"
	mixedq_target="${mixedq_site_packages}/deluge/ui/web/pluginmanager.py"
	write_fixture "${mixedq_site_packages}" mixed-quoting
	run_block "${mixedq_site_packages}" "${work_dir}/mixed-quoting.out"
	mixedq_rc=$?
	mixedq_normalised=$(grep -cF "${NORMALISED_LOOKUP}" "${mixedq_target}" || true)
	if [[ "${mixedq_rc}" -ne 0 && "${mixedq_normalised}" == "2" ]] \
		&& grep -q 'only 2/3 normalised' "${work_dir}/mixed-quoting.out"; then
		pass "mixed quoting aborts the build instead of reporting a partial patch as done"
	else
		fail "mixed quoting: exit=${mixedq_rc}, normalised=${mixedq_normalised}, output=$(cat "${work_dir}/mixed-quoting.out")"
	fi

	# a fully double quoted normalised file is already correct and must not be alarmed about
	dqnorm_site_packages="${work_dir}/double-quoted-normalised-site-packages"
	dqnorm_target="${dqnorm_site_packages}/deluge/ui/web/pluginmanager.py"
	write_fixture "${dqnorm_site_packages}" double-quoted-normalised
	cp "${dqnorm_target}" "${work_dir}/dqnorm.orig"
	run_block "${dqnorm_site_packages}" "${work_dir}/dqnorm.out"
	dqnorm_rc=$?
	if [[ "${dqnorm_rc}" -eq 0 ]] \
		&& diff -q "${work_dir}/dqnorm.orig" "${dqnorm_target}" > /dev/null \
		&& grep -q 'already normalised' "${work_dir}/dqnorm.out"; then
		pass "a double quoted normalised file is recognised as already normalised"
	else
		fail "double quoted normalised: exit=${dqnorm_rc}, output=$(cat "${work_dir}/dqnorm.out")"
	fi

	# a raw lookup beside double quoted normalised ones is patched, not aborted
	mixednorm_site_packages="${work_dir}/mixed-normalised-site-packages"
	mixednorm_target="${mixednorm_site_packages}/deluge/ui/web/pluginmanager.py"
	write_fixture "${mixednorm_site_packages}" mixed-normalised
	run_block "${mixednorm_site_packages}" "${work_dir}/mixednorm.out"
	mixednorm_rc=$?
	mixednorm_raw=$(grep -cF "${RAW_LOOKUP}" "${mixednorm_target}" || true)
	mixednorm_ok=$(grep -cF "${NORMALISED_LOOKUP}" "${mixednorm_target}" || true)
	if [[ "${mixednorm_rc}" -eq 0 && "${mixednorm_raw}" == "0" && "${mixednorm_ok}" == "1" ]] \
		&& grep -q '\[info\] Patched' "${work_dir}/mixednorm.out"; then
		pass "a raw lookup beside normalised double quoted ones is patched without aborting"
	else
		fail "mixed normalised: exit=${mixednorm_rc}, raw=${mixednorm_raw}, ok=${mixednorm_ok}, output=$(cat "${work_dir}/mixednorm.out")"
	fi

	# a helper definition alone is not enough - the registration must not use the raw name
	helper_site_packages="${work_dir}/helper-but-legacy-site-packages"
	helper_target="${helper_site_packages}/deluge/ui/web/pluginmanager.py"
	write_fixture "${helper_site_packages}" broken helper-but-legacy
	cp "${helper_target}" "${work_dir}/helper-but-legacy.orig"
	run_block "${helper_site_packages}" "${work_dir}/helper.out"
	helper_rc=$?
	if [[ "${helper_rc}" -eq 0 ]] \
		&& diff -q "${work_dir}/helper-but-legacy.orig" "${helper_target}" > /dev/null \
		&& grep -q 'registration uses the raw plugin name' "${work_dir}/helper.out"; then
		pass "a loader that defines the helper but still registers the raw name is left unchanged"
	else
		fail "helper-but-legacy loader: exit=${helper_rc}, output=$(cat "${work_dir}/helper.out")"
	fi

	# an unrecognised registration shape must be reported as unrecognised, not as legacy
	unreg_site_packages="${work_dir}/unrecognised-registration-site-packages"
	unreg_target="${unreg_site_packages}/deluge/ui/web/pluginmanager.py"
	write_fixture "${unreg_site_packages}" broken unrecognised-registration
	cp "${unreg_target}" "${work_dir}/unreg.orig"
	run_block "${unreg_site_packages}" "${work_dir}/unreg.out"
	unreg_rc=$?
	if [[ "${unreg_rc}" -eq 0 ]] \
		&& diff -q "${work_dir}/unreg.orig" "${unreg_target}" > /dev/null \
		&& grep -q 'plugin registration shape not recognised' "${work_dir}/unreg.out"; then
		pass "an unrecognised registration shape is reported as unrecognised and left unchanged"
	else
		fail "unrecognised registration: exit=${unreg_rc}, output=$(cat "${work_dir}/unreg.out")"
	fi

	# a normalised registration missing the probe's helper is reported as such
	nohelper_site_packages="${work_dir}/no-helper-site-packages"
	nohelper_target="${nohelper_site_packages}/deluge/ui/web/pluginmanager.py"
	write_fixture "${nohelper_site_packages}" broken normalised-without-helper
	cp "${nohelper_target}" "${work_dir}/nohelper.orig"
	run_block "${nohelper_site_packages}" "${work_dir}/nohelper.out"
	nohelper_rc=$?
	if [[ "${nohelper_rc}" -eq 0 ]] \
		&& diff -q "${work_dir}/nohelper.orig" "${nohelper_target}" > /dev/null \
		&& grep -q 'the _plugin_rpc_name helper is absent' "${work_dir}/nohelper.out"; then
		pass "a normalised registration without the helper is reported and left unchanged"
	else
		fail "normalised without helper: exit=${nohelper_rc}, output=$(cat "${work_dir}/nohelper.out")"
	fi

	# naming the helper without using it for the registration must not be accepted as proof
	unused_site_packages="${work_dir}/helper-unused-site-packages"
	unused_target="${unused_site_packages}/deluge/ui/web/pluginmanager.py"
	write_fixture "${unused_site_packages}" broken helper-unused
	cp "${unused_target}" "${work_dir}/unused.orig"
	run_block "${unused_site_packages}" "${work_dir}/unused.out"
	unused_rc=$?
	if [[ "${unused_rc}" -eq 0 ]] \
		&& diff -q "${work_dir}/unused.orig" "${unused_target}" > /dev/null \
		&& grep -q 'defined but not used for the registration' "${work_dir}/unused.out"; then
		pass "a helper that is defined but unused is reported and left unchanged"
	else
		fail "helper unused: exit=${unused_rc}, output=$(cat "${work_dir}/unused.out")"
	fi

	# a missing plugin base must be reported as such, not as a loader property
	no_base_site_packages="${work_dir}/no-pluginbase-site-packages"
	no_base_target="${no_base_site_packages}/deluge/ui/web/pluginmanager.py"
	write_fixture "${no_base_site_packages}" broken
	rm -f "${no_base_site_packages}/deluge/plugins/pluginbase.py"
	cp "${no_base_target}" "${work_dir}/no-pluginbase.orig"
	run_block "${no_base_site_packages}" "${work_dir}/no-pluginbase.out"
	no_base_rc=$?
	if [[ "${no_base_rc}" -eq 0 ]] \
		&& diff -q "${work_dir}/no-pluginbase.orig" "${no_base_target}" > /dev/null \
		&& grep -q 'not found, leaving' "${work_dir}/no-pluginbase.out"; then
		pass "a missing plugin base is reported and left unchanged"
	else
		fail "missing plugin base: exit=${no_base_rc}, output=$(cat "${work_dir}/no-pluginbase.out")"
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

	# paths with spaces must survive the compgen plus mapfile handling
	space_site_packages="${work_dir}/space dir/site-packages"
	space_target="${space_site_packages}/deluge/ui/web/pluginmanager.py"
	write_fixture "${space_site_packages}" broken
	run_block "${space_site_packages}" "${work_dir}/space.out"
	space_rc=$?
	space_raw=$(grep -cF "${RAW_LOOKUP}" "${space_target}" || true)
	space_normalised=$(grep -cF "${NORMALISED_LOOKUP}" "${space_target}" || true)
	if [[ "${space_rc}" -eq 0 && "${space_raw}" == "0" && "${space_normalised}" == "3" ]]; then
		pass "a site-packages path containing a space is patched"
	else
		fail "space in path: exit=${space_rc}, raw=${space_raw}, normalised=${space_normalised}, output=$(cat "${work_dir}/space.out")"
	fi

	# a sed that cannot write must abort the build rather than report success. a world
	# readable but not writable directory blocks the temp file sed -i needs, and root has
	# to drop to an unprivileged user for DAC to apply at all
	readonly_site_packages="${work_dir}/readonly-site-packages"
	write_fixture "${readonly_site_packages}" broken
	readonly_dir="${readonly_site_packages}/deluge/ui/web"
	readonly_rc=skip
	chmod 555 "${readonly_dir}"
	if [[ "$(id -u)" -eq 0 ]]; then
		if command -v runuser > /dev/null 2>&1 \
			&& id -u nobody > /dev/null 2>&1 \
			&& runuser -u nobody -- test -r "${block}" 2> /dev/null \
			&& ! runuser -u nobody -- touch "${readonly_dir}/.probe" 2> /dev/null; then
			runuser -u nobody -- env DELUGE_SITE_PACKAGES="${readonly_site_packages}" \
				bash -e "${block}" > "${work_dir}/readonly.out" 2>&1
			readonly_rc=$?
		else
			skip "cannot deny write access to the target directory as root on this host"
		fi
	elif touch "${readonly_dir}/.probe" 2> /dev/null; then
		skip "this environment can write into a 555 directory, write denial is untestable here"
	else
		run_block "${readonly_site_packages}" "${work_dir}/readonly.out"
		readonly_rc=$?
	fi
	rm -f "${readonly_dir}/.probe"
	chmod 755 "${readonly_dir}"
	if [[ "${readonly_rc}" != "skip" ]]; then
		if [[ "${readonly_rc}" -ne 0 ]] && grep -q '\[crit\] Failed to patch' "${work_dir}/readonly.out"; then
			pass "an unwritable target aborts the build with a crit message"
		else
			fail "unwritable target: exit=${readonly_rc}, output=$(cat "${work_dir}/readonly.out")"
		fi
	fi

	checker="${work_dir}/check_lookup.py"
	write_behaviour_checker "${checker}"

	# the extraction guard must fail closed, otherwise a revert to the permissive awk range
	# operator would keep the whole suite green. the child gets a sentinel so it cannot
	# re-enter this loop, and it must fail for the extraction reason, not some other one
	if [[ "${suite_controls}" == "1" ]]; then
		for doctored in missing-end reversed; do
			doctored_install="${work_dir}/${doctored}-install.sh"
			if [[ "${doctored}" == "missing-end" ]]; then
				grep -vF "${END_MARKER}" "${install_sh}" > "${doctored_install}"
			else
				awk -v b="${BEGIN_MARKER}" -v e="${END_MARKER}" \
					'$0 == b { print e; print b; next } $0 == e { next } { print }' \
					"${install_sh}" > "${doctored_install}"
			fi
			DELUGE_PATCH_SUITE_CONTROLS=0 bash "${BASH_SOURCE[0]}" "${doctored_install}" \
				> "${work_dir}/${doctored}.out" 2>&1
			child_rc=$?
			if [[ "${child_rc}" -eq 0 ]]; then
				fail "suite passed with a ${doctored} marker layout in install.sh"
			elif grep -q 'has no complete deluge plugin webui patch block' "${work_dir}/${doctored}.out"; then
				pass "suite fails closed on a ${doctored} marker layout with the extraction failure"
			else
				fail "negative control child failed for an unrelated reason (${doctored}): $(head -3 "${work_dir}/${doctored}.out")"
			fi
		done
	fi

	# the checker must accept a double quoted equivalent of the normalised lookup
	double_quoted="${work_dir}/double-quoted.py"
	for double_suffix in disable enable resources; do
		{
			printf 'def %s_plugin(self, name):\n' "${double_suffix}"
			printf '    try:\n'
			printf '        plugin = component.get("WebPlugin." + name.lower().replace("-", "_").replace(" ", "_"))\n'
			printf '    except KeyError:\n'
			printf '        return\n\n'
		} >> "${double_quoted}"
	done
	if python3 "${checker}" "${double_quoted}" > "${work_dir}/double-quoted.out" 2>&1; then
		pass "the behaviour checker accepts a double quoted normalised lookup"
	else
		fail "behaviour checker rejected a double quoted lookup: $(cat "${work_dir}/double-quoted.out")"
	fi

	python3 "${checker}" "${work_dir}/broken.orig" > "${work_dir}/control.out" 2>&1
	control_rc=$?
	if [[ "${control_rc}" -eq 1 ]] && grep -q 'mismatches:' "${work_dir}/control.out"; then
		pass "behaviour check reports mismatches on the unpatched file (the assertion is meaningful)"
	else
		fail "behaviour control: expected exit 1 with mismatches, got exit=${control_rc}: $(cat "${work_dir}/control.out")"
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
if [[ "${skipped}" -gt 0 ]]; then
	echo "${skipped} check(s) skipped in this environment." >&2
fi
exit "${failures}"
