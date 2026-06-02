#!/system/bin/sh
# Keep storage popups suppressed (lightweight background guard).
SYNC_HOME=/data/local/frame-sync
PIDFILE="$SYNC_HOME/popup_guard.pid"
LOG="$SYNC_HOME/suppress.log"

if [ -f "$PIDFILE" ]; then
    old=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
        exit 0
    fi
fi

nohup sh "$SYNC_HOME/suppress_popups.sh" loop >> "$LOG" 2>&1 &
echo $! > "$PIDFILE"
