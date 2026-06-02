#!/system/bin/sh
# Sync photos from a Samba share into Aimor's slideshow folder and update its DB.

SYNC_HOME=/data/local/frame-sync
CONFIG="$SYNC_HOME/nas.conf"
RCLONE="$SYNC_HOME/bin/rclone"
LOG="$SYNC_HOME/sync.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"
}

load_config() {
    if [ ! -f "$CONFIG" ]; then
        log "ERROR missing config: $CONFIG"
        exit 1
    fi
    . "$CONFIG"
    AIMOR_PKG=${AIMOR_PKG:-com.efercro.os.aimor}
    AIMOR_DB=${AIMOR_DB:-/data/data/$AIMOR_PKG/databases/db_aimor.db}
    PHOTO_WIDTH=${PHOTO_WIDTH:-1280}
    PHOTO_HEIGHT=${PHOTO_HEIGHT:-800}
    DB="$AIMOR_DB"
    AIMOR="$AIMOR_PKG"
}

wait_for_network() {
    tries=0
    while [ "$tries" -lt 12 ]; do
        if busybox ping -c 1 -W 2 "$NAS_HOST" >/dev/null 2>&1; then
            return 0
        fi
        tries=$((tries + 1))
        sleep 5
    done
    return 1
}

is_image() {
    case "$(echo "$1" | busybox tr '[:upper:]' '[:lower:]')" in
        *.jpg|*.jpeg|*.png|*.gif|*.webp|*.bmp) return 0 ;;
        *) return 1 ;;
    esac
}

sql_escape() {
    echo "$1" | busybox sed "s/'/''/g"
}

register_new_files() {
    now_ms=$(busybox date +%s)
    now_ms=$((now_ms * 1000))
    upload_time=$(busybox date '+%Y/%m/%d %H:%M')

    for file in "$IMAGE_DIR"/*; do
        [ -f "$file" ] || continue
        name=$(basename "$file")
        is_image "$name" || continue

        esc_name=$(sql_escape "$name")
        count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM MEDIA_BEAN WHERE DEST_FILE_NAME='$esc_name';")
        [ "$count" = "0" ] || continue

        media_path="/storage/emulated/0/aimor/image/$name"
        sqlite3 "$DB" "INSERT INTO MEDIA_BEAN (DEST_FILE_NAME,MEDIA_TYPE,IS_DISPLAY,TITLE,U_ID,MEDIA_PATH,IS_AUTO_PLAY,DURATION,MUTE,SCALE_TYPE,MAX_SCALE,MIN_SCALE,M_MULTIPLE,FOCUS_X,FOCUS_Y,TAKEN_PIC_TIME,UPLOAD_TIME,UPLOAD_TIME_LONG,PHOTO_WIDTH,PHOTOHEIGHT,LIKED,GROUP_LABEL) VALUES ('$esc_name',0,0,'$esc_name',0,'$media_path',0,0.0,0,1,1.0,1.0,1.0,0.5,0.5,$now_ms,'$upload_time',$now_ms,$PHOTO_WIDTH,$PHOTO_HEIGHT,0,'');"
        log "registered $name"
        PHOTOS_CHANGED=1
    done
}

remove_missing_files() {
    [ "$MIRROR_MODE" = "1" ] || return 0

    list="$SYNC_HOME/tmp/media_names.list"
    sqlite3 "$DB" "SELECT DEST_FILE_NAME FROM MEDIA_BEAN;" > "$list"
    while read name; do
        [ -n "$name" ] || continue
        if [ ! -f "$IMAGE_DIR/$name" ]; then
            esc_name=$(sql_escape "$name")
            sqlite3 "$DB" "DELETE FROM MEDIA_BEAN WHERE DEST_FILE_NAME='$esc_name';"
            log "removed missing $name"
            PHOTOS_CHANGED=1
        fi
    done < "$list"
}

refresh_aimor() {
    am force-stop "$AIMOR"
    sleep 2
    monkey -p "$AIMOR" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
}

run_sync_once() {
    load_config
    mkdir -p "$IMAGE_DIR" "$SYNC_HOME/tmp"

    if [ ! -x "$RCLONE" ]; then
        log "ERROR missing rclone: $RCLONE"
        return 1
    fi

    if ! wait_for_network; then
        log "WARN NAS host unreachable: $NAS_HOST"
        return 1
    fi

    remote=":smb,host=${NAS_HOST},share=${NAS_SHARE},path=${NAS_PATH}:"
    rclone_args="sync --config /dev/null --low-level-retries 1 --retries 1 --timeout 30s"
    rclone_args="$rclone_args --include *.jpg --include *.jpeg --include *.png --include *.gif --include *.webp --include *.bmp"

    if [ -n "$NAS_USER" ]; then
        rclone_args="$rclone_args --smb-user $NAS_USER --smb-pass $NAS_PASS"
    fi

    log "sync start $remote -> $IMAGE_DIR"
    # shellcheck disable=SC2086
    if ! $RCLONE $rclone_args "$remote" "$IMAGE_DIR" >> "$LOG" 2>&1; then
        log "ERROR rclone sync failed"
        return 1
    fi

    flatten_nested_sync() {
        nested="$IMAGE_DIR/nas/framepics"
        if [ ! -d "$nested" ]; then
            return 0
        fi
        for file in "$nested"/*; do
            [ -f "$file" ] || continue
            name=$(basename "$file")
            mv "$file" "$IMAGE_DIR/$name"
        done
        rm -rf "$IMAGE_DIR/nas"
        log "flattened nested NAS paths into $IMAGE_DIR"
    }
    flatten_nested_sync

    PHOTOS_CHANGED=0
    register_new_files
    remove_missing_files
    if [ "$PHOTOS_CHANGED" = "1" ]; then
        refresh_aimor
    else
        log "no photo changes; skipping Aimor restart"
    fi

    if [ -x "$SYNC_HOME/install_from_nas.sh" ]; then
        "$SYNC_HOME/install_from_nas.sh" once >> "$LOG" 2>&1 || log "WARN deploy check failed"
    fi

    if [ -x "$SYNC_HOME/process_nas_console.sh" ]; then
        "$SYNC_HOME/process_nas_console.sh" once >> "$LOG" 2>&1 || log "WARN console check failed"
    fi

    log "sync complete"
    return 0
}

case "$1" in
    once)
        run_sync_once
        ;;
    loop)
        load_config
        log "daemon started interval=${SYNC_INTERVAL}s"
        while true; do
            run_sync_once
            sleep "$SYNC_INTERVAL"
        done
        ;;
    *)
        echo "Usage: $0 {once|loop}"
        exit 1
        ;;
esac
