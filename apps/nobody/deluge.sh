#!/bin/bash

# if vpn set to "no" then don't run openvpn
if [[ $VPN_ENABLED == "no" ]]; then

	echo "[info] VPN not enabled, skipping VPN tunnel local ip checks"

else

	echo "[info] VPN is enabled, checking VPN tunnel local ip is valid"

	# run script to check ip is valid for tun0
	source /home/nobody/checkip.sh

fi

echo "[info] All checks complete, starting Deluge daemon..."

# run deluge daemon
/usr/bin/deluged -d -c /config -L info -l /config/deluged.log