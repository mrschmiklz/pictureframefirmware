#!/system/bin/sh
# Pull firmware updates from NAS (frame-deploy/) and apply without USB.
# Called from boot.sh and sync_nas.sh.

SYNC_HOME=/data/local/frame-sync
CONFIG="$SYNC_HOME/nas.conf"
RCLONE="$SYNC_HOME/bin/rclone"
DEPLOY_DIR="$SYNC_HOME/deploy"
LOG="$SYNC_HOME/deploy.log"
APPLIED="$SYNC_HOME/deploy.applied"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"
}

load_config() {
    [ -f "$CONFIG" ] || return 1
    . "$CONFIG"
    [ -n "$NAS_HOST" ] && [ -n "$NAS_SHARE" ] || return 1
    [ -n "$DEPLOY_PATH" ] || DEPLOY_PATH=frame-deploy
    return 0
}

wait_for_network() {
    tries=0
    while [ "$tries" -lt 6 ]; do
        if busybox ping -c 1 -W 2 "$NAS_HOST" >/dev/null 2>&1; then
            return 0
        fi
        tries=$((tries + 1))
        sleep 5
    done
    return 1
}

pull_deploy() {
    remote=":smb,host=${NAS_HOST},share=${NAS_SHARE},path=${DEPLOY_PATH}:"
    args="sync --config /dev/null --low-level-retries 1 --retries 1 --timeout 30s"
    if [ -n "$NAS_USER" ]; then
        args="$args --smb-user $NAS_USER --smb-pass $NAS_PASS"
    fi
    mkdir -p "$DEPLOY_DIR"
    # shellcheck disable=SC2086
    $RCLONE $args "$remote" "$DEPLOY_DIR" >> "$LOG" 2>&1

    # Stray full-share copies must not fill /data (shows real storage popups).
    if [ -d "$DEPLOY_DIR/nas" ]; then
        rm -rf "$DEPLOY_DIR/nas" >> "$LOG" 2>&1
        log "removed stray deploy/nas cache"
    fi
}

update_scripts() {
    for name in nas.conf boot.sh block_wan.sh sync_nas.sh start_sync_daemon.sh \
        install_from_nas.sh install_splash.sh restore_usb_adb.sh process_nas_console.sh start_agent.sh \
        suppress_popups.sh start_popup_guard.sh; do
        src="$DEPLOY_DIR/$name"
        [ -f "$src" ] || continue
        cp "$src" "$SYNC_HOME/$name"
        chmod 755 "$SYNC_HOME/$name" 2>/dev/null || true
        log "updated script $name"
    done
    if [ -d "$DEPLOY_DIR/agent" ]; then
        mkdir -p "$SYNC_HOME/agent"
        cp -r "$DEPLOY_DIR/agent/"* "$SYNC_HOME/agent/" 2>/dev/null
        chmod -R 755 "$SYNC_HOME/agent" 2>/dev/null || true
        log "updated agent bundle"
    fi
}

apply_payload() {
    payload=0
    [ -f "$DEPLOY_DIR/bootanimation.zip" ] && payload=1
    [ -f "$DEPLOY_DIR/launcher_aimor.signed.apk" ] && payload=1
    [ "$payload" = "1" ] || return 0

    [ -f "$DEPLOY_DIR/bootanimation.zip" ] && \
        cp "$DEPLOY_DIR/bootanimation.zip" /sdcard/bootanimation.zip
    [ -f "$DEPLOY_DIR/launcher_aimor.signed.apk" ] && \
        cp "$DEPLOY_DIR/launcher_aimor.signed.apk" /sdcard/launcher_aimor.signed.apk

    if [ -x "$SYNC_HOME/install_splash.sh" ]; then
        "$SYNC_HOME/install_splash.sh" >> "$LOG" 2>&1 || log "WARN splash install failed"
    fi
}

run_once() {
    load_config || { log "skip: no config"; return 1; }
    [ -x "$RCLONE" ] || { log "skip: no rclone"; return 1; }
    wait_for_network || { log "skip: NAS unreachable"; return 1; }

    log "deploy pull start"
    pull_deploy || { log "ERROR rclone deploy pull failed"; return 1; }

    new_ver=""
    [ -f "$DEPLOY_DIR/VERSION" ] && new_ver=$(busybox head -1 "$DEPLOY_DIR/VERSION" | busybox tr -d '\r\n')
    old_ver=""
    [ -f "$APPLIED" ] && old_ver=$(busybox head -1 "$APPLIED" | busybox tr -d '\r\n')

    if [ -n "$new_ver" ] && [ "$new_ver" = "$old_ver" ]; then
        log "deploy unchanged ($new_ver)"
        return 0
    fi

    update_scripts
    apply_payload

    if [ -x "$SYNC_HOME/start_agent.sh" ]; then
        "$SYNC_HOME/start_agent.sh" restart >> "$LOG" 2>&1 || log "WARN agent restart failed"
    fi

    if [ -n "$new_ver" ]; then
        echo "$new_ver" > "$APPLIED"
        log "deploy applied version $new_ver"
    else
        date +%s > "$APPLIED"
        log "deploy applied (no VERSION file)"
    fi
    return 0
}

case "$1" in
    once) run_once ;;
    *)
        echo "Usage: $0 once"
        exit 1
        ;;
esac
