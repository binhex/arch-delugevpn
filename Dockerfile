FROM binhex/arch-base:2015030300
MAINTAINER binhex

# additional files
##################

# add supervisor conf file for app
ADD delugevpn.conf /etc/supervisor/conf.d/delugevpn.conf

# add bash script to create tun adapter, setup ip route and create vpn tunnel
ADD start.sh /root/start.sh

# add bash script to run openvpn
ADD apps/openvpn.sh /root/openvpn.sh

# add bash script to check tunnel ip is valid
ADD apps/checkip.sh /home/nobody/checkip.sh

# add bash script to run deluge daemon
ADD apps/deluge.sh /home/nobody/deluge.sh

# add bash script to configure deluge
ADD apps/setport.sh /home/nobody/setport.sh

# add bash script to run deluge webui
ADD apps/webui.sh /home/nobody/webui.sh

# add bash script to run privoxy
ADD apps/privoxy.sh /home/nobody/privoxy.sh

# add pia certificates
ADD config/ca.crt /home/nobody/ca.crt
ADD config/crl.pem /home/nobody/crl.pem

# add sample openvpn.ovpn file (based on pia netherlands)
ADD config/openvpn.ovpn /home/nobody/openvpn.ovpn

# add install bash script
ADD install.sh /root/install.sh

# install app
#############

# make executable and run bash scripts to install app
RUN chmod +x /root/install.sh /root/start.sh /root/openvpn.sh /home/nobody/checkip.sh /home/nobody/deluge.sh /home/nobody/setport.sh /home/nobody/webui.sh /home/nobody/privoxy.sh && \
	/bin/bash /root/install.sh

# docker settings
#################

# map /config to host defined config path (used to store configuration from app)
VOLUME /config

# map /data to host defined data path (used to store data from app)
VOLUME /data

# expose port for deluge webui
EXPOSE 8112

# expose port for privoxy
EXPOSE 8118

# run supervisor
################

# run supervisor
CMD ["supervisord", "-c", "/etc/supervisor.conf", "-n"]