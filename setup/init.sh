#!/bin/bash

# if uid not specified then use default uid for user nobody 
if [[ -z "${UID}" ]]; then
	UID="99"
fi

# if gid not specifed then use default gid for group users
if [[ -z "${GID}" ]]; then
	GID="100"
fi

# set user nobody to specified user id (non unique)
usermod -o -u "${UID}" nobody
echo "[info] Env var UID  defined as ${UID}"

# set group users to specified group id (non unique)
groupmod -o -g "${GID}" users
echo "[info] Env var GID defined as ${GID}"

echo "[info] Setting permissions..."

# set permissions for /config volume mapping
chown -R "${UID}":"${GID}" /config
chmod -R 775 /config

# set permissions inside container
chown -R "${UID}":"${GID}" /home/nobody /usr/bin/deluged /usr/bin/deluge-web
chmod -R 775 /home/nobody /usr/bin/deluged /usr/bin/deluge-web

echo "[info] Starting Supervisor..."

# run supervisor
"/usr/bin/supervisord" -c "/etc/supervisor.conf" -n