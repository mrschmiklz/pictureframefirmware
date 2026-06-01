# Health check for the picture frame system (PC + device when reachable).
param(
    [string]$Adb = "",
    [switch]$SkipDevice
)

$ErrorActionPreference = "Continue"
$Root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot "frame_lib.ps1")
$Adb = Get-FrameAdbPath -Preferred $Adb
$cfg = Get-FrameConfig
$profile = Get-FrameDeviceProfile -ProfileId $cfg.DeviceProfile

$pass = 0
$fail = 0
$warn = 0

function Report {
    param([string]$Status, [string]$Message)
    switch ($Status) {
        "PASS" { Write-Host "[PASS] $Message" -ForegroundColor Green; $script:pass++ }
        "FAIL" { Write-Host "[FAIL] $Message" -ForegroundColor Red; $script:fail++ }
        "WARN" { Write-Host "[WARN] $Message" -ForegroundColor Yellow; $script:warn++ }
    }
}

Write-Host "=== Picture Frame System Test ==="
Write-Host "Host OS: $(Get-FrameHostOs)"
if ($profile) {
    Write-Host "Device profile: $($profile.name) [$($profile.id)]$(if (-not $profile.tested) { ' (community/untested)' })"
}
Write-Host ""

# PC-side checks
if (Test-Path $cfg.BootSource) {
    Report "PASS" "Boot image on NAS: $($cfg.BootSource)"
} else {
    Report "FAIL" "Boot image missing: $($cfg.BootSource)"
}

$nasPhotos = Get-FrameNasUncPath -Cfg $cfg -SubPath $cfg.NasPhotosPath
if (Test-Path $nasPhotos) {
    Report "PASS" "NAS photo share reachable: $nasPhotos"
} else {
    Report "WARN" "NAS photo share not reachable from PC: $nasPhotos"
}

$nasDeploy = Get-FrameNasUncPath -Cfg $cfg -SubPath $cfg.NasDeployPath
if (Test-Path $nasDeploy) {
    $ver = Get-Content (Join-Path $nasDeploy "VERSION") -ErrorAction SilentlyContinue
    Report "PASS" "NAS deploy folder ready ($nasDeploy) version=$ver"
} else {
    Report "WARN" "NAS deploy folder missing ($nasDeploy) - run publish_to_nas.ps1 after setup"
}

$nasConsole = Get-FrameNasUncPath -Cfg $cfg -SubPath $cfg.NasConsolePath
if (Test-Path $nasConsole) {
    $pending = @(Get-ChildItem (Join-Path $nasConsole "queue\pending") -ErrorAction SilentlyContinue).Count
    $done = @(Get-ChildItem (Join-Path $nasConsole "queue\done") -ErrorAction SilentlyContinue).Count
    $hb = Join-Path $nasConsole "heartbeat.json"
    if (Test-Path $hb) {
        Report "PASS" "NAS console heartbeat present: $(Get-Content $hb -Raw)"
    } else {
        Report "WARN" "NAS console heartbeat missing (frame has not checked in yet)"
    }
    Report "PASS" "NAS console queue pending=$pending done=$done"
} else {
    Report "WARN" "NAS console folder missing - run bootstrap_wifi_console.ps1"
}

if (Test-Path (Join-Path $Root "boot\bootanimation.zip")) {
    Report "PASS" "Local bootanimation.zip built"
} else {
    Report "WARN" "Local bootanimation.zip not built yet"
}

if (Test-Path (Join-Path $Root "boot\launcher_aimor.signed.apk")) {
    Report "PASS" "Local signed Aimor APK built"
} else {
    Report "WARN" "Local signed Aimor APK not built yet"
}

$frameUsb = Get-PnpDevice | Where-Object { $_.InstanceId -match "VID_1F3A&PID_1007" }
if ($frameUsb) {
    $unknown = $frameUsb | Where-Object { $_.Status -eq "Unknown" }
    if ($unknown) {
        Report "WARN" "Frame on USB but driver not loaded - run SETUP_FRAME.cmd"
    } else {
        Report "PASS" "Frame USB detected with driver"
    }
} else {
    Report "WARN" "Frame not on USB"
}

if (Test-Connection -ComputerName $cfg.FrameIp -Count 1 -Quiet) {
    Report "PASS" "Frame reachable on Wi-Fi: $($cfg.FrameIp)"
    $portOpen = $false
    try {
        $tcp = New-Object Net.Sockets.TcpClient
        $tcp.Connect($cfg.FrameIp, 8080)
        $portOpen = $tcp.Connected
        $tcp.Close()
    } catch {}
    if ($portOpen) {
        Report "PASS" "Wi-Fi boot console listening on ${cfg.FrameIp}:8080"
    } else {
        Report "WARN" "Boot console not up yet on port 8080"
    }
} else {
    Report "WARN" "Frame not pingable at $($cfg.FrameIp)"
}

if ($SkipDevice) {
    Write-Host ""
    Write-Host "Skipped device checks (-SkipDevice)"
} else {
    Write-Host ""
    Write-Host "=== Device checks (requires ADB) ==="
    try {
        $serial = Connect-FrameDevice -Adb $Adb -Ip $cfg.FrameIp -Port $cfg.FrameAdbPort
        Report "PASS" "ADB connected: $serial"
        $detect = Update-FrameConfigFromDevice -Adb $Adb -Serial $serial
        Show-FrameDetectionReport -Detection $detect.Detection

        $checks = @(
            @{ Name = "boot hook"; Cmd = "test -x /system/bin/setmacaddr.real && echo yes || echo no" },
            @{ Name = "boot log"; Cmd = "tail -3 /data/local/frame-sync/boot.log 2>/dev/null" },
            @{ Name = "wifi adb ip"; Cmd = "cat /data/local/frame-sync/wifi_adb_ip.txt 2>/dev/null" },
            @{ Name = "firewall"; Cmd = "iptables -L FRAME_WAN -n 2>/dev/null | head -3" },
            @{ Name = "sync daemon"; Cmd = "test -f /data/local/frame-sync/sync.pid && kill -0 $(cat /data/local/frame-sync/sync.pid) 2>/dev/null && echo running || echo stopped" },
            @{ Name = "photo count"; Cmd = "ls /sdcard/aimor/image 2>/dev/null | wc -l" },
        @{ Name = "boot animation"; Cmd = "test -f /system/media/bootanimation.zip && echo yes || echo no" },
        @{ Name = "deploy log"; Cmd = "tail -3 /data/local/frame-sync/deploy.log 2>/dev/null" },
        @{ Name = "console log"; Cmd = "tail -3 /data/local/frame-sync/console.log 2>/dev/null" },
        @{ Name = "agent log"; Cmd = "tail -3 /data/local/frame-sync/agent.log 2>/dev/null" }
        )

        foreach ($check in $checks) {
            $out = Invoke-FrameAdb -Adb $Adb -Serial $serial -Args @("shell", $check.Cmd) 2>&1
            $text = ($out | Out-String).Trim()
            if ($text -and $text -notmatch "No such file|cannot") {
                Report "PASS" "$($check.Name): $text"
            } else {
                Report "WARN" "$($check.Name): not configured or missing"
            }
        }

        $wan = Invoke-FrameAdb -Adb $Adb -Serial $serial -Args @("shell", "curl -s --connect-timeout 3 http://example.com >/dev/null 2>&1; echo exit:$?") 2>&1
        if ($wan -match "exit:7" -or $wan -match "exit:28" -or $wan -match "exit:6") {
            Report "PASS" "Outbound internet blocked (curl failed as expected)"
        } else {
            Report "WARN" "Could not confirm WAN block (curl result: $wan)"
        }
    } catch {
        Report "FAIL" "ADB not connected: $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host "=== Summary: $pass passed, $warn warnings, $fail failed ==="
if ($fail -gt 0) { exit 1 }
exit 0
