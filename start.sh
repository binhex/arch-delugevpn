#!/bin/bash

# run once, to create config files for openvpn
if [ ! -f /root/runonce ]; then
	echo "[info] Performing first time setup"
	
	# create directory
	mkdir -p /config/openvpn
	
	# copy openvpn certs to /config
	cp /root/ca.crt /config/openvpn/ca.crt
	cp /root/crl.pem /config/openvpn/crl.pem
	
	# copy openvpn config file to /config
	cp /root/openvpn.conf /config/openvpn/openvpn.conf
		
	touch /root/runonce
fi

# write pia username to file
if [ -z "${PIA_USER}" ]; then
	echo "[crit] PIA username not specified" && exit 1
else
	echo "${PIA_USER}" > /config/openvpn/credentials.conf	
fi

# append pia password to file
if [ -z "${PIA_PASS}" ]; then
	echo "[crit] PIA password not specified" && exit 1
else
	echo "${PIA_PASS}" >> /config/openvpn/credentials.conf
fi

# set permissions to user nobody
chown -R nobody:users /config/openvpn
chmod -R 775 /config/openvpn

# create the tunnel device
[ -d /dev/net ] || mkdir -p /dev/net
[ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200

# get gateway ip for eth0
DEFAULT_GATEWAY=$(ip route show default | awk '/default/ {print $3}')

# setup route for deluge webui, using set-mark to mark traffic for port 8112
echo "8112    webui" >> /etc/iproute2/rt_tables
ip rule add fwmark 1 table webui
ip route add default via $DEFAULT_GATEWAY table webui

# use mangle to set source/destination with mark 1 (port 8112)
iptables -t mangle -A OUTPUT -p tcp --dport 8112 -j MARK --set-mark 1
iptables -t mangle -A OUTPUT -p tcp --sport 8112 -j MARK --set-mark 1

echo "[info] ip routes"
ip route
echo "--------------------"

# accept output to tunnel adapter
iptables -A OUTPUT -o tun0 -j ACCEPT

# accept output to vpn gateway
iptables -A OUTPUT -p udp -o eth0 --dport 1194 -j ACCEPT

# accept output to deluge webui port 8112
iptables -A OUTPUT -p tcp -o eth0 --dport 8112 -j ACCEPT
iptables -A OUTPUT -p tcp -o eth0 --sport 8112 -j ACCEPT

# accept output dns lookup
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT

# accept output to local loopback
iptables -A OUTPUT -o lo -j ACCEPT

# reject non matching output traffic
iptables -A OUTPUT -j REJECT

echo "[info] iptable rules"
iptables -S
echo "--------------------"

# add in google public nameservers (isp may block lookup when connected to vpn)
echo 'nameserver 8.8.8.8' >> /etc/resolv.conf
echo 'nameserver 8.8.4.4' >> /etc/resolv.conf

# run openvpn to create tunnel
/usr/bin/openvpn --cd /config/openvpn --config /config/openvpn/openvpn.conf --redirect-gateway