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

# create file with contets of here doc
cat <<'EOF' > /tmp/permissions_heredoc
echo "[info] Setting permissions on files/folders inside container..." | ts '%Y-%m-%d %H:%M:%.S'
chown -R "${PUID}":"${PGID}" /usr/bin/deluged /usr/bin/deluge-web /usr/bin/privoxy /etc/privoxy /home/nobody
chmod -R 775 /usr/bin/deluged /usr/bin/deluge-web /usr/bin/privoxy /etc/privoxy /home/nobody

# set python.eggs folder to rx only for group and others
mkdir -p /home/nobody/.python-eggs && chmod -R 755 /home/nobody/.python-eggs

EOF

# replace permissions placeholder string with contents of file (here doc)
sed -i '/# PERMISSIONS_PLACEHOLDER/{
    s/# PERMISSIONS_PLACEHOLDER//g
    r /tmp/permissions_heredoc
}' /root/init.sh
rm /tmp/permissions_heredoc

# cleanup
yes|pacman -Scc
rm -rf /usr/share/locale/*
rm -rf /usr/share/man/*
rm -rf /tmp/*