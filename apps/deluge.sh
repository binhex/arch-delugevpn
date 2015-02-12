#!/bin/bash

# run script to check ip is valid for tun0
source /home/nobody/checkip.sh

echo "[info] Starting Deluge daemon..."

# run deluge daemon
/usr/bin/deluged -d -c /config -L info -l /config/deluged.log