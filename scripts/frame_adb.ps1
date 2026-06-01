# Shared helpers: locate adb and connect to the picture frame (USB or Wi-Fi).
param()

function Get-FrameAdbPath {
    param([string]$Preferred = "")

    if ($Preferred -and (Test-Path $Preferred)) {
        return $Preferred
    }

    $candidates = @(
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe\platform-tools\adb.exe",
        "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
        "$env:USERPROFILE\AppData\Local\Android\Sdk\platform-tools\adb.exe"
    )

    foreach ($path in $candidates) {
        if (Test-Path $path) {
            return $path
        }
    }

    $fromPath = Get-Command adb -ErrorAction SilentlyContinue
    if ($fromPath) {
        return $fromPath.Source
    }

    throw "adb not found. Install Android platform-tools or pass -Adb C:\path\to\adb.exe"
}

function Get-ConnectedFrameSerial {
    param([string]$Adb)

    $lines = & $Adb devices 2>&1 | Where-Object { $_ -match "\tdevice$" }
    foreach ($line in $lines) {
        $serial = ($line -split "\t")[0]
        if ($serial -and $serial -ne "List of devices attached") {
            return $serial
        }
    }
    return $null
}

function Get-FrameConfig {
    $configPath = Join-Path $PSScriptRoot "frame.conf"
    $cfg = @{
        FrameIp = "192.168.1.85"
        FrameAdbPort = 5555
        NasHost = "192.168.1.23"
        BootSource = "\\192.168.1.23\nas\boot.png"
    }

    if (-not (Test-Path $configPath)) {
        return $cfg
    }

    foreach ($line in Get-Content $configPath) {
        if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
        $key, $value = $line -split '=', 2
        $key = $key.Trim()
        $value = $value.Trim()
        switch ($key) {
            "FRAME_IP" { $cfg.FrameIp = $value }
            "FRAME_ADB_PORT" { $cfg.FrameAdbPort = [int]$value }
            "BOOT_SOURCE" { $cfg.BootSource = $value }
            "NAS_HOST" { $cfg.NasHost = $value }
        }
    }
    return $cfg
}

function Connect-FrameDevice {
    param(
        [string]$Adb,
        [string]$Ip = "",
        [int]$Port = 0
    )

    $cfg = Get-FrameConfig
    if (-not $Ip) { $Ip = $cfg.FrameIp }
    if ($Port -eq 0) { $Port = $cfg.FrameAdbPort }

    $usb = Get-ConnectedFrameSerial -Adb $Adb
    if ($usb) {
        Write-Host "Using USB device: $usb"
        return $usb
    }

    $target = "${Ip}:${Port}"
    Write-Host "No USB device. Trying Wi-Fi ADB at $target ..."
    & $Adb connect $target 2>&1 | ForEach-Object { Write-Host $_ }
    Start-Sleep 2

    $wifi = Get-ConnectedFrameSerial -Adb $Adb
    if ($wifi) {
        Write-Host "Connected over Wi-Fi: $wifi"
        return $wifi
    }

    # Last resort: enable TCP/IP over USB if partially visible
    $usbRetry = Get-ConnectedFrameSerial -Adb $Adb
    if ($usbRetry) {
        Write-Host "Enabling Wi-Fi ADB via USB..."
        & $Adb -s $usbRetry tcpip $Port 2>&1 | ForEach-Object { Write-Host $_ }
        Start-Sleep 2
        & $Adb connect $target 2>&1 | ForEach-Object { Write-Host $_ }
        Start-Sleep 2
        $wifi2 = Get-ConnectedFrameSerial -Adb $Adb
        if ($wifi2) { return $wifi2 }
    }

    throw @"
Could not reach the picture frame.

Try one of these:
  1. Plug the frame into USB, run scripts\SETUP_FRAME.cmd, click Yes on UAC.
  2. If Wi-Fi ADB was set up before, make sure the frame is on Wi-Fi and booted (~1 min), then run:
       powershell -ExecutionPolicy Bypass -File scripts\connect_frame.ps1
  3. First-time Wi-Fi ADB still needs USB once:
       & '$Adb' tcpip 5555
       & '$Adb' connect ${Ip}:${Port}

Note: plain 'adb' may not work in PowerShell unless platform-tools is on your PATH.
Use the scripts in this folder, or the full path to adb.exe.
"@
}

function Invoke-FrameAdb {
    param(
        [string]$Adb,
        [string]$Serial,
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Args
    )

    if ($Serial) {
        & $Adb -s $Serial @Args
    } else {
        & $Adb @Args
    }
}
