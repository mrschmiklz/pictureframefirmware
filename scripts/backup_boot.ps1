# Pull stock boot partition from the frame (requires USB or Wi-Fi ADB).
param(
    [string]$Adb = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe\platform-tools\adb.exe",
    [string]$OutDir = (Join-Path (Split-Path $PSScriptRoot -Parent) "dump")
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Adb)) {
    throw "adb not found at $Adb"
}

$state = & $Adb get-state 2>&1
if ($state -ne "device") {
    throw "Frame not connected. Plug in USB or run scripts\connect_frame.ps1"
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$remote = "/sdcard/boot.stock.img"
$local = Join-Path $OutDir "boot.stock.img"

Write-Host "Dumping boot partition to $remote ..."
& $Adb shell "dd if=/dev/block/by-name/boot of=$remote bs=4096"

Write-Host "Pulling $local ..."
& $Adb pull $remote $local

Write-Host "Bootloader partition listing:"
& $Adb shell "ls -laR /bootloader 2>/dev/null | head -40"

Write-Host ""
Write-Host "Saved stock boot image: $local"
Write-Host "Keep this file safe — it is your restore point."
