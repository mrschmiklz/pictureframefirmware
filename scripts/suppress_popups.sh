#!/system/bin/sh
# Stop Android "insufficient storage" dialogs on tight picture frames.
# Default threshold is ~500MB; these frames often sit at ~300-400MB free normally.

SYNC_HOME=/data/local/frame-sync
LOG="$SYNC_HOME/suppress.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"
}

apply_storage_thresholds() {
    # Only warn when almost completely full (1MB / 1% thresholds).
    settings put global sys_storage_threshold_max_bytes 1048576 2>/dev/null
    settings put global sys_storage_threshold_percentage 1 2>/dev/null
    settings put global sys_storage_full_threshold_bytes 524288 2>/dev/null
    settings put global low_storage_threshold_bytes 1048576 2>/dev/null

    max_bytes=$(settings get global sys_storage_threshold_max_bytes 2>/dev/null)
    pct=$(settings get global sys_storage_threshold_percentage 2>/dev/null)
    log "storage thresholds max_bytes=$max_bytes percentage=$pct"
}

disable_vendor_nags() {
    # YHK OTA nag (already disabled in boot.sh; repeat is harmless).
    pm disable com.yhk.qeota >/dev/null 2>&1 || true

    # Optional vendor packages seen on similar frames — ignore failures.
    for pkg in com.yhk.storage com.yhk.cleaner com.yhk.security com.android.storagemanager; do
        pm disable "$pkg" >/dev/null 2>&1 || true
    done
}

cleanup_staging_files() {
    rm -f /sdcard/bootanimation.zip /sdcard/launcher_aimor.signed.apk /sdcard/launcher_aimor.stock.apk 2>/dev/null

    # Accidental full-NAS copies under deploy/ can fill /data and trigger real storage alerts.
    if [ -d "$SYNC_HOME/deploy/nas" ]; then
        rm -rf "$SYNC_HOME/deploy/nas" 2>/dev/null
        log "removed stray deploy/nas cache"
    fi

    if [ -d "$SYNC_HOME/console-queue/pending/nas" ] || [ -d "$SYNC_HOME/console-queue/pending/n8n_files" ]; then
        rm -rf "$SYNC_HOME/console-queue/pending/nas" "$SYNC_HOME/console-queue/pending/n8n_files" 2>/dev/null
        log "removed stray console-queue cache"
    fi

    if [ -f "$SYNC_HOME/deploy.applied" ] && [ -d "$SYNC_HOME/deploy" ]; then
        rm -rf "$SYNC_HOME/deploy"/* 2>/dev/null
        log "cleared deploy cache after apply"
    fi
}

dismiss_storage_dialog() {
    windows=$(busybox timeout 3 dumpsys window windows 2>/dev/null || true)
    focus=$(echo "$windows" | busybox grep -m1 'mCurrentFocus' || true)

    case "$focus$windows" in
        *Storage*|*storage*|*Alert*|*Dialog*|*Insufficient*|*insufficient*|*364*|*space*)
            input keyevent 4 >/dev/null 2>&1 || true
            input keyevent 111 >/dev/null 2>&1 || true
            log "sent BACK/ESCAPE to dismiss storage UI"
            ;;
    esac

    case "$focus" in
        *com.efercro.os.aimor*MainActivity*) ;;
        *com.efercro.os.aimor*)
            input keyevent 4 >/dev/null 2>&1 || true
            log "sent BACK from non-main Aimor window"
            ;;
    esac
}

apply_aimor_quiet_prefs() {
    prefs=/data/data/com.efercro.os.aimor/shared_prefs/sp_moshare.xml
    [ -f "$prefs" ] || return 0

    if ! busybox grep -q 'is_show_guide" value="true"' "$prefs" 2>/dev/null \
        && ! busybox grep -q 'is_show_guide_image" value="true"' "$prefs" 2>/dev/null \
        && ! busybox grep -q 'is_show_guide_empty" value="true"' "$prefs" 2>/dev/null; then
        return 0
    fi

    am force-stop com.efercro.os.aimor >/dev/null 2>&1 || killall com.efercro.os.aimor >/dev/null 2>&1 || true
    sleep 1

    if [ ! -f "$prefs.quiet" ]; then
        cp "$prefs" "$prefs.quiet" 2>/dev/null || true
    fi

    sed -i 's/name="is_show_guide" value="true"/name="is_show_guide" value="false"/g' "$prefs"
    sed -i 's/name="is_show_guide_image" value="true"/name="is_show_guide_image" value="false"/g' "$prefs"
    sed -i 's/name="is_show_guide_empty" value="true"/name="is_show_guide_empty" value="false"/g' "$prefs"
    chmod 660 "$prefs" 2>/dev/null
    chown system:system "$prefs" 2>/dev/null
    log "aimor guide prefs suppressed"

    monkey -p com.efercro.os.aimor -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
}

run_once() {
    apply_storage_thresholds
    disable_vendor_nags
    cleanup_staging_files
    apply_aimor_quiet_prefs
    dismiss_storage_dialog
}

case "$1" in
    once) run_once ;;
    loop)
        log "popup suppress loop started"
        while true; do
            run_once
            sleep 10
        done
        ;;
    *)
        echo "Usage: $0 {once|loop}"
        exit 1
        ;;
esac
