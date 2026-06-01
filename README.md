# Picture Frame Firmware Tools

Custom tooling for the **AEEZO / YHK PF109** — a cheap Chinese Android picture frame (Allwinner A33, 1280×800, Android 6).

## Why this exists

The stock workflow for adding photos is ridiculous: copy images to a **USB stick**, plug it into the frame, hope it mounts, maybe dig through menus or a phone app, and repeat whenever you want new pictures. Some models want you to email photos to a cloud service owned by the vendor. For a device sitting on your wall in your house.

This project replaces that with something sane:

- Drop photos in a folder on your **NAS** (`\\your-nas\nas\framepics`)
- The frame **pulls them over Wi‑Fi** every few minutes
- No USB stick shuffle, no cloud account, no outbound internet after setup
- Manage the frame remotely over **Wi‑Fi ADB** once you’ve done a one-time USB setup

So here we are.

## Features

- **NAS photo sync** — mirror a Samba share to the Aimor slideshow folder
- **LAN-only firewall** — block outbound internet, keep local network access
- **Persistent boot hook** — Wi‑Fi ADB, firewall, and sync survive reboot
- **Custom boot splash** — build from a single `boot.png` (Android animation + Aimor backgrounds)
- **Wi‑Fi management** — ADB over Wi‑Fi and NAS command queue (no USB after setup)

## Quick start

1. Copy `scripts/frame.conf.example` to `scripts/frame.conf` and set your frame IP + NAS paths.
2. Download [rclone for Linux ARM](https://rclone.org/downloads/) into `tools/rclone-v1.74.2-linux-arm/rclone`.
3. Plug in USB once, install the driver (`scripts/INSTALL_DRIVER.cmd` as admin), then run `scripts/SETUP_FRAME.cmd`.
4. After setup, connect over Wi‑Fi only:
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

- Common white-label frame: **AEEZO / YHK PF109**, Allwinner A33, Android 6.0.1 eng build.
- Frame Wi‑Fi IP may change (check router or `adb shell ip addr show wlan0`).
- This device’s BusyBox has no `httpd`; use **Wi‑Fi ADB** or the **NAS command queue** for remote access.
- Stock launcher APK can be pulled once with `adb pull /system/priv-app/launcher_aimor/launcher_aimor.apk dump/`.

## What’s not in this repo

Large binaries are gitignored (rclone binary, built APKs, pulled device dumps). No secrets — only example LAN IPs in `frame.conf.example`. Your live `frame.conf` stays local.

## License

MIT — use at your own risk. Vendor firmware and the Aimor app remain their owners’ property; this repo only contains home-lab scripts that talk to the device you already bought.
