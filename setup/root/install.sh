#!/bin/bash

# exit script if return code != 0
set -e

# define pacman packages
pacman_packages="unzip unrar pygtk python2-service-identity python2-mako python2-notify gnu-netcat python2-pip nano gcc pkg-config"

# install pre-reqs
pacman -S --needed $pacman_packages --noconfirm

#install flextget
pip2 install --upgrade pip
pip2 install --upgrade --force-reinstall requests[security]
pip2 install --upgrade setuptools
pip2 install --upgrade flexget

# call aor script (arch official repo) - commented out for now to force non dev version, remove comment and deluge from above packages list once official release out
source /root/aor.sh

# cleanup
yes|pacman -Rs gcc
yes|pacman -Scc
rm -rf /usr/share/locale/*
rm -rf /usr/share/man/*
rm -rf /tmp/*
