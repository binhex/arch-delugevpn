#!/bin/bash

# wait for deluge process to start (listen for port)
while [[ $(netstat -lnt | awk '$6 == "LISTEN" && $4 ~ ".58846"') == "" ]]; do
	sleep 0.1
done

# define location and name of pid file
pid_file="/home/nobody/downloader.sleep.pid"

# set sleep period for recheck (in secs)
sleep_period="10"

while true; do

	# check if deluge is running, if not then kill sleep process for deluge.sh shell
	if ! pgrep -f /usr/bin/deluged > /dev/null; then

		if [[ -f "${pid_file}" ]]; then

			echo "[warn] Deluge process terminated, killing sleep command in deluge.sh to force restart and refresh of ip/port..."
			pkill -P $(<"${pid_file}") sleep
			echo "[info] Sleep process killed"

			# sleep for 30 secs to give deluge chance to start before re-checking
			sleep 30s

		else

			echo "[info] No PID file containing PID for sleep command in deluge.sh present, assuming script hasn't started yet."

		fi

	fi

	sleep "${sleep_period}"s

done
