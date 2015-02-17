#!/bin/bash

# run script to check ip is valid for tun0
source /home/nobody/checkip.sh

# if privoxy enabled then run
if [[ -z "${ENABLE_PRIVOXY}" ]]; then
	echo "[warn] Privoxy not specified, defaulting to disabled"
else
	echo "[info] Privoxy defined as ENABLE_PRIVOXY=$ENABLE_PRIVOXY"
	if [[ $ENABLE_PRIVOXY == "yes" ]]; then	
		echo "[info] Starting Privoxy..."		
		mkdir -p /config/privoxy
		if [[ ! -f "/config/privoxy/config" ]]; then
			cp -R /etc/privoxy/ /config/
		fi
		LAN_IP=$(hostname -i)
		sed -i -e "s/confdir \/etc\/privoxy/confdir \/config\/privoxy/g" /config/privoxy/config
		sed -i -e "s/logdir \/var\/log\/privoxy/logdir \/config\/privoxy/g" /config/privoxy/config
		sed -i -e "s/listen-address.*/listen-address  $LAN_IP:8118/g" /config/privoxy/config
		/usr/bin/privoxy --no-daemon /config/privoxy/config
	else
		echo "[info] Privoxy set to disabled"		
	fi
fi
