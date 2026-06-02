#!/system/bin/sh
# Install custom bootanimation + patched Aimor launcher. Requires root.
# Reads from /sdcard/bootanimation.zip and /sdcard/launcher_aimor.signed.apk

SYNC_HOME=/data/local/frame-sync
LOG="$SYNC_HOME/splash.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"
}

if [ "$(id -u)" != "0" ]; then
    log "ERROR root required"
    exit 1
fi

changed=0

mount -o remount,rw /system 2>/dev/null || {
    log "ERROR could not remount /system rw"
    exit 1
}

if [ -f /sdcard/bootanimation.zip ]; then
    mkdir -p /system/media
    cp /sdcard/bootanimation.zip /system/media/bootanimation.zip
    chmod 644 /system/media/bootanimation.zip
    if [ -d /bootloader ]; then
        cp /sdcard/bootanimation.zip /bootloader/bootanimation.zip 2>/dev/null || true
    fi
    log "installed bootanimation.zip"
    changed=1
fi

if [ -f /sdcard/launcher_aimor.signed.apk ]; then
    mkdir -p /system/priv-app/launcher_aimor
    if [ ! -f /system/priv-app/launcher_aimor/launcher_aimor.apk.stock ]; then
        cp /system/priv-app/launcher_aimor/launcher_aimor.apk \
            /system/priv-app/launcher_aimor/launcher_aimor.apk.stock 2>/dev/null || true
    fi
    cp /sdcard/launcher_aimor.signed.apk /system/priv-app/launcher_aimor/launcher_aimor.apk
    chmod 644 /system/priv-app/launcher_aimor/launcher_aimor.apk
    log "installed launcher_aimor.apk"
    changed=1
fi

prefs=/data/data/com.efercro.os.aimor/shared_prefs/sp_moshare.xml
if [ -f "$prefs" ]; then
    if [ ! -f "$prefs.stock" ]; then
        cp "$prefs" "$prefs.stock"
    fi
    sed -i 's/name="is_show_guide" value="true"/name="is_show_guide" value="false"/g' "$prefs"
    sed -i 's/name="is_show_guide_image" value="true"/name="is_show_guide_image" value="false"/g' "$prefs"
    sed -i 's/name="is_show_guide_empty" value="true"/name="is_show_guide_empty" value="false"/g' "$prefs"
    grep -q 'name="start_up_time"' "$prefs" || echo '    <long name="start_up_time" value="3000" />' >> "$prefs"
    sed -i 's/name="start_up_time" value="[0-9]*"/name="start_up_time" value="3000"/g' "$prefs"
    chmod 660 "$prefs"
    chown system:system "$prefs"
    log "updated Aimor prefs (guide off, 3s startup)"
fi

if [ "$changed" = "1" ]; then
    rm -f /sdcard/bootanimation.zip /sdcard/launcher_aimor.signed.apk 2>/dev/null
    echo "aimor_splash_installed"
    log "splash install complete"
    exit 0
fi

log "nothing to install"
exit 0
