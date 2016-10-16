#!/bin/bash

# exit script if return code != 0
set -e

# define pacman packages
pacman_packages="unzip unrar pygtk python2-service-identity python2-mako python2-notify gnu-netcat"

# install pre-reqs
pacman -S --needed $pacman_packages --noconfirm

# call aor script (arch official repo)
#source /root/aor.sh

# manually download stable package from binhex repo
curl -o /tmp/deluge-1.3.11-3-any.pkg.tar.xz -L https://github.com/binhex/arch-packages/raw/master/compiled/deluge-1.3.13-1-any.pkg.tar.xz
pacman -U /tmp/deluge-1.3.11-3-any.pkg.tar.xz --noconfirm

# manually remove .dev0 from compiled package name (is a result of pull commit from github)
mv "/usr/lib/python2.7/site-packages/deluge-1.3.13.dev0-py2.7.egg-info/" "/usr/lib/python2.7/site-packages/deluge-1.3.13-py2.7.egg-info/"
sed -i -e 's~\.dev0~~g' "/usr/lib/python2.7/site-packages/deluge-1.3.13-py2.7.egg-info/PKG-INFO" "/usr/bin/deluge" "/usr/bin/deluge-console" "/usr/bin/deluged" "/usr/bin/deluge-gtk" "/usr/bin/deluge-web"

# cleanup
yes|pacman -Scc
rm -rf /usr/share/locale/*
rm -rf /usr/share/man/*
rm -rf /tmp/*
