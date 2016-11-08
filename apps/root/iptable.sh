#!/bin/bash

# ip route
###

# split comma seperated string into list from LAN_NETWORK env variable
IFS=',' read -ra lan_network_list <<< "${LAN_NETWORK}"

# process lan networks in the list
for lan_network_item in "${lan_network_list[@]}"; do

	# strip whitespace from start and end of lan_network_item
	lan_network_item=$(echo "${lan_network_item}" | sed -e 's/^[ \t]*//')

	echo "[info] Adding ${lan_network_item} as route via docker eth0"
	ip route add "${lan_network_item}" via "${DEFAULT_GATEWAY}" dev eth0

done

echo "[info] ip route defined as follows..."
echo "--------------------"
ip route
echo "--------------------"


# setup iptables marks to allow routing of defined ports via eth0
###

# check kernel for iptable_mangle module
lsmod | grep "iptable_mangle" > /dev/null
iptable_mangle_exit_code=$?

if [[ "${DEBUG}" == "true" ]]; then
	echo "[debug] Modules currently loaded for kernel" ; lsmod
fi

# if iptable_mangle is not available then attempt to load module
if [[ $iptable_mangle_exit_code != 0 ]]; then

	# attempt to load module
	echo "[info] iptable_mangle module not supported, attempting to load..."
	modprobe iptable_mangle > /dev/null
	iptable_mangle_exit_code=$?
fi

# if iptable_mangle is available then set fwmark
if [[ $iptable_mangle_exit_code == 0 ]]; then

	echo "[info] iptable_mangle support detected, adding fwmark for tables"

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

else

	echo "[warn] iptable_mangle module not supported, you will not be able to connect to Deluge webui or Privoxy outside of your LAN"

fi

# input iptable rules
###

# set policy to drop for input
iptables -P INPUT DROP

# accept input to tunnel adapter
iptables -A INPUT -i "${VPN_DEVICE_TYPE}0" -j ACCEPT

# accept input to/from docker containers (172.x range is internal dhcp)
iptables -A INPUT -s 172.17.0.0/16 -d 172.17.0.0/16 -j ACCEPT

# accept input to vpn gateway
iptables -A INPUT -i eth0 -p $VPN_PROTOCOL --sport $VPN_PORT -j ACCEPT

# accept input to deluge webui port 8112
iptables -A INPUT -i eth0 -p tcp --dport 8112 -j ACCEPT
iptables -A INPUT -i eth0 -p tcp --sport 8112 -j ACCEPT

# accept input to flexget webui port 3539
iptables -A INPUT -i eth0 -p tcp --dport 3539 -j ACCEPT
iptables -A INPUT -i eth0 -p tcp --sport 3539 -j ACCEPT

# accept input to privoxy port 8118 if enabled
if [[ $ENABLE_PRIVOXY == "yes" ]]; then
	iptables -A INPUT -i eth0 -p tcp --dport 8118 -j ACCEPT
	iptables -A INPUT -i eth0 -p tcp --sport 8118 -j ACCEPT
fi

# process lan networks in the list
for lan_network_item in "${lan_network_list[@]}"; do

	# strip whitespace from start and end of lan_network_item
	lan_network_item=$(echo "${lan_network_item}" | sed -e 's/^[ \t]*//')

	# accept input to deluge daemon port - used for lan access
	iptables -A INPUT -i eth0 -s "${lan_network_item}" -p tcp --dport 58846 -j ACCEPT

done

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
iptables -A OUTPUT -o "${VPN_DEVICE_TYPE}0" -j ACCEPT

# accept output to/from docker containers (172.x range is internal dhcp)
iptables -A OUTPUT -s 172.17.0.0/16 -d 172.17.0.0/16 -j ACCEPT

# accept output from vpn gateway
iptables -A OUTPUT -o eth0 -p $VPN_PROTOCOL --dport $VPN_PORT -j ACCEPT

# if iptable mangle is available (kernel module) then use mark
if [[ $iptable_mangle_exit_code == 0 ]]; then

	# accept output from deluge webui port 8112 - used for external access
	iptables -t mangle -A OUTPUT -p tcp --dport 8112 -j MARK --set-mark 1
	iptables -t mangle -A OUTPUT -p tcp --sport 8112 -j MARK --set-mark 1

	# accept output from flexget webui port 3539 - used for external access
	iptables -t mangle -A OUTPUT -p tcp --dport 3539 -j MARK --set-mark 1
	iptables -t mangle -A OUTPUT -p tcp --sport 3539 -j MARK --set-mark 1

	# accept output from privoxy port 8118 - used for external access
	if [[ $ENABLE_PRIVOXY == "yes" ]]; then
		iptables -t mangle -A OUTPUT -p tcp --dport 8118 -j MARK --set-mark 2
		iptables -t mangle -A OUTPUT -p tcp --sport 8118 -j MARK --set-mark 2
	fi
	
fi

# accept output from deluge webui port 8112 - used for lan access
iptables -A OUTPUT -o eth0 -p tcp --dport 8112 -j ACCEPT
iptables -A OUTPUT -o eth0 -p tcp --sport 8112 -j ACCEPT

# accept output from flexget webui port 3539 - used for lan access
iptables -A OUTPUT -o eth0 -p tcp --dport 3539 -j ACCEPT
iptables -A OUTPUT -o eth0 -p tcp --sport 3539 -j ACCEPT

# accept output from privoxy port 8118 - used for lan access
if [[ $ENABLE_PRIVOXY == "yes" ]]; then
	iptables -A OUTPUT -o eth0 -p tcp --dport 8118 -j ACCEPT
	iptables -A OUTPUT -o eth0 -p tcp --sport 8118 -j ACCEPT
fi

# process lan networks in the list
for lan_network_item in "${lan_network_list[@]}"; do

	# strip whitespace from start and end of lan_network_item
	lan_network_item=$(echo "${lan_network_item}" | sed -e 's/^[ \t]*//')

	# accept output to deluge daemon port - used for lan access
	iptables -A OUTPUT -o eth0 -d "${lan_network_item}" -p tcp --sport 58846 -j ACCEPT

done

# accept output for dns lookup
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT

# accept output for icmp (ping)
iptables -A OUTPUT -p icmp --icmp-type echo-request -j ACCEPT

# accept output from local loopback adapter
iptables -A OUTPUT -o lo -j ACCEPT

echo "[info] iptables defined as follows..."
echo "--------------------"
iptables -S
echo "--------------------"
