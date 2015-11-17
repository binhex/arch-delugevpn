#!/bin/bash

# exit script if return code != 0
set -e

# define pacman packages
pacman_packages="unzip unrar librsvg pygtk python2-service-identity python2-mako python2-notify deluge"

# install pre-reqs
pacman -Syu --ignore filesystem --noconfirm
pacman -S --needed $pacman_packages --noconfirm

# set permissions
chown -R nobody:users /home/nobody /usr/bin/deluged /usr/bin/deluge-web
chmod -R 775 /home/nobody /usr/bin/deluged /usr/bin/deluge-web

# install patched deluge scheduler plugin (bug with 1.3.12 release)
curl -o /usr/lib/python2.7/site-packages/deluge/plugins/Scheduler-0.2-py2.7.egg https://github.com/binhex/arch-patches/releases/download/scheduler-0.2-py2.7/Scheduler-0.2-py2.7.egg

# cleanup
yes|pacman -Scc
rm -rf /usr/share/locale/*
rm -rf /usr/share/man/*
rm -rf /tmp/*
