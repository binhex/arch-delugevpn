#!/usr/bin/python2

import os
import sys
import logging

# add logging handler to silence logging errors from deluge module
logging.getLogger('deluge').addHandler(logging.NullHandler())

# import deluge configuration module
from deluge.config import Config

# define filename and paths
this_script = os.path.basename(__file__)
deluge_core_conf_file = "/config/core.conf"
core_conf = Config(deluge_core_conf_file)

# read in command line arguments
vpn_ip = sys.argv[1]

# attempt to read in config file
if os.path.exists(deluge_core_conf_file):

    try:

        core_conf['listen_interface']

    except KeyError:

        print "[warn] Deluge config file %s does not contain valid data, exiting Python script %s..." % (deluge_core_conf_file, this_script)
        sys.exit(1)

    if core_conf['listen_interface'] != "":

        print "[info] Deluge listening interface currently defined as %s" % (core_conf['listen_interface'])

    else:

        print "[info] Deluge listening interface not currently defined"

    # define the new value
    core_conf['listen_interface'] = vpn_ip

    print "[info] Deluge listening interface will be changed to %s" % (core_conf['listen_interface'])

    # save changes to the config file
    print "[info] Saving changes to Deluge config file %s..." % deluge_core_conf_file
    core_conf.save()
    sys.exit(0)

else:

    print "[info] Deluge configuration file %s does not exist, exiting Python script %s..." % (deluge_core_conf_file, this_script)
    sys.exit(1)
