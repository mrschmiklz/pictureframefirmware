@echo off
REM Legacy entry point — use setup.cmd in the repo root instead.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_wizard.ps1" %*
