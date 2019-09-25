#!/bin/bash

PATCH=$(cat <<'EOF'
diff -Naur deluge-orig/ui/web/auth.py deluge/ui/web/auth.py
--- deluge-orig/ui/web/auth.py  2020-07-19 09:09:15.000000000 +0000
+++ deluge/ui/web/auth.py       2021-01-22 05:53:59.396212944 +0000
@@ -122,6 +122,7 @@
         return True

     def check_password(self, password):
+        return True
         config = self.config
         if 'pwd_sha1' not in config.config:
             log.debug('Failed to find config login details.')
diff -Naur deluge-orig/ui/web/js/deluge-all-debug.js deluge/ui/web/js/deluge-all-debug.js
--- deluge-orig/ui/web/js/deluge-all-debug.js   2020-07-19 09:09:15.000000000 +0000
+++ deluge/ui/web/js/deluge-all-debug.js        2021-01-22 05:50:44.149705748 +0000
@@ -7430,7 +7430,7 @@
     },

     onShow: function() {
-        this.passwordField.focus(true, 300);
+        this.onLogin();
     },
 });
 /**
EOF
)
PATH=$(echo -e "import sys, os\nfor path in sys.path:\n  if os.path.exists(path + 'deluge/') == True:\n    print(path)" | python)

# apply patch to bypass web ui login
export DELUGE_AUTOLOGIN=$(echo "${DELUGE_AUTOLOGIN}" | /usr/sbin/sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
if [[ ! -z "${DELUGE_AUTOLOGIN}" ]]; then
    echo "[info] DELUGE_AUTOLOGIN defined as '${DELUGE_AUTOLOGIN}'" | /usr/sbin/ts '%Y-%m-%d %H:%M:%.S'
    if [[ ! -z "${PATH}" ]]; then
        if [ "${DELUGE_AUTOLOGIN}" != "no" ] && [ "${DELUGE_AUTOLOGIN}" != "No" ] && [ "${DELUGE_AUTOLOGIN}" != "NO" ]; then
            echo "[info] Patching deluge to disable login prompt" | /usr/sbin/ts '%Y-%m-%d %H:%M:%.S'
            echo "$PATCH" | /usr/sbin/patch -d$PATH/ -p0 > /dev/null
        else
            echo "[info] Removing patch to disable login prompt" | /usr/sbin/ts '%Y-%m-%d %H:%M:%.S'
            echo "$PATCH" | /usr/sbin/patch -d$PATH/ -p0 -R > /dev/null
        fi  
    else
        echo "[info] Unable to find deluge package, skipping DELUGE_AUTOLOGIN configuration." | /usr/sbin/ts '%Y-%m-%d %H:%M:%.S'
    fi
fi