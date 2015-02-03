Deluge
======

Deluge - http://deluge-torrent.org/

Latest stable Deluge release for Arch Linux.

**Pull image**

```
docker pull binhex/arch-deluge
```

**Run container**

```
docker run -d -p 8112:8112 -p 58846:58846 -p 58946:58946 --name=<container name> -v <path for data files>:/data -v <path for config files>:/config -v /etc/localtime:/etc/localtime:ro binhex/arch-deluge
```

Please replace all user variables in the above command defined by <> with the correct values.

**Access application**

```
http://<host ip>:8112
```

Default password for the webui is "deluge"
