#!/system/bin/sh
# Start LAN HTTP boot console (busybox httpd).

SYNC_HOME=/data/local/frame-sync
AGENT_HOME="$SYNC_HOME/agent"
PIDFILE="$AGENT_HOME/agent.pid"
LOG="$SYNC_HOME/agent.log"
CONF="$AGENT_HOME/agent.conf"

load_conf() {
    AGENT_PORT=8080
    WEB_ROOT="$AGENT_HOME/www"
    if [ -f "$CONF" ]; then
        . "$CONF"
    fi
}

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"
}

stop_agent() {
    if [ -f "$PIDFILE" ]; then
        pid=$(cat "$PIDFILE")
        kill "$pid" 2>/dev/null
        rm -f "$PIDFILE"
    fi
    busybox killall httpd 2>/dev/null
}

start_agent() {
    load_conf
    mkdir -p "$AGENT_HOME/www/cgi-bin" "$AGENT_HOME/lib"
    chmod 755 "$AGENT_HOME/www/cgi-bin"/*.cgi 2>/dev/null
    chmod 755 "$AGENT_HOME/lib"/*.sh 2>/dev/null

    stop_agent

    if ! busybox httpd -h 2>&1 | busybox grep -q httpd; then
        log "ERROR busybox httpd unavailable"
        return 1
    fi

    busybox httpd -p "$AGENT_PORT" -h "$WEB_ROOT" -c "$WEB_ROOT/httpd.conf" >> "$LOG" 2>&1 &
    echo $! > "$PIDFILE"
    log "agent started on port $AGENT_PORT pid $(cat "$PIDFILE")"
    return 0
}

case "$1" in
    start) start_agent ;;
    stop) stop_agent ;;
    restart) stop_agent; start_agent ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
        ;;
esac
