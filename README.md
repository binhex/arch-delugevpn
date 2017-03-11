This is a fork of the fine work of Binhex at https://github.com/binhex/arch-delugevpn

**Application**

[Flexget website](http://flexget.com/)    
[Deluge website](http://deluge-torrent.org/) 

[OpenVPN website](https://openvpn.net/)  
[Privoxy website](http://www.privoxy.org/)

**Description Binhex's DelugeVPN**

Deluge is a full-featured ​BitTorrent client for Linux, OS X, Unix and Windows. It uses ​libtorrent in its backend and features multiple user-interfaces including: GTK+, web and console. It has been designed using the client server model with a daemon process that handles all the bittorrent activity. The Deluge daemon is able to run on headless machines with the user-interfaces being able to connect remotely from any platform. This Docker includes OpenVPN to ensure a secure and private connection to the Internet, including use of iptables to prevent IP leakage when the tunnel is down. It also includes Privoxy to allow unfiltered access to index sites, to use Privoxy please point your application at `http://<host ip>:8118`.

**Description Flexget with webui daemon**

FlexGet is a multipurpose automation tool for content like torrents, nzbs, podcasts, comics, series, movies, etc. It can use different kinds of sources like RSS-feeds, html pages, csv files, search engines and there are even plugins for sites that do not provide any kind of useful feeds.  There are numerous plugins that allow utilizing FlexGet in interesting ways and more are being added continuously.  FlexGet is extremely useful in conjunction with applications which have watch directory support or provide interface for external utilities like FlexGet.

**Access Flexget-webui** [password is flexpass]

 Change passord with:   

    docker exec -it paulpoco-delugevpn /bin/bash
    flexget web passwd <some_password>  #from inside container

`http://<host ip>:3539`

**Build notes**

Latest stable Deluge release from Arch Linux repo.
Latest stable OpenVPN release from Arch Linux repo.
Latest stable Privoxy release from Arch Linux repo.
Latest stable Flexget release from Python.

**Usage**
```
docker run -d \
    --cap-add=NET_ADMIN \
    -p 8112:8112 \
    -p 8118:8118 \
    -p 58846:58846 \
    -p 58946:58946 \
    --name=<container name> \
    -v <path for data files>:/data \
    -v <path for config files>:/config \
    -v /etc/localtime:/etc/localtime:ro \
    -e VPN_ENABLED=<yes|no> \
    -e VPN_USER=<vpn username> \
    -e VPN_PASS=<vpn password> \
    -e VPN_REMOTE=<vpn remote gateway> \
    -e VPN_PORT=<vpn remote port> \
    -e VPN_PROTOCOL=<vpn remote protocol> \
    -e VPN_DEVICE_TYPE=<tun|tap> \
    -e VPN_PROV=<pia|airvpn|custom> \
    -e ENABLE_PRIVOXY=<yes|no> \
    -e LAN_NETWORK=<lan ipv4 network>/<cidr notation> \
    -e NAME_SERVERS=<name server ip(s)> \
    -e DEBUG=<true|false> \
    -e UMASK=<umask for created files> \
    -e PUID=<UID for user> \
    -e PGID=<GID for user> \
    binhex/arch-delugevpn
```

Please replace all user variables in the above command defined by <> with the correct values.

**Access Deluge**

`http://<host ip>:8112`

**Access Privoxy**

`http://<host ip>:8118`

**PIA provider**

PIA users will need to supply VPN_USER and VPN_PASS, optionally define VPN_REMOTE (list of gateways https://www.privateinternetaccess.com/pages/client-support) if you wish to use another remote gateway other than the Netherlands.

**PIA example**
```
 docker run -d \
     --cap-add=NET_ADMIN \
     -p 8112:8112 \
     -p 8118:8118 \
     -p 58846:58846 \
     -p 58946:58946 \
     --name=delugevpn \
     -v /apps/docker/deluge/data:/data \
     -v /apps/docker/deluge/config:/config \
     -v /etc/localtime:/etc/localtime:ro \
     -e VPN_ENABLED=yes \
     -e VPN_USER=myusername \
     -e VPN_PASS=mypassword \
     -e VPN_REMOTE=nl.privateinternetaccess.com \
     -e VPN_PORT=1198 \
     -e VPN_PROTOCOL=udp \
     -e VPN_DEVICE_TYPE=tun \
     -e VPN_PROV=pia \
     -e STRONG_CERTS=no \
     -e ENABLE_PRIVOXY=yes \
     -e LAN_NETWORK=192.168.1.0/24 \
     -e NAME_SERVERS=8.8.8.8,8.8.4.4 \
     -e DEBUG=false \
     -e UMASK=000 \
     -e PUID=0 \
     -e PGID=0 \
     binhex/arch-delugevpn
```

**AirVPN provider**

AirVPN users will need to generate a unique OpenVPN configuration file by using the following link https://airvpn.org/generator/

1. Please select Linux and then choose the country you want to connect to
2. Save the ovpn file to somewhere safe
3. Start the delugevpn docker to create the folder structure
4. Stop delugevpn docker and copy the saved ovpn file to the /config/openvpn/ folder on the host
5. Start delugevpn docker
6. Check supervisor.log to make sure you are connected to the tunnel

**AirVPN example**
```
 docker run -d \
     --cap-add=NET_ADMIN \
     -p 8112:8112 \
     -p 8118:8118 \
     -p 58846:58846 \
     -p 58946:58946 \
     --name=delugevpn \
     -v /apps/docker/deluge/data:/data \
     -v /apps/docker/deluge/config:/config \
     -v /etc/localtime:/etc/localtime:ro \
     -e VPN_ENABLED=yes \
     -e VPN_REMOTE=nl.vpn.airdns.org \
     -e VPN_PORT=443 \
     -e VPN_PROTOCOL=udp \
     -e VPN_DEVICE_TYPE=tun \
     -e VPN_PROV=airvpn \
     -e ENABLE_PRIVOXY=yes \
     -e LAN_NETWORK=192.168.1.0/24 \
     -e NAME_SERVERS=8.8.8.8,8.8.4.4 \
     -e DEBUG=false \
     -e UMASK=000 \
     -e PUID=0 \
     -e PGID=0 \
     binhex/arch-delugevpn
```

**Notes**

Default password for the webui is "deluge"

User ID (PUID) and Group ID (PGID) can be found by issuing the following command for the user you want to run the container as:-

```
id <username>
```
The STRONG_CERTS environment variable is used to define whether to use strong certificates and enhanced encryption ciphers when connecting to PIA (does not affect other providers).

___
If you appreciate Binhex's work, then please consider buying him a beer  :D

[![PayPal donation](https://www.paypal.com/en_US/i/btn/btn_donate_SM.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=MM5E27UX6AUU4)

[Support forum] Coming soon
