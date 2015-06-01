#!/bin/bash

# wait for deluge daemon process to start (listen for port)
while [[ $(netstat -lnt | awk '$6 == "LISTEN" && $4 ~ ".58846"') == "" ]]; do
	sleep 0.1
done

# if vpn set to "no" then set deluge to listen on all ip addresses
if [[ $VPN_ENABLED == "no" ]]; then

	echo "[info] VPN not enabled, configuring Deluge listen interface to all IP addresses on the local machine"
	/usr/bin/deluge-console -c /config "config --set listen_interface 0.0.0.0"

else

	# while loop to check incoming port every 5 mins
	while true
	do
		# run script to check ip is valid for tun0
		source /home/nobody/checkip.sh

		# query deluge for current ip for tunnel
		LISTEN_INTERFACE=`/usr/bin/deluge-console -c /config "config listen_interface" | grep -P -o -m 1 '[\d\.]+'`

		# if current listen interface ip is different to tunnel local ip then re-configure deluge
		if [[ $LISTEN_INTERFACE != "$LOCAL_IP" ]]; then

			echo "[info] Deluge listening interface IP $LISTEN_INTERFACE and OpenVPN local IP $LOCAL_IP different, configuring Deluge..."

			# set listen interface to tunnel local ip
			/usr/bin/deluge-console -c /config "config --set listen_interface $LOCAL_IP"

		fi

		sleep 5m

	done

fi
