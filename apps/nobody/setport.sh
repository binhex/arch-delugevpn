#!/bin/bash

# wait for deluge daemon process to start (listen for port)
while [[ $(netstat -lnt | awk '$6 == "LISTEN" && $4 ~ ".58846"') == "" ]]; do
	sleep 0.1
done

# while loop to check/set incoming port every 50 mins (required for pia)
while true
do
	# run script to check/get ip for tun0
	source /home/nobody/checkip.sh
					
	if [[ $VPN_PROV == "pia" ]]; then
	
		# get username and password from credentials file
		USERNAME=$(sed -n '1p' /config/openvpn/credentials.conf)
		PASSWORD=$(sed -n '2p' /config/openvpn/credentials.conf)

		# create pia client id (randomly generated)
		CLIENT_ID=`head -n 100 /dev/urandom | md5sum | tr -d " -"`
	
		echo "[info] PIA settings: Username=$USERNAME, Password=$PASSWORD, Client ID=$CLIENT_ID, Local IP=$LOCAL_IP"

		# lookup the dynamic pia incoming port (response in json format)
		PIA_INCOMING_PORT=`curl --connect-timeout 5 --max-time 20 --retry 5 --retry-delay 0 --retry-max-time 120 -s -d "user=$USERNAME&pass=$PASSWORD&client_id=$CLIENT_ID&local_ip=$LOCAL_IP" https://www.privateinternetaccess.com/vpninfo/port_forward_assignment | head -1 | grep -Po "[0-9]*"`
		
		# lookup the currently set deluge incoming port
		DELUGE_INCOMING_PORT=`/usr/bin/deluge-console -c /config "config listen_ports" | grep -P -o -m 1 '[\d]+'`

		if [[ $PIA_INCOMING_PORT =~ ^-?[0-9]+$ ]]; then

			if [[ $DELUGE_INCOMING_PORT != "$PIA_INCOMING_PORT" ]]; then
			
				echo "[info] Deluge incoming port $DELUGE_INCOMING_PORT and PIA incoming port $PIA_INCOMING_PORT different, configuring Deluge..."
				
				# enable bind incoming port to specific port (disable random)
				/usr/bin/deluge-console -c /config "config --set random_port False"

				# set incoming port
				/usr/bin/deluge-console -c /config "config --set listen_ports ($PIA_INCOMING_PORT,$PIA_INCOMING_PORT)"
			
			fi
						
		else
		
			echo "[warn] PIA incoming port is not an integer, downloads will be slow, check if remote gateway supports port forwarding"
			
		fi
		
	fi
	
	sleep 50m
	
done	