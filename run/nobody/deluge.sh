#!/bin/bash

# if config file doesnt exist then copy stock config file
if [[ ! -f /config/core.conf ]]; then

	echo "[info] Deluge config file doesn't exist, copying default..."
	cp /home/nobody/deluge/core.conf /config/

else

	echo "[info] Deluge config file already exists, skipping copy"

fi

# if pid file exists then remove (generated from previous run)
rm -f /config/deluged.pid

# if vpn set to "no" then don't run openvpn
if [[ "${VPN_ENABLED}" == "no" ]]; then

	echo "[info] VPN not enabled, skipping VPN tunnel local ip/port checks"

	deluge_ip="0.0.0.0"

	# set listen interface ip address for deluge using python script
	/home/nobody/config_deluge.py "${deluge_ip}"

	# run deluge daemon (daemonized, non-blocking)
	echo "[info] Attempting to start Deluge..."
	/usr/bin/deluged -c /config -L info -l /config/deluged.log

	# run script to check we don't have any torrents in an error state
	/home/nobody/torrentcheck.sh

	# run cat to prevent script exit
	cat

else

	echo "[info] VPN is enabled, checking VPN tunnel local ip is valid"

	# set triggers to first run
	deluge_running="false"
	ip_change="false"
	port_change="false"

	# set default values for port and ip
	deluge_port="6890"
	deluge_ip="0.0.0.0"

	# while loop to check ip and port
	while true; do

		# run script to check ip is valid for tunnel device (will block until valid)
		source /home/nobody/getvpnip.sh

		# if vpn_ip is not blank then run, otherwise log warning
		if [[ ! -z "${vpn_ip}" ]]; then

			# check if deluge is running, if not then skip reconfigure for port/ip
			if ! pgrep -x deluged > /dev/null; then

				echo "[info] Deluge not running"

				# mark as deluge not running
				deluge_running="false"

			else

				# if deluge is running, then reconfigure port/ip
				deluge_running="true"

			fi

			# if current bind interface ip is different to tunnel local ip then re-configure deluge
			if [[ "${deluge_ip}" != "${vpn_ip}" ]]; then

				echo "[info] Deluge listening interface IP $deluge_ip and VPN provider IP ${vpn_ip} different, marking for reconfigure"

				# mark as reload required due to mismatch
				ip_change="true"

			fi

			if [[ "${VPN_PROV}" == "pia" ]]; then

				# run scripts to identify vpn port
				source /home/nobody/getvpnport.sh

				# if vpn port is not an integer then dont change port
				if [[ ! "${VPN_INCOMING_PORT}" =~ ^-?[0-9]+$ ]]; then

					# set vpn port to current deluge port, as we currently cannot detect incoming port (line saturated, or issues with pia)
					VPN_INCOMING_PORT="${deluge_port}"

					# ignore port change as we cannot detect new port
					port_change="false"

				else

					if [[ "${deluge_running}" == "true" ]]; then

						# run netcat to identify if port still open, use exit code
						nc_exitcode=$(/usr/bin/nc -z -w 3 "${deluge_ip}" "${deluge_port}")

						if [[ "${nc_exitcode}" -ne 0 ]]; then

							echo "[info] Deluge incoming port closed, marking for reconfigure"

							# mark as reconfigure required due to mismatch
							port_change="true"

						elif [[ "${deluge_port}" != "${VPN_INCOMING_PORT}" ]]; then

							echo "[info] Deluge incoming port $deluge_port and VPN incoming port ${VPN_INCOMING_PORT} different, marking for reconfigure"

							# mark as reconfigure required due to mismatch
							port_change="true"

						fi

					fi

				fi

			fi

			if [[ "${deluge_running}" == "true" ]]; then

				if [[ "${VPN_PROV}" == "pia" ]]; then

					# reconfigure deluge with new port
					if [[ "${port_change}" == "true" ]]; then

						echo "[info] Reconfiguring Deluge due to port change..."

						# enable bind incoming port to specific port (disable random)
						/usr/bin/deluge-console -c /config "config --set random_port False"

						# set incoming port
						/usr/bin/deluge-console -c /config "config --set listen_ports (${VPN_INCOMING_PORT},${VPN_INCOMING_PORT})"

						echo "[info] Deluge reconfigured for port change"

					fi

				fi

				# reconfigure deluge with new ip
				if [[ "${ip_change}" == "true" ]]; then

					echo "[info] Reconfiguring Deluge due to ip change..."

					# set listen interface to tunnel local ip using command line
					/usr/bin/deluge-console -c /config "config --set listen_interface ${vpn_ip}"

					echo "[info] Deluge reconfigured for ip change"

				fi

			else

				echo "[info] Attempting to start Deluge..."

				# if pid file exists then remove (generated from previous run)
				rm -f /config/deluged.pid

				# set listen interface ip address for deluge using python script
				/home/nobody/config_deluge.py "${vpn_ip}"

				# run deluge daemon (daemonized, non-blocking)
				/usr/bin/deluged -c /config -L info -l /config/deluged.log

				if [[ "${VPN_PROV}" == "pia" || -n "${VPN_INCOMING_PORT}" ]]; then

					# wait for deluge process to start (listen for port)
					while [[ $(netstat -lnt | awk '$6 == "LISTEN" && $4 ~ ".58846"') == "" ]]; do
						sleep 0.1
					done

					# enable bind incoming port to specific port (disable random)
					/usr/bin/deluge-console -c /config "config --set random_port False"

					# set incoming port
					/usr/bin/deluge-console -c /config "config --set listen_ports (${VPN_INCOMING_PORT},${VPN_INCOMING_PORT})"

				fi

				echo "[info] Deluge started"

				# run script to check we don't have any torrents in an error state
				/home/nobody/torrentcheck.sh

			fi

			# set deluge ip and port to current vpn ip and port (used when checking for changes on next run)
			deluge_ip="${vpn_ip}"
			deluge_port="${VPN_INCOMING_PORT}"

			# reset triggers to negative values
			deluge_running="false"
			ip_change="false"
			port_change="false"

			if [[ "${DEBUG}" == "true" ]]; then

				echo "[debug] VPN incoming port is ${VPN_INCOMING_PORT}"
				echo "[debug] VPN IP is ${vpn_ip}"
				echo "[debug] Deluge incoming port is ${deluge_port}"
				echo "[debug] Deluge IP is ${deluge_ip}"

			fi

		else

			echo "[warn] VPN IP not detected, VPN tunnel maybe down"

		fi

		sleep 30s

	done

fi
