#!/bin/bash

# exit script if return code != 0
set -e

# release tag name from buildx arg, stripped of build ver using string manipulation
RELEASETAG="${1//-[0-9][0-9]/}"

# target arch from buildx arg
TARGETARCH="${2}"

if [[ -z "${RELEASETAG}" ]]; then
	echo "[warn] Release tag name from build arg is empty, exiting script..."
	exit 1
fi

if [[ -z "${TARGETARCH}" ]]; then
	echo "[warn] Target architecture name from build arg is empty, exiting script..."
	exit 1
fi

# ensure we have the latest build scripts
refresh.sh

# aur packages
####

# define aur packages
# note we are currently using the aur package ' libtorrent-rasterbar-1_2-git' as opposed to
# the stable aur package 'libtorrent-rasterbar-1' because we require 'python-bindings=ON',
# failure to enable python-bindings will result in deluge reporting
# 'ModuleNotFoundError: No module named 'libtorrent''
aur_packages="libtorrent-rasterbar-1_2-git"

# the base image's aur.sh disables debug packages with a non-idempotent sed, so an
# image that already ships '!debug' (aarch64) ends up with the invalid '!!debug'
# option, which makes makepkg lint fail and breaks paru resolution of split package
# dependencies - normalise the value so the sed still produces a valid '!debug'
if grep -qF 's/\bdebug\b/!debug/g' "$(command -v aur.sh)"; then
	sed -i '/^OPTIONS=/s/!*debug\b/debug/g' '/etc/makepkg.conf'
fi

# call aur install script (arch user repo)
aur.sh --aur-package "${aur_packages}"

# ignore aor package 'libtorrent-rasterbar' to prevent upgrade to libtorrent v2 as libtorrent
# v2 causes numerous issues, including crashing on unraid due to kernel bug
sed -i -e 's~IgnorePkg.*~IgnorePkg = filesystem libtorrent-rasterbar~g' '/etc/pacman.conf'

# pacman packages
####

# call pacman db and package updater script
source upd.sh

# define pacman packages
pacman_packages="deluge"

# install compiled packages using pacman
if [[ ! -z "${pacman_packages}" ]]; then
	pacman -S --needed $pacman_packages --noconfirm
fi

# deluge loads its plugins through pkg_resources, which setuptools removed in v82
# (Feb 2026) - install the standalone redistribution (source: pypa/setuptools) into
# the system python used by deluge until upstream migrates to importlib
if ! python3 -c 'import pkg_resources' &>/dev/null; then
	pacman -S --needed uv --noconfirm
	cat <<'EOF' > /tmp/pkg_resources_requirements.txt
standard-pkg-resources==1.0.0 --hash=sha256:4cb8701c863000f60637495427121c0da697b395c9088dff7e864bc741a3f2e8
EOF
	site_packages=$(python3 -c 'import site; print(site.getsitepackages()[0])')
	uv pip install --no-cache --no-deps --require-hashes --python "$(command -v python3)" \
		--target "${site_packages}" -r /tmp/pkg_resources_requirements.txt
	rm -f /tmp/pkg_resources_requirements.txt "${site_packages}/.lock"
	pacman -Rns uv --noconfirm
	python3 -c 'import pkg_resources' || { echo "[crit] Failed to install pkg_resources, exiting build process..." ; exit 1; }
fi

# custom
####

# required as there is no arm64 package for 7zip at present 2025-04-13
if [[ "${TARGETARCH}" == "arm64" ]]; then
	curl -o /tmp/7zip.tar.xz -L https://www.7-zip.org/a/7z2600-linux-arm64.tar.xz
else
	curl -o /tmp/7zip.tar.xz -L https://www.7-zip.org/a/7z2600-linux-x64.tar.xz
fi

# extract, remove tar file and move to /usr/bin
tar -xvf /tmp/7zip.tar.xz -C /tmp
rm /tmp/7zip.tar.xz
mv /tmp/7zzs /usr/bin/7z
chmod +x /usr/bin/7z

# tweaks
####

# create path to store deluge python eggs
mkdir -p /home/nobody/.cache/Python-Eggs

# remove permissions for group and other from the Python-Eggs folder
chmod -R 700 /home/nobody/.cache/Python-Eggs

# change peerid to appear to be 2.1.1 stable - note this does not work for all/any private trackers at present
sed -i -e "s~peer_id = substitute_chr(peer_id, 6, release_chr)~peer_id = \'-DE211s-\'\n        release_chr = \'s\'~g" /usr/lib/python3*/site-packages/deluge/core/core.py

# deluge plugin webui patch - begin
# Arch's deluge package backports the importlib plugin loader (upstream commit dab761f3) but
# not the matching web ui lookup, so plugins register as 'WebPlugin.<snake case name>' while
# deluge/ui/web/pluginmanager.py still asks for 'WebPlugin.<original name>' - mixed case
# plugins such as Label, Scheduler and YaRSS2 then log 'contains no WebUI code' and lose
# their web ui, normalise the three lookups to match the registration. this mirrors the
# backport's '_plugin_rpc_name()' helper (lower case, dash and space to underscore) and is
# only applied when the installed loader normalises component names. ascii names only: the
# backport ascii folds the plugin name before normalising, this does not ascii fold
# NOTE: the same block ships on the libtorrentv1 branch - keep both copies in sync, the
# workflow-test job diffs them
deluge_site_packages="${DELUGE_SITE_PACKAGES:-/usr/lib/python3*/site-packages}"
deluge_web_pluginmanager="${deluge_site_packages}/deluge/ui/web/pluginmanager.py"
deluge_web_lookup_raw="component.get('WebPlugin.' + name)"
deluge_web_lookup_normalised="component.get('WebPlugin.' + name.lower().replace('-', '_').replace(' ', '_'))"
deluge_web_lookup_fixed="component.get('WebPlugin.' + _plugin_rpc_name(name))"
mapfile -t deluge_web_files < <(compgen -G "${deluge_web_pluginmanager}" 2> /dev/null || true)
if [[ "${#deluge_web_files[@]}" -eq 0 ]]; then
	echo "[warn] deluge WebUI plugin manager not found at '${deluge_web_pluginmanager}', patch not applied"
else
	for deluge_web_file in "${deluge_web_files[@]}"; do
		deluge_web_pluginbase="${deluge_web_file%deluge/ui/web/pluginmanager.py}deluge/plugins/pluginbase.py"
		if [[ ! -f "${deluge_web_pluginbase}" ]]; then
			echo "[warn] '${deluge_web_pluginbase}' not found, leaving '${deluge_web_file}' unchanged"
			continue
		fi
		# the rewrite below is only correct when the installed loader normalises component
		# names, so require the backport's helper and a registration that does not use the
		# raw plugin name. only the known single quoted one line registration shape is
		# recognised, anything else is warned about and left unpatched, never mispatched
		deluge_web_registration=''
		deluge_web_registration=$(grep -oE "'WebPlugin\.' \+ [A-Za-z_.]+" "${deluge_web_pluginbase}" \
			2> /dev/null | head -1 || true)
		deluge_web_normalising=0
		if [[ -n "${deluge_web_registration}" && "${deluge_web_registration}" != *plugin_name* ]] \
			&& grep -qF -e '_plugin_rpc_name' "${deluge_web_pluginbase}"; then
			deluge_web_normalising=1
		fi
		if [[ "${deluge_web_normalising}" != "1" ]]; then
			echo "[warn] deluge does not normalise plugin component names, leaving '${deluge_web_file}' unchanged"
			continue
		fi
		deluge_web_patched=0
		if grep -qF "${deluge_web_lookup_raw}" "${deluge_web_file}"; then
			deluge_web_patched=1
			sed -i "s~component\.get('WebPlugin\.' + name)~${deluge_web_lookup_normalised}~g" "${deluge_web_file}" \
				|| { echo "[crit] Failed to patch '${deluge_web_file}', exiting build process..." ; exit 1 ; }
			if grep -qF "${deluge_web_lookup_raw}" "${deluge_web_file}"; then
				echo "[crit] raw lookup still present in '${deluge_web_file}', exiting build process..."
				exit 1
			fi
		fi
		deluge_web_lookups=$(grep -cE "component\.get\('WebPlugin\." "${deluge_web_file}" || true)
		deluge_web_lookups=${deluge_web_lookups:-0}
		deluge_web_ok=$(grep -cF "${deluge_web_lookup_normalised}" "${deluge_web_file}" || true)
		deluge_web_ok=${deluge_web_ok:-0}
		deluge_web_ok_fixed=$(grep -cF "${deluge_web_lookup_fixed}" "${deluge_web_file}" || true)
		deluge_web_ok_fixed=${deluge_web_ok_fixed:-0}
		deluge_web_ok=$((deluge_web_ok + deluge_web_ok_fixed))
		if [[ "${deluge_web_lookups}" == "0" ]]; then
			echo "[warn] no lookup matching '${deluge_web_lookup_raw}' in '${deluge_web_file}', patch not applied"
		elif [[ "${deluge_web_ok}" != "${deluge_web_lookups}" && "${deluge_web_patched}" == "1" ]]; then
			echo "[crit] only ${deluge_web_ok}/${deluge_web_lookups} normalised in '${deluge_web_file}', exiting build process..."
			exit 1
		elif [[ "${deluge_web_ok}" != "${deluge_web_lookups}" ]]; then
			echo "[warn] only ${deluge_web_ok}/${deluge_web_lookups} normalised in '${deluge_web_file}', patch not applied"
		elif [[ "${deluge_web_patched}" == "1" ]]; then
			echo "[info] Patched deluge WebUI plugin name lookup for mixed case plugins"
		else
			echo "[info] deluge WebUI plugin name lookup already normalised, no patch required"
		fi
	done
fi
# deluge plugin webui patch - end

# container perms
####

# define comma separated list of paths
install_paths="/etc/privoxy,/home/nobody,/usr/lib/python*/site-packages/deluge"

# split comma separated string into list for install paths
IFS=',' read -ra install_paths_list <<< "${install_paths}"

# process install paths in the list
for i in "${install_paths_list[@]}"; do

	# confirm path(s) exist, if not then exit, do not quote to permit wildcards
	if [ ! -d ${i} ]; then
		echo "[crit] Path '${i}' does not exist, exiting build process..." ; exit 1
	fi

done

# convert comma separated string of install paths to space separated, required for chmod/chown processing
install_paths=$(echo "${install_paths}" | tr ',' ' ')

# set permissions for container during build - Do NOT double quote variable for install_paths otherwise this will wrap space separated paths as a single string
chmod -R 775 ${install_paths}

# set permissions for python eggs to be a more restrictive 755, this prevents the warning message thrown by deluge on startup
mkdir -p /home/nobody/.cache/Python-Eggs ; chmod -R 755 /home/nobody/.cache/Python-Eggs

# disable built-in Deluge Plugin 'stats', as its currently broken in Deluge 2.x and causes log spam
# see here for details https://dev.deluge-torrent.org/ticket/3310
chmod 000 /usr/lib/python3*/site-packages/deluge/plugins/Stats*.egg

# create file with contents of here doc, note EOF is NOT quoted to allow us to expand current variable 'install_paths'
# we use escaping to prevent variable expansion for PUID and PGID, as we want these expanded at runtime of init.sh
cat <<EOF > /tmp/permissions_heredoc

# get previous puid/pgid (if first run then will be empty string)
previous_puid=\$(cat "/root/puid" 2>/dev/null || true)
previous_pgid=\$(cat "/root/pgid" 2>/dev/null || true)

# if first run (no puid or pgid files in /tmp) or the PUID or PGID env vars are different
# from the previous run then re-apply chown with current PUID and PGID values.
if [[ ! -f "/root/puid" || ! -f "/root/pgid" || "\${previous_puid}" != "\${PUID}" || "\${previous_pgid}" != "\${PGID}" ]]; then

	# set permissions inside container - Do NOT double quote variable for install_paths otherwise this will wrap space separated paths as a single string
	chown -R "\${PUID}":"\${PGID}" ${install_paths}

fi

# write out current PUID and PGID to files in /root (used to compare on next run)
echo "\${PUID}" > /root/puid
echo "\${PGID}" > /root/pgid

EOF

# replace permissions placeholder string with contents of file (here doc)
sed -i '/# PERMISSIONS_PLACEHOLDER/{
    s/# PERMISSIONS_PLACEHOLDER//g
    r /tmp/permissions_heredoc
}' /usr/bin/init.sh
rm /tmp/permissions_heredoc

# env vars
####

cat <<'EOF' > /tmp/envvars_heredoc

export DELUGE_DAEMON_LOG_LEVEL=$(echo "${DELUGE_DAEMON_LOG_LEVEL}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
if [[ ! -z "${DELUGE_DAEMON_LOG_LEVEL}" ]]; then
	echo "[info] DELUGE_DAEMON_LOG_LEVEL defined as '${DELUGE_DAEMON_LOG_LEVEL}'" | ts '%Y-%m-%d %H:%M:%.S'
else
	echo "[info] DELUGE_DAEMON_LOG_LEVEL not defined,(via -e DELUGE_DAEMON_LOG_LEVEL), defaulting to 'info'" | ts '%Y-%m-%d %H:%M:%.S'
	export DELUGE_DAEMON_LOG_LEVEL="info"
fi

export DELUGE_WEB_LOG_LEVEL=$(echo "${DELUGE_WEB_LOG_LEVEL}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
if [[ ! -z "${DELUGE_WEB_LOG_LEVEL}" ]]; then
	echo "[info] DELUGE_WEB_LOG_LEVEL defined as '${DELUGE_WEB_LOG_LEVEL}'" | ts '%Y-%m-%d %H:%M:%.S'
else
	echo "[info] DELUGE_WEB_LOG_LEVEL not defined,(via -e DELUGE_WEB_LOG_LEVEL), defaulting to 'info'" | ts '%Y-%m-%d %H:%M:%.S'
	export DELUGE_WEB_LOG_LEVEL="info"
fi

export DELUGE_ENABLE_WEBUI_PASSWORD=$(echo "${DELUGE_ENABLE_WEBUI_PASSWORD}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
if [[ ! -z "${DELUGE_ENABLE_WEBUI_PASSWORD}" ]]; then
	echo "[info] DELUGE_ENABLE_WEBUI_PASSWORD defined as '${DELUGE_ENABLE_WEBUI_PASSWORD}'" | ts '%Y-%m-%d %H:%M:%.S'
else
	echo "[info] DELUGE_ENABLE_WEBUI_PASSWORD not defined,(via -e DELUGE_ENABLE_WEBUI_PASSWORD), defaulting to 'yes'" | ts '%Y-%m-%d %H:%M:%.S'
	export DELUGE_ENABLE_WEBUI_PASSWORD="yes"
fi

export APPLICATION="deluge"

EOF

# replace env vars placeholder string with contents of file (here doc)
sed -i '/# ENVVARS_PLACEHOLDER/{
    s/# ENVVARS_PLACEHOLDER//g
    r /tmp/envvars_heredoc
}' /usr/bin/init.sh
rm /tmp/envvars_heredoc

# cleanup
cleanup.sh
