#!/system/bin/sh
. /data/local/frame-sync/agent/lib/common.sh
require_auth

print_json_header
path=$(echo "$QUERY_STRING" | busybox sed -n 's/.*path=\([^&]*\).*/\1/p' | busybox sed 's/%2F/\//g; s/%2f/\//g')
if ! safe_path "$path"; then
    echo '{"error":"invalid path"}'
    exit 0
fi

len=${CONTENT_LENGTH:-0}
if [ "$len" -le 0 ]; then
    echo '{"error":"empty body"}'
    exit 0
fi

case "$path" in
    /system/*) remount_system_rw ;;
esac

dir=$(dirname "$path")
mkdir -p "$dir"
busybox dd bs=1 count="$len" of="$path" 2>/dev/null
chmod 644 "$path" 2>/dev/null

case "$path" in
    /system/*) remount_system_ro ;;
esac

echo -n '{"ok":true,"path":"'
json_escape "$path"
echo -n '","bytes":'
echo -n "$len"
echo '"}'
