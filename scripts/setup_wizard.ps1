# Interactive first-run wizard: detect frame, ask for NAS, write config, run full setup.
param(
    [string]$Adb = "",
    [switch]$SkipSetup,
    [switch]$SkipSplash,
    [switch]$SkipReboot,
    [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"
$Scripts = $PSScriptRoot
. (Join-Path $Scripts "frame_lib.ps1")

Write-Host "=== Picture Frame Setup Wizard ==="
Write-Host "Host OS: $(Get-FrameHostOs)"
Write-Host ""

$Adb = Get-FrameAdbPath -Preferred $Adb
Write-Host "Using adb: $Adb"
& $Adb kill-server 2>$null | Out-Null
Start-Sleep 1
& $Adb start-server | Out-Null

$cfg = Get-FrameConfig
$configExists = Test-Path (Get-FrameConfigPath)

if (-not $configExists -and -not $NonInteractive) {
    Write-Host "No scripts/frame.conf yet — we'll create one."
    Write-Host ""
    $defaultNas = $cfg.NasHost
    $nas = Read-Host "NAS IP or hostname [$defaultNas]"
    if ($nas) { $cfg.NasHost = $nas.Trim() }
    $share = Read-Host "NAS share name [$($cfg.NasShare)]"
    if ($share) { $cfg.NasShare = $share.Trim() }
    $cfg.BootSource = Get-FrameNasUncPath -Cfg $cfg -SubPath "boot.png"
}

Write-Host ""
Write-Host "Looking for a connected frame (USB or Wi-Fi ADB)..."
$serial = $null
$deadline = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt $deadline) {
    $serial = Get-ConnectedFrameSerial -Adb $Adb
    if ($serial) { break }
    try {
        $serial = Connect-FrameDevice -Adb $Adb -Ip $cfg.FrameIp -Port $cfg.FrameAdbPort
        if ($serial) { break }
    } catch {}
    Write-Host "  waiting for device..."
    Start-Sleep 3
}

if ($serial) {
    $result = Update-FrameConfigFromDevice -Adb $Adb -Serial $serial -WriteConfig
    $cfg = $result.Config
    Show-FrameDetectionReport -Detection $result.Detection
    Write-Host ""
    Write-Host "Saved frame IP: $($cfg.FrameIp)"
    if (-not $NonInteractive) {
        $confirm = Read-Host "Use this device profile [$($cfg.DeviceProfile)]? [Y/n]"
        if ($confirm -match '^[Nn]') {
            Write-Host "Edit DEVICE_PROFILE in scripts/frame.conf and re-run setup."
            exit 1
        }
    }
} else {
    Write-Host ""
    Write-Host "WARN: Could not connect over ADB yet."
    if ((Get-FrameHostOs) -eq "windows") {
        Write-Host "Plug in USB, then run setup again. Windows may need the Allwinner driver (setup will offer UAC)."
    } else {
        Write-Host "Plug in USB and authorize the RSA fingerprint on the frame if prompted."
    }
    if (-not $NonInteractive) {
        $cont = Read-Host "Continue anyway and save NAS settings only? [y/N]"
        if ($cont -notmatch '^[Yy]') { exit 1 }
    }
    Save-FrameConfig -Cfg $cfg
}

Write-Host ""
$rclonePath = Get-FrameRclonePath -Profile (Get-FrameDeviceProfile -ProfileId $cfg.DeviceProfile)
if (-not (Test-Path $rclonePath)) {
    Write-Host "NOTE: Download rclone for the frame CPU and place it at:"
    Write-Host "  $rclonePath"
    Write-Host "  https://rclone.org/downloads/"
    Write-Host ""
}

if ($SkipSetup) {
    Write-Host "Config ready. Run setup when the frame is connected."
    exit 0
}

$setupArgs = @("-ExecutionPolicy", "Bypass", "-File", (Join-Path $Scripts "setup_frame.ps1"), "-Adb", $Adb)
if ($SkipSplash) { $setupArgs += "-SkipSplash" }
if ($SkipReboot) { $setupArgs += "-SkipReboot" }
& powershell.exe @setupArgs
exit $LASTEXITCODE
