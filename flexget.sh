#!/bin/bash

echo "[info] Starting Flexget daemon..."

# Remove lockfile if exists
if [ -f /config/.flexget-lock ]; then
        echo "Lockfile found...removing"
        /bin/rm -f /config/.flexget-lock
fi

# run deluge daemon
/usr/bin/flexget daemon start
