#!/bin/bash

# run script to check ip is valid for tun0
source /home/nobody/checkip.sh

if [ -z "${ENABLE_PRIVOXY}" ]; then
	echo "[warn] Privoxy not specified, defaulting to disabled"
else
	echo "[info] Privoxy defined as ENABLE_PRIVOXY=$ENABLE_PRIVOXY"
	if [ $ENABLE_PRIVOXY == "yes" ]; then	
		echo "[info] Starting Privoxy..."
		mkdir -p /config/privoxy
		/usr/bin/privoxy --no-daemon /config/privoxy
	else
		echo "[info] Privoxy set to disabled"