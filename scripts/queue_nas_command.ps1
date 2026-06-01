# Queue a Wi-Fi-only command on the NAS for the frame to pull and execute.
param(
    [Parameter(Mandatory = $true)]
    [string]$Command,
    [string]$NasConsole = "\\192.168.1.23\nas\frame-console"
)

$ErrorActionPreference = "Stop"
$pending = Join-Path $NasConsole "queue\pending"
$done = Join-Path $NasConsole "queue\done"
New-Item -ItemType Directory -Force -Path $pending, $done | Out-Null

$id = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$cmdFile = Join-Path $pending "$id.cmd"
Set-Content -Path $cmdFile -Value $Command -NoNewline
Write-Host "Queued: $cmdFile"
Write-Host "Command: $Command"
Write-Host ""
Write-Host "The frame runs this on next sync/boot (usually within 5 minutes)."
Write-Host "Result: $done\$id.result"
