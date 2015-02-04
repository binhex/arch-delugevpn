#!/bin/bash

# exit if non zero exit code from commands below
set -e

# create the tun device
[ -d /dev/net ] || mkdir -p /dev/net
[ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200

# setup route for deluge web ui
DEFAULT_GATEWAY=$(ip route show default | awk '/default/ {print $3}')

if [ -z "${HOST_SUBNET}" ]; then
	echo "[warn] HOST_SUBNET not specified, deluge web interface will not work"
else
	ip route add $HOST_SUBNET via $DEFAULT_GATEWAY
fi

echo "[info] current route"
ip route
echo "--------------------"

# create openvpn tunnel
/usr/bin/openvpn --cd /config --config /config/openvpn.conf
