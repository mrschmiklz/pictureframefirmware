@echo off
REM Complete picture frame setup. Plug in USB, click Yes on UAC, wait ~2 min.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_frame.ps1"
if errorlevel 1 (
  echo.
  echo Setup failed. See messages above.
  pause
  exit /b 1
)
echo.
echo Done. You can unplug USB after reboot; frame updates over Wi-Fi + NAS.
pause
