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
docker run -d --cap-add=NET_ADMIN -p 8112:8112 -p 8118:8118 --name=<container name> -v <path for data files>:/data -v <path for config files>:/config -v /etc/localtime:/etc/localtime:ro -e VPN_USER=<vpn username> -e VPN_PASS=<vpn password> -e VPN_REMOTE=<vpn remote gateway> -e VPN_PORT=<vpn remote port> -e VPN_PROV=<pia|custom> -e ENABLE_PRIVOXY=<yes|no> binhex/arch-delugevpn
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

**Example command**

```
docker run -d --cap-add=NET_ADMIN -p 8112:8112 -p 8118:8118 --name=delugevpn -v /root/docker/data:/data -v /root/docker/config:/config -v /etc/localtime:/etc/localtime:ro -e VPN_USER=myusername -e VPN_PASS=mypassword -e VPN_REMOTE=nl.privateinternetaccess.com -e VPN_PORT=1194 -e VPN_PROV=pia -e ENABLE_PRIVOXY=yes binhex/arch-delugevpn
```

**IMPORTANT**

This Docker relies on a VPN connection, please sign-up with a VPN provider.
