FROM binhex/arch-int-vpn:latest
LABEL org.opencontainers.image.authors="binhex"
LABEL org.opencontainers.image.source="https://github.com/binhex/arch-delugevpn"

# release tag name from buildx arg
ARG RELEASETAG

# arch from buildx --platform, e.g. amd64
ARG TARGETARCH

# additional files
##################

# add supervisor conf file for app
ADD build/*.conf /etc/supervisor/conf.d/

# add bash scripts to install app
ADD build/root/*.sh /root/

# add bash script to run deluge
ADD run/nobody/*.sh /home/nobody/

# add python script to configure deluge
ADD run/nobody/*.py /home/nobody/

# add pre-configured config files for deluge
ADD config/nobody/ /home/nobody/

# install app
#############

# make executable and run bash scripts to install app
RUN chmod +x /root/*.sh /home/nobody/*.sh /home/nobody/*.py && \
	/bin/bash /root/install.sh "${RELEASETAG}" "${TARGETARCH}"

# set permissions
#################

# run script to set uid, gid and permissions
CMD ["/bin/bash", "/usr/local/bin/init.sh"]