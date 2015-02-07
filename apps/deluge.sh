#!/bin/bash

# create function to check tunnel local ip is valid
check_valid_ip() {

    IP_ADDRESS="$1"
	
    # check if the format looks right
    echo "$IP_ADDRESS" | egrep -qE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' || return 1
	
    # check that each octect is less than or equal to 255
    echo $IP_ADDRESS | awk -F'.' '$1 <=255 && $2 <= 255 && $3 <=255 && $4 <= 255 {print "Y" } ' | grep -q Y || return 1
	
    return 0
}

# loop and wait until adapter tun0 local ip is valid
tun_local_ip=""
while ! check_valid_ip "$tun_local_ip"
do
	sleep 0.1
	tun_local_ip=`ifconfig tun0 | grep 'inet' | grep -P -o -m 1 '(?<=inet\s)[^\s]+'`
done

echo "[info] tunnel local ip is $tun_local_ip"

# save values as env variables
export TUN_LOCAL_IP=$tun_local_ip

# run deluge daemon
/usr/bin/deluged -d -c /config -L info -l /config/deluged.log