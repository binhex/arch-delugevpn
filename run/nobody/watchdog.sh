#!/bin/bash

# if deluge-web config file doesnt exist then copy stock config file
if [[ ! -f /config/web.conf ]]; then
	echo "[info] Deluge-web config file doesn't exist, copying default..."
	cp /home/nobody/webui/web.conf /config/
fi


# if deluge config file doesnt exist then copy stock config file
if [[ ! -f /config/core.conf ]]; then
	echo "[info] Deluge config file doesn't exist, copying default..."
	cp /home/nobody/deluge/core.conf /config/
fi

# force unix line endings conversion in case user edited core.conf with notepad
/usr/bin/dos2unix "/config/core.conf"

# set default values for port and ip
deluge_port="6890"
deluge_ip="0.0.0.0"

# while loop to check ip and port
while true; do

	# reset triggers to negative values
	deluge_running="false"
	deluge_web_running="false"
	privoxy_running="false"
	ip_change="false"
	port_change="false"

	if [[ "${VPN_ENABLED}" == "yes" ]]; then

		# run script to check ip is valid for tunnel device (will block until valid)
		source /home/nobody/getvpnip.sh

		# if vpn_ip is not blank then run, otherwise log warning
		if [[ ! -z "${vpn_ip}" ]]; then

			# if current bind interface ip is different to tunnel local ip then re-configure deluge
			if [[ "${deluge_ip}" != "${vpn_ip}" ]]; then

				echo "[info] Deluge listening interface IP ${deluge_ip} and VPN provider IP ${vpn_ip} different, marking for reconfigure"

				# mark as reload required due to mismatch
				ip_change="true"

			fi

			# check if deluged is running
			if ! pgrep -fa "deluged" > /dev/null; then

				echo "[info] Deluge not running"

			else

				deluge_running="true"

			fi

			# check if deluge-web is running
			if ! pgrep -fa "deluge-web" > /dev/null; then

				echo "[info] Deluge Web UI not running"

			else

				deluge_web_running="true"

			fi

			if [[ "${ENABLE_PRIVOXY}" == "yes" ]]; then

				# check if privoxy is running, if not then skip shutdown of process
				if ! pgrep -fa "privoxy" > /dev/null; then

					echo "[info] Privoxy not running"

				else

					# mark as privoxy as running
					privoxy_running="true"

				fi

			fi

			# run scripts to identify external ip address
			source /home/nobody/getvpnextip.sh

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
						nc_exitcode=$(/usr/bin/nc -z -w 3 "${vpn_ip}" "${deluge_port}")

						if [[ "${nc_exitcode}" -ne 0 ]]; then

							echo "[info] Deluge incoming port closed, marking for reconfigure"

							# mark as reconfigure required due to mismatch
							port_change="true"

						fi

					fi

					if [[ "${deluge_port}" != "${VPN_INCOMING_PORT}" ]]; then

						echo "[info] Deluge incoming port $deluge_port and VPN incoming port ${VPN_INCOMING_PORT} different, marking for reconfigure"

						# mark as reconfigure required due to mismatch
						port_change="true"

					fi

				fi

			fi

			if [[ "${port_change}" == "true" || "${ip_change}" == "true" || "${deluge_running}" == "false" || "${deluge_web_running}" == "false" ]]; then

				# run script to start deluge
				source /home/nobody/deluge.sh

			fi

			if [[ "${ENABLE_PRIVOXY}" == "yes" ]]; then

				if [[ "${privoxy_running}" == "false" ]]; then

					# run script to start privoxy
					source /home/nobody/privoxy.sh

				fi

			fi

		else

			echo "[warn] VPN IP not detected, VPN tunnel maybe down"

		fi

	else

		# check if deluged is running
		if ! pgrep -fa "deluged" > /dev/null; then

			echo "[info] Deluge not running"

		else

			deluge_running="true"

		fi

		# check if deluge-web is running
		if ! pgrep -fa "deluge-web" > /dev/null; then

			echo "[info] Deluge Web UI not running"

		else

			deluge_web_running="true"

		fi

		if [[ "${ENABLE_PRIVOXY}" == "yes" ]]; then

			# check if privoxy is running, if not then start via privoxy.sh
			if ! pgrep -fa "privoxy" > /dev/null; then

				echo "[info] Privoxy not running"

				# run script to start privoxy
				source /home/nobody/privoxy.sh

			fi

		fi

		if [[ "${deluge_running}" == "false" || "${deluge_web_running}" == "false" ]]; then

			# run script to start deluge
			source /home/nobody/deluge.sh

		fi

	fi

	if [[ "${DEBUG}" == "true" && "${VPN_ENABLED}" == "yes" ]]; then

		if [[ "${VPN_PROV}" == "pia" && -n "${VPN_INCOMING_PORT}" ]]; then

			echo "[debug] VPN incoming port is ${VPN_INCOMING_PORT}"
			echo "[debug] Deluge incoming port is ${deluge_port}"

		fi

		echo "[debug] VPN IP is ${vpn_ip}"
		echo "[debug] Deluge IP is ${deluge_ip}"

	fi

	sleep 30s

done
