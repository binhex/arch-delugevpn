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

# note do NOT download build scripts - inherited from int script with envvars common defined

# custom
####

# this downgrades libtorrent from the troublesome v2 to v1
# see here for details:- https://forums.unraid.net/bug-reports/stable-releases/crashes-since-updating-to-v611x-for-qbittorrent-and-deluge-users-r2153/?do=findComment&comment=21671
package_name_list="libtorrent-rasterbar.tar boost-libs.tar boost.tar"

if [[ "${TARGETARCH}" == "amd64" ]]; then
	archive_extension="zst"
elif [[ "${TARGETARCH}" == "arm64" ]]; then
	archive_extension="xz"
fi

for package_name in ${package_name_list}; do

	# download package
	rcurl.sh -o "/tmp/${package_name}.${archive_extension}" "https://github.com/binhex/packages/raw/master/compiled/${TARGETARCH}/${package_name}.${archive_extension}"

	# install package
	pacman -U "/tmp/${package_name}.${archive_extension}" --noconfirm

done

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

# tweaks
####

# create path to store deluge python eggs
mkdir -p /home/nobody/.cache/Python-Eggs

# remove permissions for group and other from the Python-Eggs folder
chmod -R 700 /home/nobody/.cache/Python-Eggs

# change peerid to appear to be 2.1.1 stable - note this does not work for all/any private trackers at present
sed -i -e "s~peer_id = substitute_chr(peer_id, 6, release_chr)~peer_id = \'-DE211s-\'\n        release_chr = \'s\'~g" /usr/lib/python3*/site-packages/deluge/core/core.py

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
}' /usr/local/bin/init.sh
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
}' /usr/local/bin/init.sh
rm /tmp/envvars_heredoc

# cleanup
cleanup.sh
