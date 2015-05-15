Deluge + OpenVPN + Privoxy
==========================

Deluge - http://deluge-torrent.org/
OpenVPN - https://openvpn.net/
Privoxy - http://www.privoxy.org/

Latest stable Deluge release for Arch Linux, including OpenVPN to tunnel torrent traffic securely (using iptables to block any traffic not bound for tunnel). This now also includes Privoxy to allow unfiltered http|https traffic via VPN.

**Pull image**

```
docker pull binhex/arch-delugevpn
```

**Run container**

```
docker run -d --cap-add=NET_ADMIN -p 8112:8112 -p 8118:8118 --name=<container name> -v <path for data files>:/data -v <path for config files>:/config -v /etc/localtime:/etc/localtime:ro -e VPN_ENABLED=<yes|no> -e VPN_USER=<vpn username> -e VPN_PASS=<vpn password> -e VPN_REMOTE=<vpn remote gateway> -e VPN_PORT=<vpn remote port> -e VPN_PROV=<pia|airvpn|custom> -e ENABLE_PRIVOXY=<yes|no> binhex/arch-delugevpn
```

Please replace all user variables in the above command defined by <> with the correct values.

**Access Deluge**

```
http://<host ip>:8112
```

Default password for the webui is "deluge"

**Access Privoxy**

```
<host ip>:8118
```

Default is no authentication required

**PIA user**

PIA users will need to supply VPN_USER and VPN_PASS, optionally define VPN_REMOTE (list of gateways https://www.privateinternetaccess.com/pages/client-support/#signup) if you wish to use another remote gateway other than the Netherlands.

**Example**

```
docker run -d --cap-add=NET_ADMIN -p 8112:8112 -p 8118:8118 --name=delugevpn -v /root/docker/data:/data -v /root/docker/config:/config -v /etc/localtime:/etc/localtime:ro -e VPN_ENABLED=yes -e VPN_USER=myusername -e VPN_PASS=mypassword -e VPN_REMOTE=nl.privateinternetaccess.com -e VPN_PORT=1194 -e VPN_PROV=pia -e ENABLE_PRIVOXY=yes binhex/arch-delugevpn
```

**AirVPN user**

AirVPN users will need to generate a unique OpenVPN configuration file by using the following link https://airvpn.org/generator/

1. Please select Linux and then choose the country you want to connect to
2. Save the ovpn file to somewhere safe
3. Start the delugevpn docker to create the folder structure
4. Stop delugevpn docker and copy the saved ovpn file to the /config/openvpn/ folder on the host
5. Start delugevpn docker
6. Check supervisor.log to make sure you are connected to the tunnel

**Example**

```
docker run -d --cap-add=NET_ADMIN -p 8112:8112 -p 8118:8118 --name=delugevpn -v /root/docker/data:/data -v /root/docker/config:/config -v /etc/localtime:/etc/localtime:ro -e VPN_ENABLED=yes -e VPN_PROV=airvpn -e ENABLE_PRIVOXY=yes binhex/arch-delugevpn
```
