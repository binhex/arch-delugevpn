Deluge + OpenVPN
================

Deluge - http://deluge-torrent.org/

OpenVPN - https://openvpn.net/

Latest stable Deluge release for Arch Linux, including OpenVPN to tunnel torrent traffic securely (using iptables to block any traffic not bound for tunnel).

**Pull image**

```
docker pull binhex/arch-delugevpn
```

**Run container**

```
docker run -d --cap-add=NET_ADMIN -p 8112:8112 --name=<container name> -v <path for data files>:/data -v <path for config files>:/config -v /etc/localtime:/etc/localtime:ro -e PIA_USER=<pia username> -e PIA_PASS=<pia password>  -e PIA_REMOTE=<pia remote gateway> binhex/arch-delugevpn
```

Please replace all user variables in the above command defined by <> with the correct values.

IMPORTANT - This Docker relies on a VPN connection to PIA (PrivateInternetAccess), please sign-up and enter your credentials in the above run command. The environment variable PIA_REMOTE allows you to define the country you want the tunnel connected to, choices are:- UK London, UK Southampton, US California, US East, US Florida, US Midwest, US Seattle, US Texas, US West, Australia, CA North York, CA Toronto, France, Germany, Hong Kong, Israel, Japan, Netherlands, Romania, Sweden, Switzerland.

**Access application**

```
http://<host ip>:8112
```

Default password for the webui is "deluge"
