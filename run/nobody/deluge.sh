#!/bin/bash

if [[ "${deluge_running}" == "false" ]]; then

	echo "[info] Attempting to start Deluge..."

	echo "[info] Removing deluge pid file (if it exists)..."
	rm -f /config/deluged.pid

	# set listen interface ip address for deluge using python script
	/home/nobody/config_deluge.py "/config/core.conf" "listen_interface" "${vpn_ip}"

	# set outgoing interface name for deluge using python script
	/home/nobody/config_deluge.py "/config/core.conf" "outgoing_interface" "${VPN_DEVICE_TYPE}"

	if [ -f  "/config/hostlist.conf" ]; then

		# get host id for daemon, used to auto login web ui (see next step)
		host_id=$(cat /config/hostlist.conf | grep -E -o -m 1 '[a-z0-9]{32,256}')

		# set web ui to auto login using host id for locally running daemon
		/home/nobody/config_deluge.py "/config/web.conf" "default_daemon" "${host_id}"

	fi

	# run deluge daemon (daemonized, non-blocking)
	/usr/bin/deluged -c /config -L "${DELUGE_DAEMON_LOG_LEVEL}" -l /config/deluged.log

	# make sure process deluged DOES exist
	retry_count=30
	while true; do

		if ! pgrep -fa "deluged" > /dev/null; then

			retry_count=$((retry_count-1))
			if [ "${retry_count}" -eq "0" ]; then

				echo "[warn] Wait for Deluge process to start aborted, too many retries"
				echo "[warn] Showing output from command before exit..."
				timeout 10 /usr/bin/deluged -c /config -L "${DELUGE_DAEMON_LOG_LEVEL}" -l /config/deluged.log
				cat /config/deluged.log ; exit 1

			else

				if [[ "${DEBUG}" == "true" ]]; then
					echo "[debug] Waiting for Deluge process to start..."
				fi

				sleep 1s

			fi

		else

			echo "[info] Deluge process started"
			break

		fi

	done

	echo "[info] Waiting for Deluge process to start listening on port 58846..."

	while [[ $(netstat -lnt | awk "\$6 == \"LISTEN\" && \$4 ~ \".58846\"") == "" ]]; do
		sleep 0.1
	done

	echo "[info] Deluge process listening on port 58846"

else

	# set listen interface ip address for deluge
	/usr/bin/deluge-console -c /config "config --set listen_interface ${vpn_ip}"

fi

# change incoming port using the deluge console
if [[ "${VPN_PROV}" == "pia" && -n "${VPN_INCOMING_PORT}" ]]; then

	# enable bind incoming port to specific port (disable random)
	/usr/bin/deluge-console -c /config "config --set random_port False"

	# set incoming port
	/usr/bin/deluge-console -c /config "config --set listen_ports (${VPN_INCOMING_PORT},${VPN_INCOMING_PORT})"

	# set deluge port to current vpn port (used when checking for changes on next run)
	deluge_port="${VPN_INCOMING_PORT}"

fi

# run script to check we don't have any torrents in an error state
/home/nobody/torrentcheck.sh

if [[ "${deluge_web_running}" == "false" ]]; then

	echo "[info] Starting Deluge Web UI..."

	# run deluge-web
	nohup /usr/bin/deluge-web -c /config -L "${DELUGE_WEB_LOG_LEVEL}" -l /config/deluge-web.log &
	echo "[info] Deluge Web UI started"

fi

# set deluge ip to current vpn ip (used when checking for changes on next run)
deluge_ip="${vpn_ip}"
