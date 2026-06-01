# Queue recovery commands on NAS (runs when frame Wi-Fi/sync comes back).
$ErrorActionPreference = "Stop"
& (Join-Path $PSScriptRoot "queue_nas_command.ps1") -Command "pull_deploy"
& (Join-Path $PSScriptRoot "queue_nas_command.ps1") -Command "copy_nas:frame-deploy/agent/www/index.html>/dev/null"
# Restore stock launcher from deploy if we saved a .stock on device - use reboot to retry boot
& (Join-Path $PSScriptRoot "queue_nas_command.ps1") -Command "reboot"
Write-Host "Queued NAS recovery reboot. Frame needs Wi-Fi for this to run."
