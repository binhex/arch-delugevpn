#!/bin/bash

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

# setup route for deluge daemon using set-mark to route traffic for port 58846 to eth0
if [[ ! -z "${LAN_RANGE}" ]]; then
	echo "58846    deluged" >> /etc/iproute2/rt_tables
	ip rule add fwmark 3 table deluged
	ip route add default via $DEFAULT_GATEWAY table deluged
fi

echo "[info] ip routing table"
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

# accept input to deluge daemon port 58846 for lan range if specified
if [[ ! -z "${LAN_RANGE}" ]]; then
	iptables -A INPUT -i eth0 -m iprange --src-range $LAN_RANGE -j ACCEPT
	iptables -A INPUT -i eth0 -m iprange --dst-range $LAN_RANGE -j ACCEPT
fi

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

# accept output from deluge webui port 8112 (use mark to force connection over eth0 when tun up)
iptables -t mangle -A OUTPUT -p tcp --dport 8112 -j MARK --set-mark 1
iptables -t mangle -A OUTPUT -p tcp --sport 8112 -j MARK --set-mark 1

# accept output from privoxy port 8118 if enabled (use mark to force connection over eth0 when tun up)
if [[ $ENABLE_PRIVOXY == "yes" ]]; then
	iptables -t mangle -A OUTPUT -p tcp --dport 8118 -j MARK --set-mark 2
	iptables -t mangle -A OUTPUT -p tcp --sport 8118 -j MARK --set-mark 2
fi

# accept output from deluge daemon port 58846 for lan range if specified (use mark to force connection over eth0 when tun up)
if [[ ! -z "${LAN_RANGE}" ]]; then
	iptables -t mangle -A OUTPUT -m iprange --dst-range $LAN_RANGE -j MARK --set-mark 3
	iptables -t mangle -A OUTPUT -m iprange --src-range $LAN_RANGE -j MARK --set-mark 3
fi

# accept output for dns lookup
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT

# accept output for icmp (ping)
iptables -A OUTPUT -p icmp --icmp-type echo-request -j ACCEPT

# accept output from local loopback adapter
iptables -A OUTPUT -o lo -j ACCEPT

echo "[info] iptables"
iptables -S
echo "--------------------"
