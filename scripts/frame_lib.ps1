# Shared helpers: host OS, adb, device profiles, auto-detection, config generation.
param()

function Get-FrameRepoRoot {
    param([string]$From = $PSScriptRoot)
    if (-not $From) { $From = Split-Path -Parent $MyInvocation.MyCommand.Path }
    return Split-Path $From -Parent
}

function Get-FrameHostOs {
    if ($IsWindows -or $env:OS -match "Windows") { return "windows" }
    if ($IsMacOS) { return "macos" }
    if ($IsLinux) { return "linux" }
    if ($env:OS -eq "Darwin") { return "macos" }
    return "unknown"
}

function Get-FrameAdbPath {
    param([string]$Preferred = "")

    if ($Preferred -and (Test-Path $Preferred)) {
        return $Preferred
    }

    $candidates = @()
    if ($env:LOCALAPPDATA) {
        $candidates += "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe\platform-tools\adb.exe"
        $candidates += "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
    }
    if ($env:USERPROFILE) {
        $candidates += "$env:USERPROFILE\AppData\Local\Android\Sdk\platform-tools\adb.exe"
    }
    if ($env:ANDROID_HOME) {
        $candidates += (Join-Path $env:ANDROID_HOME "platform-tools\adb")
        $candidates += (Join-Path $env:ANDROID_HOME "platform-tools\adb.exe")
    }
    if ($env:ANDROID_SDK_ROOT) {
        $candidates += (Join-Path $env:ANDROID_SDK_ROOT "platform-tools\adb")
        $candidates += (Join-Path $env:ANDROID_SDK_ROOT "platform-tools\adb.exe")
    }
    $candidates += @(
        "/usr/local/bin/adb",
        "/opt/homebrew/bin/adb",
        "$env:HOME/Library/Android/sdk/platform-tools/adb",
        "$env:HOME/Android/Sdk/platform-tools/adb"
    )

    foreach ($path in $candidates) {
        if ($path -and (Test-Path $path)) {
            return $path
        }
    }

    $fromPath = Get-Command adb -ErrorAction SilentlyContinue
    if ($fromPath) {
        return $fromPath.Source
    }

    throw @"
adb not found.

Install Android platform-tools:
  Windows: winget install Google.PlatformTools
  macOS:   brew install --cask android-platform-tools
  Linux:   sudo apt install adb   (or use Android SDK platform-tools)

Then re-run setup, or pass -Adb /path/to/adb
"@
}

function Get-FrameConfigPath {
    return Join-Path $PSScriptRoot "frame.conf"
}

function Get-FrameConfig {
    $configPath = Get-FrameConfigPath
    $cfg = @{
        FrameIp = "192.168.1.85"
        FrameAdbPort = 5555
        NasHost = "192.168.1.23"
        NasShare = "nas"
        NasPhotosPath = "framepics"
        NasDeployPath = "frame-deploy"
        NasConsolePath = "frame-console"
        BootSource = "\\192.168.1.23\nas\boot.png"
        DeviceProfile = ""
        AgentPort = 8080
        AgentToken = "frame-local"
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
            "NAS_SHARE" { $cfg.NasShare = $value }
            "NAS_PHOTOS_PATH" { $cfg.NasPhotosPath = $value }
            "NAS_DEPLOY_PATH" { $cfg.NasDeployPath = $value }
            "NAS_CONSOLE_PATH" { $cfg.NasConsolePath = $value }
            "DEVICE_PROFILE" { $cfg.DeviceProfile = $value }
            "AGENT_PORT" { $cfg.AgentPort = [int]$value }
            "AGENT_TOKEN" { $cfg.AgentToken = $value }
        }
    }

    if ($cfg.BootSource -match '^\\[^\\]+\\') {
        # keep UNC boot source as-is
    } elseif ($cfg.NasHost) {
        $cfg.BootSource = "\\$($cfg.NasHost)\$($cfg.NasShare)\boot.png"
    }

    return $cfg
}

function Get-FrameNasUncPath {
    param(
        [hashtable]$Cfg,
        [string]$SubPath
    )
    $hostOs = Get-FrameHostOs
    if ($hostOs -eq "windows") {
        return "\\$($Cfg.NasHost)\$($Cfg.NasShare)\$SubPath"
    }
    return "//$(($Cfg.NasHost) -replace ':','/')/$($Cfg.NasShare)/$SubPath"
}

function Save-FrameConfig {
    param([hashtable]$Cfg)

    $lines = @(
        "# Generated/managed by pictureframefirmware setup",
        "FRAME_IP=$($Cfg.FrameIp)",
        "FRAME_ADB_PORT=$($Cfg.FrameAdbPort)",
        "DEVICE_PROFILE=$($Cfg.DeviceProfile)",
        "",
        "NAS_HOST=$($Cfg.NasHost)",
        "NAS_SHARE=$($Cfg.NasShare)",
        "NAS_PHOTOS_PATH=$($Cfg.NasPhotosPath)",
        "NAS_DEPLOY_PATH=$($Cfg.NasDeployPath)",
        "NAS_CONSOLE_PATH=$($Cfg.NasConsolePath)",
        "",
        "AGENT_PORT=$($Cfg.AgentPort)",
        "AGENT_TOKEN=$($Cfg.AgentToken)",
        "",
        "BOOT_SOURCE=$($Cfg.BootSource)"
    )
    Set-Content -Path (Get-FrameConfigPath) -Value ($lines -join "`n") -Encoding UTF8
}

function Get-FrameDeviceCatalog {
    $path = Join-Path (Get-FrameRepoRoot -From $PSScriptRoot) "config\devices.json"
    if (-not (Test-Path $path)) {
        throw "Device catalog missing: $path"
    }
    return (Get-Content $path -Raw | ConvertFrom-Json)
}

function Test-PropPattern {
    param(
        [string]$Actual,
        [string]$Expected
    )
    if ($null -eq $Actual) { $Actual = "" }
    if ($Expected -like '*`**') {
        $regex = '^' + ($Expected -replace '\*', '.*') + '$'
        return $Actual -match $regex
    }
    return $Actual -eq $Expected
}

function Test-ProfilePropSet {
    param(
        [object]$PropSet,
        [hashtable]$Props
    )
    foreach ($name in $PropSet.PSObject.Properties.Name) {
        $expected = $PropSet.$name
        $actual = $Props[$name]
        if (-not (Test-PropPattern -Actual $actual -Expected $expected)) {
            return $false
        }
    }
    return $true
}

function Test-DeviceProfileMatch {
    param(
        [object]$Profile,
        [hashtable]$Props,
        [string[]]$Packages,
        [string[]]$UsbVidPid = @(),
        [switch]$RequirePackages
    )

    if ($Profile.match.fallback) {
        return $true
    }

    if ($RequirePackages -and $Profile.match.packages) {
        foreach ($pkg in $Profile.match.packages) {
            if ($Packages -notcontains $pkg) {
                return $false
            }
        }
    }

    if ($Profile.match.usb_vid_pid -and $UsbVidPid.Count -gt 0) {
        $hit = $false
        foreach ($pattern in $Profile.match.usb_vid_pid) {
            if ($UsbVidPid -contains $pattern) { $hit = $true; break }
        }
        if (-not $hit) { return $false }
    }

    if ($Profile.match.any_of) {
        $anyHit = $false
        foreach ($set in $Profile.match.any_of) {
            if (Test-ProfilePropSet -PropSet $set -Props $Props) {
                $anyHit = $true
                break
            }
        }
        if (-not $anyHit) {
            $usbIdentified = $false
            if ($Profile.match.usb_vid_pid -and $UsbVidPid.Count -gt 0) {
                foreach ($pattern in $Profile.match.usb_vid_pid) {
                    if ($UsbVidPid -contains $pattern) {
                        $usbIdentified = $true
                        break
                    }
                }
            }
            if (-not $usbIdentified) { return $false }
        }
    }

    if ($Profile.match.all_props) {
        if (-not (Test-ProfilePropSet -PropSet $Profile.match.all_props -Props $Props)) {
            return $false
        }
    }

    return $true
}

function Get-UsbFrameVidPid {
    if ((Get-FrameHostOs) -ne "windows") { return @() }
    $found = @()
    try {
        Get-PnpDevice -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.InstanceId -match 'USB\\VID_([0-9A-F]{4})&PID_([0-9A-F]{4})') {
                $found += "$($Matches[1]):$($Matches[2])"
            }
        }
    } catch {}
    return ($found | Select-Object -Unique)
}

function Get-FrameDeviceProps {
    param(
        [string]$Adb,
        [string]$Serial = ""
    )

    $props = @{}
    $propNames = @(
        "ro.product.brand", "ro.product.manufacturer", "ro.product.model", "ro.product.device",
        "ro.build.flavor", "ro.board.platform", "ro.sys.cputype", "ro.es_frame.product",
        "ro.build.yhk.id", "ro.product.cpu.abilist", "ro.build.version.release"
    )
    foreach ($name in $propNames) {
        $args = @("shell", "getprop", $name)
        if ($Serial) { $args = @("-s", $Serial) + $args }
        $value = (& $Adb @args 2>$null | Out-String).Trim()
        $props[$name] = $value
    }
    return $props
}

function Get-FrameInstalledPackages {
    param(
        [string]$Adb,
        [string]$Serial = ""
    )

    $args = @("shell", "pm", "list", "packages")
    if ($Serial) { $args = @("-s", $Serial) + $args }
    $lines = & $Adb @args 2>$null
    $packages = @()
    foreach ($line in $lines) {
        if ($line -match '^package:(.+)$') {
            $packages += $Matches[1]
        }
    }
    return $packages
}

function Get-FrameWifiIp {
    param(
        [string]$Adb,
        [string]$Serial = ""
    )

    $cmds = @(
        "ip -f inet addr show wlan0 2>/dev/null | awk '/inet / {print \$2}' | cut -d/ -f1",
        "ifconfig wlan0 2>/dev/null | awk '/inet addr/ {print \$2}' | cut -d: -f2",
        "getprop dhcp.wlan0.ipaddress"
    )
    foreach ($cmd in $cmds) {
        $args = @("shell", $cmd)
        if ($Serial) { $args = @("-s", $Serial) + $args }
        $ip = (& $Adb @args 2>$null | Out-String).Trim()
        if ($ip -match '^\d{1,3}(\.\d{1,3}){3}$') {
            return $ip
        }
    }
    return $null
}

function Resolve-FrameDeviceProfile {
    param(
        [string]$Adb = "",
        [string]$Serial = "",
        [string]$PreferredId = ""
    )

    $catalog = Get-FrameDeviceCatalog
    $props = @{}
    $packages = @()
    $usb = Get-UsbFrameVidPid

    if ($Adb) {
        try {
            if (-not $Serial) {
                $lines = & $Adb devices 2>&1 | Where-Object { $_ -match "\tdevice$" }
                if ($lines) {
                    $Serial = (($lines | Select-Object -First 1) -split "`t")[0]
                }
            }
            if ($Serial) {
                $props = Get-FrameDeviceProps -Adb $Adb -Serial $Serial
                $packages = Get-FrameInstalledPackages -Adb $Adb -Serial $Serial
            }
        } catch {}
    }

    if ($PreferredId) {
        $forced = $catalog.profiles | Where-Object { $_.id -eq $PreferredId } | Select-Object -First 1
        if ($forced) {
            return [pscustomobject]@{
                Profile = $forced
                Props = $props
                Packages = $packages
                UsbVidPid = $usb
                Confidence = "configured"
            }
        }
    }

    $requirePackages = $packages.Count -gt 0
    $fallback = $null
    foreach ($profile in $catalog.profiles) {
        if ($profile.match.fallback) {
            $fallback = $profile
            continue
        }
        if (Test-DeviceProfileMatch -Profile $profile -Props $props -Packages $packages -UsbVidPid $usb -RequirePackages:$requirePackages) {
            return [pscustomobject]@{
                Profile = $profile
                Props = $props
                Packages = $packages
                UsbVidPid = $usb
                Confidence = $(if ($profile.tested) { "tested" } else { "likely" })
            }
        }
    }

    return [pscustomobject]@{
        Profile = $fallback
        Props = $props
        Packages = $packages
        UsbVidPid = $usb
        Confidence = "fallback"
    }
}

function Get-FrameDeviceProfile {
    param(
        [string]$ProfileId = ""
    )
    $cfg = Get-FrameConfig
    if (-not $ProfileId) { $ProfileId = $cfg.DeviceProfile }
    $resolved = Resolve-FrameDeviceProfile -PreferredId $ProfileId
    return $resolved.Profile
}

function Get-FrameRclonePath {
    param(
        [object]$Profile,
        [string]$Root = ""
    )
    if (-not $Root) { $Root = Get-FrameRepoRoot -From $PSScriptRoot }
    $arch = "linux-arm"
    if ($Profile -and $Profile.device.rclone_arch) {
        $arch = $Profile.device.rclone_arch
    }
    $folder = switch ($arch) {
        "linux-arm64" { "rclone-v1.74.2-linux-arm64" }
        default { "rclone-v1.74.2-linux-arm" }
    }
    return Join-Path $Root "tools\$folder\rclone"
}

function Write-FrameNasConf {
    param(
        [hashtable]$Cfg,
        [object]$Profile,
        [string]$OutPath = ""
    )

    if (-not $OutPath) {
        $OutPath = Join-Path $PSScriptRoot "nas.conf"
    }

    $dev = $Profile.device
    $content = @"
# NAS picture sync configuration (generated for $($Profile.name))
# Path on device: /data/local/frame-sync/nas.conf

DEVICE_PROFILE=$($Profile.id)

NAS_HOST=$($Cfg.NasHost)
NAS_SHARE=$($Cfg.NasShare)
NAS_PATH=$($Cfg.NasPhotosPath)
DEPLOY_PATH=$($Cfg.NasDeployPath)
CONSOLE_PATH=$($Cfg.NasConsolePath)
AGENT_PORT=$($Cfg.AgentPort)
AGENT_TOKEN=$($Cfg.AgentToken)

NAS_USER=
NAS_PASS=

AIMOR_PKG=$($dev.aimor_package)
AIMOR_DB=$($dev.aimor_db)
IMAGE_DIR=$($dev.image_dir)
PHOTO_WIDTH=$($dev.photo_width)
PHOTO_HEIGHT=$($dev.photo_height)

SYNC_INTERVAL=300
MIRROR_MODE=1
"@
    Set-Content -Path $OutPath -Value $content -Encoding UTF8
    return $OutPath
}

function Update-FrameConfigFromDevice {
    param(
        [string]$Adb,
        [string]$Serial,
        [switch]$WriteConfig
    )

    $cfg = Get-FrameConfig
    $resolved = Resolve-FrameDeviceProfile -Adb $Adb -Serial $Serial -PreferredId $cfg.DeviceProfile
    $profile = $resolved.Profile

    $wifiIp = Get-FrameWifiIp -Adb $Adb -Serial $Serial
    if ($wifiIp) {
        $cfg.FrameIp = $wifiIp
    }

    $cfg.DeviceProfile = $profile.id
    $cfg.BootSource = Get-FrameNasUncPath -Cfg $cfg -SubPath "boot.png"

    if ($WriteConfig) {
        Save-FrameConfig -Cfg $cfg
        Write-FrameNasConf -Cfg $cfg -Profile $profile
    }

    return [pscustomobject]@{
        Config = $cfg
        Detection = $resolved
    }
}

function Show-FrameDetectionReport {
    param($Detection)

    $profile = $Detection.Profile
    Write-Host ""
    Write-Host "Detected device profile: $($profile.name) [$($profile.id)]"
    Write-Host "Confidence: $($Detection.Confidence)$(if (-not $profile.tested) { ' (not fully tested on this model)' } else { ' (tested)' })"
    if ($profile.notes) {
        Write-Host "Notes: $($profile.notes)"
    }
    if ($Detection.Props.Count -gt 0) {
        Write-Host "Props:"
        foreach ($key in @("ro.product.brand", "ro.product.manufacturer", "ro.product.model", "ro.es_frame.product", "ro.build.version.release")) {
            if ($Detection.Props.ContainsKey($key) -and $Detection.Props[$key]) {
                Write-Host "  $key=$($Detection.Props[$key])"
            }
        }
    }
    if ($Detection.UsbVidPid.Count -gt 0) {
        Write-Host "USB VID:PID: $($Detection.UsbVidPid -join ', ')"
    }
}

function Get-ConnectedFrameSerial {
    param([string]$Adb)

    $lines = & $Adb devices 2>&1 | Where-Object { $_ -match "\tdevice$" }
    foreach ($line in $lines) {
        $serial = ($line -split "\t")[0]
        if ($serial -and ($serial -ne "List of devices attached")) {
            return $serial
        }
    }
    return $null
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

    $hostOs = Get-FrameHostOs
    $setupHint = switch ($hostOs) {
        "windows" { "Run setup.cmd from the repo root (or scripts\SETUP_FRAME.cmd)." }
        default { "Run ./setup.sh from the repo root." }
    }

    throw @"
Could not reach the picture frame.

Try one of these:
  1. Plug the frame into USB, then run: $setupHint
  2. If Wi-Fi ADB was set up before, wait for boot (~1 min) then run connect script.
  3. First-time Wi-Fi ADB still needs USB once:
       adb tcpip $Port
       adb connect ${Ip}:${Port}
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
