# Complete picture frame setup: USB driver, NAS sync, firewall, splash, NAS OTA publish.
param(
    [string]$Adb = "",
    [switch]$SkipSplash,
    [switch]$SkipReboot,
    [switch]$SkipDetect
)

$ErrorActionPreference = "Stop"
$Scripts = $PSScriptRoot
$Root = Split-Path $Scripts -Parent
$DriverInf = Join-Path $Root "boot\tools\usb_driver\frame_allwinner_adb.inf"

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-UsbDriver {
    param([string[]]$VidPidPatterns = @("VID_1F3A&PID_1007"))

    if (-not (Test-Path $DriverInf)) {
        Write-Host "WARN: driver inf missing, skipping driver install"
        return
    }

    $frame = @()
    foreach ($pattern in $VidPidPatterns) {
        $frame += Get-PnpDevice | Where-Object { $_.InstanceId -match $pattern }
    }
    if (-not $frame) {
        Write-Host "Frame not on USB - plug in USB cable to continue"
        return
    }

    $unknown = $frame | Where-Object { $_.Status -eq "Unknown" }
    if (-not $unknown) { return }

    if (-not (Test-IsAdmin)) {
        Write-Host "Requesting Administrator to install USB driver..."
        Write-Host "Click YES on the UAC prompt within 60 seconds."
        $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath)
        if ($SkipSplash) { $argList += "-SkipSplash" }
        if ($SkipReboot) { $argList += "-SkipReboot" }
        if ($SkipDetect) { $argList += "-SkipDetect" }
        $proc = Start-Process powershell.exe -Verb RunAs -ArgumentList $argList -PassThru
        $proc.WaitForExit(60000) | Out-Null
        if (-not $proc.HasExited) {
            $proc.Kill()
            throw "UAC prompt timed out. Right-click setup.cmd and choose Run as administrator."
        }
        exit $proc.ExitCode
    }

    Write-Host "Installing Allwinner USB driver..."
    & pnputil /add-driver $DriverInf /install
    Start-Sleep 3
}

. (Join-Path $Scripts "frame_lib.ps1")
$Adb = Get-FrameAdbPath -Preferred $Adb
$cfg = Get-FrameConfig
$profilePreview = Resolve-FrameDeviceProfile -PreferredId $cfg.DeviceProfile
$vidPatterns = @("VID_1F3A&PID_1007")
if ($profilePreview.Profile.match.usb_vid_pid) {
    $vidPatterns = @($profilePreview.Profile.match.usb_vid_pid | ForEach-Object {
        $parts = $_ -split ':'
        if ($parts.Count -eq 2) { "VID_$($parts[0])&PID_$($parts[1])" } else { $_ }
    })
}

Ensure-UsbDriver -VidPidPatterns $vidPatterns

Write-Host ""
Write-Host "=== Step 1/6: Connect ADB ==="
& $Adb kill-server 2>$null
Start-Sleep 1
& $Adb start-server

$serial = $null
$deadline = (Get-Date).AddSeconds(45)
while ((Get-Date) -lt $deadline) {
    try {
        $serial = Connect-FrameDevice -Adb $Adb -Ip $cfg.FrameIp -Port $cfg.FrameAdbPort
        break
    } catch {
        Start-Sleep 3
    }
}
if (-not $serial) { throw "Could not connect to frame over USB or Wi-Fi ADB" }

if (-not $SkipDetect) {
    $detect = Update-FrameConfigFromDevice -Adb $Adb -Serial $serial -WriteConfig
    $cfg = $detect.Config
    Show-FrameDetectionReport -Detection $detect.Detection
    if (-not $SkipSplash -and -not $detect.Detection.Profile.device.splash_patch) {
        Write-Host "Skipping splash for this device profile (splash_patch=false)."
        $SkipSplash = $true
    }
}

Write-Host ""
Write-Host "=== Step 2/6: Deploy NAS sync tools ==="
& (Join-Path $Scripts "install.ps1") -Adb $Adb

Write-Host ""
Write-Host "=== Step 3/6: Persistent boot hook (firewall + Wi-Fi ADB + sync on boot) ==="
& (Join-Path $Scripts "install_persistent.ps1") -Adb $Adb

Write-Host ""
Write-Host "=== Step 4/6: Apply firewall now ==="
& (Join-Path $Scripts "lockdown_network.ps1") -Adb $Adb

if (-not $SkipSplash) {
    Write-Host ""
    Write-Host "=== Step 5/6: Install custom boot splash ==="
    $splashArgs = @("-ExecutionPolicy", "Bypass", "-File", (Join-Path $Scripts "install_aimor_splash.ps1"), "-Source", $cfg.BootSource, "-Ip", $cfg.FrameIp, "-Adb", $Adb)
    & powershell.exe @splashArgs
    if ($LASTEXITCODE -ne 0) { throw "splash install failed" }
}

Write-Host ""
Write-Host "=== Step 6/6: Publish OTA bundle + Wi-Fi boot console ==="
& (Join-Path $Scripts "bootstrap_wifi_console.ps1") -SkipUsb

Write-Host ""
Write-Host "Enabling Wi-Fi ADB for unplugging USB..."
Invoke-FrameAdb -Adb $Adb -Serial $serial -Args @("tcpip", "$($cfg.FrameAdbPort)")
Start-Sleep 2
Invoke-FrameAdb -Adb $Adb -Serial $serial -Args @("connect", "$($cfg.FrameIp):$($cfg.FrameAdbPort)")

Write-Host ""
Write-Host "Setup complete."
Write-Host "  Device:  $($cfg.DeviceProfile)"
Write-Host "  Photos: drop in \\$($cfg.NasHost)\$($cfg.NasShare)\$($cfg.NasPhotosPath)"
Write-Host "  Updates: run publish_to_nas.ps1 after changing boot.png or scripts"
Write-Host "  Test:    powershell -ExecutionPolicy Bypass -File scripts\test_frame.ps1"

if (-not $SkipReboot) {
    Write-Host ""
    Write-Host "Rebooting frame..."
    Invoke-FrameAdb -Adb $Adb -Serial $serial -Args @("reboot")
}
