#!/bin/bash

# wait for deluge daemon process to start
until pids=$(pgrep -f deluged)
do   
    sleep 0.1
done

# get values from environment variables set via docker run
#USERNAME=
#PASSWORD=
#CLIENTID=

# lookup the dynamic incoming PORT (response in json format)
#INCOMING_PORT=`curl -s -d "user=$USERNAME&pass=$PASSWORD&client_id=$CLIENTID&local_ip=$LOCAL_IP" https://www.privateinternetaccess.com/vpninfo/port_forward_assignment | head -1 | grep -Po "[0-9]*"`

echo "INCOMING_PORT=${INCOMING_PORT}"
if [[ $INCOMING_PORT =~ ^-?[0-9]+$ ]] 
then
  echo [deluge-config-settings] Local IP=$LOCAL_IP, Incoming Port=$INCOMING_PORT, Client ID=$CLIENTID
  
  # enable bind incoming port to specific port (disable random)
  /usr/bin/deluge-console -c /config "config --set random_port False"

  # set incoming port
  deluge-console -c /app/deluge "config --set listen_ports ($INCOMING_PORT,$INCOMING_PORT)"
  
else
  echo ERROR: Incoming Port $INCOMING_PORT is not an integer.
  exit 1
fi

# run deluge webui
/usr/bin/deluge-web -c /config