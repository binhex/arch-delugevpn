#!/bin/bash
#this should be run as the user running deluged service on the local deluge machine or container

#logfile="/config/deluge-checkerrors.log"
dconsole=$(which deluge-console)
dfolder=$(dirname $dconsole)

cd $dfolder
myarray=( $($dconsole -c /config "info" | grep -B 1 'State: Error' | grep -v -e "--" -e Error | awk '{ print $2 }') )

#echo Checking for failed torrents in Deluge >>$logfile
echo "[info] Checking for failed torrents in Deluge"
#date >>$logfile
#echo "${#myarray[@]} torrents in error state">>$logfile

if [[ ${#myarray[@]} -eq $zero ]];
  then echo "[info] ${#myarray[@]} torrents in error state.";
  else echo "[warn] ${#myarray[@]} torrents in error state, rechecking torrents.";
fi

for torrents in "${myarray[@]}"
do
  $dconsole -c /config "recheck $torrents"
done

#echo Finished. >>$logfile
#echo -- >>$logfile
