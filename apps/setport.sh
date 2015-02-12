#!/bin/bash

# wait for deluge daemon process to start
until [[ $(pgrep -f deluged) ]]; do
    sleep 0.1	
done

# loop over incoming port, checking every 30 minutes
while true
do
	# get username and password from credentials file
	USERNAME=$(sed -n '1p' /config/openvpn/credentials.conf)
	PASSWORD=$(sed -n '2p' /config/openvpn/credentials.conf)

	# create pia client id (randomly generated)
	CLIENT_ID=`head -n 100 /dev/urandom | md5sum | tr -d " -"`

	# run script to check ip is valid for tun0
	source /home/nobody/checkip.sh

	echo "[info] PIA settings: Username=$USERNAME, Password=$PASSWORD, Client ID=$CLIENT_ID, Local IP=$LOCAL_IP"

	# lookup the dynamic incoming port (response in json format)
	INCOMING_PORT=`curl --connect-timeout 5 --max-time 20 --retry 5 --retry-delay 0 --retry-max-time 120 -s -d "user=$USERNAME&pass=$PASSWORD&client_id=$CLIENT_ID&local_ip=$LOCAL_IP" https://www.privateinternetaccess.com/vpninfo/port_forward_assignment | head -1 | grep -Po "[0-9]*"`

	echo "[info] PIA Incoming Port=$INCOMING_PORT"

	if [[ $INCOMING_PORT =~ ^-?[0-9]+$ ]]; then
	  
		# enable bind incoming port to specific port (disable random)
		/usr/bin/deluge-console -c /config "config --set random_port False"

		# set incoming port
		/usr/bin/deluge-console -c /config "config --set listen_ports ($INCOMING_PORT,$INCOMING_PORT)"
	else
		echo "[warn]: Incoming Port $INCOMING_PORT is not an integer, downloads will be slow"
	fi

	sleep 30m
done
