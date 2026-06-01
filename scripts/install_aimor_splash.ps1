# Replace Aimor splash + Android boot animation using NAS boot.png.
param(
    [string]$Adb = "",
    [string]$Source = "\\192.168.1.23\nas\boot.png",
    [string]$Ip = "192.168.1.85",
    [switch]$BuildOnly,
    [switch]$Reboot
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
$BootDir = Join-Path $Root "boot"
$DumpDir = Join-Path $Root "dump"
$StockApk = Join-Path $DumpDir "launcher_aimor.apk"
$PatchedApk = Join-Path $BootDir "launcher_aimor.patched.apk"
$SignedApk = Join-Path $BootDir "launcher_aimor.signed.apk"

. (Join-Path $PSScriptRoot "frame_adb.ps1")
$Adb = Get-FrameAdbPath -Preferred $Adb
$cfg = Get-FrameConfig
if (-not $PSBoundParameters.ContainsKey("Source")) { $Source = $cfg.BootSource }
if (-not $PSBoundParameters.ContainsKey("Ip")) { $Ip = $cfg.FrameIp }

Write-Host "Step 1/4: Build Android bootanimation.zip from $Source"
python (Join-Path $BootDir "render_bootanimation.py") --source $Source
if ($LASTEXITCODE -ne 0) { throw "render_bootanimation failed" }

Write-Host "Step 2/4: Patch Aimor launcher splash PNGs"
if (Test-Path $StockApk) {
    python (Join-Path $BootDir "tools\patch_aimor_apk.py") --source $Source --input-apk $StockApk --output-apk $PatchedApk
    if ($LASTEXITCODE -ne 0) { throw "patch_aimor_apk failed" }
    Write-Host "Step 3/4: Sign patched Aimor APK (AOSP testkey)"
    python (Join-Path $BootDir "tools\sign_apk_testkey.py") $PatchedApk $SignedApk
    if ($LASTEXITCODE -ne 0) { throw "sign_apk_testkey failed" }
} else {
    Write-Host "No local stock APK; will pull from frame after connect."
}

if ($BuildOnly) {
    Write-Host "Built:"
    Write-Host "  $(Join-Path $BootDir 'bootanimation.zip')"
    Write-Host "  $SignedApk"
    exit 0
}

$serial = Connect-FrameDevice -Adb $Adb -Ip $Ip

if (-not (Test-Path $StockApk)) {
    Write-Host "Pulling stock launcher APK from frame..."
    Invoke-FrameAdb -Adb $Adb -Serial $serial -Args @("pull", "/system/priv-app/launcher_aimor/launcher_aimor.apk", $StockApk)
    Write-Host "Patching pulled stock APK..."
    python (Join-Path $BootDir "tools\patch_aimor_apk.py") --source $Source --input-apk $StockApk --output-apk $PatchedApk
    if ($LASTEXITCODE -ne 0) { throw "patch_aimor_apk failed" }
    python (Join-Path $BootDir "tools\sign_apk_testkey.py") $PatchedApk $SignedApk
    if ($LASTEXITCODE -ne 0) { throw "sign_apk_testkey failed" }
}

Write-Host "Step 4/4: Install on frame..."
Invoke-FrameAdb -Adb $Adb -Serial $serial -Args @("push", (Join-Path $BootDir "bootanimation.zip"), "/sdcard/bootanimation.zip")
Invoke-FrameAdb -Adb $Adb -Serial $serial -Args @("push", $SignedApk, "/sdcard/launcher_aimor.signed.apk")
Invoke-FrameAdb -Adb $Adb -Serial $serial -Args @("push", (Join-Path $PSScriptRoot "install_splash.sh"), "/data/local/frame-sync/install_splash.sh")
Invoke-FrameAdb -Adb $Adb -Serial $serial -Args @("shell", "chmod 755 /data/local/frame-sync/install_splash.sh; sh /data/local/frame-sync/install_splash.sh")

Write-Host ""
Write-Host "Installed custom boot splash:"
Write-Host "  Android boot animation: /system/media/bootanimation.zip"
Write-Host "  Aimor splash backgrounds patched in launcher_aimor.apk"
Write-Host "  Guide screens disabled; startup timer shortened"
Write-Host ""
Write-Host "Note: the 3-2-1 countdown is still drawn as text over your image."

if ($Reboot) {
    Write-Host "Rebooting..."
    Invoke-FrameAdb -Adb $Adb -Serial $serial -Args @("reboot")
} else {
    Write-Host "Reboot to apply:"
    Write-Host "  powershell -ExecutionPolicy Bypass -File scripts\install_aimor_splash.ps1 -Reboot"
}
