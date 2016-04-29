#!/bin/bash

# exit script if return code != 0
set -e

# define pacman packages
pacman_packages="unzip unrar pygtk python2-service-identity python2-mako python2-notify gnu-netcat python2-pip nano"

# install pre-reqs
pacman -S --needed $pacman_packages --noconfirm

# remove faulty scheduler plugin (bug with 1.3.12 release)
rm -f /usr/lib/python2.7/site-packages/deluge/plugins/Scheduler-0.2-py2.7.egg

#install flextget
pip2 install --upgrade pip
pip2 install --upgrade --force-reinstall requests[security]
pip2 install --upgrade setuptools
pip2 install --upgrade flexget

# call aor script (arch official repo)
source /root/aor.sh

# cleanup
yes|pacman -Scc
rm -rf /usr/share/locale/*
rm -rf /usr/share/man/*
rm -rf /tmp/*
