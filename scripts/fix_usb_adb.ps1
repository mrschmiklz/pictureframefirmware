# Fix Windows USB/ADB for the picture frame (VID_1F3A PID_1007).
# We did NOT disable USB on the device - this usually fixes a Windows driver bind issue.
param(
    [string]$Adb = "",
    [switch]$DriverHelpOnly
)

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "frame_adb.ps1")
$Adb = Get-FrameAdbPath -Preferred $Adb

Write-Host "=== Picture frame USB diagnostics ==="
Write-Host ""

$frameDevices = Get-PnpDevice | Where-Object { $_.InstanceId -match "VID_1F3A&PID_1007" }
if (-not $frameDevices) {
    Write-Host "Frame NOT seen on USB at all."
    Write-Host "  - Try another data cable and USB port"
    Write-Host "  - Wake the frame (tap screen)"
    Write-Host "  - Unplug/replug while frame is on"
} else {
    Write-Host "Frame IS on USB (Allwinner VID_1F3A PID_1007):"
    $frameDevices | Format-Table Status, Class, FriendlyName -AutoSize

    $unknown = $frameDevices | Where-Object { $_.Status -eq "Unknown" }
    if ($unknown) {
        Write-Host "Problem: Windows shows Unknown status = driver not loaded."
        Write-Host "This is a PC-side issue, not the frame blocking USB."
        Write-Host ""
        $driverInf = Join-Path (Split-Path $PSScriptRoot -Parent) "boot\tools\usb_driver\frame_allwinner_adb.inf"
        if (Test-Path $driverInf) {
            Write-Host "Attempting automatic driver install from:"
            Write-Host "  $driverInf"
            $pnputil = & pnputil /add-driver $driverInf /install 2>&1
            $pnputil | ForEach-Object { Write-Host $_ }
            Start-Sleep 3
            $androidDev = Get-PnpDevice | Where-Object {
                $_.InstanceId -match "VID_1F3A&PID_1007&MI_01" -and $_.FriendlyName -eq "Android"
            } | Select-Object -First 1
            if ($androidDev -and $androidDev.Status -eq "Unknown") {
                Write-Host "Trying Update-PnpDevice on Android interface..."
                try {
                    Update-PnpDevice -InstanceId $androidDev.InstanceId -Confirm:$false -ErrorAction Stop
                } catch {
                    Write-Host "Update-PnpDevice failed: $($_.Exception.Message)"
                }
            }
        }
        Write-Host ""
        Write-Host "If ADB still empty, fix in Device Manager (Administrator):"
        Write-Host "  1. Open devmgmt.msc"
        Write-Host "  2. Find entries named Frame, Android, or Unknown under Universal Serial Bus devices"
        Write-Host "  3. Right-click Android -> Update driver -> Browse -> Let me pick"
        Write-Host "  4. Try: Android Device -> Android ADB Interface"
        Write-Host "     Or: Android Device -> Android Composite ADB Interface"
        Write-Host "  5. Unplug/replug USB after driver install"
    }
}

if ($DriverHelpOnly) { exit 0 }

Write-Host ""
Write-Host "Restarting ADB..."
& $Adb kill-server 2>$null
Start-Sleep 2
& $Adb start-server
& $Adb devices -l

Write-Host ""
Write-Host "Trying Wi-Fi ADB (192.168.1.85:5555)..."
& $Adb connect 192.168.1.85:5555 2>&1
Start-Sleep 2
& $Adb devices -l

Write-Host ""
Write-Host "=== What we changed on the frame (USB was NOT disabled) ==="
Write-Host "  - Outbound internet firewall only (does not touch USB)"
Write-Host "  - Wi-Fi ADB on port 5555 (adds network access; USB should still work)"
Write-Host "  - Disabled OTA app only"
Write-Host ""
Write-Host "If you get Wi-Fi ADB working, run on the frame:"
Write-Host '  sh /data/local/frame-sync/restore_usb_adb.sh'
Write-Host "  (or push scripts\restore_usb_adb.sh first)"
