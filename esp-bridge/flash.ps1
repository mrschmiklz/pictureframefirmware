# ESP32 bridge — flash and monitor helpers (Windows)

param(
    [string]$Port = "",
    [switch]$MonitorOnly,
    [switch]$BuildOnly
)

$ErrorActionPreference = "Stop"
$BridgeDir = $PSScriptRoot
$Secrets = Join-Path $BridgeDir "secrets.ini"
$SecretsExample = Join-Path $BridgeDir "secrets.example.ini"

if (-not (Test-Path $Secrets)) {
    if (Test-Path $SecretsExample) {
        Copy-Item $SecretsExample $Secrets
        Write-Host "Created secrets.ini from example — edit Wi-Fi + frame IP, then re-run."
        exit 1
    }
    throw "Missing secrets.ini"
}

function Ensure-PlatformIo {
    $pio = Get-Command pio -ErrorAction SilentlyContinue
    if ($pio) { return $pio.Source }
    Write-Host "Installing PlatformIO..."
    python -m pip install -q platformio
    $pio = Get-Command pio -ErrorAction SilentlyContinue
    if (-not $pio) {
        $pioPath = Join-Path $env:USERPROFILE ".platformio\penv\Scripts\pio.exe"
        if (Test-Path $pioPath) { return $pioPath }
        throw "PlatformIO install failed"
    }
    return $pio.Source
}

$pio = Ensure-PlatformIo
Push-Location $BridgeDir
try {
    if ($MonitorOnly) {
        & $pio device monitor
        exit $LASTEXITCODE
    }

    if (-not $BuildOnly) {
        Write-Host "Detecting serial port..."
        if (-not $Port) {
            $ports = & $pio device list 2>&1 | Out-String
            Write-Host $ports
            if ($ports -match '(COM\d+)') {
                $Port = $Matches[1]
                Write-Host "Using $Port"
            }
        }
    }

    & $pio run
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    if ($BuildOnly) { exit 0 }

    if ($Port) {
        & $pio run -t upload --upload-port $Port
    } else {
        & $pio run -t upload
    }
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "Flashed. Connect ADB via bridge:"
        Write-Host "  adb connect frame-bridge.local:5555"
        Write-Host "  (or the ESP IP shown in serial monitor)"
        Write-Host ""
        Write-Host "Serial monitor: powershell -ExecutionPolicy Bypass -File esp-bridge\flash.ps1 -MonitorOnly"
    }
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
