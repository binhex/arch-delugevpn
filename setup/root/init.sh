#!/bin/bash

# exit script if return code != 0
set -e

# send stdout and stderr to supervisor log file (to capture output from this script)
exec &>/config/supervisord.log

export PUID=$(echo "${PUID}" | sed -e 's/^[ \t]*//')
if [[ ! -z "${PUID}" ]]; then
	echo "[info] PUID defined as ${PUID}" | ts '%Y-%m-%d %H:%M:%S'
else
	echo "[warn] PUID not defined (via -e PUID), defaulting to '99'" | ts '%Y-%m-%d %H:%M:%S,%3N'
	export PUID="99"
fi

# set user nobody to specified user id (non unique)
usermod -o -u "${PUID}" nobody &>/dev/null

export PGID=$(echo "${PGID}" | sed -e 's/^[ \t]*//')
if [[ ! -z "${PGID}" ]]; then
	echo "[info] PGID defined as ${PGID}" | ts '%Y-%m-%d %H:%M:%S,%3N'
else
	echo "[warn] PGID not defined (via -e PGID), defaulting to '100'" | ts '%Y-%m-%d %H:%M:%S,%3N'
	export PGID="100"
fi

# set group users to specified group id (non unique)
groupmod -o -g "${PGID}" users &>/dev/null

# check for presence of perms file, if it exists then skip setting
# permissions, otherwise recursively set on /config and /data
if [[ ! -f "/config/perms.txt" ]]; then

	# set permissions for /config and /data volume mapping
	echo "[info] Setting permissions recursively on /config and /data..." | ts '%Y-%m-%d %H:%M:%S,%3N'
	chown -R "${PUID}":"${PGID}" /config /data
	chmod -R 775 /config /data
	echo "This file prevents permissions from being applied/re-applied to /config, if you want to reset permissions then please delete this file and restart the container." > /config/perms.txt | ts '%Y-%m-%d %H:%M:%S,%3N'

else

	echo "[info] Permissions already set for /config and /data" | ts '%Y-%m-%d %H:%M:%S,%3N'

fi

# set permissions inside container
chown -R "${PUID}":"${PGID}" /usr/bin/deluged /usr/bin/deluge-web /usr/bin/privoxy /etc/privoxy /home/nobody
chmod -R 775 /usr/bin/deluged /usr/bin/deluge-web /usr/bin/privoxy /etc/privoxy /home/nobody

# strip whitespace from start and end of env var
export VPN_ENABLED=$(echo "${VPN_ENABLED}" | sed -e 's/^[ \t]*//')

export VPN_PROV=$(echo "${VPN_PROV}" | sed -e 's/^[ \t]*//')
if [[ ! -z "${VPN_PROV}" ]]; then
	echo "[info] VPN_PROV defined as ${VPN_PROV}" | ts '%Y-%m-%d %H:%M:%S,%3N'
else
	echo "[crit] VPN_PROV not defined,(via -e VPN_PROV), exiting..." | ts '%Y-%m-%d %H:%M:%S,%3N' && exit 1
fi

export VPN_REMOTE=$(echo "${VPN_REMOTE}" | sed -e 's/^[ \t]*//')
if [[ ! -z "${VPN_REMOTE}" ]]; then
	echo "[info] VPN_REMOTE defined as ${VPN_REMOTE}" | ts '%Y-%m-%d %H:%M:%S,%3N'
else
	echo "[crit] VPN_REMOTE not defined (via -e VPN_REMOTE), exiting..." | ts '%Y-%m-%d %H:%M:%S,%3N' && exit 1
fi

export VPN_PORT=$(echo "${VPN_PORT}" | sed -e 's/^[ \t]*//')
if [[ ! -z "${VPN_PORT}" ]]; then
	echo "[info] VPN_PORT defined as ${VPN_PORT}" | ts '%Y-%m-%d %H:%M:%S,%3N'
else
	echo "[crit] VPN_PORT not defined (via -e VPN_PORT), exiting..." | ts '%Y-%m-%d %H:%M:%S,%3N' && exit 1
fi

export VPN_PROTOCOL=$(echo "${VPN_PROTOCOL}" | sed -e 's/^[ \t]*//')
if [[ ! -z "${VPN_PROTOCOL}" ]]; then
	echo "[info] VPN_PROTOCOL defined as ${VPN_PROTOCOL}" | ts '%Y-%m-%d %H:%M:%S,%3N'
else
	echo "[crit] VPN_PROTOCOL not defined (via -e VPN_PROTOCOL), exiting..." | ts '%Y-%m-%d %H:%M:%S,%3N' && exit 1
fi

export VPN_USER=$(echo "${VPN_USER}" | sed -e 's/^[ \t]*//')
if [[ ! -z "${VPN_USER}" ]]; then
	echo "[info] VPN_USER defined as ${VPN_USER}" | ts '%Y-%m-%d %H:%M:%S,%3N'
else
	echo "[crit] VPN_USER not specified, please specify using env variable VPN_USER" | ts '%Y-%m-%d %H:%M:%S,%3N' && exit 1
fi

export VPN_PASS=$(echo "${VPN_PASS}" | sed -e 's/^[ \t]*//')
if [[ ! -z "${VPN_PASS}" ]]; then
	echo "[info] VPN_PASS defined as ${VPN_PASS}" | ts '%Y-%m-%d %H:%M:%S,%3N'
else
	echo "[crit] VPN_PASS not specified, please specify using env variable VPN_PASS" | ts '%Y-%m-%d %H:%M:%S,%3N' && exit 1
fi

export LAN_NETWORK=$(echo "${LAN_NETWORK}" | sed -e 's/^[ \t]*//')
if [[ ! -z "${LAN_NETWORK}" ]]; then
	echo "[info] LAN_NETWORK defined as ${LAN_NETWORK}" | ts '%Y-%m-%d %H:%M:%S,%3N'
else
	echo "[crit] LAN_NETWORK not specified, please specify using env variable LAN_NETWORK" | ts '%Y-%m-%d %H:%M:%S,%3N' && exit 1
fi

export VPN_DEVICE_TYPE=$(echo "${VPN_DEVICE_TYPE}" | sed -e 's/^[ \t]*//')
if [[ ! -z "${VPN_DEVICE_TYPE}" ]]; then
	echo "[info] VPN_DEVICE_TYPE defined as ${VPN_DEVICE_TYPE}" | ts '%Y-%m-%d %H:%M:%S,%3N'
else
	echo "[warn] VPN_DEVICE_TYPE not defined (via -e VPN_DEVICE_TYPE), defaulting to 'tun'" | ts '%Y-%m-%d %H:%M:%S,%3N'
	export VPN_DEVICE_TYPE="tun"
fi

export STRONG_CERTS=$(echo "${STRONG_CERTS}" | sed -e 's/^[ \t]*//')
if [[ ! -z "${STRONG_CERTS}" ]]; then
	echo "[info] STRONG_CERTS defined as ${STRONG_CERTS}" | ts '%Y-%m-%d %H:%M:%S,%3N'
else
	echo "[warn] STRONG_CERTS not defined (via -e STRONG_CERTS), defaulting to 'no'" | ts '%Y-%m-%d %H:%M:%S,%3N'
	export STRONG_CERTS="no"
fi

export ENABLE_PRIVOXY=$(echo "${ENABLE_PRIVOXY}" | sed -e 's/^[ \t]*//')
if [[ ! -z "${ENABLE_PRIVOXY}" ]]; then
	echo "[info] ENABLE_PRIVOXY defined as ${ENABLE_PRIVOXY}" | ts '%Y-%m-%d %H:%M:%S,%3N'
else
	echo "[warn] ENABLE_PRIVOXY not defined (via -e ENABLE_PRIVOXY), defaulting to 'no'" | ts '%Y-%m-%d %H:%M:%S,%3N'
	export ENABLE_PRIVOXY="no"
fi

echo "[info] Starting Supervisor..." | ts '%Y-%m-%d %H:%M:%S,%3N'

# run supervisor
exec /usr/bin/supervisord -c /etc/supervisor.conf -n