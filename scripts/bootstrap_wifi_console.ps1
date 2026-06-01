# Bootstrap Wi-Fi boot console: publish to NAS, queue commands, try USB deploy.
param(
    [switch]$SkipUsb
)

$ErrorActionPreference = "Stop"
$Scripts = $PSScriptRoot

Write-Host "=== Wi-Fi Boot Console Bootstrap ==="

Write-Host "1) Publish deploy bundle + agent to NAS..."
& (Join-Path $Scripts "publish_to_nas.ps1")

Write-Host "2) Queue NAS commands (works without inbound ports)..."
& (Join-Path $Scripts "queue_nas_command.ps1") -Command "pull_deploy"
& (Join-Path $Scripts "queue_nas_command.ps1") -Command "start_agent"
& (Join-Path $Scripts "queue_nas_command.ps1") -Command "install_splash"

if (-not $SkipUsb) {
    Write-Host "3) Try USB deploy (fast path if driver works)..."
    try {
        . (Join-Path $Scripts "frame_adb.ps1")
        $Adb = Get-FrameAdbPath
        $cfg = Get-FrameConfig
        $serial = Connect-FrameDevice -Adb $Adb -Ip $cfg.FrameIp -Port $cfg.FrameAdbPort
        Write-Host "USB/Wi-Fi ADB connected: $serial"
        & (Join-Path $Scripts "install.ps1") -Adb $Adb
        & (Join-Path $Scripts "install_persistent.ps1") -Adb $Adb
        Invoke-FrameAdb -Adb $Adb -Serial $serial -Args @("shell", "/data/local/frame-sync/start_agent.sh start")
        Invoke-FrameAdb -Adb $Adb -Serial $serial -Args @("shell", "/data/local/frame-sync/process_nas_console.sh once")
        Write-Host "USB deploy complete."
    } catch {
        Write-Host "USB deploy skipped: $($_.Exception.Message)"
        Write-Host "Frame will pick up NAS queue on next sync (<=5 min) if sync daemon is already running."
    }
}

Write-Host ""
Write-Host "4) Start PC console UI:"
Write-Host "   scripts\START_WIFI_CONSOLE.cmd"
Write-Host ""
Write-Host "Direct frame UI (once agent is up): http://192.168.1.85:8080/"
