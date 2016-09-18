#!/bin/bash

# if config file doesnt exist then copy stock config file
if [[ ! -f /config/core.conf ]]; then

	cp /home/nobody/deluge/core.conf /config/

else

	echo "[info] deluge config file already exists, skipping copy"

fi

# if vpn set to "no" then don't run openvpn
if [[ $VPN_ENABLED == "no" ]]; then

	echo "[info] VPN not enabled, skipping VPN tunnel local ip checks"

	deluge_ip="0.0.0.0"

	# run deluge
	echo "[info] All checks complete, starting deluge..."

	# set listen interface ip address for deluge
	sed -i -e 's~"listen_interface":\s*"[^"]*~"listen_interface": "'"${deluge_ip}"'~g' /config/core.conf

	# run deluge daemon (non daemonized, blocking)
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

	# set default values for port and ip
	deluge_port="6890"
	deluge_ip="0.0.0.0"

	# set sleep period for recheck (in mins)
	sleep_period="10"

	# while loop to check ip and port
	while true; do

		# run scripts to identity vpn ip
		source /home/nobody/getvpnip.sh

		# if vpn_ip is not blank then run, otherwise log warning
		if [[ ! -z "${vpn_ip}" ]]; then

			# check deluge is running, if not then set to first_run and reload
			if ! pgrep -f /usr/bin/deluged > /dev/null; then

				echo "[info] Deluge daemon not running, marking as first run"

				# mark as first run and reload required due to deluge not running
				first_run="true"
				reload="true"

			else

				# if current bind interface ip is different to tunnel local ip then re-configure deluge
				if [[ $deluge_ip != "$vpn_ip" ]]; then

					echo "[info] Deluge listening interface IP $deluge_ip and VPN provider IP different, marking for reload"

					# mark as reload required due to mismatch
					first_run="false"
					reload="true"

				fi

			fi

			if [[ $VPN_PROV == "pia" ]]; then

				# run scripts to identify vpn port
				source /home/nobody/getvpnport.sh

				if [[ $first_run == "false" ]]; then

					# if vpn port is not an integer then log warning
					if [[ ! $vpn_port =~ ^-?[0-9]+$ ]]; then

						echo "[warn] PIA incoming port is not an integer, downloads will be slow, does PIA remote gateway supports port forwarding?"

						# set vpn port to current deluge port, as we currently cannot detect incoming port (line saturated, or issues with pia)
						vpn_port="${deluge_port}"

					elif [[ $deluge_port != "$vpn_port" ]]; then

						echo "[info] Deluge incoming port $deluge_port and VPN incoming port $vpn_port different, marking for reload"

						# mark as reload required due to mismatch
						first_run="false"
						reload="true"

					# run netcat to identify if port still open, use exit code
					nc_exitcode=$(/usr/bin/nc -z -w 3 "${deluge_ip}" "${deluge_port}")

					elif [[ "${nc_exitcode}" -ne 0 ]]; then

						echo "[info] Deluge incoming port closed, marking for reload"

						# mark as reload required due to mismatch
						first_run="false"
						reload="true"

					fi

				else

					# if vpn port is not an integer then log warning
					if [[ ! $vpn_port =~ ^-?[0-9]+$ ]]; then

						echo "[warn] PIA incoming port is not an integer, downloads will be slow, does PIA remote gateway supports port forwarding?"

					fi

					# mark as reload required due to first run
					first_run="true"
					reload="true"

				fi

			fi

			if [[ $reload == "true" ]]; then

				if [[ $first_run == "false" ]]; then

					echo "[info] Reload required, configuring Deluge..."

					# set listen interface to tunnel local ip using command line
					/usr/bin/deluge-console -c /config "config --set listen_interface $vpn_ip"

					# set deluge ip to current vpn ip (used when checking for changes on next run)
					deluge_ip="${vpn_ip}"

					if [[ $VPN_PROV == "pia" ]]; then

						# enable bind incoming port to specific port (disable random)
						/usr/bin/deluge-console -c /config "config --set random_port False"

						# set incoming port
						/usr/bin/deluge-console -c /config "config --set listen_ports ($vpn_port,$vpn_port)"
						
						# set deluge port to current vpn port (used when checking for changes on next run)
						deluge_port="${vpn_port}"


					fi

				else

					# set listen interface ip address for deluge using sed
					sed -i -e 's~"listen_interface":\s*"[^"]*~"listen_interface": "'"${vpn_ip}"'~g' /config/core.conf

					# set deluge ip to current vpn ip (used when checking for changes on next run)
					deluge_ip="${vpn_ip}"

					echo "[info] All checks complete, starting Deluge..."
					
					# run deluge daemon (daemonized, non-blocking)
					/usr/bin/deluged -c /config -L info -l /config/deluged.log

					if [[ $VPN_PROV == "pia" ]]; then

						# wait for deluge daemon process to start (listen for port)
						while [[ $(netstat -lnt | awk '$6 == "LISTEN" && $4 ~ ".58846"') == "" ]]; do
							sleep 0.1
						done

						# enable bind incoming port to specific port (disable random)
						/usr/bin/deluge-console -c /config "config --set random_port False"

						# set incoming port
						/usr/bin/deluge-console -c /config "config --set listen_ports ($vpn_port,$vpn_port)"

						# set deluge port to current vpn port (used when checking for changes on next run)
						deluge_port="${vpn_port}"

					fi

				fi

			fi

			if [[ "${DEBUG}" == "true" ]]; then

				echo "[debug] VPN incoming port is $vpn_port"
				echo "[debug] Deluge incoming port is $deluge_port"
				echo "[debug] VPN IP is $vpn_ip"
				echo "[debug] Deluge IP is $deluge_ip"

			fi

			# reset triggers to negative values
			first_run="false"
			reload="false"

		else

			echo "[warn] VPN IP not detected"

		fi

		echo "[info] Sleeping for ${sleep_period} mins before rechecking listen interface and port (port checking is for PIA only)"
		sleep "${sleep_period}"m

	done

fi
