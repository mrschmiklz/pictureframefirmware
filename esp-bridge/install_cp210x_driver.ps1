# Install CP210x USB-UART driver so the ESP32 COM port works on Windows.
$ErrorActionPreference = "Stop"
$InfDir = Join-Path $PSScriptRoot "tools\cp210x"
$Inf = Join-Path $InfDir "silabser.inf"

if (-not (Test-Path $Inf)) {
    throw "Driver not found at $Inf"
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Show-ManualDriverSteps {
    Write-Host ""
    Write-Host "=== Manual fix (Device Manager) ==="
    Write-Host "1. Win+X -> Device Manager"
    Write-Host "2. Expand 'Ports (COM & LPT)' or 'Other devices'"
    Write-Host "3. Right-click each 'Silicon Labs CP210x' with yellow warning -> Update driver"
    Write-Host "4. Browse my computer -> Let me pick from a list"
    Write-Host "5. Ports (COM & LPT) -> Silicon Labs CP210x USB to UART Bridge"
    Write-Host "   (If missing: Have Disk -> browse to:)"
    Write-Host "   $InfDir"
    Write-Host "6. Unplug ESP USB, wait 3s, plug back in"
    Write-Host ""
}

if (-not (Test-IsAdmin)) {
    Write-Host "Requesting Administrator to install CP210x driver..."
    Write-Host "Click YES on the UAC prompt within 60 seconds."
    $proc = Start-Process powershell.exe -Verb RunAs -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath
    ) -PassThru
    $proc.WaitForExit(60000)
    if (-not $proc.HasExited) {
        $proc.Kill()
        Write-Host "UAC timed out. Right-click INSTALL_DRIVER.cmd -> Run as administrator."
        Show-ManualDriverSteps
        exit 1
    }
    exit $proc.ExitCode
}

Write-Host "Installing Silicon Labs CP210x driver from:"
Write-Host "  $Inf"
& pnputil /add-driver $Inf /install
Start-Sleep 1
& pnputil /scan-devices 2>$null | Out-Null
Start-Sleep 2

$cp210 = @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'CP210' })
$cp210 | Format-Table Status, FriendlyName, InstanceId -AutoSize

$ok = @($cp210 | Where-Object { $_.Status -eq 'OK' })
if ($ok.Count -gt 0) {
    Write-Host ""
    Write-Host "Driver OK on: $($ok[0].FriendlyName)"
    Write-Host "Flash with: powershell -ExecutionPolicy Bypass -File esp-bridge\flash.ps1"
    exit 0
}

Write-Host ""
Write-Host "Driver package is installed but the ESP still shows Unknown."
Write-Host "Windows often needs a manual bind once."
Show-ManualDriverSteps
Start-Process devmgmt.msc
exit 1
