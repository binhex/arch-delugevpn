#!/bin/bash

# create directory
mkdir -p /config/openvpn
	
if [[ -z "${VPN_PROV}" ]]; then
	echo "[info] VPN provider not defined, please specify via env variable VPN_PROV"	
fi

# wildcard search for openvpn config files
OPENVPN_CONFIG=$(find /config/openvpn -maxdepth 1 \( -name "*.ovpn" -o -name "*.conf" \) -print)

# if pia vpn provider choosen then copy base config file and pia certs
if [[ $VPN_PROV == "pia" ]]; then

	echo "[info] VPN provider defined as $VPN_PROV"	
	cp -f /home/nobody/ca.crt /config/openvpn/ca.crt
	cp -f /home/nobody/crl.pem /config/openvpn/crl.pem
	
	if [[ -z "${OPENVPN_CONFIG}" ]]; then
		cp -f "/home/nobody/openvpn.conf" "/config/openvpn/openvpn.conf"
		
		if [[ -z "${VPN_REMOTE}" || -z "${VPN_PORT}" ]]; then
			echo "[warn] VPN provider remote and/or port not defined, defaulting to Netherlands"
			sed -i -e "s/remote.*/remote nl.privateinternetaccess.com 1194/g" "/config/openvpn/openvpn.conf"
		else
			echo "[info] VPN provider remote and port defined as $VPN_REMOTE $VPN_PORT"
			sed -i -e "s/remote.*/remote $VPN_REMOTE $VPN_PORT/g" "/config/openvpn/openvpn.conf"
		fi		
		
		if ! $(grep -Fxq "auth-user-pass credentials.conf" /config/openvpn/openvpn.conf); then
			sed -i -e 's/auth-user-pass/auth-user-pass credentials.conf/g' /config/openvpn/openvpn.conf
		fi			
		
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
	
fi

# if custom|airvpn vpn provider chosen then do not copy base config file
if [[ $VPN_PROV == "custom" || $VPN_PROV == "airvpn" ]]; then
	echo "[info] VPN provider defined as $VPN_PROV"
	if [[ -z "${OPENVPN_CONFIG}" ]]; then
		echo "[crit] VPN provider defined as $VPN_PROV, OpenVPN config files does not exist in /config/openvpn/ please create and restart delugevpn" && exit 1
	fi
fi

# customise openvpn.conf to ping tunnel every 10 mins
if ! $(grep -Fxq "ping 600" $OPENVPN_CONFIG); then
	sed -i '/crl-verify crl.pem/a ping 600' $OPENVPN_CONFIG
fi

# customise openvpn.conf to restart tunnel after 20 mins if no reply from ping
if ! $(grep -Fxq "ping-restart 1200" $OPENVPN_CONFIG); then
	sed -i '/ping 600/a ping-restart 1200' $OPENVPN_CONFIG
fi

# read port number and protocol from openvpn.conf (used to define iptables rule)
VPN_PORT=$(cat $OPENVPN_CONFIG | grep -P -o -m 1 '^remote[^\r\n]+' | grep -P -o -m 1 '[\d]+$')
VPN_PROTOCOL=$(cat $OPENVPN_CONFIG | grep -P -o -m 1 '(?<=proto\s)[^\r\n]+')
	
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

# setup route for privoxy using set-mark to route traffic for port 8118 to eth0
if [[ $ENABLE_PRIVOXY == "yes" ]]; then
	echo "8118    privoxy" >> /etc/iproute2/rt_tables
	ip rule add fwmark 2 table privoxy
	ip route add default via $DEFAULT_GATEWAY table privoxy
fi
	
echo "[info] ip route"
ip route
echo "--------------------"

# set policy to drop for input
iptables -P INPUT DROP

# accept input to tunnel adapter
iptables -A INPUT -i tun0 -j ACCEPT

# accept input to vpn gateway
iptables -A INPUT -p $VPN_PROTOCOL -i eth0 --sport $VPN_PORT -j ACCEPT

# accept input to deluge webui port 8112
iptables -A INPUT -p tcp -i eth0 --dport 8112 -j ACCEPT
iptables -A INPUT -p tcp -i eth0 --sport 8112 -j ACCEPT

# accept input to privoxy port 8118
iptables -A INPUT -p tcp -i eth0 --dport 8118 -j ACCEPT
iptables -A INPUT -p tcp -i eth0 --sport 8118 -j ACCEPT
	
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
iptables -A OUTPUT -p $VPN_PROTOCOL -o eth0 --dport $VPN_PORT -j ACCEPT

# accept output to deluge webui port 8112 (used when tunnel down)
iptables -A OUTPUT -p tcp -o eth0 --dport 8112 -j ACCEPT
iptables -A OUTPUT -p tcp -o eth0 --sport 8112 -j ACCEPT

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

# add in google public nameservers (isp may block lookup when connected to vpn)
echo 'nameserver 8.8.8.8' > /etc/resolv.conf
echo 'nameserver 8.8.4.4' >> /etc/resolv.conf

echo "[info] nameservers"
cat /etc/resolv.conf
echo "--------------------"

# start openvpn tunnel
source /root/openvpn.sh