#!/bin/bash

# ip route
###

if [[ ! -z "${LAN_NETWORK}" ]]; then

	echo "[info] Adding ${LAN_NETWORK} as route via docker eth0"
	ip route add "${LAN_NETWORK}" via "${DEFAULT_GATEWAY}" dev eth0

else

	echo "[crit] LAN network not defined, please specify via env variable LAN_NETWORK" && exit 1

fi

echo "[info] ip routes defined as follows..."
ip route
echo "--------------------"

# input iptable rules
###

# set policy to drop for input
iptables -P INPUT DROP

# accept input to tunnel adapter
iptables -A INPUT -i tun0 -j ACCEPT

# accept input to/from docker containers (172.x range is internal dhcp)
iptables -A INPUT -s 172.17.0.0/16 -d 172.17.0.0/16 -j ACCEPT

# accept input to vpn gateway
iptables -A INPUT -i eth0 -p $VPN_PROTOCOL --sport $VPN_PORT -j ACCEPT

# accept input to deluge webui port 8112
iptables -A INPUT -i eth0 -p tcp --dport 8112 -j ACCEPT
iptables -A INPUT -i eth0 -p tcp --sport 8112 -j ACCEPT

# accept input to privoxy port 8118 if enabled
if [[ $ENABLE_PRIVOXY == "yes" ]]; then
	iptables -A INPUT -i eth0 -p tcp --dport 8118 -j ACCEPT
	iptables -A INPUT -i eth0 -p tcp --sport 8118 -j ACCEPT
fi

# accept input to deluge daemon port 58846 for lan network
iptables -A INPUT -i eth0 -s "${LAN_NETWORK}" -p tcp --dport 58846 -j ACCEPT

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

# accept output from tunnel adapter
iptables -A OUTPUT -o tun0 -j ACCEPT

# accept output to/from docker containers (172.x range is internal dhcp)
iptables -A OUTPUT -s 172.17.0.0/16 -d 172.17.0.0/16 -j ACCEPT

# accept output from vpn gateway
iptables -A OUTPUT -o eth0 -p $VPN_PROTOCOL --dport $VPN_PORT -j ACCEPT

# accept output from deluge webui port 8112 (used when tunnel down)
iptables -A OUTPUT -o eth0 -p tcp --dport 8112 -j ACCEPT
iptables -A OUTPUT -o eth0 -p tcp --sport 8112 -j ACCEPT

# accept output from privoxy port 8118 (used when tunnel down)
if [[ $ENABLE_PRIVOXY == "yes" ]]; then
	iptables -A OUTPUT -o eth0 -p tcp --dport 8118 -j ACCEPT
	iptables -A OUTPUT -o eth0 -p tcp --sport 8118 -j ACCEPT
fi

# accept output to deluge daemon port 58846 for lan network
iptables -A OUTPUT -o eth0 -d "${LAN_NETWORK}" -p tcp --sport 58846 -j ACCEPT

# accept output for dns lookup
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT

# accept output for icmp (ping)
iptables -A OUTPUT -p icmp --icmp-type echo-request -j ACCEPT

# accept output from local loopback adapter
iptables -A OUTPUT -o lo -j ACCEPT

echo "[info] iptables defined as follows..."
iptables -S
echo "--------------------"
