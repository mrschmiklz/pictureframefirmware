#!/system/bin/sh
SYNC_HOME=/data/local/frame-sync
PIDFILE="$SYNC_HOME/sync.pid"

if [ -f "$PIDFILE" ]; then
    old_pid=$(cat "$PIDFILE")
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
        echo "sync daemon already running (pid $old_pid)"
        exit 0
    fi
fi

nohup "$SYNC_HOME/sync_nas.sh" loop >> "$SYNC_HOME/daemon.log" 2>&1 &
echo $! > "$PIDFILE"
echo "started sync daemon pid $(cat "$PIDFILE")"
