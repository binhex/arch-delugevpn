#!/bin/bash

# set tun local ip to invalid ip
LOCAL_IP="256.256.256.256"

# loop and wait until tun local ip is valid
until ipcalc -c $LOCAL_IP
do
  sleep 0.1
  LOCAL_IP=`ifconfig tun0 | grep 'inet' | grep -P -o -m 1 '(?<=inet\s)[^\s]+'`
done

echo "[info] tunnel local ip is $LOCAL_IP"

# run deluge daemon
/usr/bin/deluged -d -c /config -L info -l /config/deluged.log

# set listen interface for deluge to local ip for tunnel
/usr/bin/deluge-console -c /config "config --set listen_interface $LOCAL_IP"

# enable bind incoming port to specific port (disable random)
/usr/bin/deluge-console -c /config "config --set random_port False"

# set incoming port to specific value
# /usr/bin/deluge-console -c /config "config --set listen_ports ($PORT,$PORT)"

# echo "[info] incoming listening port is $PORT"

# run deluge webui
/usr/bin/deluge-web -c /config