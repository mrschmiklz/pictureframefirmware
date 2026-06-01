# Pull Google Tasks, render PNG, and push to the frame over USB.
$root = Split-Path $PSScriptRoot -Parent
Set-Location (Join-Path $root "tasks")

pip install -r requirements.txt -q
python google_tasks.py sync
Set-Location $root
powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "push_tasks_slide.ps1")
