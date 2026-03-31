#!/usr/bin/dumb-init /bin/bash

# create folders if they don't exist
if [[ ! -d /skins ]]; then
	echo "[info] /skins folder doesn't exist, creating..."
    mkdir /skins
    mkdir /skins/themes
    mkdir /skins/icons
    mkdir /skins/images
fi

# cleanup broken symlinks
echo "[info] Cleaning up old custom deluge web ui skin symlinks"
find /usr/lib/python3.12/site-packages/deluge/ui/web/themes/ -type l -exec unlink {} \;
find /usr/lib/python3.12/site-packages/deluge/ui/web/icons/ -type l -exec unlink {} \;
find /usr/lib/python3.12/site-packages/deluge/ui/web/images/ -type l -exec unlink {} \;

# map current skin files to repective deluge web ui folders
echo "[info] Creating new custom deluge web ui skin symlinks"
cp -rs /skins/themes /usr/lib/python3.12/site-packages/deluge/ui/web/
cp -rs /skins/icons /usr/lib/python3.12/site-packages/deluge/ui/web/
cp -rs /skins/images /usr/lib/python3.12/site-packages/deluge/ui/web/