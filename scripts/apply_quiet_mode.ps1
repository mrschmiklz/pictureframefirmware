# Push quiet-mode scripts and suppress storage popups on the frame now.
param(
    [string]$Adb = ""
)

$ErrorActionPreference = "Stop"
$Scripts = $PSScriptRoot

. (Join-Path $Scripts "frame_lib.ps1")
$Adb = Get-FrameAdbPath -Preferred $Adb
$serial = Connect-FrameDevice -Adb $Adb

foreach ($name in @("suppress_popups.sh", "start_popup_guard.sh", "sync_nas.sh", "boot.sh")) {
    $local = Join-Path $Scripts $name
    if (-not (Test-Path $local)) { continue }
    Invoke-FrameAdb -Adb $Adb -Serial $serial -Args @("push", $local, "/data/local/frame-sync/$name")
    Invoke-FrameAdb -Adb $Adb -Serial $serial -Args @("shell", "chmod 755 /data/local/frame-sync/$name")
}

Invoke-FrameAdb -Adb $Adb -Serial $serial -Args @("shell", "/data/local/frame-sync/suppress_popups.sh once; /data/local/frame-sync/start_popup_guard.sh")
Write-Host "Quiet mode applied. Storage popups should stop; Aimor only restarts when photos change."
