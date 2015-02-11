#!/bin/bash

# wait for deluge daemon process to start
until pids=$(pgrep -f deluged)
do   
    sleep 0.1
	exit 1
done

# run deluge webui
/usr/bin/deluge-web -c /config