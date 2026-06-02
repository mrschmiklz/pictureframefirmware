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
        Write-Host "Created secrets.ini from example - edit Wi-Fi + frame IP, then re-run."
        exit 1
    }
    throw "Missing secrets.ini"
}

function Get-PlatformIoCommand {
    $pio = Get-Command pio -ErrorAction SilentlyContinue
    if ($pio) {
        return @{ Exe = $pio.Source; Prefix = @() }
    }
    $pioPath = Join-Path $env:USERPROFILE ".platformio\penv\Scripts\pio.exe"
    if (Test-Path $pioPath) {
        return @{ Exe = $pioPath; Prefix = @() }
    }
    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) {
        return @{ Exe = $python.Source; Prefix = @("-m", "platformio") }
    }
    Write-Host "Installing PlatformIO..."
    python -m pip install -q platformio
    return @{ Exe = "python"; Prefix = @("-m", "platformio") }
}

function Invoke-PlatformIo {
    param([string[]]$PioArgs)
    $cmd = Get-PlatformIoCommand
    if ($cmd.Prefix.Count -gt 0) {
        & $cmd.Exe @($cmd.Prefix + $PioArgs)
    } else {
        & $cmd.Exe @PioArgs
    }
}

function Get-EspComPort {
    $cp210 = @(Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.FriendlyName -match 'CP210' -and $_.FriendlyName -match 'COM(\d+)' })

    foreach ($dev in $cp210) {
        if ($dev.Status -eq 'OK' -and $dev.FriendlyName -match 'COM(\d+)') {
            return "COM$($Matches[1])"
        }
    }

    if ($cp210.Count -gt 0) {
        $names = ($cp210 | ForEach-Object { "$($_.FriendlyName) [$($_.Status)]" }) -join '; '
        throw @"
ESP32 USB serial is visible but the CP210x driver is not loaded:
  $names

Fix:
  1. Right-click esp-bridge\INSTALL_DRIVER.cmd -> Run as administrator -> Yes on UAC
  2. Device Manager should show CP210x with Status OK (not Unknown)
  3. Re-run: powershell -ExecutionPolicy Bypass -File esp-bridge\flash.ps1

Do NOT use COM3/COM4 — those are Bluetooth ports, not the ESP32.
"@
    }

    return $null
}

function Get-SerialPortFromPlatformIo {
    $text = Invoke-PlatformIo @("device", "list") 2>&1 | Out-String
    Write-Host $text
    $blocks = $text -split '(?=COM\d+\r?\n----)'
    foreach ($block in $blocks) {
        if ($block -match '^(COM\d+)\r?\n----[\s\S]*?Description: ([^\r\n]+)') {
            $port = $Matches[1]
            $desc = $Matches[2]
            if ($desc -match 'Bluetooth|BTHENUM') { continue }
            if ($desc -match 'CP210|USB Serial|UART|USB-Enhanced-SERIAL|Silicon Labs') {
                return $port
            }
        }
    }
    return $null
}

$null = Get-PlatformIoCommand
Push-Location $BridgeDir
try {
    if ($MonitorOnly) {
        Invoke-PlatformIo @("device", "monitor")
        exit $LASTEXITCODE
    }

    if (-not $BuildOnly) {
        Write-Host "Detecting serial port..."
        if (-not $Port) {
            $Port = Get-EspComPort
            if ($Port) {
                Write-Host "Using ESP port $Port"
            } else {
                $Port = Get-SerialPortFromPlatformIo
                if ($Port) {
                    Write-Host "Using $Port"
                } else {
                    throw "No ESP32 serial port found. Plug in the ESP32 (data USB cable) and install the CP210x driver (esp-bridge\INSTALL_DRIVER.cmd as admin)."
                }
            }
        } elseif ($Port -match '^COM[34]$') {
            throw "COM3/COM4 are Bluetooth serial ports on this PC, not the ESP32. Install the CP210x driver and use COM5/COM6/COM7, or run without -Port."
        }
    }

    Invoke-PlatformIo @("run")
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    if ($BuildOnly) { exit 0 }

    if ($Port) {
        Invoke-PlatformIo @("run", "-t", "upload", "--upload-port", $Port)
    } else {
        Invoke-PlatformIo @("run", "-t", "upload")
    }
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "Flashed. Connect ADB via bridge:"
        Write-Host "  adb connect frame-bridge.local:5555"
        Write-Host "  (or the ESP IP shown in serial monitor)"
        Write-Host ""
        Write-Host 'Serial monitor: powershell -ExecutionPolicy Bypass -File esp-bridge\flash.ps1 -MonitorOnly'
    } else {
        Write-Host ""
        Write-Host "Upload failed. If CP210x shows Unknown in Device Manager, run esp-bridge\INSTALL_DRIVER.cmd as admin."
        Write-Host "Then hold BOOT, tap EN, release BOOT, and re-run flash.ps1"
    }
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
