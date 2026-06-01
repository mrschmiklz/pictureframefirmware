#!/system/bin/sh
. /data/local/frame-sync/agent/lib/common.sh
require_auth

print_json_header
path=$(echo "$QUERY_STRING" | busybox sed -n 's/.*path=\([^&]*\).*/\1/p' | busybox sed 's/%2F/\//g; s/%2f/\//g')
if ! safe_path "$path" || [ ! -f "$path" ]; then
    echo '{"error":"invalid path"}'
    exit 0
fi

size=$(busybox stat -c %s "$path" 2>/dev/null || echo 0)
max=524288
if [ "$size" -gt "$max" ]; then
    echo "{\"error\":\"file too large for read API (> ${max})\"}"
    exit 0
fi

b64=$(busybox base64 "$path" 2>/dev/null | busybox tr -d '\n')
echo -n '{"ok":true,"path":"'
json_escape "$path"
echo -n '","size":'
echo -n "$size"
echo -n ',"data_base64":"'
echo -n "$b64"
echo '"}'
