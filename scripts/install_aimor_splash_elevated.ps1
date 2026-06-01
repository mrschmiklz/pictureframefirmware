# One UAC prompt: install Allwinner USB driver, then deploy custom boot splash.
param(
    [string]$Source = "\\192.168.1.23\nas\boot.png",
    [string]$Ip = "192.168.1.85",
    [switch]$Reboot
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
$DriverInf = Join-Path $Root "boot\tools\usb_driver\frame_allwinner_adb.inf"
$InstallScript = Join-Path $PSScriptRoot "install_aimor_splash.ps1"

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    Write-Host "Requesting Administrator access to install the USB driver..."
    $argList = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $PSCommandPath,
        "-Source", $Source,
        "-Ip", $Ip
    )
    if ($Reboot) { $argList += "-Reboot" }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argList -Wait
    exit $LASTEXITCODE
}

Write-Host "=== Admin: install Allwinner ADB driver ==="
if (-not (Test-Path $DriverInf)) {
    throw "Missing driver inf: $DriverInf"
}

& pnputil /add-driver $DriverInf /install
Start-Sleep 3

Write-Host ""
Write-Host "=== Restart ADB ==="
. (Join-Path $PSScriptRoot "frame_adb.ps1")
$Adb = Get-FrameAdbPath

& $Adb kill-server 2>$null
Start-Sleep 1
& $Adb start-server

$deadline = (Get-Date).AddSeconds(30)
$serial = $null
while ((Get-Date) -lt $deadline) {
    $serial = Get-ConnectedFrameSerial -Adb $Adb
    if ($serial) { break }
    Start-Sleep 2
}

if (-not $serial) {
    Write-Host "ADB still empty after driver install."
    Write-Host "Unplug/replug the USB cable, wait 5 seconds, then run:"
    Write-Host "  powershell -ExecutionPolicy Bypass -File scripts\\install_aimor_splash.ps1 -Reboot"
    exit 1
}

Write-Host "ADB connected: $serial"
Write-Host ""
Write-Host "=== Deploy custom splash ==="
$installArgs = @("-ExecutionPolicy", "Bypass", "-File", $InstallScript, "-Source", $Source, "-Ip", $Ip)
if ($Reboot) { $installArgs += "-Reboot" }
& powershell.exe @installArgs
exit $LASTEXITCODE
