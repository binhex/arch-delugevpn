
#!/bin/bash

echo "[info] Starting Flexget daemon..."

# Remove lockfile if exists
if [ -f /home/nobody/.flexget/.flexget-lock ]; then
        echo "Lockfile found...removing"
        /bin/rm -f /home/nobody/.flexget/.flexget-lock
fi

# run flexget set webui password and run daemon
/usr/bin/flexget -c /home/nobody/.flexget/config.yml daemon start
/usr/bin/flexget web passwd flexpass
