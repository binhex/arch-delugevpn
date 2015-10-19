#!/bin/bash

# if vpn set to "no" then skip config deluge ip and port
if [[ $VPN_ENABLED == "no" ]]; then
	echo "[info] VPN not enabled, skipping configuration of Deluge"
else
	echo "[info] VPN enabled, configuring Deluge..."

	# run script to check ip is valid for tun0
	source /home/nobody/checkip.sh

	# run scripts to configure deluge ip and port
	source /home/nobody/setip.sh & source /home/nobody/setport.sh &
fi

echo "[info] All checks complete, starting Deluge daemon..."

# run deluge daemon
/usr/bin/deluged -d -c /config -L info -l /config/deluged.log