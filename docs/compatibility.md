# Device compatibility

This project targets **Android-based digital picture frames** — usually cheap white-label hardware with a slideshow app, ADB over USB, and Wi‑Fi. The **AEEZO / YHK PF109** is the primary tested device; other frames may work with the same or a generic profile.

## Supported host operating systems

| OS | One-click setup | Wi‑Fi ADB | USB driver | Notes |
|----|-----------------|-----------|------------|-------|
| **Windows 10/11** | `setup.cmd` | Yes | Allwinner `.inf` included | Full setup: boot hook, splash, firewall |
| **macOS** | `./setup.sh` | Yes | Not needed | Install `adb` via Homebrew; USB authorize once |
| **Linux** | `./setup.sh` | Yes | Not needed | `sudo apt install adb` or Android SDK tools |

Requirements on all hosts:

- **adb** (Android platform-tools)
- **Python 3** (splash build + Linux/macOS auto-detect)
- **Samba access** to your NAS photo folder
- **rclone** binary for the frame’s CPU (see below)

## Device profiles

Profiles live in `config/devices.json`. Setup **auto-detects** the best match via ADB (`getprop`, installed packages, USB VID:PID on Windows).

| Profile ID | Name | Tested | Typical hardware |
|------------|------|--------|------------------|
| `pf109_aimor` | AEEZO / YHK PF109 | **Yes** | Allwinner A33, Android 6, Aimor app |
| `aimor_white_label` | White-label Aimor frame | Community | Any frame with `com.efercro.os.aimor` |
| `allwinner_adb` | Allwinner ADB frame | Community | A33/A64 boards, unknown slideshow app |
| `generic_android` | Generic fallback | Untested | Manual review of `nas.conf` recommended |

### What “compatible” means

**Likely to work out of the box**

- Android 5–8 tablet/frame with **rootless ADB** (USB or Wi‑Fi)
- **Aimor** slideshow app (`com.efercro.os.aimor`) — NAS sync + DB registration
- Allwinner frames with **`/system/bin/setmacaddr`** boot hook (persistent firewall + sync)

**May need profile tweaks**

- Different slideshow package or photo folder → edit `IMAGE_DIR`, `AIMOR_PKG`, `AIMOR_DB` in generated `scripts/nas.conf`
- Different boot hook binary → inspect `/system/bin` and adjust `boot.sh` / `install_persistent.ps1`
- **arm64** frames → download `linux-arm64` rclone into `tools/rclone-v1.74.2-linux-arm64/`

**Known limitations**

- Frame BusyBox often has **no `httpd`** — use Wi‑Fi ADB or NAS command queue, not the HTTP agent
- Splash patching is **Aimor-specific** — disabled automatically for non-Aimor profiles
- Windows USB shows **Unknown device** until the included Allwinner driver is installed (one-time UAC)

## Auto-detection

```powershell
# Windows
powershell -ExecutionPolicy Bypass -File scripts\frame_detect.ps1 -WriteConfig

# Linux / macOS
bash scripts/frame_detect.sh --write-config
```

Detection reads:

- `ro.product.brand`, `ro.product.manufacturer`, `ro.es_frame.product`
- Installed packages (Aimor)
- USB VID:PID `1F3A:1007` (Allwinner ADB) on Windows
- **Wi‑Fi IP** from `wlan0` → writes `FRAME_IP` in `scripts/frame.conf`

Override with `DEVICE_PROFILE=pf109_aimor` in `frame.conf` if auto-detect picks the wrong profile.

## Adding a new frame

1. Connect over USB, run detect, note `getprop` values:
   ```bash
   adb shell getprop | grep -E 'product|es_frame|yhk|aimor'
   adb shell pm list packages | grep -i aimor
   ```
2. Add a profile block to `config/devices.json` (copy `aimor_white_label` as a template).
3. Run setup again — `nas.conf` is regenerated from the profile.
4. Open a PR with your model name and props if you’d like it listed as community-tested.

## rclone on the frame

The frame runs **Linux ARM** userland. Download the matching rclone build:

| Frame CPU | Folder |
|-----------|--------|
| `armeabi-v7a` / 32-bit Allwinner | `tools/rclone-v1.74.2-linux-arm/rclone` |
| `arm64-v8a` | `tools/rclone-v1.74.2-linux-arm64/rclone` |

Check with: `adb shell getprop ro.product.cpu.abilist`
