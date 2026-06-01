#!/system/bin/sh
. /data/local/frame-sync/agent/lib/common.sh
require_auth

print_json_header
name=$(echo "$QUERY_STRING" | busybox sed -n 's/.*name=\([^&]*\).*/\1/p')
case "$name" in
    boot) file="$SYNC_HOME/boot.log" ;;
    sync) file="$SYNC_HOME/sync.log" ;;
    deploy) file="$SYNC_HOME/deploy.log" ;;
    console) file="$SYNC_HOME/console.log" ;;
    firewall) file="$SYNC_HOME/firewall.log" ;;
    *) echo '{"error":"unknown log"}'; exit 0 ;;
esac

if [ ! -f "$file" ]; then
    echo '{"error":"missing log"}'
    exit 0
fi

tail -n 80 "$file" 2>/dev/null | while IFS= read -r line; do
    printf '%s\n' "$line"
done > "$SYNC_HOME/agent/.logtmp"

b64=$(busybox base64 "$SYNC_HOME/agent/.logtmp" 2>/dev/null | busybox tr -d '\n')
rm -f "$SYNC_HOME/agent/.logtmp"
echo -n '{"ok":true,"name":"'
json_escape "$name"
echo -n '","data_base64":"'
echo -n "$b64"
echo '"}'
