#!/bin/bash

# exit script if return code != 0
set -e

# app name from buildx arg, used in healthcheck to identify app and monitor correct process
APPNAME="${1}"
shift

# release tag name from buildx arg, stripped of build ver using string manipulation
RELEASETAG="${1}"
shift

# target arch from buildx arg
TARGETARCH="${1}"
shift

if [[ -z "${APPNAME}" ]]; then
	echo "[warn] App name from build arg is empty, exiting script..."
	exit 1
fi

if [[ -z "${RELEASETAG}" ]]; then
	echo "[warn] Release tag name from build arg is empty, exiting script..."
	exit 1
fi

if [[ -z "${TARGETARCH}" ]]; then
	echo "[warn] Target architecture name from build arg is empty, exiting script..."
	exit 1
fi

# write APPNAME and RELEASETAG to file to record the app name and release tag used to build the image
echo -e "export APPNAME=${APPNAME}\nexport IMAGE_RELEASE_TAG=${RELEASETAG}\n" >> '/etc/image-build-info'

# ensure we have the latest builds scripts
refresh.sh

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

# aur packages
####

# define aur packages
aur_packages=""

# call aur install script (arch user repo)
source aur.sh

# custom
####

# required as there is no arm64 package for 7zip at present 2025-04-13
if [[ "${TARGETARCH}" == "arm64" ]]; then
	curl -o /tmp/7zip.tar.xz -L https://www.7-zip.org/a/7z2409-linux-arm64.tar.xz
else
	curl -o /tmp/7zip.tar.xz -L https://www.7-zip.org/a/7z2409-linux-x64.tar.xz
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
sed -i -e "s~peer_id = substitute_chr(peer_id, 6, release_chr)~peer_id = \'-DE220s-\'\n        release_chr = \'s\'~g" /usr/lib/python3*/site-packages/deluge/core/core.py

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
