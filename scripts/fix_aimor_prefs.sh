#!/system/bin/sh
prefs=/data/data/com.efercro.os.aimor/shared_prefs/sp_moshare.xml
[ -f "$prefs" ] || exit 1
killall com.efercro.os.aimor >/dev/null 2>&1 || true
sleep 1
sed -i 's/name="is_show_guide" value="true"/name="is_show_guide" value="false"/g' "$prefs"
sed -i 's/name="is_show_guide_image" value="true"/name="is_show_guide_image" value="false"/g' "$prefs"
sed -i 's/name="is_show_guide_empty" value="true"/name="is_show_guide_empty" value="false"/g' "$prefs"
chmod 660 "$prefs" 2>/dev/null
chown system:system "$prefs" 2>/dev/null
grep guide "$prefs"
monkey -p com.efercro.os.aimor -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
