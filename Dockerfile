FROM binhex/arch-base:2015031900
MAINTAINER binhex

# additional files
##################

# add supervisor conf file for app
ADD *.conf /etc/supervisor/conf.d/

# add bash scripts to install app, and setup iptables, routing etc
ADD *.sh /root/

# add bash script to run openvpn
ADD apps/root/*.sh /root/

# add bash script to run deluge and privoxy
ADD apps/nobody/*.sh /home/nobody/

# add pia certificates and sample openvpn.ovpn file
ADD config/pia/* /home/nobody/

# install app
#############

# make executable and run bash scripts to install app
RUN chmod +x /root/*.sh /home/nobody/*.sh && \
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
