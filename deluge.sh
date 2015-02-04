#!/bin/bash

# set tun local ip to empty string
LOCAL_IP=""

# loop and wait until tun local ip is valid
until ipcalc -c $LOCAL_IP
do
  sleep 0.1
  LOCAL_IP=`ifconfig $DEVICE | grep 'inet addr:' | cut -d: -f2| cut -d' ' -f1`
done
 
# run deluge daemon
/usr/bin/deluged -d -c /config -L info -l /config/deluged.log

# set listen interface for deluge to local ip for tunnel
/usr/bin/deluge-console -c /config "config --set listen_interface $LOCAL_IP"

# enable bind incoming port to specific port (disable random)
/usr/bin/deluge-console -c /config "config --set random_port False"

# set incoming port to specific value
# /usr/bin/deluge-console -c /config "config --set listen_ports ($PORT,$PORT)"

# run deluge webui
/usr/bin/deluge-web -c /config