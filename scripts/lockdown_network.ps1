# Apply LAN-only firewall and disable cloud/OTA packages on the frame.
param(
    [string]$Adb = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe\platform-tools\adb.exe",
    [string]$LanDns = "192.168.1.1"
)

$ErrorActionPreference = "Stop"
$scriptDir = $PSScriptRoot

& $Adb push (Join-Path $scriptDir "block_wan.sh") /data/local/frame-sync/block_wan.sh
& $Adb shell "chmod 755 /data/local/frame-sync/block_wan.sh"
& $Adb shell "/data/local/frame-sync/block_wan.sh"

Write-Host "Disabling OTA updater package..."
& $Adb shell "pm disable com.yhk.qeota 2>/dev/null || true"

Write-Host "Firewall status:"
& $Adb shell "iptables -L FRAME_WAN -n 2>/dev/null | head -15"
Write-Host "Done. This is a one-shot apply; for reboot persistence run:"
Write-Host "  powershell -ExecutionPolicy Bypass -File scripts\install_persistent.ps1"
Write-Host "Tail firewall log: adb shell cat /data/local/frame-sync/firewall.log"
