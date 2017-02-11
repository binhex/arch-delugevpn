#!/bin/bash

# exit script if return code != 0
set -e

# define pacman packages
pacman_packages="unzip unrar pygtk python2-service-identity python2-mako python2-notify gnu-netcat python2-pip nano gcc pkg-config freetype2"

# install pre-reqs
pacman -S --needed $pacman_packages --noconfirm

#install flextget
pip2 install --upgrade pip
pip2 install --upgrade --force-reinstall requests[security]
pip2 install --upgrade setuptools
pip2 install --upgrade flexget

# call aor script (arch official repo) - commented out for now to force non dev version, remove comment and deluge from above packages list once official release out
#source /root/aor.sh

# manually download stable package from binhex repo
curl -o /tmp/deluge-1.3.11-3-any.pkg.tar.xz -L https://github.com/binhex/arch-packages/raw/master/compiled/deluge-1.3.13-1-any.pkg.tar.xz
pacman -U /tmp/deluge-1.3.11-3-any.pkg.tar.xz --noconfirm

# manually remove .dev0 from compiled package name (is a result of pull commit from github)
mv "/usr/lib/python2.7/site-packages/deluge-1.3.13.dev0-py2.7.egg-info/" "/usr/lib/python2.7/site-packages/deluge-1.3.13-py2.7.egg-info/"
sed -i -e 's~\.dev0~~g' "/usr/lib/python2.7/site-packages/deluge-1.3.13-py2.7.egg-info/PKG-INFO" "/usr/bin/deluge" "/usr/bin/deluge-console" "/usr/bin/deluged" "/usr/bin/deluge-gtk" "/usr/bin/deluge-web"
 
cat <<EOF >> /root/init.sh
echo "[info] Setting permissions on files/folders inside container..." | ts '%Y-%m-%d %H:%M:%.S'
chown -R "${PUID}":"${PGID}" /usr/bin/deluged /usr/bin/deluge-web /usr/bin/privoxy /etc/privoxy /home/nobody /home/nobody/.flexget
chmod -R 775 /usr/bin/deluged /usr/bin/deluge-web /usr/bin/privoxy /etc/privoxy /home/nobody /home/nobody/.flexget

echo "[info] Starting Supervisor..." | ts '%Y-%m-%d %H:%M:%.S'
exec /usr/bin/supervisord -c /etc/supervisor.conf -n
EOF

# cleanup
yes|pacman -Rs gcc
yes|pacman -Scc
rm -rf /usr/share/locale/*
rm -rf /usr/share/man/*
rm -rf /tmp/*
