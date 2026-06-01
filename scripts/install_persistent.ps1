# One-time install: firewall + NAS sync survive reboot via the stock setmacaddr boot hook.
param(
    [string]$Adb = ""
)

$ErrorActionPreference = "Stop"
$scriptDir = $PSScriptRoot

. (Join-Path $scriptDir "frame_lib.ps1")
$Adb = Get-FrameAdbPath -Preferred $Adb
$serial = Connect-FrameDevice -Adb $Adb

Write-Host "Step 1/3: Deploy frame-sync scripts..."
& (Join-Path $scriptDir "install.ps1") -Adb $Adb

Write-Host "Step 2/3: Push firewall + boot scripts..."
$scriptNames = @(
    "block_wan.sh", "boot.sh", "install_from_nas.sh", "install_splash.sh", "restore_usb_adb.sh",
    "process_nas_console.sh", "start_agent.sh"
)
foreach ($name in $scriptNames) {
    Invoke-FrameAdb -Adb $Adb -Serial $serial -Args @("push", (Join-Path $scriptDir $name), "/data/local/frame-sync/$name")
}
Invoke-FrameAdb -Adb $Adb -Serial $serial -Args @("shell", "chmod 755 /data/local/frame-sync/block_wan.sh /data/local/frame-sync/boot.sh /data/local/frame-sync/install_from_nas.sh /data/local/frame-sync/install_splash.sh /data/local/frame-sync/restore_usb_adb.sh")

Write-Host "Step 3/3: Install boot hook on /system (backs up stock setmacaddr)..."
$wrapperLocal = Join-Path $env:TEMP "setmacaddr_frame_wrapper"
Copy-Item (Join-Path $scriptDir "setmacaddr_wrapper.sh") $wrapperLocal -Force
Invoke-FrameAdb -Adb $Adb -Serial $serial -Args @("push", $wrapperLocal, "/data/local/frame-sync/setmacaddr_wrapper.sh")
Remove-Item $wrapperLocal -Force

$installCmd = @'
mount -o remount,rw /system
mkdir -p /data/local/frame-sync/backup
if [ ! -f /system/bin/setmacaddr.real ]; then
  cp /system/bin/setmacaddr /data/local/frame-sync/backup/setmacaddr
  cp /system/bin/setmacaddr /system/bin/setmacaddr.real
  chmod 755 /system/bin/setmacaddr.real
fi
cp /data/local/frame-sync/setmacaddr_wrapper.sh /system/bin/setmacaddr
chmod 755 /system/bin/setmacaddr
if ! grep -q '^persist.adb.tcp.port=' /system/build.prop; then
  echo '' >> /system/build.prop
  echo 'persist.adb.tcp.port=5555' >> /system/build.prop
fi
echo INSTALLED
'@ -replace "`r`n", "`n"

Invoke-FrameAdb -Adb $Adb -Serial $serial -Args @("shell", $installCmd)

Write-Host ""
Write-Host "Persistent install complete."
Write-Host "After reboot the frame will automatically:"
Write-Host "  - enable Wi-Fi ADB on port 5555"
Write-Host "  - apply LAN-only firewall"
Write-Host "  - disable OTA package"
Write-Host "  - start NAS photo sync daemon"
Write-Host ""
Write-Host "Connect over Wi-Fi (after reboot, same LAN):"
Write-Host "  powershell -ExecutionPolicy Bypass -File scripts\connect_frame.ps1"
Write-Host ""
Write-Host "Verify after reboot:"
Write-Host "  adb shell cat /data/local/frame-sync/boot.log"
Write-Host "  adb shell cat /data/local/frame-sync/wifi_adb_ip.txt"
Write-Host "  adb shell cat /data/local/frame-sync/firewall.log"
Write-Host "  adb shell iptables -L FRAME_WAN -n | head -5"
