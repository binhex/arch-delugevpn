FROM binhex/arch-openvpn
MAINTAINER binhex

# additional files
##################

# add supervisor conf file for app
ADD setup/*.conf /etc/supervisor/conf.d/

# add bash scripts to install app
ADD setup/root/*.sh /root/

# add bash script to setup iptables
ADD apps/root/*.sh /root/

# add bash script to run deluge
ADD apps/nobody/*.sh /home/nobody/

# add pre-configured config files for nobody
ADD config/nobody/ /home/nobody/

# install app
#############
RUN yes| pacman -Sy
RUN yes| pacman -S python2-pip
RUN yes| pip2 install --upgrade setuptools
RUN yes| pip2 install flexget
RUN yes| pacman -S nano
RUN yes| mkdir /home/nobody/.flexget
RUN yes| pacman -S cronie
RUN yes| export EDITOR=nano



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

# set permissions
#################

# run script to set uid, gid and permissions
CMD ["/bin/bash", "/root/init.sh"]
