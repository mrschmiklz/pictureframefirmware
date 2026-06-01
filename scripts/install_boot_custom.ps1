# Install custom boot animation + optional custom boot.img on the picture frame.
param(
    [string]$Adb = "",
    [switch]$SkipBackup,
    [switch]$BootAnimationOnly,
    [switch]$FlashBoot,
    [switch]$RestoreStockBoot
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
$StockBoot = Join-Path $Root "dump\boot.stock.img"
$CustomBoot = Join-Path $Root "boot\boot.custom.img"
$BootAnim = Join-Path $Root "boot\bootanimation.zip"

. (Join-Path $PSScriptRoot "frame_adb.ps1")
$Adb = Get-FrameAdbPath -Preferred $Adb
$script:FrameSerial = $null

function Ensure-FrameDevice {
    if (-not $script:FrameSerial) {
        $script:FrameSerial = Connect-FrameDevice -Adb $Adb
    }
}

function Invoke-Adb {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    Ensure-FrameDevice
    & $Adb -s $script:FrameSerial @Args
}

function Restore-StockSetmacaddr {
    Write-Host "Restoring stock /system/bin/setmacaddr (boot.img now owns the boot hook)..."
    Invoke-Adb shell @'
mount -o remount,rw /system
if [ -f /system/bin/setmacaddr.real ]; then
  cp /system/bin/setmacaddr.real /system/bin/setmacaddr
  chmod 755 /system/bin/setmacaddr
fi
echo setmacaddr_restored
'@
}

if ($RestoreStockBoot) {
    Ensure-FrameDevice
    if (-not (Test-Path $StockBoot)) {
        throw "Missing stock backup: $StockBoot"
    }
    Write-Host "Restoring stock boot partition..."
    Invoke-Adb push $StockBoot /sdcard/boot.stock.img
    Invoke-Adb shell "dd if=/sdcard/boot.stock.img of=/dev/block/by-name/boot bs=4096"
    Write-Host "Stock boot restored. Reboot the frame."
    exit 0
}

Ensure-FrameDevice

if (-not $SkipBackup -and -not (Test-Path $StockBoot)) {
    Write-Host "No stock boot backup found - creating one first..."
    & (Join-Path $PSScriptRoot "backup_boot.ps1") -Adb $Adb
}

if (-not (Test-Path $BootAnim) -or (-not $BootAnimationOnly -and -not (Test-Path $CustomBoot))) {
    & (Join-Path $PSScriptRoot "build_boot_custom.ps1")
}

Write-Host "Deploying frame-sync scripts (boot.sh must exist before first reboot)..."
& (Join-Path $PSScriptRoot "install.ps1") -Adb $Adb
Invoke-Adb push (Join-Path $PSScriptRoot "block_wan.sh") /data/local/frame-sync/block_wan.sh
Invoke-Adb push (Join-Path $PSScriptRoot "boot.sh") /data/local/frame-sync/boot.sh
Invoke-Adb shell "chmod 755 /data/local/frame-sync/block_wan.sh /data/local/frame-sync/boot.sh"

Write-Host "Installing boot animation..."
Invoke-Adb push $BootAnim /sdcard/bootanimation.zip
Invoke-Adb shell @'
mount -o remount,rw /system
mkdir -p /system/media
cp /sdcard/bootanimation.zip /system/media/bootanimation.zip
chmod 644 /system/media/bootanimation.zip
if [ -d /bootloader ]; then
  cp /sdcard/bootanimation.zip /bootloader/bootanimation.zip 2>/dev/null || true
fi
echo bootanimation_installed
'@

if ($BootAnimationOnly) {
    Write-Host "Boot animation installed. Reboot to preview."
    exit 0
}

if (-not $FlashBoot) {
    Write-Host ""
    Write-Host "Custom boot.img is built but NOT flashed yet."
    Write-Host "Review boot\boot.custom.img, then run:"
    Write-Host '  powershell -ExecutionPolicy Bypass -File scripts\install_boot_custom.ps1 -FlashBoot'
    exit 0
}

Write-Host "Flashing custom boot.img (keep USB connected until reboot finishes)..."
Invoke-Adb push $CustomBoot /sdcard/boot.custom.img
Invoke-Adb shell "dd if=/sdcard/boot.custom.img of=/dev/block/by-name/boot bs=4096"
Restore-StockSetmacaddr

Write-Host ""
Write-Host "Custom boot installed."
Write-Host "  - boot animation on /system/media/bootanimation.zip"
Write-Host "  - init.rc starts /data/local/frame-sync/boot.sh on every boot"
Write-Host "  - stock setmacaddr wrapper removed"
Write-Host ""
Write-Host "Reboot with:"
Write-Host '  powershell -ExecutionPolicy Bypass -File scripts\install_boot_animation.ps1 -Reboot'
Write-Host "If the frame fails to boot, restore with:"
Write-Host '  powershell -ExecutionPolicy Bypass -File scripts\install_boot_custom.ps1 -RestoreStockBoot'
