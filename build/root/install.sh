#!/bin/bash

# exit script if return code != 0
set -e

# build scripts
####

# download build scripts from github
curl --connect-timeout 5 --max-time 600 --retry 5 --retry-delay 0 --retry-max-time 60 -o /tmp/scripts-master.zip -L https://github.com/binhex/scripts/archive/master.zip

# unzip build scripts
unzip /tmp/scripts-master.zip -d /tmp

# move shell scripts to /root
mv /tmp/scripts-master/shell/arch/docker/*.sh /root/

# custom scripts
####

# call custom install script
source /root/custom.sh

# pacman packages
####

# define pacman packages
pacman_packages="pygtk python2-service-identity python2-mako python2-notify gnu-netcat ipcalc python2-pip"

# install compiled packages using pacman
if [[ ! -z "${pacman_packages}" ]]; then
	pacman -S --needed $pacman_packages --noconfirm
fi

# aor packages
####

# define arch official repo (aor) packages
aor_packages="deluge"

# call aor script (arch official repo)
source /root/aor.sh

# aur packages
####

# define aur packages
aur_packages=""

# call aur install script (arch user repo)
source /root/aur.sh

# pip packages
####
pip_packages="flexget"

# install pip packages
if [[ ! -z "${pip_packages}" ]]; then
    yes | pip2 install ${pip_packages}
fi

# container perms
####

# create file with contets of here doc
cat <<'EOF' > /tmp/permissions_heredoc
echo "[info] Setting permissions on files/folders inside container..." | ts '%Y-%m-%d %H:%M:%.S'

# create path to store deluge python eggs
mkdir -p /home/nobody/.cache/Python-Eggs

chown -R "${PUID}":"${PGID}" /usr/bin/deluged /usr/bin/deluge-web /usr/bin/privoxy /etc/privoxy /home/nobody
chmod -R 775 /usr/bin/deluged /usr/bin/deluge-web /usr/bin/privoxy /etc/privoxy /home/nobody

# remove permissions for group and other from the Python-Eggs folder
chmod -R 700 /home/nobody/.cache/Python-Eggs

EOF

# replace permissions placeholder string with contents of file (here doc)
sed -i '/# PERMISSIONS_PLACEHOLDER/{
    s/# PERMISSIONS_PLACEHOLDER//g
    r /tmp/permissions_heredoc
}' /root/init.sh
rm /tmp/permissions_heredoc

# env vars
####

cat <<'EOF' > /tmp/envvars_heredoc

# check for presence of network interface docker0
check_network=$(ifconfig | grep docker0 || true)

# if network interface docker0 is present then we are running in host mode and thus must exit
if [[ ! -z "${check_network}" ]]; then
	echo "[crit] Network type detected as 'Host', this will cause major issues, please stop the container and switch back to 'Bridge' mode" | ts '%Y-%m-%d %H:%M:%.S' && exit 1
fi

export VPN_ENABLED=$(echo "${VPN_ENABLED}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
if [[ ! -z "${VPN_ENABLED}" ]]; then
	echo "[info] VPN_ENABLED defined as '${VPN_ENABLED}'" | ts '%Y-%m-%d %H:%M:%.S'
else
	echo "[warn] VPN_ENABLED not defined,(via -e VPN_ENABLED), defaulting to 'yes'" | ts '%Y-%m-%d %H:%M:%.S'
	export VPN_ENABLED="yes"
fi

if [[ $VPN_ENABLED == "yes" ]]; then

	# create directory to store openvpn config files
	mkdir -p /config/openvpn

	# set perms and owner for files in /config/openvpn directory
	set +e
	chown -R "${PUID}":"${PGID}" "/config/openvpn" &> /dev/null
	exit_code_chown=$?
	chmod -R 775 "/config/openvpn" &> /dev/null
	exit_code_chmod=$?
	set -e

	if (( ${exit_code_chown} != 0 || ${exit_code_chmod} != 0 )); then
		echo "[warn] Unable to chown/chmod /config/openvpn/, assuming SMB mountpoint" | ts '%Y-%m-%d %H:%M:%.S'
	fi

	# wildcard search for openvpn config files (match on first result)
	export VPN_CONFIG=$(find /config/openvpn -maxdepth 1 -name "*.ovpn" -print -quit)

	# if ovpn file not found in /config/openvpn then exit
	if [[ -z "${VPN_CONFIG}" ]]; then
		echo "[crit] No OpenVPN config file located in /config/openvpn/ (ovpn extension), please download from your VPN provider and then restart this container, exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1
	fi

	echo "[info] OpenVPN config file (ovpn extension) is located at ${VPN_CONFIG}" | ts '%Y-%m-%d %H:%M:%.S'

	# convert CRLF (windows) to LF (unix) for ovpn
	/usr/bin/dos2unix "${VPN_CONFIG}" 1> /dev/null

	# parse values from ovpn file
	export vpn_remote_line=$(cat "${VPN_CONFIG}" | grep -P -o -m 1 '(?<=^remote\s)[^\n\r]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${vpn_remote_line}" ]]; then
		echo "[info] VPN remote line defined as '${vpn_remote_line}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[crit] VPN configuration file ${VPN_CONFIG} does not contain 'remote' line, showing contents of file before exit..." | ts '%Y-%m-%d %H:%M:%.S'
		cat "${VPN_CONFIG}" && exit 1
	fi

	export VPN_REMOTE=$(echo "${vpn_remote_line}" | grep -P -o -m 1 '^[^\s\r\n]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${VPN_REMOTE}" ]]; then
		echo "[info] VPN_REMOTE defined as '${VPN_REMOTE}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[crit] VPN_REMOTE not found in ${VPN_CONFIG}, exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1
	fi

	export VPN_PORT=$(echo "${vpn_remote_line}" | grep -P -o -m 1 '(?<=\s)\d{2,5}(?=\s)?+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${VPN_PORT}" ]]; then
		echo "[info] VPN_PORT defined as '${VPN_PORT}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[crit] VPN_PORT not found in ${VPN_CONFIG}, exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1
	fi

	export VPN_PROTOCOL=$(cat "${VPN_CONFIG}" | grep -P -o -m 1 '(?<=^proto\s)[^\r\n]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${VPN_PROTOCOL}" ]]; then
		echo "[info] VPN_PROTOCOL defined as '${VPN_PROTOCOL}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		export VPN_PROTOCOL=$(echo "${vpn_remote_line}" | grep -P -o -m 1 'udp|tcp-client|tcp$' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		if [[ ! -z "${VPN_PROTOCOL}" ]]; then
			echo "[info] VPN_PROTOCOL defined as '${VPN_PROTOCOL}'" | ts '%Y-%m-%d %H:%M:%.S'
		else
			echo "[warn] VPN_PROTOCOL not found in ${VPN_CONFIG}, assuming udp" | ts '%Y-%m-%d %H:%M:%.S'
			export VPN_PROTOCOL="udp"
		fi
	fi

	# required for use in iptables
	if [[ "${VPN_PROTOCOL}" == "tcp-client" ]]; then
		export VPN_PROTOCOL="tcp"
	fi

	export VPN_DEVICE_TYPE=$(cat "${VPN_CONFIG}" | grep -P -o -m 1 '(?<=^dev\s)[^\r\n]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${VPN_DEVICE_TYPE}" ]]; then
		echo "[info] VPN_DEVICE_TYPE defined as '${VPN_DEVICE_TYPE}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[crit] VPN_DEVICE_TYPE not found in ${VPN_CONFIG}, exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1
	fi

	# get values from env vars as defined by user
	export VPN_PROV=$(echo "${VPN_PROV}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${VPN_PROV}" ]]; then
		echo "[info] VPN_PROV defined as '${VPN_PROV}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[crit] VPN_PROV not defined,(via -e VPN_PROV), exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1
	fi

	export LAN_NETWORK=$(echo "${LAN_NETWORK}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${LAN_NETWORK}" ]]; then
		echo "[info] LAN_NETWORK defined as '${LAN_NETWORK}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[crit] LAN_NETWORK not defined (via -e LAN_NETWORK), exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1
	fi

	export NAME_SERVERS=$(echo "${NAME_SERVERS}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${NAME_SERVERS}" ]]; then
		echo "[info] NAME_SERVERS defined as '${NAME_SERVERS}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[warn] NAME_SERVERS not defined (via -e NAME_SERVERS), defaulting to Google and FreeDNS name servers" | ts '%Y-%m-%d %H:%M:%.S'
		export NAME_SERVERS="8.8.8.8,37.235.1.174,8.8.4.4,37.235.1.177"
	fi

	if [[ $VPN_PROV != "airvpn" ]]; then
		export VPN_USER=$(echo "${VPN_USER}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		if [[ ! -z "${VPN_USER}" ]]; then
			echo "[info] VPN_USER defined as '${VPN_USER}'" | ts '%Y-%m-%d %H:%M:%.S'
		else
			echo "[warn] VPN_USER not defined (via -e VPN_USER), assuming authentication via other method" | ts '%Y-%m-%d %H:%M:%.S'
		fi

		export VPN_PASS=$(echo "${VPN_PASS}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		if [[ ! -z "${VPN_PASS}" ]]; then
			echo "[info] VPN_PASS defined as '${VPN_PASS}'" | ts '%Y-%m-%d %H:%M:%.S'
		else
			echo "[warn] VPN_PASS not defined (via -e VPN_PASS), assuming authentication via other method" | ts '%Y-%m-%d %H:%M:%.S'
		fi
	fi

	export VPN_OPTIONS=$(echo "${VPN_OPTIONS}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${VPN_OPTIONS}" ]]; then
		echo "[info] VPN_OPTIONS defined as '${VPN_OPTIONS}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[info] VPN_OPTIONS not defined (via -e VPN_OPTIONS)" | ts '%Y-%m-%d %H:%M:%.S'
		export VPN_OPTIONS=""
	fi

	if [[ $VPN_PROV == "pia" ]]; then

		export STRICT_PORT_FORWARD=$(echo "${STRICT_PORT_FORWARD}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		if [[ ! -z "${STRICT_PORT_FORWARD}" ]]; then
			echo "[info] STRICT_PORT_FORWARD defined as '${STRICT_PORT_FORWARD}'" | ts '%Y-%m-%d %H:%M:%.S'
		else
			echo "[warn] STRICT_PORT_FORWARD not defined (via -e STRICT_PORT_FORWARD), defaulting to 'yes'" | ts '%Y-%m-%d %H:%M:%.S'
			export STRICT_PORT_FORWARD="yes"
		fi

	fi

	export ENABLE_PRIVOXY=$(echo "${ENABLE_PRIVOXY}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${ENABLE_PRIVOXY}" ]]; then
		echo "[info] ENABLE_PRIVOXY defined as '${ENABLE_PRIVOXY}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[warn] ENABLE_PRIVOXY not defined (via -e ENABLE_PRIVOXY), defaulting to 'no'" | ts '%Y-%m-%d %H:%M:%.S'
		export ENABLE_PRIVOXY="no"
	fi

elif [[ $VPN_ENABLED == "no" ]]; then
	echo "[warn] !!IMPORTANT!! You have set the VPN to disabled, you will NOT be secure!" | ts '%Y-%m-%d %H:%M:%.S'
fi

EOF

# replace env vars placeholder string with contents of file (here doc)
sed -i '/# ENVVARS_PLACEHOLDER/{
    s/# ENVVARS_PLACEHOLDER//g
    r /tmp/envvars_heredoc
}' /root/init.sh
rm /tmp/envvars_heredoc

# cleanup
yes|pacman -Scc
rm -rf /usr/share/locale/*
rm -rf /usr/share/man/*
rm -rf /usr/share/gtk-doc/*
rm -rf /tmp/*
