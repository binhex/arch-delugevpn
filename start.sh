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
	
	# write pia username and password to file
	if [ ! -f /config/openvpn/credentials.conf ]; then
		[ -z "${PIA_USER}" ] && echo "[crit] PIA username not specified" && exit 1
		[ -z "${PIA_PASS}" ] && echo "[crit] PIA password not specified" && exit 1
		echo "${PIA_USER}" > /config/openvpn/credentials.conf
		echo "${PIA_PASS}" >> /config/openvpn/credentials.conf
	fi
	
	touch /root/runonce
	
fi

# create pia client id (randomly generated)
CLIENT_ID=`head -n 100 /dev/urandom | md5sum | tr -d " -"`
echo "[info] PIA client set to $CLIENT_ID"

# save values as env variables
export CLIENT_ID=$CLIENT_ID

# create the tunnel device
[ -d /dev/net ] || mkdir -p /dev/net
[ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200

# setup route for deluge webui
DEFAULT_GATEWAY=$(ip route show default | awk '/default/ {print $3}')

if [ -z "${HOST_SUBNET}" ]; then
	echo "[warn] HOST_SUBNET not specified, deluge web interface will not work"
else
	ip route add $HOST_SUBNET via $DEFAULT_GATEWAY
fi

echo "[info] current route"
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

echo "[info] iptables defined"

# add in google public nameservers (isp ns may block lookup when connected to vpn)
echo '8.8.8.8' >> /etc/resolv.conf
echo '8.8.4.4' >> /etc/resolv.conf

echo "[info] nameservers defined"

# run openvpn to create tunnel
/usr/bin/openvpn --cd /config --config /config/openvpn/openvpn.conf --redirect-gateway