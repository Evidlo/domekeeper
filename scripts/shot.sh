#!/bin/bash
# Screenshot a local page with headless Chromium: shot.sh <url> <out.png> [WxH]
chromium --headless=new --disable-gpu --no-sandbox --allow-file-access-from-files \
  --window-size=${3:-1500,950} --virtual-time-budget=4000 --hide-scrollbars \
  --screenshot="$2" "$1" 2>&1 | grep -iE "error|uncaught" | grep -v -iE "dbus|gpu|vaapi|sandbox|gcm|fontconfig" | head -5
