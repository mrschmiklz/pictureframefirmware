#!/system/bin/sh
# Runs on every boot via the setmacaddr init hook (see install_persistent.ps1).

SYNC_HOME=/data/local/frame-sync
LOG="$SYNC_HOME/boot.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"
}

get_wlan_ip() {
    ip -4 addr show wlan0 2>/dev/null | busybox sed -n 's/.*inet \([0-9.]*\)\/.*/\1/p' | head -1
}

enable_wifi_adb() {
    PORT=5555
    setprop persist.adb.tcp.port "$PORT"
    setprop service.adb.tcp.port "$PORT"
    stop adbd 2>/dev/null
    start adbd
    setprop ctl.restart adbd 2>/dev/null

    tries=0
    ip=""
    while [ "$tries" -lt 18 ]; do
        ip=$(get_wlan_ip)
        [ -n "$ip" ] && break
        tries=$((tries + 1))
        sleep 5
    done

    if [ -n "$ip" ]; then
        echo "$ip" > "$SYNC_HOME/wifi_adb_ip.txt"
        log "wifi adb enabled on ${ip}:${PORT}"
    else
        log "wifi adb enabled on port ${PORT} (wlan IP not ready yet)"
    fi
}

log "boot hook started"

# Wi-Fi and DHCP usually finish shortly after boot_completed.
sleep 20

enable_wifi_adb

if [ -x "$SYNC_HOME/block_wan.sh" ]; then
    "$SYNC_HOME/block_wan.sh" || log "WARN firewall script failed"
else
    log "WARN missing block_wan.sh"
fi

pm disable com.yhk.qeota >/dev/null 2>&1 || true

if [ -x "$SYNC_HOME/start_sync_daemon.sh" ]; then
    "$SYNC_HOME/start_sync_daemon.sh" || log "WARN sync daemon failed to start"
else
    log "WARN missing start_sync_daemon.sh"
fi

if [ -x "$SYNC_HOME/install_from_nas.sh" ]; then
    "$SYNC_HOME/install_from_nas.sh" once >> "$LOG" 2>&1 || log "WARN NAS deploy check failed"
fi

if [ -x "$SYNC_HOME/process_nas_console.sh" ]; then
    "$SYNC_HOME/process_nas_console.sh" once >> "$LOG" 2>&1 || log "WARN NAS console check failed"
fi

if [ -x "$SYNC_HOME/start_agent.sh" ]; then
    "$SYNC_HOME/start_agent.sh" start >> "$LOG" 2>&1 || log "WARN agent start failed"
fi

log "boot hook complete"
