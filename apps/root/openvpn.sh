#!/bin/bash

echo "[info] Starting OpenVPN..."

# run openvpn to create tunnel
/usr/bin/openvpn --cd /config/openvpn --config "$VPN_CONFIG"