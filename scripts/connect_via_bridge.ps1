# Connect ADB through the ESP32 Wi-Fi bridge (frame-bridge.local or configured IP).
param(
    [string]$BridgeHost = "frame-bridge.local",
    [int]$BridgePort = 5555,
    [string]$Adb = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot "frame_lib.ps1")
$Adb = Get-FrameAdbPath -Preferred $Adb

& $Adb kill-server 2>$null | Out-Null
& $Adb start-server | Out-Null

$target = "${BridgeHost}:${BridgePort}"
Write-Host "Connecting ADB via ESP bridge at $target ..."
& $Adb connect $target 2>&1 | ForEach-Object { Write-Host $_ }
Start-Sleep 2
& $Adb devices -l
