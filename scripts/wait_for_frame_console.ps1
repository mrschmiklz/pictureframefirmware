# Wait until the frame Wi-Fi boot console is reachable (HTTP or NAS heartbeat).
param(
    [int]$TimeoutMinutes = 10
)

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "frame_adb.ps1")
$cfg = Get-FrameConfig
$hb = "\\$($cfg.NasHost)\nas\frame-console\heartbeat.json"
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)

while ((Get-Date) -lt $deadline) {
    $open = $false
    try {
        $c = New-Object Net.Sockets.TcpClient
        $iar = $c.BeginConnect($cfg.FrameIp, 8080, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne(800) -and $c.Connected) { $open = $true }
        $c.Close()
    } catch {}

    if ($open) {
        Write-Host "Boot console up: http://$($cfg.FrameIp):8080/"
        exit 0
    }
    if (Test-Path $hb) {
        Write-Host "Frame checked in via NAS: $(Get-Content $hb -Raw)"
        exit 0
    }

    Write-Host "$(Get-Date -Format HH:mm:ss) waiting..."
    Start-Sleep 15
}

Write-Host "Timed out. Run SETUP_FRAME.cmd once with USB if this is a fresh frame."
exit 1
