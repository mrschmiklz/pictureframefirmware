#!/system/bin/sh
# Installed as /system/bin/setmacaddr by install_persistent.ps1.
# Preserves stock Wi-Fi MAC setup, then starts frame-sync boot tasks.

if [ -x /system/bin/setmacaddr.real ]; then
    /system/bin/setmacaddr.real "$@"
fi

/system/bin/sh /data/local/frame-sync/boot.sh >/dev/null 2>&1 &
exit 0
