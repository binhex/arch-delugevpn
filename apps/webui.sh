#!/bin/bash

# wait for deluge daemon process to start (listen for port)
while [[ $(netstat -lnt | awk '$6 == "LISTEN" && $4 ~ ".58846"') == "" ]]; do
	sleep 0.1
done

echo "[info] Starting Deluge webui..."

# run deluge webui
/usr/bin/deluge-web -c /config