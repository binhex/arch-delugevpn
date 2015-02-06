#!/bin/bash

# wait for deluge daemon process to start
until pids=$(pidof deluged)
do   
    sleep 0.1
done

# run deluge webui
/usr/bin/deluge-web -c /config