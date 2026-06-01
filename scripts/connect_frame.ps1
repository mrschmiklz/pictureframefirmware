# Connect to the picture frame over Wi-Fi ADB (no USB required after boot hook is installed).
param(
    [string]$Adb = "",
    [string]$Ip = "192.168.1.85",
    [int]$Port = 5555
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "frame_adb.ps1")
$Adb = Get-FrameAdbPath -Preferred $Adb
$cfg = Get-FrameConfig

$usb = Get-ConnectedFrameSerial -Adb $Adb
if ($usb) {
    Write-Host "Already connected over USB: $usb"
    exit 0
}

$serial = Connect-FrameDevice -Adb $Adb -Ip $cfg.FrameIp -Port $cfg.FrameAdbPort
$model = & $Adb -s $serial shell getprop ro.product.model
Write-Host "Connected: $model at $serial"
