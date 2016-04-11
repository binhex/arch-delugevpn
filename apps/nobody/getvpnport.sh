#!/bin/bash

# get username and password from credentials file
USERNAME=$(sed -n '1p' /config/openvpn/credentials.conf)
PASSWORD=$(sed -n '2p' /config/openvpn/credentials.conf)

# lookup the dynamic pia incoming port (response in json format)
vpn_port=`curl --connect-timeout 5 --max-time 20 --retry 5 --retry-delay 0 --retry-max-time 120 -s -d "user=$USERNAME&pass=$PASSWORD&client_id=$client_id&local_ip=$vpn_ip" https://www.privateinternetaccess.com/vpninfo/port_forward_assignment | head -1 | grep -Po "[0-9]*"`