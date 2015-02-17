#!/bin/bash

# wait for deluge daemon process to start (listen for port)
while [[ $(netstat -lnt | awk '$6 == "LISTEN" && $4 ~ ".58846"') == "" ]]; do
	sleep 0.1
done

if [[ $VPN_PROV == "custom" ]]; then

	# loop over incoming port, checking every 10 minutes
	while true
	do
		# run script to check ip is valid for tun0
		source /home/nobody/checkip.sh
		
		# query deluge for current ip for tunnel
		LISTEN_INTERFACE=`/usr/bin/deluge-console -c /config "config listen_interface" | grep -P -o -m 1 '[\d\.]+'`
			 
		echo "[info] Deluge listening interface is $LISTEN_INTERFACE"
			
		# if current listen interface ip is different to tunnel local ip then force re-detect of incoming port
		if [[ "$LISTEN_INTERFACE" != "$LOCAL_IP" ]]; then

			echo "[info] Deluge listening interface IP $LISTEN_INTERFACE and OpenVPN local IP $LOCAL_IP different, configuring Deluge..."

			# enable bind incoming port to specific port (disable random)
			/usr/bin/deluge-console -c /config "config --set random_port False"

			# set listen interface to tunnel local ip
			/usr/bin/deluge-console -c /config "config --set listen_interface $LOCAL_IP"
			
		fi
		
		sleep 10m
	done

elif [[ $VPN_PROV == "pia" || -z "${VPN_PROV}" ]]; then		

	# loop over incoming port, checking every 10 minutes
	while true
	do
		# run script to check ip is valid for tun0
		source /home/nobody/checkip.sh
		
		# query deluge for current ip for tunnel
		LISTEN_INTERFACE=`/usr/bin/deluge-console -c /config "config listen_interface" | grep -P -o -m 1 '[\d\.]+'`
			 
		echo "[info] Deluge listening interface is $LISTEN_INTERFACE"
			
		# if current listen interface ip is different to tunnel local ip then force re-detect of incoming port
		if [[ "$LISTEN_INTERFACE" != "$LOCAL_IP" ]]; then

			echo "[info] Deluge listening interface IP $LISTEN_INTERFACE and OpenVPN local IP $LOCAL_IP different, configuring Deluge..."
			
			# get username and password from credentials file
			USERNAME=$(sed -n '1p' /config/openvpn/credentials.conf)
			PASSWORD=$(sed -n '2p' /config/openvpn/credentials.conf)

			# create pia client id (randomly generated)
			CLIENT_ID=`head -n 100 /dev/urandom | md5sum | tr -d " -"`
		
			echo "[info] PIA settings: Username=$USERNAME, Password=$PASSWORD, Client ID=$CLIENT_ID, Local IP=$LOCAL_IP"

			# lookup the dynamic incoming port (response in json format)
			INCOMING_PORT=`curl --connect-timeout 5 --max-time 20 --retry 5 --retry-delay 0 --retry-max-time 120 -s -d "user=$USERNAME&pass=$PASSWORD&client_id=$CLIENT_ID&local_ip=$LOCAL_IP" https://www.privateinternetaccess.com/vpninfo/port_forward_assignment | head -1 | grep -Po "[0-9]*"`

			echo "[info] PIA incoming port is $INCOMING_PORT"

			if [[ $INCOMING_PORT =~ ^-?[0-9]+$ ]]; then
			  
				# enable bind incoming port to specific port (disable random)
				/usr/bin/deluge-console -c /config "config --set random_port False"

				# set listen interface to tunnel local ip
				/usr/bin/deluge-console -c /config "config --set listen_interface $LOCAL_IP"

				# set incoming port
				/usr/bin/deluge-console -c /config "config --set listen_ports ($INCOMING_PORT,$INCOMING_PORT)"
			else
				echo "[warn] PIA incoming port is not an integer, downloads will be slow"
			fi
		fi
		
		sleep 10m
	done	
fi
