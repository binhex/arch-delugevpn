#!/bin/bash

# if config file doesnt exist then copy stock config file
if [[ ! -f /config/core.conf ]]; then
	cp /home/nobody/deluge/core.conf /config/
fi

# if vpn set to "no" then don't run openvpn
if [[ $VPN_ENABLED == "no" ]]; then

	echo "[info] VPN not enabled, skipping VPN tunnel local ip checks"

	deluge_ip=""

	# set listen interface ip address for deluge
	sed -i -e 's~"listen_interface":\s*"[^"]*~"listen_interface": "'"${deluge_ip}"'~g' /config/core.conf

	# run deluge daemon
	echo "[info] All checks complete, starting Deluge..."
	/usr/bin/deluged -d -c /config -L info -l /config/deluged.log

else

	echo "[info] VPN is enabled, checking VPN tunnel local ip is valid"

	# create pia client id (randomly generated)
	client_id=`head -n 100 /dev/urandom | md5sum | tr -d " -"`

	# run script to check ip is valid for tun0
	source /home/nobody/checkip.sh

	# set triggers to first run
	first_run="true"
	reload="false"

	# set empty values for port and ip
	deluge_port=""
	deluge_ip=""

	# set sleep period for recheck (in mins)
	sleep_period="5"

	# while loop to check ip and port
	while true; do

		# run scripts to identity vpn ip
		source /home/nobody/getvpnip.sh

		if [[ $first_run == "false" ]]; then

			# if current bind interface ip is different to tunnel local ip then re-configure deluge
			if [[ $deluge_ip != "$vpn_ip" ]]; then

				echo "[info] Deluge listening interface IP $deluge_ip and VPN provider IP different, reconfiguring for VPN provider IP $vpn_ip"

				# mark as reload required due to mismatch
				deluge_ip="${vpn_ip}"
				reload="true"

			else

				echo "[info] Deluge listening interface IP $deluge_ip and VPN provider IP $vpn_ip match"

			fi

		else

			echo "[info] First run detected, setting Deluge listening interface $vpn_ip"

			# mark as reload required due to first run
			deluge_ip="${vpn_ip}"
			reload="true"

		fi

		if [[ $VPN_PROV == "pia" ]]; then

			if [[ $first_run == "false" ]]; then

				# run netcat to identify if port still open, use exit code
				if ! /usr/bin/nc -z -w 3 "${deluge_ip}" "${deluge_port}"; then

					echo "[info] Deluge incoming port $deluge_port closed"

					# run scripts to identify vpn port
					source /home/nobody/getvpnport.sh

					echo "[info] Reconfiguring for VPN provider port $vpn_port"

					# mark as reload required due to mismatch
					deluge_port="${vpn_port}"
					reload="true"

				else

					echo "[info] Deluge incoming port $deluge_port open"

				fi

			else

				# run scripts to identify vpn port
				source /home/nobody/getvpnport.sh

				echo "[info] First run detected, setting Deluge incoming port $vpn_port"

				if [[ ! $vpn_port =~ ^-?[0-9]+$ ]]; then
					echo "[warn] PIA incoming port is not an integer, downloads will be slow, does PIA remote gateway supports port forwarding?"
				fi

				# mark as reload required due to first run
				deluge_port="${vpn_port}"
				reload="true"

			fi

		fi

		if [[ $reload == "true" ]]; then

			echo "[info] Setting listening interface for Deluge..."

			if [[ $first_run == "false" ]]; then

				# set listen interface to tunnel local ip using command line
				/usr/bin/deluge-console -c /config "config --set listen_interface $deluge_ip"

			else

				# set listen interface ip address for deluge using sed
				sed -i -e 's~"listen_interface":\s*"[^"]*~"listen_interface": "'"${deluge_ip}"'~g' /config/core.conf

				# run deluge daemon
				echo "[info] All checks complete, starting Deluge..."
				/usr/bin/deluged -c /config -L info -l /config/deluged.log

			fi

			if [[ $VPN_PROV == "pia" ]]; then

				echo "[info] Setting incoming port for Deluge..."

				# wait for deluge daemon process to start (listen for port)
				while [[ $(netstat -lnt | awk '$6 == "LISTEN" && $4 ~ ".58846"') == "" ]]; do
					sleep 0.1
				done

				# enable bind incoming port to specific port (disable random)
				/usr/bin/deluge-console -c /config "config --set random_port False"

				# set incoming port
				/usr/bin/deluge-console -c /config "config --set listen_ports ($deluge_port,$deluge_port)"

			fi

		fi

		# reset triggers to negative values
		first_run="false"
		reload="false"

		echo "[info] Sleeping for ${sleep_period} mins before rechecking listen interface and port (port checking is for PIA only)"
		sleep "${sleep_period}"m

	done

fi
