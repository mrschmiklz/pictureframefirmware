@echo off
REM Install Silicon Labs CP210x driver for ESP32 USB serial (run as Administrator).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_cp210x_driver.ps1"
pause
