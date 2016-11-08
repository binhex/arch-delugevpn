#!/bin/bash

# check to see if docker is installed
hash docker 2>/dev/null || { echo >&2 "Docker not installed, please install Docker and then re-run, aborting install."; exit 1; }

# check to see if systemd is installed
hash systemctl 2>/dev/null || { echo >&2 "systemd not installed, this script supports the creation of unit files for systemd only, aborting install."; exit 1; }

while true; do
  read -e -p "Enter the VPN propvider type (pia|airvpn|custom): " -i "pia" vpn_prov
  vpn_prov=$(echo "${vpn_prov}" | sed -e 's/^[ \t]*//')

  if [[ "${vpn_prov}" == "pia" || "${vpn_prov}" == "airvpn" || "${vpn_prov}" == "custom" ]]; then
    break
  else
    echo "bad choice"
  fi
done

while true; do
  read -e -p "Enter the friendly name for the contaner: " -i "DelugeVPN" container_name
  container_name=$(echo "${container_name}" | sed -e 's/^[ \t]*//')

  if [[ -z "${container_name}"  ]]; then
    break
  else
    echo "Invalid input, please enter a valid value."
  fi
done

while true; do
  read -e -p "Enter the username the container will run as: " -i "root" user_name
  user_name=$(echo "${user_name}" | sed -e 's/^[ \t]*//')

  if [[ -z "${user_name}"  ]]; then
    break
  else
    echo "Invalid input, please enter a valid value."
  fi
done

id=$(id "${user_name}")
puid=$(echo "${id}" | grep -P -o -m 1 '(?<=uid\=)\d+')
pgid=$(echo "${id}" | grep -P -o -m 1 '(?<=gid\=)\d+')

# find home dir of specified username
user_home=$(eval echo "~$user_name")

while true; do
  read -e -p "Enter the path to store incomplete/completed downloads: " -i "${user_home}/docker/deluge/data" data_host_path
  data_host_path=$(echo "${data_host_path}" | sed -e 's/^[ \t]*//')

  if [[ -z "${data_host_path}"  ]]; then
    break
  else
    echo "Invalid input, please enter a valid value."
  fi
done

while true; do
  read -e -p "Enter the path to store Deluge configuration: " -i "${user_home}/docker/deluge/config" config_host_path
  config_host_path=$(echo "${config_host_path}" | sed -e 's/^[ \t]*//')

  if [[ -z "${config_host_path}"  ]]; then
    break
  else
    echo "Invalid input, please enter a valid value."
  fi
done

while true; do
  read -e -p "Enter the VPN providers username: " vpn_user
  vpn_user=$(echo "${vpn_user}" | sed -e 's/^[ \t]*//')

  if [[ -z "${vpn_user}"  ]]; then
    break
  else
    echo "Invalid input, please enter a valid value."
  fi
done

while true; do
  read -e -p "Enter the VPN providers password: " vpn_pass
  vpn_pass=$(echo "${vpn_pass}" | sed -e 's/^[ \t]*//')

  if [[ -z "${vpn_pass}"  ]]; then
    break
  else
    echo "Invalid input, please enter a valid value."
  fi
done


if [[ "{vpn_prov}" == "pia" ]]; then

  while true; do
    read -e -p "Enter the VPN providers remote endpoint: " -i "nl.privateinternetaccess.com" vpn_remote
    vpn_remote=$(echo "${vpn_remote}" | sed -e 's/^[ \t]*//')

    if [[ -z "${vpn_remote}"  ]]; then
      break
    else
      echo "Invalid input, please enter a valid value."
    fi
  done

  while true; do
    read -e -p "Enter the VPN providers protocol (tcp|udp): " -i "udp" vpn_proto
    vpn_proto=$(echo "${vpn_proto}" | sed -e 's/^[ \t]*//')

    if [[ "${vpn_proto}" == "yes" || "${vpn_proto}" == "no" ]]; then
      break
    else
      echo "Invalid input, please select from the list of available options."
    fi
  done

  while true; do
    read -e -p "Enable strong certificates (yes|no): " -i "yes" strong_certs
    strong_certs=$(echo "${strong_certs}" | sed -e 's/^[ \t]*//')

    if [[ "${vpn_proto}" == "yes" || "${vpn_proto}" == "no" ]]; then
      break
    else
      echo "Invalid input, please select from the list of available options."
    fi
  done

  if [[ "{vpn_proto}" == "udp" ]]; then
    if [[ "{strong_certs}" == "yes" ]]; then
      vpn_port="1197"
    else
      vpn_port="1198"
    fi
  else
    if [[ "{strong_certs}" == "yes" ]]; then
      vpn_port="501"
    else
      vpn_port="502"
    fi
  fi

else

  while true; do
    read -e -p "Enter the VPN providers remote endpoint: " vpn_remote
    vpn_remote=$(echo "${vpn_remote}" | sed -e 's/^[ \t]*//')

    if [[ -z "${vpn_remote}"  ]]; then
      break
    else
      echo "Invalid input, please enter a valid value."
    fi
  done

  while true; do
    read -e -p "Enter the VPN providers port: " vpn_port
    vpn_port=$(echo "${vpn_port}" | sed -e 's/^[ \t]*//')
  
    if [[ $vpn_port =~ ^-?[0-9]+$ ]]; then
      break
    else
      echo "Invalid input, please select from the list of available options."
    fi
  done

  while true; do
    read -e -p "Enter the VPN providers protocol (tcp|udp): " -i "udp" vpn_proto
    vpn_proto=$(echo "${vpn_proto}" | sed -e 's/^[ \t]*//')

    if [[ "${vpn_proto}" == "yes" || "${vpn_proto}" == "no" ]]; then
      break
    else
      echo "Invalid input, please select from the list of available options."
    fi
  done
  
while true; do
  read -e -p "Enable Privoxy (yes|no): " -i "yes" enable_privoxy
  enable_privoxy=$(echo "${enable_privoxy}" | sed -e 's/^[ \t]*//')

  if [[ "${enable_privoxy}" == "yes" || "${enable_privoxy}" == "no" ]]; then
    break
  else
    echo "Invalid input, please select from the list of available options."
  fi
done

while true; do
  read -e -p "Enter the LAN network range in CIDR format: " -i "192.168.1.0/24" lan_network
  lan_network=$(echo "${lan_network}" | sed -e 's/^[ \t]*//')

  if [[ -z "${lan_network}" ]]; then
    break
  else
    echo "Invalid input, please enter a valid value."
  fi
done

while true; do
  read -e -p "Enable debug mode (yes|no): " -i "no" debug
  debug=$(echo "${debug}" | sed -e 's/^[ \t]*//')

  if [[ "${debug}" == "yes" || "${debug}" == "no" ]]; then
    break
  else
    echo "Invalid input, please select from the list of available options."
  fi
done

# write docker run command to service file

# register service file and start service file

# tell user image being pulled and echo out url to connect to running docker
