# Recover a black-screen frame: restore stock launcher, optional splash removal, reboot.
param(
    [string]$Adb = "",
    [switch]$RestoreLauncher,
    [switch]$RemoveBootHook,
    [switch]$Reboot
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
$StockApk = Join-Path $Root "dump\launcher_aimor.apk"

. (Join-Path $PSScriptRoot "frame_adb.ps1")
$Adb = Get-FrameAdbPath -Preferred $Adb
$cfg = Get-FrameConfig
$serial = Connect-FrameDevice -Adb $Adb -Ip $cfg.FrameIp -Port $cfg.FrameAdbPort

Write-Host "Connected: $serial"

if (-not $RestoreLauncher -and -not $RemoveBootHook -and -not $Reboot) {
    $RestoreLauncher = $true
    $Reboot = $true
}

$shell = @()
if ($RestoreLauncher) {
    if (-not (Test-Path $StockApk)) {
        throw "Missing stock APK at $StockApk"
    }
    Invoke-FrameAdb -Adb $Adb -Serial $serial -Args @("push", $StockApk, "/sdcard/launcher_aimor.stock.apk")
    $shell += @'
mount -o remount,rw /system
if [ -f /system/priv-app/launcher_aimor/launcher_aimor.apk.stock ]; then
  cp /system/priv-app/launcher_aimor/launcher_aimor.apk.stock /system/priv-app/launcher_aimor/launcher_aimor.apk
else
  cp /sdcard/launcher_aimor.stock.apk /system/priv-app/launcher_aimor/launcher_aimor.apk
fi
chmod 644 /system/priv-app/launcher_aimor/launcher_aimor.apk
echo restored_launcher
'@
}

if ($RemoveBootHook) {
    $shell += @'
mount -o remount,rw /system
if [ -f /system/bin/setmacaddr.real ]; then
  cp /system/bin/setmacaddr.real /system/bin/setmacaddr
  chmod 755 /system/bin/setmacaddr
fi
echo removed_boot_hook
'@
}

if ($shell.Count -gt 0) {
    $cmd = ($shell -join "`n") -replace "`r`n", "`n"
    Invoke-FrameAdb -Adb $Adb -Serial $serial -Args @("shell", $cmd)
}

Write-Host "Recent boot log:"
Invoke-FrameAdb -Adb $Adb -Serial $serial -Args @("shell", "tail -20 /data/local/frame-sync/boot.log 2>/dev/null; logcat -d -t 30 2>/dev/null | tail -20")

if ($Reboot) {
    Write-Host "Rebooting..."
    Invoke-FrameAdb -Adb $Adb -Serial $serial -Args @("reboot")
}

Write-Host "Recovery commands sent."
