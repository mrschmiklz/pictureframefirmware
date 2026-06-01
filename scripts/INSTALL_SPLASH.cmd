@echo off
REM Double-click this file, click Yes on the UAC prompt, keep USB plugged in.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_aimor_splash_elevated.ps1" -Reboot
pause
