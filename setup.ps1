# One-click picture frame setup (Windows PowerShell)
param(
    [switch]$SkipSplash,
    [switch]$SkipReboot,
    [switch]$ConfigOnly
)

$Root = $PSScriptRoot
$wizardArgs = @("-ExecutionPolicy", "Bypass", "-File", (Join-Path $Root "scripts\setup_wizard.ps1"))
if ($SkipSplash) { $wizardArgs += "-SkipSplash" }
if ($SkipReboot) { $wizardArgs += "-SkipReboot" }
if ($ConfigOnly) { $wizardArgs += "-SkipSetup" }

& powershell.exe @wizardArgs
exit $LASTEXITCODE
