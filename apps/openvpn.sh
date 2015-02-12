#!/bin/bash

echo "[info] Starting OpenVPN..."

# run openvpn to create tunnel
/usr/bin/openvpn --cd /config/openvpn --config /config/openvpn/openvpn.conf --redirect-gateway