#!/bin/bash

# sleep to allow openvpn to create tunnel (supervisor does not support dependencies)
sleep 20

# get tun ip address
LOCAL_IP=`ifconfig $DEVICE | grep 'inet addr:' | cut -d: -f2| cut -d' ' -f1`

# set listen interface for deluge to local ip for tunnel
deluge-console -c /config "config --set listen_interface $LOCAL_IP"

# enable bind incoming port to specific port (disable random)
deluge-console -c /config "config --set random_port False"

# set incoming port to specific value
# deluge-console -c /config "config --set listen_ports ($PORT,$PORT)"

# check tunnel status is "UP"
# ip link show tun0
 
# run deluge daemon first
/usr/bin/deluged -d -c /config -L info -l /config/deluged.log

# run deluge webui
/usr/bin/deluge-web -c /config