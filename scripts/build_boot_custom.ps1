# Build custom boot.img (patched init.rc) and bootanimation.zip.
param(
    [string]$StockBoot = (Join-Path (Split-Path $PSScriptRoot -Parent) "dump\boot.stock.img"),
    [string]$WorkDir = (Join-Path (Split-Path $PSScriptRoot -Parent) "boot\work"),
    [string]$OutputBoot = (Join-Path (Split-Path $PSScriptRoot -Parent) "boot\boot.custom.img"),
    [string]$OutputAnim = (Join-Path (Split-Path $PSScriptRoot -Parent) "boot\bootanimation.zip")
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
$Tools = Join-Path $Root "boot\tools"
$Python = "python"

if (-not (Test-Path $StockBoot)) {
    throw "Missing $StockBoot. Run scripts\backup_boot.ps1 with the frame connected first."
}

Write-Host "Building boot animation..."
& $Python (Join-Path $Root "boot\render_bootanimation.py")

Write-Host "Unpacking stock boot image..."
if (Test-Path $WorkDir) {
    Remove-Item -Recurse -Force $WorkDir
}
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

& $Python (Join-Path $Tools "unpack_bootimg.py") $StockBoot $WorkDir
if ($LASTEXITCODE -ne 0) { throw "unpack_bootimg failed" }

Write-Host "Patching ramdisk init.rc..."
$patchedRamdisk = Join-Path $WorkDir "ramdisk.patched.gz"
& $Python (Join-Path $Tools "patch_ramdisk.py") (Join-Path $WorkDir "ramdisk.gz") $patchedRamdisk
if ($LASTEXITCODE -ne 0) { throw "patch_ramdisk failed" }

Copy-Item $patchedRamdisk (Join-Path $WorkDir "ramdisk.gz") -Force

Write-Host "Repacking custom boot.img..."
& $Python (Join-Path $Tools "repack_bootimg.py") $WorkDir $OutputBoot
if ($LASTEXITCODE -ne 0) { throw "repack_bootimg failed" }

Write-Host ""
Write-Host "Built:"
Write-Host "  $OutputBoot"
Write-Host "  $OutputAnim"
