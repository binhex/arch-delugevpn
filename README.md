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
docker run -d --cap-add=NET_ADMIN -p 8112:8112 -p 58846:58846 -p 58946:58946 --name=<container name> -v <path for data files>:/data -v <path for config files>:/config -v /etc/localtime:/etc/localtime:ro -e PIA_USER=<pia username> -e PIA_PASS=<pia password> binhex/arch-delugevpn
```

Please replace all user variables in the above command defined by <> with the correct values.

**Access application**

```
http://<host ip>:8112
```

Default password for the webui is "deluge"
