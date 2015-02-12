FROM binhex/arch-base:2015020300
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

# add bash script to identify pia incoming port
ADD apps/setport.sh /home/nobody/setport.sh

# add bash script to run deluge webui
ADD apps/webui.sh /home/nobody/webui.sh

# add pia certificates
ADD config/ca.crt /root/ca.crt
ADD config/crl.pem /root/crl.pem

# add pia config file (netherlands)
ADD config/openvpn.conf /root/openvpn.conf

# install app
#############

# install install app using pacman, set perms, cleanup
RUN pacman -Sy --noconfirm && \
	pacman -S net-tools openvpn unzip unrar librsvg pygtk python2-service-identity python2-mako python2-notify deluge --noconfirm && \
	chmod +x /root/start.sh /root/openvpn.sh /home/nobody/checkip.sh /home/nobody/deluge.sh /home/nobody/setport.sh /home/nobody/webui.sh && \
	chown -R nobody:users /usr/bin/deluged /usr/bin/deluge-web && \
	chmod -R 775 /usr/bin/deluged /usr/bin/deluge-web && \
	yes|pacman -Scc && \	
	rm -rf /usr/share/locale/* && \
	rm -rf /usr/share/man/* && \
	rm -rf /tmp/*

# docker settings
#################

# map /config to host defined config path (used to store configuration from app)
VOLUME /config

# map /data to host defined data path (used to store data from app)
VOLUME /data

# expose port for deluge webui
EXPOSE 8112

# set environment variables for user nobody
ENV HOME /home/nobody

# set environment variable for terminal
ENV TERM xterm

# run supervisor
################

# run supervisor
CMD ["supervisord", "-c", "/etc/supervisor.conf", "-n"]