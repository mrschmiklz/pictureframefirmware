# Publish built firmware + scripts to NAS for over-the-air frame updates.
param(
    [string]$NasDeploy = "",
    [string]$NasConsole = "",
    [string]$Source = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
$BootDir = Join-Path $Root "boot"
$Scripts = $PSScriptRoot
$AgentDir = Join-Path $Root "frame-agent"

. (Join-Path $Scripts "frame_lib.ps1")
$cfg = Get-FrameConfig
$profile = Get-FrameDeviceProfile -ProfileId $cfg.DeviceProfile
if (-not $Source) { $Source = $cfg.BootSource }
if (-not $NasDeploy) { $NasDeploy = Get-FrameNasUncPath -Cfg $cfg -SubPath $cfg.NasDeployPath }
if (-not $NasConsole) { $NasConsole = Get-FrameNasUncPath -Cfg $cfg -SubPath $cfg.NasConsolePath }

Write-FrameNasConf -Cfg $cfg -Profile $profile | Out-Null

Write-Host "Step 1/3: Build splash from $Source"
& (Join-Path $Scripts "install_aimor_splash.ps1") -Source $Source -BuildOnly
if ($LASTEXITCODE -ne 0) { throw "build failed" }

Write-Host "Step 2/3: Publish to $NasDeploy"
New-Item -ItemType Directory -Force -Path $NasDeploy | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $NasConsole "queue\pending"), (Join-Path $NasConsole "queue\done") | Out-Null

$version = Get-Date -Format "yyyyMMdd-HHmmss"
Set-Content -Path (Join-Path $NasDeploy "VERSION") -Value $version -NoNewline

$payloads = @(
    @{ Src = (Join-Path $BootDir "bootanimation.zip"); Dst = "bootanimation.zip" },
    @{ Src = (Join-Path $BootDir "launcher_aimor.signed.apk"); Dst = "launcher_aimor.signed.apk" }
)
foreach ($item in $payloads) {
    Copy-Item $item.Src (Join-Path $NasDeploy $item.Dst) -Force
    Write-Host "  copied $($item.Dst)"
}

$scriptNames = @(
    "nas.conf", "boot.sh", "block_wan.sh", "sync_nas.sh", "start_sync_daemon.sh",
    "install_from_nas.sh", "install_splash.sh", "restore_usb_adb.sh",
    "process_nas_console.sh", "start_agent.sh", "suppress_popups.sh", "start_popup_guard.sh"
)
foreach ($name in $scriptNames) {
    Copy-Item (Join-Path $Scripts $name) (Join-Path $NasDeploy $name) -Force
    Write-Host "  copied $name"
}

$deployAgent = Join-Path $NasDeploy "agent"
if (Test-Path $deployAgent) { Remove-Item $deployAgent -Recurse -Force }
Copy-Item $AgentDir $deployAgent -Recurse -Force
Write-Host "  copied agent/ bundle"

Write-Host ""
Write-Host "Published deploy bundle version $version"
Write-Host "NAS console queue: $NasConsole\queue\pending"
