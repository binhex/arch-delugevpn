#!/usr/bin/dumb-init /bin/bash

# This script ensures that we recheck any torrents that are in an error state when we
# start Deluge. This script must be run as the user running the Deluge daemon (deluged).

# identify any torrents with state error and save these torrent id's as an array
torrent_id_error_array=( $(deluge-console -c /config "info -v" | grep -B 1 'State: Error' | xargs | grep -P -o -m 1 '(?<=ID:\s)[^\s]+' | xargs) )

if [[ -n ${torrent_id_error_array[@]} ]]; then

	echo "[warn] Torrents with state 'Error' found"

	# loop over torrent id's with state error and recheck
	for i in "${torrent_id_error_array[@]}"; do
		echo "[info] Rechecking Torrent ID ${i} ..."
		deluge-console -c /config "recheck ${i}"
	done

else

	echo "[info] No torrents with state 'Error' found"

fi
