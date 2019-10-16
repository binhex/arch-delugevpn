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
/usr/local/bin/dos2unix.sh "/config/core.conf"

# set default values for port and ip
deluge_port="6890"
deluge_ip="0.0.0.0"

# define sleep period between loops
sleep_period_secs=30

# define sleep period between incoming port checks
sleep_period_incoming_port_secs=1800

# sleep period counter - used to limit number of hits to external website to check incoming port
sleep_period_counter_secs=0

# while loop to check ip and port
while true; do

	# reset triggers to negative values
	deluge_running="false"
	deluge_web_running="false"
	privoxy_running="false"
	ip_change="false"
	vpn_port_change="false"
	deluge_port_change="false"

	if [[ "${VPN_ENABLED}" == "yes" ]]; then

		# run script to get all required info
		source /home/nobody/preruncheck.sh

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
				if ! pgrep -fa "/usr/bin/privoxy" > /dev/null; then

					echo "[info] Privoxy not running"

				else

					# mark as privoxy as running
					privoxy_running="true"

				fi

			fi

			if [[ "${VPN_PROV}" == "pia" ]]; then

				# if vpn port is not an integer then dont change port
				if [[ ! "${VPN_INCOMING_PORT}" =~ ^-?[0-9]+$ ]]; then

					# set vpn port to current deluge port, as we currently cannot detect incoming port (line saturated, or issues with pia)
					VPN_INCOMING_PORT="${deluge_port}"

					# ignore port change as we cannot detect new port
					deluge_port_change="false"

				else

					if [[ "${deluge_running}" == "true" ]]; then

						if [ "${sleep_period_counter_secs}" -ge "${sleep_period_incoming_port_secs}" ]; then

							# run script to check incoming port is accessible
							source /home/nobody/checkextport.sh

							# reset sleep period counter
							sleep_period_counter_secs=0

						fi

					fi

					if [[ "${deluge_port}" != "${VPN_INCOMING_PORT}" ]]; then

						echo "[info] Deluge incoming port $deluge_port and VPN incoming port ${VPN_INCOMING_PORT} different, marking for reconfigure"

						# mark as reconfigure required due to mismatch
						deluge_port_change="true"

					fi

				fi

			fi

			if [[ "${deluge_port_change}" == "true" || "${ip_change}" == "true" || "${deluge_running}" == "false" || "${deluge_web_running}" == "false" ]]; then

				# run script to start deluge
				source /home/nobody/deluge.sh

			fi

			# if port is detected as closed then create empty file to trigger restart of openvpn process (restart code in /root/openvpn.sh)
			if [[ "${vpn_port_change}" == "true" ]];then

				touch "/tmp/portclosed"

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
			if ! pgrep -fa "/usr/bin/privoxy" > /dev/null; then

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

	# increment sleep period counter - used to limit number of hits to external website to check incoming port
	sleep_period_counter_secs=$((sleep_period_counter_secs+"${sleep_period_secs}"))

	sleep "${sleep_period_secs}"s

done
