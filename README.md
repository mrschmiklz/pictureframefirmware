# Picture Frame Firmware Tools

Turn cheap **Android digital picture frames** into LAN-first photo displays: NAS sync, outbound firewall, Wi‑Fi management — no USB stick shuffle, no vendor cloud.

**Primary tested device:** AEEZO / YHK PF109 (Allwinner A33, Android 6, Aimor app). Many white-label Aimor frames should work with auto-detection. See [docs/compatibility.md](docs/compatibility.md).

## Why this exists

The stock workflow for adding photos is ridiculous: copy images to a **USB stick**, plug it into the frame, hope it mounts, maybe dig through menus or a phone app, and repeat whenever you want new pictures. Want Grandma’s birthday on the wall? Better find that micro‑USB cable and a stick you haven’t formatted since 2019.

Or — and this is the modern “convenience” option — **email your family photos to a vendor’s cloud**. Upload them to someone else’s server. Create an account. Accept the privacy policy you didn’t read. Trust that a white‑label frame maker in Shenzhen will still be operating their API in five years. Pay no one, yet somehow *you* are the product shuffling JPEGs through their pipeline so a $40 Android slab on your mantle can show pictures that were **already on your network**.

It’s a picture frame. In your house. On your Wi‑Fi. The photos are yours. The cloud is not required. Shockingly.

This project replaces all of that with something sane:

- Drop photos in a folder on your **NAS** (`\\your-nas\nas\framepics` or `//your-nas/nas/framepics`)
- The frame **pulls them over Wi‑Fi** every few minutes — LAN only, like civilized people
- No USB stick shuffle, no cloud account, no “please verify your email to view your own children”
- **Firewall blocks outbound internet** after setup — the frame can see your NAS and nothing else
- Manage the frame remotely over **Wi‑Fi ADB** once you’ve done a one-time USB setup

Your photos stay on your NAS. Your frame stays on your LAN. The vendor’s cloud can go touch grass.

So here we are.

## Features

- **Auto device detection** — profiles for PF109, generic Aimor, Allwinner, and fallback Android frames
- **Cross-platform host tools** — Windows, macOS, and Linux entry points
- **One-click setup** — wizard writes config, detects IP, deploys sync + firewall
- **NAS photo sync** — mirror a Samba share to the slideshow folder
- **LAN-only firewall** — block outbound internet; your frame doesn’t need to phone home to Shenzhen
- **Persistent boot hook** — Wi‑Fi ADB, firewall, and sync survive reboot
- **Custom boot splash** — build from a single `boot.png` (Android animation + Aimor backgrounds)
- **Wi‑Fi management** — ADB over Wi‑Fi and NAS command queue (no USB after setup)

## Quick start (one click)

### Windows

1. Install [Android platform-tools](https://developer.android.com/tools/releases/platform-tools) (`winget install Google.PlatformTools`).
2. Download [rclone linux-arm](https://rclone.org/downloads/) → `tools/rclone-v1.74.2-linux-arm/rclone`.
3. Plug frame into USB, double-click **`setup.cmd`** (click Yes on UAC for the Allwinner driver).
4. Drop photos in your NAS `framepics` folder. Done.

### macOS / Linux

1. Install adb: `brew install --cask android-platform-tools` or `sudo apt install adb`.
2. Download rclone (linux-arm) into `tools/rclone-v1.74.2-linux-arm/rclone`.
3. `chmod +x setup.sh scripts/*.sh` then **`./setup.sh`** with USB connected.
4. For persistent boot hook + Aimor splash, run **`setup.cmd` on Windows once** or use Wi‑Fi ADB after a Windows setup.

### After setup (any OS)

```powershell
# Windows
powershell -ExecutionPolicy Bypass -File scripts\connect_frame.ps1
powershell -ExecutionPolicy Bypass -File scripts\test_frame.ps1
```

```bash
# macOS / Linux
bash scripts/connect.sh
bash scripts/test.sh
```

### Manual config (optional)

Copy `scripts/frame.conf.example` → `scripts/frame.conf`, or let setup auto-detect:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\frame_detect.ps1 -WriteConfig
```

```bash
bash scripts/frame_detect.sh --write-config
```

## Key scripts

| Script | Purpose |
|--------|---------|
| **`setup.cmd`** / **`setup.sh`** | One-click wizard + full setup |
| `scripts/frame_detect.ps1` / `.sh` | Auto-detect frame model + write config |
| `scripts/connect_frame.ps1` / `connect.sh` | Connect Wi-Fi ADB |
| `scripts/publish_to_nas.ps1` | Push updates to NAS for OTA deploy |
| `scripts/queue_nas_command.ps1` | Queue Wi-Fi commands via NAS |
| `scripts/recover_frame.ps1` | Restore stock launcher if boot issues |
| `scripts/test_frame.ps1` / `test.sh` | Health check |

Device profiles: **`config/devices.json`**. Compatibility details: **[docs/compatibility.md](docs/compatibility.md)**.

## Optional: ESP32 Wi‑Fi bridge

An **ESP32** on your LAN can proxy ADB so you always connect to `frame-bridge.local:5555` instead of chasing the frame’s IP. See **[esp-bridge/README.md](esp-bridge/README.md)**.

```powershell
powershell -ExecutionPolicy Bypass -File esp-bridge\flash.ps1
powershell -ExecutionPolicy Bypass -File scripts\connect_via_bridge.ps1
```

True USB‑host bridging (ESP USB → frame USB) needs ESP32‑S3 and is experimental; v1 uses Wi‑Fi on both sides.

## Hardware notes

- Common white-label frame: **AEEZO / YHK PF109**, Allwinner A33, Android 6.0.1 eng build.
- Similar frames often ship **Aimor** (`com.efercro.os.aimor`) with the same NAS sync paths.
- Frame Wi‑Fi IP may change — setup auto-detects it; check router or `adb shell ip addr show wlan0`.
- BusyBox on these frames often has **no `httpd`**; use **Wi‑Fi ADB** or the **NAS command queue**.
- Stock launcher APK: `adb pull /system/priv-app/launcher_aimor/launcher_aimor.apk dump/`

## What’s not in this repo

Large binaries are gitignored (rclone binary, built APKs, pulled device dumps). No secrets — only example LAN IPs in `frame.conf.example`. Your live `frame.conf` stays local.

## License

MIT — use at your own risk. Vendor firmware and the Aimor app remain their owners’ property; this repo only contains home-lab scripts that talk to the device you already bought.
