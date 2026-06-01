#!/system/bin/sh
. /data/local/frame-sync/agent/lib/common.sh
require_auth

print_json_header
path=$(echo "$QUERY_STRING" | busybox sed -n 's/.*path=\([^&]*\).*/\1/p' | busybox sed 's/%2F/\//g; s/%2f/\//g')
if ! safe_path "$path" || [ ! -d "$path" ]; then
    echo '{"error":"invalid path"}'
    exit 0
fi

echo -n '{"ok":true,"path":"'
json_escape "$path"
echo -n '","entries":['
first=1
for entry in "$path"/*; do
    [ -e "$entry" ] || continue
    name=$(basename "$entry")
    if [ -d "$entry" ]; then kind="dir"; else kind="file"; fi
    size=$(busybox stat -c %s "$entry" 2>/dev/null || echo 0)
    [ "$first" = 1 ] || echo -n ","
    first=0
    echo -n "{\"name\":\"$(json_escape "$name")\",\"type\":\"$kind\",\"size\":$size}"
done
echo "]}"
