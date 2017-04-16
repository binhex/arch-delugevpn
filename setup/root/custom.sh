#!/bin/bash

# exit script if return code != 0
set -e

# install boost-libs (required for boost)
pkg_name="boost-libs"
pkg_ver="1.60.0-5-x86_64"

# download compiled package(s) from binhex repo
curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 60 -L -o "/tmp/${pkg_name}-${pkg_ver}.pkg.tar.xz" "https://github.com/binhex/arch-packages/raw/master/compiled/${pkg_name}-${pkg_ver}.pkg.tar.xz"
pacman -U "/tmp/${pkg_name}-${pkg_ver}.pkg.tar.xz" --noconfirm

# install boost (required for libtorrent)
pkg_name="boost"
pkg_ver="1.60.0-5-x86_64"

# download compiled package(s) from binhex repo
curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 60 -L -o "/tmp/${pkg_name}-${pkg_ver}.pkg.tar.xz" "https://github.com/binhex/arch-packages/raw/master/compiled/${pkg_name}-${pkg_ver}.pkg.tar.xz"
pacman -U "/tmp/${pkg_name}-${pkg_ver}.pkg.tar.xz" --noconfirm

# install libtorrent (required due to the fact that libtorrent 1.1.x is not compatible with deluge 1.3.x - hopefully fixed in deluge 2.x)
pkg_name="libtorrent-rasterbar"
pkg_ver="1-1.0.9-1-x86_64"

# download compiled package(s) from binhex repo
curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 60 -L -o "/tmp/${pkg_name}-${pkg_ver}.pkg.tar.xz" "https://github.com/binhex/arch-packages/raw/master/compiled/${pkg_name}-${pkg_ver}.pkg.tar.xz"
pacman -U "/tmp/${pkg_name}-${pkg_ver}.pkg.tar.xz" --noconfirm
