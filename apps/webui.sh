#!/bin/bash

# wait for deluge daemon process to start
until pids=$(pidof deluged)
do   
    sleep 0.1
done

# set listen interface for deluge to tunnel local ip
# /usr/bin/deluge-console -c /config "config --set listen_interface $TUN_LOCAL_IP"

# enable bind incoming port to specific port (disable random)
/usr/bin/deluge-console -c /config "config --set random_port False"

# set incoming port to specific value
# /usr/bin/deluge-console -c /config "config --set listen_ports ($PORT,$PORT)"

# echo "[info] incoming listening port is $PORT"

# run deluge webui
/usr/bin/deluge-web -c /config