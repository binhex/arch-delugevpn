#!/bin/bash

# get currently allocated ip address for tunnel adapter
vpn_ip=`ifconfig "${VPN_DEVICE_TYPE}"0 2>/dev/null | grep 'inet' | grep -P -o -m 1 '(?<=inet\s)[^\s]+'`