#!/bin/bash

# exit script if return code != 0
set -e

# define arch official repo (aor) packages
aor_packages="deluge"

# download and install package
curl -L -o "/tmp/$aor_packages.tar.xz" "https://www.archlinux.org/packages/community/x86_64/$aor_packages/download/"
pacman -U "/tmp/$aor_packages.tar.xz" --noconfirm