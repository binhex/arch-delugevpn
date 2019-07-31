#!/bin/bash

# change openvpn config 'tcp-client' to compatible iptables 'tcp'
if [[ "${VPN_PROTOCOL}" == "tcp-client" ]]; then
	export VPN_PROTOCOL="tcp"
fi

# identify docker bridge interface name (probably "${docker_interface}")
docker_interface=$(netstat -ie | grep -vE "lo|tun|tap" | sed -n '1!p' | grep -P -o -m 1 '^[^:]+')
if [[ "${DEBUG}" == "true" ]]; then
	echo "[debug] Docker interface defined as ${docker_interface}"
fi

# identify ip for docker bridge interface
docker_ip=$(ifconfig "${docker_interface}" | grep -P -o -m 1 '(?<=inet\s)[^\s]+')
if [[ "${DEBUG}" == "true" ]]; then
	echo "[debug] Docker IP defined as ${docker_ip}"
fi

# identify netmask for docker bridge interface
docker_mask=$(ifconfig "${docker_interface}" | grep -P -o -m 1 '(?<=netmask\s)[^\s]+')
if [[ "${DEBUG}" == "true" ]]; then
	echo "[debug] Docker netmask defined as ${docker_mask}"
fi

# convert netmask into cidr format
docker_network_cidr=$(ipcalc "${docker_ip}" "${docker_mask}" | grep -P -o -m 1 "(?<=Network:)\s+[^\s]+")
echo "[info] Docker network defined as ${docker_network_cidr}"

# ip route
###

# split comma separated string into list from LAN_NETWORK env variable
IFS=',' read -ra lan_network_list <<< "${LAN_NETWORK}"

# process lan networks in the list
for lan_network_item in "${lan_network_list[@]}"; do

	# strip whitespace from start and end of lan_network_item
	lan_network_item=$(echo "${lan_network_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

	echo "[info] Adding ${lan_network_item} as route via docker ${docker_interface}"
	ip route add "${lan_network_item}" via "${DEFAULT_GATEWAY}" dev "${docker_interface}"

done

echo "[info] ip route defined as follows..."
echo "--------------------"
ip route
echo "--------------------"

# setup iptables marks to allow routing of defined ports via lan interface
###

if [[ "${DEBUG}" == "true" ]]; then
	echo "[debug] Modules currently loaded for kernel" ; lsmod
fi

# check we have iptable_mangle, if so setup fwmark
lsmod | grep iptable_mangle
iptable_mangle_exit_code=$?

if [[ $iptable_mangle_exit_code == 0 ]]; then

	echo "[info] iptable_mangle support detected, adding fwmark for tables"

	# setup route for deluge webui using set-mark to route traffic for port 8112 to eth0
	echo "8112    webui" >> /etc/iproute2/rt_tables
	ip rule add fwmark 1 table webui
	ip route add default via $DEFAULT_GATEWAY table webui

fi

# input iptable rules
###

# set policy to drop ipv4 for input
iptables -P INPUT DROP

# set policy to drop ipv6 for input
ip6tables -P INPUT DROP 1>&- 2>&-

# accept input to tunnel adapter
iptables -A INPUT -i "${VPN_DEVICE_TYPE}" -j ACCEPT

# accept input to/from docker containers (172.x range is internal dhcp)
iptables -A INPUT -s "${docker_network_cidr}" -d "${docker_network_cidr}" -j ACCEPT

# accept input to vpn gateway
iptables -A INPUT -i "${docker_interface}" -p $VPN_PROTOCOL --sport $VPN_PORT -j ACCEPT

# accept input to deluge Web UI port 8112
iptables -A INPUT -i "${docker_interface}" -p tcp --dport 8112 -j ACCEPT
iptables -A INPUT -i "${docker_interface}" -p tcp --sport 8112 -j ACCEPT

# process lan networks in the list
for lan_network_item in "${lan_network_list[@]}"; do

	# strip whitespace from start and end of lan_network_item
	lan_network_item=$(echo "${lan_network_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

	# accept input to deluge daemon port - used for lan access
	iptables -A INPUT -i "${docker_interface}" -s "${lan_network_item}" -p tcp --dport 58846 -j ACCEPT

	# accept input for web traffic on the lan - used for the execute plugin 
	iptables -A INPUT -i "${docker_interface}" -s "${lan_network_item}" -p tcp --sport 80 -m state --state RELATED,ESTABLISHED -j ACCEPT
	iptables -A INPUT -i "${docker_interface}" -s "${lan_network_item}" -p tcp --sport 443 -m state --state RELATED,ESTABLISHED -j ACCEPT


	# accept input to privoxy if enabled
	if [[ $ENABLE_PRIVOXY == "yes" ]]; then
		iptables -A INPUT -i "${docker_interface}" -p tcp -s "${lan_network_item}" -d "${docker_network_cidr}" -j ACCEPT
	fi

done

# accept input icmp (ping)
iptables -A INPUT -p icmp --icmp-type echo-reply -j ACCEPT

# accept input to local loopback
iptables -A INPUT -i lo -j ACCEPT

# forward iptable rules
###

# set policy to drop ipv4 for forward
iptables -P FORWARD DROP

# set policy to drop ipv6 for forward
ip6tables -P FORWARD DROP 1>&- 2>&-

# output iptable rules
###

# set policy to drop ipv4 for output
iptables -P OUTPUT DROP

# set policy to drop ipv6 for output
ip6tables -P OUTPUT DROP 1>&- 2>&-

# accept output to/from docker containers (172.x range is internal dhcp)
iptables -A OUTPUT -s "${docker_network_cidr}" -d "${docker_network_cidr}" -j ACCEPT

# accept output from vpn gateway
iptables -A OUTPUT -o "${docker_interface}" -p $VPN_PROTOCOL --dport $VPN_PORT -j ACCEPT

# if iptable mangle is available (kernel module) then use mark
if [[ $iptable_mangle_exit_code == 0 ]]; then

	# accept output from deluge-web port 8112 - used for external access
	iptables -t mangle -A OUTPUT -p tcp --dport 8112 -j MARK --set-mark 1
	iptables -t mangle -A OUTPUT -p tcp --sport 8112 -j MARK --set-mark 1

fi

# accept output from deluge-web port 8112 - used for lan access
iptables -A OUTPUT -o "${docker_interface}" -p tcp --dport 8112 -j ACCEPT
iptables -A OUTPUT -o "${docker_interface}" -p tcp --sport 8112 -j ACCEPT

# process lan networks in the list
for lan_network_item in "${lan_network_list[@]}"; do

	# strip whitespace from start and end of lan_network_item
	lan_network_item=$(echo "${lan_network_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

	# accept output to deluge daemon port - used for lan access
	iptables -A OUTPUT -o "${docker_interface}" -d "${lan_network_item}" -p tcp --sport 58846 -j ACCEPT

	# accept output for web traffic on the lan - used for the execute plugin 
	iptables -A OUTPUT -o "${docker_interface}" -d "${lan_network_item}" -p tcp --dport 80 -j ACCEPT
	iptables -A OUTPUT -o "${docker_interface}" -d "${lan_network_item}" -p tcp --dport 443 -j ACCEPT

	# accept output from privoxy if enabled - used for lan access
	if [[ $ENABLE_PRIVOXY == "yes" ]]; then
		iptables -A OUTPUT -o "${docker_interface}" -p tcp -s "${docker_network_cidr}" -d "${lan_network_item}" -j ACCEPT
	fi

done

# accept output for icmp (ping)
iptables -A OUTPUT -p icmp --icmp-type echo-request -j ACCEPT

# accept output from local loopback adapter
iptables -A OUTPUT -o lo -j ACCEPT

# accept output from tunnel adapter
iptables -A OUTPUT -o "${VPN_DEVICE_TYPE}" -j ACCEPT

echo "[info] iptables defined as follows..."
echo "--------------------"
iptables -S 2>&1 | tee /tmp/checkiptables
chmod +r /tmp/checkiptables
echo "--------------------"

# change iptable 'tcp' to openvpn config compatible 'tcp-client' (this file is sourced)
if [[ "${VPN_PROTOCOL}" == "tcp" ]]; then
	export VPN_PROTOCOL="tcp-client"
fi
