# Deploy NAS sync tooling to the picture frame over USB/ADB.
param(
    [string]$Adb = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Rclone = Join-Path $Root "tools\rclone-v1.74.2-linux-arm\rclone"

. (Join-Path $PSScriptRoot "frame_adb.ps1")
$Adb = Get-FrameAdbPath -Preferred $Adb
$cfg = Get-FrameConfig

if (-not (Test-Path $Rclone)) {
    throw "rclone not found at $Rclone"
}

$serial = Connect-FrameDevice -Adb $Adb -Ip $cfg.FrameIp -Port $cfg.FrameAdbPort
Write-Host "Connected: $serial"

Write-Host "Creating /data/local/frame-sync on frame..."
& $Adb -s $serial shell "mkdir -p /data/local/frame-sync/bin"

Write-Host "Pushing rclone (this takes ~15s)..."
& $Adb -s $serial push $Rclone /data/local/frame-sync/bin/rclone

Write-Host "Pushing sync scripts..."
$scriptNames = @(
    "nas.conf", "sync_nas.sh", "start_sync_daemon.sh", "block_wan.sh", "boot.sh",
    "install_from_nas.sh", "install_splash.sh", "restore_usb_adb.sh",
    "process_nas_console.sh", "start_agent.sh"
)
foreach ($name in $scriptNames) {
    & $Adb -s $serial push (Join-Path $PSScriptRoot $name) "/data/local/frame-sync/$name"
}

Write-Host "Pushing Wi-Fi boot console agent..."
& $Adb -s $serial shell "mkdir -p /data/local/frame-sync/agent"
& $Adb -s $serial push (Join-Path $Root "frame-agent\agent.conf") /data/local/frame-sync/agent/agent.conf
& $Adb -s $serial push (Join-Path $Root "frame-agent\start_agent.sh") /data/local/frame-sync/agent/start_agent.sh
& $Adb -s $serial push (Join-Path $Root "frame-agent\lib") /data/local/frame-sync/agent/lib
& $Adb -s $serial push (Join-Path $Root "frame-agent\www") /data/local/frame-sync/agent/www

& $Adb -s $serial shell "chmod 755 /data/local/frame-sync/bin/rclone /data/local/frame-sync/sync_nas.sh /data/local/frame-sync/start_sync_daemon.sh /data/local/frame-sync/block_wan.sh /data/local/frame-sync/boot.sh /data/local/frame-sync/install_from_nas.sh /data/local/frame-sync/install_splash.sh /data/local/frame-sync/restore_usb_adb.sh /data/local/frame-sync/process_nas_console.sh /data/local/frame-sync/start_agent.sh /data/local/frame-sync/agent/start_agent.sh /data/local/frame-sync/agent/www/cgi-bin/*.cgi /data/local/frame-sync/agent/lib/*.sh"

Write-Host "Starting background sync daemon..."
& $Adb -s $serial shell "/data/local/frame-sync/start_sync_daemon.sh"

Write-Host ""
Write-Host "Installed. Tail logs with:"
Write-Host "  adb shell tail -f /data/local/frame-sync/sync.log"
Write-Host ""
Write-Host "Run one sync immediately with:"
Write-Host "  adb shell /data/local/frame-sync/sync_nas.sh once"
