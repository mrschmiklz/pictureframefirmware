#!/system/bin/sh
# Restore USB ADB if Wi-Fi shell access works. Does not remove LAN firewall.
setprop persist.adb.tcp.port ""
setprop service.adb.tcp.port ""
setprop ctl.restart adbd 2>/dev/null || { stop adbd; start adbd; }
echo usb_adb_reset
