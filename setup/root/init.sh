#!/bin/bash

# exit script if return code != 0
set -e

# if uid not specified then use default uid for user nobody 
if [[ -z "${PUID}" ]]; then
	PUID="99"
fi

# if gid not specifed then use default gid for group users
if [[ -z "${PGID}" ]]; then
	PGID="100"
fi

# set user nobody to specified user id (non unique)
usermod -o -u "${PUID}" nobody
echo "[info] Env var PUID  defined as ${PUID}"

# set group users to specified group id (non unique)
groupmod -o -g "${PGID}" users
echo "[info] Env var PGID defined as ${PGID}"

# check for presence of perms file, if it exists then skip setting
# permissions, otherwise recursively set on /config and /data
if [[ ! -f "/config/perms.txt" ]]; then

	# set permissions for /config and /data volume mapping
	echo "[info] Setting permissions recursively on /config and /data..."
	chown -R "${PUID}":"${PGID}" /config /data
	chmod -R 775 /config /data
	echo "This file prevents permissions from being applied/re-applied to /config, if you want to reset permissions then please delete this file and restart the container." > /config/perms.txt

else

	echo "[info] Permissions already set for /config and /data"

fi

# set permissions inside container
chown -R "${PUID}":"${PGID}" /usr/bin/deluged /usr/bin/deluge-web /usr/bin/privoxy /etc/privoxy /home/nobody
chmod -R 775 /usr/bin/deluged /usr/bin/deluge-web /usr/bin/privoxy /etc/privoxy /home/nobody

echo "[info] Starting Supervisor..."

# run supervisor
exec /usr/bin/supervisord -c /etc/supervisor.conf -n