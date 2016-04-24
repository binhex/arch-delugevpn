FROM binhex/arch-openvpn
MAINTAINER paulpoco

# additional files
##################

# add supervisor conf file for app
ADD setup/*.conf /etc/supervisor/conf.d/

# add bash scripts to install app
ADD setup/root/*.sh /root/

# add bash script to setup iptables
ADD apps/root/*.sh /root/

# add bash script to run deluge & flexget
ADD apps/nobody/*.sh /home/nobody/

# add pre-configured config files for nobody
ADD config/nobody/ /home/nobody/

# install app
#############

# make executable and run bash scripts to install app
RUN chmod +x /root/*.sh /home/nobody/*.sh && \
	/bin/bash /root/install.sh

ADD bashrc /home/nobody/.bashrc

# docker settings
#################

# map /config to host defined config path (used to store configuration from app)
VOLUME /config

# map /data to host defined data path (used to store data from app)
VOLUME /data

# map /home/nobody/.flexget to host defined data path (used to store data from app)
VOLUME /home/nobody/.flexget

# expose port for deluge webui
EXPOSE 8112

# expose port for flexget webui
EXPOSE 3539

# set permissions
#################

# run script to set uid, gid and permissions
CMD ["/bin/bash", "/root/init.sh"]
