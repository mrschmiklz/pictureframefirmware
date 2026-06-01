@echo off
echo Installing Allwinner picture frame USB driver...
echo.
pnputil /add-driver "%~dp0..\boot\tools\usb_driver\frame_allwinner_adb.inf" /install
echo.
echo Unplug and replug the USB cable, then run SETUP_FRAME.cmd
pause
