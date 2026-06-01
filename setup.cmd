@echo off
REM One-click picture frame setup (Windows)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\setup_wizard.ps1" %*
if errorlevel 1 (
  echo.
  echo Setup failed. See messages above.
  pause
  exit /b 1
)
echo.
echo Done.
pause
