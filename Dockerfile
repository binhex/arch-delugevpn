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

# add bash script to run deluge
ADD apps/nobody/*.sh /home/nobody/

# add pre-configured config files for nobody
ADD config/nobody/ /home/nobody/

# install app
#############

# make executable and run bash scripts to install app
RUN chmod +x /root/*.sh /home/nobody/*.sh && \
	/bin/bash /root/install.sh

RUN pacman -Syu --needed --noconfirm python2-pip nano cronie
RUN pip2 install --upgrade setuptools
RUN pip2 install flexget
RUN mkdir /home/nobody/.flexget
RUN export EDITOR=nano
#change later once installed
RUN /usr/sbin/flexget web passwd flexpassword
# Add our crontab file
ADD crons.conf /home/nobody/.flexget/crons/crons.conf

# Use the crontab file.
RUN crontab /home/nobody/.flexget/crons/crons.conf



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
