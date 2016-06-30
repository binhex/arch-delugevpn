#!/bin/bash

# exit script if return code != 0
set -e

# define pacman packages
pacman_packages="unzip unrar pygtk python2-service-identity python2-mako python2-notify gnu-netcat"

# install pre-reqs
pacman -S --needed $pacman_packages --noconfirm

# call aor script (arch official repo)
source /root/aor.sh

# remove faulty scheduler plugin (bug with 1.3.12 release)
rm -f /usr/lib/python2.7/site-packages/deluge/plugins/Scheduler-0.2-py2.7.egg

# install patched schedulder plugin from github (remove this for 1.3.13+ release)
curl -L -o "/usr/lib/python2.7/site-packages/deluge/plugins/Scheduler-0.2-py2.7.egg" "https://github.com/binhex/arch-patches/raw/master/arch-deluge/plugins/scheduler/Scheduler-0.2-py2.7.egg"

# cleanup
yes|pacman -Scc
rm -rf /usr/share/locale/*
rm -rf /usr/share/man/*
rm -rf /tmp/*
