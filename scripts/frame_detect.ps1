# Auto-detect picture frame model and optionally write scripts/frame.conf + nas.conf.
param(
    [string]$Adb = "",
    [switch]$WriteConfig,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "frame_lib.ps1")

$Adb = Get-FrameAdbPath -Preferred $Adb
& $Adb start-server 2>$null | Out-Null

$serial = Get-ConnectedFrameSerial -Adb $Adb
if (-not $serial) {
    try {
        $cfg = Get-FrameConfig
        $serial = Connect-FrameDevice -Adb $Adb -Ip $cfg.FrameIp -Port $cfg.FrameAdbPort
    } catch {
        $serial = $null
    }
}

if ($serial) {
    $result = Update-FrameConfigFromDevice -Adb $Adb -Serial $serial -WriteConfig:$WriteConfig
} else {
    $resolved = Resolve-FrameDeviceProfile -Adb ""
    $result = [pscustomobject]@{
        Config = Get-FrameConfig
        Detection = $resolved
    }
    if ($WriteConfig) {
        Write-Host "WARN: No ADB device connected - USB-only hints used if available."
    }
}

if ($Json) {
    $result | ConvertTo-Json -Depth 6
    exit 0
}

Show-FrameDetectionReport -Detection $result.Detection
if ($result.Config.FrameIp) {
    Write-Host "Frame IP: $($result.Config.FrameIp)"
}
if ($WriteConfig -and $serial) {
    Write-Host ""
    $confPath = Get-FrameConfigPath
    Write-Host "Wrote $confPath and scripts/nas.conf"
}
