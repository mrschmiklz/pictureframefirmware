# Picture Frame Firmware Tools

Custom tooling for the **AEEZO / YHK PF109** Android picture frame (Allwinner A33, 1280×800).

## Features

- **NAS photo sync** — mirror `\\NAS\nas\framepics` to the frame slideshow
- **LAN-only firewall** — block outbound internet, keep local network access
- **Persistent boot hook** — Wi-Fi ADB, firewall, and sync survive reboot
- **Custom boot splash** — build from `boot.png` (Android animation + Aimor backgrounds)
- **Wi-Fi management** — ADB over Wi-Fi and NAS command queue (no USB after setup)

## Quick start

1. Copy `scripts/frame.conf.example` to `scripts/frame.conf` and set your frame IP + NAS paths.
2. Download [rclone for Linux ARM](https://rclone.org/downloads/) into `tools/rclone-v1.74.2-linux-arm/rclone`.
3. Plug in USB once, install the driver (`scripts/INSTALL_DRIVER.cmd` as admin), then run `scripts/SETUP_FRAME.cmd`.
4. After setup, connect over Wi-Fi only:
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts/connect_frame.ps1
   ```

## Key scripts

| Script | Purpose |
|--------|---------|
| `scripts/SETUP_FRAME.cmd` | One-time full setup (USB) |
| `scripts/connect_frame.ps1` | Connect Wi-Fi ADB |
| `scripts/publish_to_nas.ps1` | Push updates to NAS for OTA deploy |
| `scripts/queue_nas_command.ps1` | Queue Wi-Fi commands via NAS |
| `scripts/recover_frame.ps1` | Restore stock launcher if boot issues |
| `scripts/test_frame.ps1` | Health check |

## Hardware notes

- Frame Wi-Fi IP may change (check router or `adb shell ip addr show wlan0`).
- This device's BusyBox has no `httpd`; use **Wi-Fi ADB** or the **NAS command queue** for remote access.
- Stock launcher APK can be pulled once with `adb pull /system/priv-app/launcher_aimor/launcher_aimor.apk dump/`.

## License

Private home-lab project. Device firmware remains vendor property.
