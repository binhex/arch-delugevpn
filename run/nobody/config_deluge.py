#!/usr/bin/python3

import os
import sys
import logging

# script to write out values to keys in the deluge core.conf file, as deluge-console is horrible and broken

# add logging handler to silence logging errors from deluge module
logging.getLogger('deluge').addHandler(logging.NullHandler())

# import deluge configuration module
from deluge.config import Config

# define filename and paths
this_script = os.path.basename(__file__)

# read in command line arguments for key
deluge_conf_path = sys.argv[1]

# read in command line arguments for key
key = sys.argv[2]

# read in command line argument for value
value = sys.argv[3]

# parse file
core_conf = Config(deluge_conf_path)

# attempt to read in config file
if os.path.exists(deluge_conf_path):

    try:

        core_conf[key]

    except KeyError:

        print("[warn] Deluge config file %s does not contain valid data, exiting Python script %s..." % (deluge_conf_path, this_script))
        sys.exit(1)

    if core_conf[key] != "":

        print("[info] Deluge key '%s' currently has a value of '%s'" % (key, core_conf[key]))

    else:

        print("[info] Deluge key '%s' currently has an undefined value" % (key))

    print("[info] Deluge key '%s' will have a new value '%s'" % (key, value))

    # define the new value
    core_conf[key] = value

    # save changes to the config file
    print("[info] Writing changes to Deluge config file '%s'..." % (deluge_conf_path))
    core_conf.save()
    sys.exit(0)

else:

    print("[info] Deluge configuration file %s does not exist, exiting Python script %s..." % (deluge_conf_path, this_script))
    sys.exit(1)
