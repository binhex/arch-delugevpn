#!/bin/bash

# exit script if return code != 0
set -e

# manually download stable package from binhex repo (latest deluge on aor is beta/rc)
curl -o /tmp/deluge-1.3.11-3-any.pkg.tar.xz -L https://github.com/binhex/arch-packages/raw/master/compiled/deluge-1.3.13-1-any.pkg.tar.xz
pacman -U /tmp/deluge-1.3.11-3-any.pkg.tar.xz --noconfirm
