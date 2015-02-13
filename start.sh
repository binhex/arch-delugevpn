#!/bin/bash

# run once, to create config files for openvpn
if [ ! -f /root/runonce ]; then
	echo "[info] Performing first time setup..."
	
	# create directory
	mkdir -p /config/openvpn
	
	# copy openvpn certs to /config
	cp /home/nobody/openvpn/ca.crt /config/openvpn/ca.crt
	cp /home/nobody/openvpn/crl.pem /config/openvpn/crl.pem
			
	touch /root/runonce
fi

# get country from env and copy matching pia remote gateway file to /config/openvpn/openvpn.conf
if [ -z "${PIA_REMOTE}" ]; then
	echo "[warn] PIA remote gateway not specified, defaulting to Netherlands"
	cp -f "/home/nobody/openvpn/Netherlands.ovpn" "/config/openvpn/openvpn.conf"
else
	echo "[info] PIA remote gateway defined as $PIA_REMOTE"
	if [ ! -f "/home/nobody/openvpn/$PIA_REMOTE.ovpn" ]; then
		echo "[warn] PIA remote gateway not found, defaulting to Netherlands"	
		cp -f "/home/nobody/openvpn/Netherlands.ovpn" "/config/openvpn/openvpn.conf"
	else
		cp -f "/home/nobody/openvpn/$PIA_REMOTE.ovpn" "/config/openvpn/openvpn.conf"
	fi
fi

# customise openvpn.conf to ping tunnel every 10 mins
if ! $(grep -Fxq "ping 600" /config/openvpn/openvpn.conf); then
	echo "ping 600" >> /config/openvpn/openvpn.conf
fi

# customise openvpn.conf to restart tunnel after 20 mins if no reply from ping
if ! $(grep -Fxq "ping-restart 1200" /config/openvpn/openvpn.conf); then
	echo "ping-restart 1200" >> /config/openvpn/openvpn.conf
fi

# customise openvpn.conf to allow automatic login using credentials.conf file
if ! $(grep -Fxq "auth-user-pass credentials.conf" /config/openvpn/openvpn.conf); then
	sed -i -e 's/auth-user-pass/auth-user-pass credentials.conf/g' /config/openvpn/openvpn.conf
fi

# read port number and protocol from openvpn.conf (used to define iptables rule)
PIA_PORT=$(cat /config/openvpn/openvpn.conf | grep -P -o -m 1 '^remote.*' | grep -P -o -m 1 '[\d]+$')
PIA_PROTOCOL=$(cat /config/openvpn/openvpn.conf | grep -P -o -m 1 '(?<=proto\s).*')
	
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

# setup route for deluge webui using set-mark to route traffic for port 8112 to eth0
echo "8112    webui" >> /etc/iproute2/rt_tables
ip rule add fwmark 1 table webui
ip route add default via $DEFAULT_GATEWAY table webui

# use mangle to set source/destination with mark 1 (port 8112)
iptables -t mangle -A OUTPUT -p tcp --dport 8112 -j MARK --set-mark 1
iptables -t mangle -A OUTPUT -p tcp --sport 8112 -j MARK --set-mark 1

echo "[info] ip route"
ip route
echo "--------------------"

# set policy to drop for input
iptables -P INPUT DROP

# accept input to tunnel adapter
iptables -A INPUT -i tun0 -j ACCEPT

# accept input to vpn gateway
iptables -A INPUT -p $PIA_PROTOCOL -i eth0 --sport $PIA_PORT -j ACCEPT

# accept input to deluge webui port 8112
iptables -A INPUT -p tcp -i eth0 --dport 8112 -j ACCEPT
iptables -A INPUT -p tcp -i eth0 --sport 8112 -j ACCEPT

# accept input dns lookup
iptables -A INPUT -p udp --sport 53 -j ACCEPT

# accept input icmp (ping)
iptables -A INPUT -p icmp --icmp-type echo-reply -j ACCEPT

# accept input to local loopback
iptables -A INPUT -i lo -j ACCEPT

# set policy to drop for output
iptables -P OUTPUT DROP

# accept output to tunnel adapter
iptables -A OUTPUT -o tun0 -j ACCEPT

# accept output to vpn gateway
iptables -A OUTPUT -p $PIA_PROTOCOL -o eth0 --dport $PIA_PORT -j ACCEPT

# accept output to deluge webui port 8112
iptables -A OUTPUT -p tcp -o eth0 --dport 8112 -j ACCEPT
iptables -A OUTPUT -p tcp -o eth0 --sport 8112 -j ACCEPT

# accept output dns lookup
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT

# accept output icmp (ping) 
iptables -A OUTPUT -p icmp --icmp-type echo-request -j ACCEPT

# accept output to local loopback
iptables -A OUTPUT -o lo -j ACCEPT

echo "[info] iptables"
iptables -S
echo "--------------------"

# add in google public nameservers (isp may block lookup when connected to vpn)
echo 'nameserver 8.8.8.8' > /etc/resolv.conf
echo 'nameserver 8.8.4.4' >> /etc/resolv.conf

echo "[info] nameservers"
cat /etc/resolv.conf
echo "--------------------"

# start openvpn tunnel
source /root/openvpn.sh