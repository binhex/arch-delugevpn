#!/bin/bash

# create function to check ip for tunnal is valid
check_valid_ip() {

    IP_ADDRESS="$1"
	
    # check if the format looks right
    echo "$IP_ADDRESS" | egrep -qE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' || return 1
	
    # check that each octect is less than or equal to 255
    echo $IP_ADDRESS | awk -F'.' '$1 <=255 && $2 <= 255 && $3 <=255 && $4 <= 255 {print "Y" } ' | grep -q Y || return 1
	
    return 0
}

# loop and wait until tun local ip is valid
LOCAL_IP=""
while ! check_valid_ip "$LOCAL_IP"
do
	sleep 0.1
	LOCAL_IP=`ifconfig tun0 | grep 'inet' | grep -P -o -m 1 '(?<=inet\s)[^\s]+'`
done

echo "[info] tunnel local ip is $LOCAL_IP"

# set listen interface for deluge to local ip for tunnel
sed -i -e 's/\"listen_interface\"\:.*/\"listen_interface\"\: \"1.1.1.1\",/g' /config/core.conf

# enable bind incoming port to specific port (disable random)
sed -i -e 's/\"random_port\"\:.*/\"random_port\"\: false,/g' /config/core.conf

# set incoming port to specific value
# /usr/bin/deluge-console -c /config "config --set listen_ports ($PORT,$PORT)"

# echo "[info] incoming listening port is $PORT"

# run deluge daemon
/usr/bin/deluged -d -c /config -L info -l /config/deluged.log

# run deluge webui
/usr/bin/deluge-web -c /config