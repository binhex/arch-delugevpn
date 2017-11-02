#!/bin/bash

# wait for deluge to create auth file 
until test -f /config/auth ; do
	sleep 1
done

#add flexgetuser
grep "flexgetuser:flexgetpassword:10" /config/auth || echo "flexgetuser:flexgetpassword:10" >> /config/auth

# if config file doesnt exist then copy stock config file
if [[ ! -f /config/flexget.yml ]]; then

	echo "[info] Flexget config file doesn't exist, copying default..."
	cp /home/nobody/flexget/flexget.yml /config/

else

	echo "[info] Flexget config file already exists, skipping copy"

fi



flexget -c /config/flexget.yml daemon start --autoreload-config 
