#!/bin/bash

# exit script if return code != 0
set -e

deluge_ver="1.3.13-1"

# manually download stable package from binhex repo (latest deluge on aor is beta/rc)
curl -o "/tmp/deluge-${deluge_ver}-any.pkg.tar.xz" -L "https://github.com/binhex/arch-packages/raw/master/compiled/deluge-${deluge_ver}-any.pkg.tar.xz"
pacman -U "/tmp/deluge-${deluge_ver}-any.pkg.tar.xz" --noconfirm
