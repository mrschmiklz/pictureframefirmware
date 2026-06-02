#!/system/bin/sh
# Process Wi-Fi-only commands queued on the NAS (outbound pull, no USB needed).

SYNC_HOME=/data/local/frame-sync
CONFIG="$SYNC_HOME/nas.conf"
RCLONE="$SYNC_HOME/bin/rclone"
LOG="$SYNC_HOME/console.log"
QUEUE_LOCAL="$SYNC_HOME/console-queue"
NAS_QUEUE="frame-console/queue/pending"
NAS_DONE="frame-console/queue/done"
NAS_HEARTBEAT="frame-console/heartbeat.json"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"
}

load_config() {
    [ -f "$CONFIG" ] || return 1
    . "$CONFIG"
    [ -n "$NAS_HOST" ] && [ -n "$NAS_SHARE" ] || return 1
    [ -n "$CONSOLE_PATH" ] || CONSOLE_PATH=frame-console
    return 0
}

rclone_remote() {
    echo ":smb,host=${NAS_HOST},share=${NAS_SHARE},path=${1}:"
}

rclone_args_base() {
    args="--config /dev/null --low-level-retries 1 --retries 1 --timeout 30s"
    if [ -n "$NAS_USER" ]; then
        args="$args --smb-user $NAS_USER --smb-pass $NAS_PASS"
    fi
    echo "$args"
}

pull_queue() {
    mkdir -p "$QUEUE_LOCAL/pending" "$QUEUE_LOCAL/done"
    remote=$(rclone_remote "${CONSOLE_PATH}/queue/pending")
    args=$(rclone_args_base)
    args="$args --include *.cmd --exclude *"
    # shellcheck disable=SC2086
    $RCLONE copy $args "$remote" "$QUEUE_LOCAL/pending" >> "$LOG" 2>&1

    # Ignore accidental directory copies from a misconfigured NAS queue.
    rm -rf "$QUEUE_LOCAL/pending/nas" "$QUEUE_LOCAL/pending/n8n_files" 2>/dev/null
    for stray in "$QUEUE_LOCAL/pending"/*; do
        [ -e "$stray" ] || continue
        case "$stray" in
            *.cmd) ;;
            *) rm -rf "$stray" 2>/dev/null; log "removed stray queue item $(basename "$stray")" ;;
        esac
    done
}

push_done() {
    file="$1"
    base=$(basename "$file")
    remote=$(rclone_remote "${CONSOLE_PATH}/queue/done")
    args=$(rclone_args_base)
    # shellcheck disable=SC2086
    $RCLONE copyto $args "$file" "$remote/$base" >> "$LOG" 2>&1
}

delete_remote_pending() {
    base="$1"
    remote=$(rclone_remote "${CONSOLE_PATH}/queue/pending")
    args=$(rclone_args_base)
    # shellcheck disable=SC2086
    $RCLONE delete $args "$remote/$base" >> "$LOG" 2>&1
}

push_heartbeat() {
    ip=$(ip -4 addr show wlan0 2>/dev/null | busybox sed -n 's/.*inet \([0-9.]*\)\/.*/\1/p' | head -1)
    tmp="$QUEUE_LOCAL/heartbeat.json"
    mkdir -p "$QUEUE_LOCAL"
    cat > "$tmp" <<EOF
{"time":"$(date '+%Y-%m-%dT%H:%M:%S')","ip":"$ip","agent":"$([ -f $SYNC_HOME/agent/agent.pid ] && echo up || echo down)"}
EOF
    remote=$(rclone_remote "${CONSOLE_PATH}")
    args=$(rclone_args_base)
    # shellcheck disable=SC2086
    $RCLONE copyto $args "$tmp" "$remote/heartbeat.json" >> "$LOG" 2>&1
}

run_cmd_file() {
    file="$1"
    base=$(basename "$file")
    id=$(echo "$base" | busybox sed 's/\.cmd$//')
    cmd=$(busybox head -1 "$file" | busybox tr -d '\r\n')
    result="$QUEUE_LOCAL/done/${id}.result"
    log "run $base: $cmd"

    case "$cmd" in
        reboot)
            echo "ok reboot scheduled" > "$result"
            delete_remote_pending "$base"
            push_done "$result"
            push_heartbeat
            ( sleep 2; reboot ) >/dev/null 2>&1 &
            return 0
            ;;
        start_agent)
            [ -x "$SYNC_HOME/start_agent.sh" ] && "$SYNC_HOME/start_agent.sh" start >> "$LOG" 2>&1
            echo "ok agent started" > "$result"
            ;;
        install_splash)
            [ -x "$SYNC_HOME/install_splash.sh" ] && "$SYNC_HOME/install_splash.sh" >> "$LOG" 2>&1
            echo "ok splash installed" > "$result"
            ;;
        suppress_popups|quiet_mode)
            [ -x "$SYNC_HOME/suppress_popups.sh" ] && "$SYNC_HOME/suppress_popups.sh" once >> "$LOG" 2>&1
            [ -x "$SYNC_HOME/start_popup_guard.sh" ] && "$SYNC_HOME/start_popup_guard.sh" >> "$LOG" 2>&1
            echo "ok quiet mode applied" > "$result"
            ;;
        pull_deploy)
            [ -x "$SYNC_HOME/install_from_nas.sh" ] && "$SYNC_HOME/install_from_nas.sh" once >> "$LOG" 2>&1
            echo "ok deploy pulled" > "$result"
            ;;
        copy_nas:*)
            spec=$(echo "$cmd" | busybox cut -d: -f2-)
            nas_rel=$(echo "$spec" | busybox cut -d'>' -f1)
            dest=$(echo "$spec" | busybox cut -d'>' -f2)
            case "$dest" in /system/*) mount -o remount,rw /system ;; esac
            remote=$(rclone_remote "$nas_rel")
            args=$(rclone_args_base)
            mkdir -p "$(dirname "$dest")"
            # shellcheck disable=SC2086
            $RCLONE copyto $args "$remote" "$dest" >> "$LOG" 2>&1 && echo "ok copied to $dest" > "$result" || echo "fail copy" > "$result"
            case "$dest" in /system/*) mount -o remount,ro /system ;; esac
            ;;
        write_text:*)
            spec=$(echo "$cmd" | busybox cut -d: -f2-)
            dest=$(echo "$spec" | busybox cut -d'>' -f1)
            payload=$(echo "$spec" | busybox cut -d'>' -f2-)
            case "$dest" in /system/*) mount -o remount,rw /system ;; esac
            mkdir -p "$(dirname "$dest")"
            printf '%s' "$payload" > "$dest"
            echo "ok wrote $dest" > "$result"
            case "$dest" in /system/*) mount -o remount,ro /system ;; esac
            ;;
        *)
            echo "fail unknown cmd: $cmd" > "$result"
            ;;
    esac

    delete_remote_pending "$base"
    push_done "$result"
}

process_once() {
    load_config || return 1
    [ -x "$RCLONE" ] || return 1
    pull_queue || return 1
    push_heartbeat

    for file in "$QUEUE_LOCAL/pending"/*.cmd; do
        [ -f "$file" ] || continue
        run_cmd_file "$file"
        rm -f "$file"
    done
    return 0
}

case "$1" in
    once) process_once ;;
    *)
        echo "Usage: $0 once"
        exit 1
        ;;
esac
