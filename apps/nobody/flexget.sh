#!/bin/bash

echo "[info] Starting Flexget daemon..."

# Remove lockfile if exists
if [ -f /home/nobody/.flexget/.config-lock ]; then
        echo "Lockfile found...removing"
        /bin/rm -f /home/nobody/.flexget/.config-lock
fi

# Check if config.yml exists. If not, copy in
if [ -f /home/nobody/.flexget/config.yml ]; then
  echo "Using existing config file."
else
  echo "Creating config.yml from template."
  cp /config.yml  /home/nobody/.flexget/config.yml
  chown nobody:users /home/nobody/.flexget/config.yml
  chmod +x /home/nobody/.flexget/config.yml
fi

# if FLEXGET_WEBUI_PASSWORD not specified then use default FLEXGET_WEBUI_PASSWORD = flexpass 
if [[ -z "${FLEXGET_WEBUI_PASSWORD}" ]]; then
	FLEXGET_WEBUI_PASSWORD="flexpass"
	echo "Using default Flexget-webui password of flexpass"
else
	echo "Using userdefined Flexget-webui password of " "${FLEXGET_WEBUI_PASSWORD}"
fi

# run flexget set webui password and run daemon
/usr/bin/flexget web passwd "${FLEXGET_WEBUI_PASSWORD}"
/usr/bin/flexget -c /home/nobody/.flexget/config.yml daemon start
