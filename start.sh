#!/bin/bash

# create directory
mkdir -p /config/openvpn

# wildcard search for openvpn config files
VPN_CONFIG=$(find /config/openvpn -maxdepth 1 -name "*.ovpn" -print)

# if vpn provider not set then exit
if [[ -z "${VPN_PROV}" ]]; then
	echo "[crit] VPN provider not defined, please specify via env variable VPN_PROV" && exit 1

# if custom|airvpn vpn provider chosen then do NOT copy base config file
elif [[ $VPN_PROV == "custom" || $VPN_PROV == "airvpn" ]]; then

	echo "[info] VPN provider defined as $VPN_PROV"
	if [[ -z "${VPN_CONFIG}" ]]; then
		echo "[crit] VPN provider defined as $VPN_PROV, no files with an ovpn extension exist in /config/openvpn/ please create and restart delugevpn" && exit 1
	fi

# if pia vpn provider chosen then copy base config file and pia certs
elif [[ $VPN_PROV == "pia" ]]; then

	# copy default certs
	echo "[info] VPN provider defined as $VPN_PROV"
	cp -f /home/nobody/ca.crt /config/openvpn/ca.crt
	cp -f /home/nobody/crl.pem /config/openvpn/crl.pem

	# if no ovpn files exist then copy base file
	if [[ -z "${VPN_CONFIG}" ]]; then
		cp -f "/home/nobody/openvpn.ovpn" "/config/openvpn/openvpn.ovpn"
		VPN_CONFIG="/config/openvpn/openvpn.ovpn"
	fi

	# if remote not specified then use netherlands and default port
	if [[ -z "${VPN_REMOTE}" ]]; then
		echo "[warn] VPN provider remote not defined, defaulting to Netherlands port 1194"
		sed -i -e "s/remote\s.*/remote nl.privateinternetaccess.com 1194/g" "$VPN_CONFIG"
	elif [[ ! -z "${VPN_REMOTE}" && -z "${VPN_PORT}" ]]; then
		echo "[warn] VPN provider port not defined, defaulting to 1194"
		sed -i -e "s/remote\s.*/remote $VPN_REMOTE 1194/g" "$VPN_CONFIG"
	else
		echo "[info] VPN provider remote and port defined as $VPN_REMOTE $VPN_PORT"
		sed -i -e "s/remote\s.*/remote $VPN_REMOTE $VPN_PORT/g" "$VPN_CONFIG"
	fi

	# store credentials in separate file for authentication
	if ! $(grep -Fq "auth-user-pass credentials.conf" "$VPN_CONFIG"); then
		sed -i -e 's/auth-user-pass.*/auth-user-pass credentials.conf/g' "$VPN_CONFIG"
	fi

	# write vpn username to file
	if [[ -z "${VPN_USER}" ]]; then
		echo "[crit] VPN username not specified" && exit 1
	else
		echo "${VPN_USER}" > /config/openvpn/credentials.conf
	fi

	# append vpn password to file
	if [[ -z "${VPN_PASS}" ]]; then
		echo "[crit] VPN password not specified" && exit 1
	else
		echo "${VPN_PASS}" >> /config/openvpn/credentials.conf
	fi

# if provider none of the above then exit
else
	echo "[crit] VPN provider unknown, please specify airvpn, pia, or custom" && exit 1
fi

# customise openvpn.ovpn to ping tunnel every 5 mins
if ! $(grep -Fxq "ping 300" "$VPN_CONFIG"); then
	sed -i '/remote\s.*/a ping 300' "$VPN_CONFIG"
fi

# customise openvpn.ovpn to restart tunnel after 10 mins if no reply from ping (twice)
if ! $(grep -Fxq "ping-restart 600" "$VPN_CONFIG"); then
	sed -i '/ping 300/a ping-restart 600' "$VPN_CONFIG"
fi

# read port number and protocol from openvpn.ovpn (used to define iptables rule)
VPN_PORT=$(cat "$VPN_CONFIG" | grep -P -o -m 1 '^remote\s[^\r\n]+' | grep -P -o -m 1 '[\d]+$')
VPN_PROTOCOL=$(cat "$VPN_CONFIG" | grep -P -o -m 1 '(?<=proto\s)[^\r\n]+')

# set permissions to user nobody
chown -R nobody:users /config/openvpn
chmod -R 775 /config/openvpn

# create the tunnel device
[ -d /dev/net ] || mkdir -p /dev/net
[ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200

# get ip for local gateway (eth0)
DEFAULT_GATEWAY=$(ip route show default | awk '/default/ {print $3}')

# add route for ns lookup via eth0 (required when tunnel down)
ip route add 8.8.8.8/32 via $DEFAULT_GATEWAY
ip route add 8.8.4.4/32 via $DEFAULT_GATEWAY

# get ip (might be list) for remote gateway (tunnel)
REMOTE_GATEWAY=$(getent hosts $VPN_REMOTE | cut -d' ' -f1)

# if REMOTE_GATEWAY is empty then assume VPN_REMOTE is specific ip address
if [[ -z "${REMOTE_GATEWAY}" ]]; then
	ip route add $VPN_REMOTE via $DEFAULT_GATEWAY

# add route to remote gateway subnet via eth0 (required when tunnel down)
else

	for REMOTE_GATEWAY_IP in $REMOTE_GATEWAY; do

		REMOTE_GATEWAY_SUBNET=$(echo $REMOTE_GATEWAY_IP | grep -P -o -m 1 '[\d]{1,3}\.[\d]{1,3}\.')
		REMOTE_GATEWAY_SUBNET+="0.0/16"
		ip route add $REMOTE_GATEWAY_SUBNET via $DEFAULT_GATEWAY

	done

fi

# setup route for deluge webui using set-mark to route traffic for port 8112 to eth0
echo "8112    webui" >> /etc/iproute2/rt_tables
ip rule add fwmark 1 table webui
ip route add default via $DEFAULT_GATEWAY table webui

# setup route for privoxy using set-mark to route traffic for port 8118 to eth0
if [[ $ENABLE_PRIVOXY == "yes" ]]; then
	echo "8118    privoxy" >> /etc/iproute2/rt_tables
	ip rule add fwmark 2 table privoxy
	ip route add default via $DEFAULT_GATEWAY table privoxy
fi

echo "[info] ip route"
ip route
echo "--------------------"

# input iptable rules
###

# set policy to drop for input
iptables -P INPUT DROP

# accept input to tunnel adapter
iptables -A INPUT -i tun0 -j ACCEPT

# accept input to vpn gateway
iptables -A INPUT -i eth0 -p $VPN_PROTOCOL --sport $VPN_PORT -j ACCEPT

# accept input to deluge webui port 8112
iptables -A INPUT -i eth0 -p tcp --dport 8112 -j ACCEPT
iptables -A INPUT -i eth0 -p tcp --sport 8112 -j ACCEPT

# accept input to privoxy port 8118
iptables -A INPUT -i eth0 -p tcp --dport 8118 -j ACCEPT
iptables -A INPUT -i eth0 -p tcp --sport 8118 -j ACCEPT

# accept input dns lookup
iptables -A INPUT -p udp --sport 53 -j ACCEPT

# accept input icmp (ping)
iptables -A INPUT -p icmp --icmp-type echo-reply -j ACCEPT

# accept input to local loopback
iptables -A INPUT -i lo -j ACCEPT

# output iptable rules
###

# set policy to drop for output
iptables -P OUTPUT DROP

# accept output to tunnel adapter
iptables -A OUTPUT -o tun0 -j ACCEPT

# accept output to vpn gateway
iptables -A OUTPUT -o eth0 -p $VPN_PROTOCOL --dport $VPN_PORT -j ACCEPT

# accept output to deluge webui port 8112 (used when tunnel down)
iptables -A OUTPUT -o eth0 -p tcp --dport 8112 -j ACCEPT
iptables -A OUTPUT -o eth0 -p tcp --sport 8112 -j ACCEPT

# accept output to deluge webui port 8112 (used when tunnel up)
iptables -t mangle -A OUTPUT -p tcp --dport 8112 -j MARK --set-mark 1
iptables -t mangle -A OUTPUT -p tcp --sport 8112 -j MARK --set-mark 1

# accept output to privoxy port 8118 (used when tunnel up)
iptables -t mangle -A OUTPUT -p tcp --dport 8118 -j MARK --set-mark 2
iptables -t mangle -A OUTPUT -p tcp --sport 8118 -j MARK --set-mark 2

# accept output dns lookup
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT

# accept output icmp (ping)
iptables -A OUTPUT -p icmp --icmp-type echo-request -j ACCEPT

# accept output to local loopback
iptables -A OUTPUT -o lo -j ACCEPT

echo "[info] iptables"
iptables -S
echo "--------------------"

# add in google public nameservers (isp may block ns lookup when connected to vpn)
echo 'nameserver 8.8.8.8' > /etc/resolv.conf
echo 'nameserver 8.8.4.4' >> /etc/resolv.conf

echo "[info] nameservers"
cat /etc/resolv.conf
echo "--------------------"

# start openvpn tunnel
source /root/openvpn.sh