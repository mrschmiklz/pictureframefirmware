#!/system/bin/sh
. /data/local/frame-sync/agent/lib/common.sh
require_auth

print_json_header
echo '{"ok":true,"message":"reboot scheduled"}'
( sleep 2; reboot ) >/dev/null 2>&1 &
