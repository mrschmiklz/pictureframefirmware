# Call the frame boot console over Wi-Fi HTTP (when agent is running).
param(
    [string]$Path = "/cgi-bin/status.cgi",
    [ValidateSet("GET", "POST")]
    [string]$Method = "GET",
    [string]$BodyFile = "",
    [string]$Ip = "",
    [int]$Port = 8080,
    [string]$Token = "frame-local"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "frame_adb.ps1")
$cfg = Get-FrameConfig
if (-not $Ip) { $Ip = $cfg.FrameIp }

$sep = if ($Path -match '\?') { '&' } else { '?' }
$url = "http://${Ip}:${Port}${Path}${sep}token=$Token"

Write-Host "$Method $url"

if ($Method -eq "POST" -and $BodyFile) {
    $bytes = [System.IO.File]::ReadAllBytes($BodyFile)
    $resp = Invoke-WebRequest -Uri $url -Method Post -Body $bytes -UseBasicParsing -TimeoutSec 20
} else {
    $resp = Invoke-WebRequest -Uri $url -Method $Method -UseBasicParsing -TimeoutSec 20
}

Write-Host $resp.Content
