#!/bin/bash

# get currently allocated ip address for adapter tun0
vpn_ip=`ifconfig tun0 2>/dev/null | grep 'inet' | grep -P -o -m 1 '(?<=inet\s)[^\s]+'`