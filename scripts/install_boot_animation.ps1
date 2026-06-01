# Build bootanimation.zip from NAS boot.png and install on the frame.
param(
    [string]$Adb = "",
    [string]$Source = "\\192.168.1.23\nas\boot.png",
    [string]$Ip = "192.168.1.85",
    [switch]$BuildOnly,
    [switch]$Reboot
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
$BootAnim = Join-Path $Root "boot\bootanimation.zip"

. (Join-Path $PSScriptRoot "frame_adb.ps1")
$Adb = Get-FrameAdbPath -Preferred $Adb

Write-Host "Building boot animation from $Source ..."
python (Join-Path $Root "boot\render_bootanimation.py") --source $Source
if ($LASTEXITCODE -ne 0) { throw "render_bootanimation failed" }

if ($BuildOnly) {
    Write-Host "Built $BootAnim"
    exit 0
}

$serial = Connect-FrameDevice -Adb $Adb -Ip $Ip

Write-Host "Installing boot animation..."
Invoke-FrameAdb -Adb $Adb -Serial $serial -Args @("push", $BootAnim, "/sdcard/bootanimation.zip")

$shellScript = @'
mount -o remount,rw /system
mkdir -p /system/media
cp /sdcard/bootanimation.zip /system/media/bootanimation.zip
chmod 644 /system/media/bootanimation.zip
if [ -d /bootloader ]; then
  cp /sdcard/bootanimation.zip /bootloader/bootanimation.zip 2>/dev/null || true
fi
echo bootanimation_installed
'@ -replace "`r`n", "`n"

Invoke-FrameAdb -Adb $Adb -Serial $serial -Args @("shell", $shellScript)

Write-Host "Boot animation installed."

if ($Reboot) {
    Write-Host "Rebooting frame..."
    Invoke-FrameAdb -Adb $Adb -Serial $serial -Args @("reboot")
    Write-Host "Reboot sent."
} else {
    Write-Host "Reboot to preview:"
    Write-Host "  powershell -ExecutionPolicy Bypass -File scripts\install_boot_animation.ps1 -Reboot"
}
