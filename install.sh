#!/bin/bash

# exit script if return code != 0
set -e

# define pacman packages
pacman_packages="unzip unrar librsvg pygtk python2-service-identity python2-mako python2-notify"

# install pre-reqs
pacman -Sy --noconfirm
pacman -S --needed $pacman_packages --noconfirm

# download and install package
curl -L https://github.com/binhex/arch-packages/raw/master/deluge-1.3.11-3-any.pkg.tar.xz -o /tmp/deluge-1.3.11-3-any.pkg.tar.xz
curl -L https://github.com/binhex/arch-packages/raw/master/deluge-1.3.11-3-any.pkg.tar.xz.sig -o /tmp/deluge-1.3.11-3-any.pkg.tar.xz.sig
pacman -U /tmp/deluge-1.3.11-3-any.pkg.tar.xz --noconfirm

# set permissions
chown -R nobody:users /home/nobody /usr/bin/deluged /usr/bin/deluge-web
chmod -R 775 /home/nobody /usr/bin/deluged /usr/bin/deluge-web

# cleanup
yes|pacman -Scc
rm -rf /usr/share/locale/*
rm -rf /usr/share/man/*
rm -rf /tmp/*
