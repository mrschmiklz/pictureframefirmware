#!/system/bin/sh
. /data/local/frame-sync/agent/lib/common.sh
require_auth

print_json_header
ip=$(ip -4 addr show wlan0 2>/dev/null | busybox sed -n 's/.*inet \([0-9.]*\)\/.*/\1/p' | head -1)
agent_pid=""
[ -f "$SYNC_HOME/agent/agent.pid" ] && agent_pid=$(cat "$SYNC_HOME/agent/agent.pid")
boot=$(getprop ro.product.model 2>/dev/null)
echo "{"
echo "  \"ok\": true,"
echo "  \"model\": \"$(json_escape "$boot")\","
echo "  \"ip\": \"$(json_escape "$ip")\","
echo "  \"agent_port\": ${AGENT_PORT:-8080},"
echo "  \"agent_pid\": \"$(json_escape "$agent_pid")\","
echo "  \"uptime\": \"$(json_escape "$(busybox uptime 2>/dev/null)")\""
echo "}"
