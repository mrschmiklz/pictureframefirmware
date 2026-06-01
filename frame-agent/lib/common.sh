#!/system/bin/sh
# Shared helpers for frame-agent CGI scripts.

SYNC_HOME=/data/local/frame-sync
AGENT_HOME="$SYNC_HOME/agent"
CONF="$AGENT_HOME/agent.conf"

load_agent_conf() {
    AGENT_PORT=8080
    TOKEN="frame-local"
    if [ -f "$CONF" ]; then
        . "$CONF"
    fi
}

json_escape() {
    echo "$1" | busybox sed 's/\\/\\\\/g; s/"/\\"/g'
}

require_auth() {
    load_agent_conf
    got=""
    case "$QUERY_STRING" in
        *token=*) got=$(echo "$QUERY_STRING" | busybox sed -n 's/.*token=\([^&]*\).*/\1/p') ;;
    esac
    if [ -z "$got" ] && [ -n "$HTTP_AUTHORIZATION" ]; then
        got=$(echo "$HTTP_AUTHORIZATION" | busybox sed 's/^Bearer //')
    fi
    if [ "$got" != "$TOKEN" ]; then
        echo "Status: 401 Unauthorized"
        echo "Content-Type: application/json"
        echo ""
        echo '{"error":"unauthorized"}'
        exit 0
    fi
}

remount_system_rw() {
    mount -o remount,rw /system 2>/dev/null
}

remount_system_ro() {
    mount -o remount,ro /system 2>/dev/null
}

safe_path() {
    path="$1"
    case "$path" in
        ""|/*/*..*|*../*|*/..|../*) return 1 ;;
        /system/*|/bootloader/*|/sdcard/*|/data/local/frame-sync/*|/storage/*) return 0 ;;
        *) return 1 ;;
    esac
}

print_json_header() {
    echo "Content-Type: application/json"
    echo ""
}
