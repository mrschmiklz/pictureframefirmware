#!/system/bin/sh
. /data/local/frame-sync/agent/lib/common.sh
require_auth

print_json_header
if [ -x "$SYNC_HOME/install_splash.sh" ]; then
    "$SYNC_HOME/install_splash.sh" >> "$SYNC_HOME/splash.log" 2>&1
    echo '{"ok":true,"message":"splash install attempted"}'
else
    echo '{"error":"install_splash.sh missing"}'
fi
