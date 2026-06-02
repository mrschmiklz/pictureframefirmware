# Picture Frame ESP32 Bridge

Optional add-on: an **ESP32 on your Wi‑Fi** that proxies **ADB over TCP** to the picture frame. Manage the frame from your PC even when the frame’s IP changes — connect to `frame-bridge.local:5555` instead.

## What it does (v1 — shipping now)

```
Your PC  --Wi-Fi-->  ESP32 bridge  --Wi-Fi-->  Picture frame (ADB :5555)
```

- ESP32 joins your LAN (e.g. `Kutuhala` 2.4 GHz).
- Listens on **port 5555** and forwards bytes to the frame’s **Wi‑Fi ADB** port.
- Advertises **`frame-bridge.local`** via mDNS.
- **Setup web UI** at `http://<esp-ip>/` if Wi‑Fi or frame IP needs changing.
- **Serial CLI** over USB when the ESP is plugged into your PC (115200 baud).

This does **not** require the ESP to be USB‑connected to the frame for v1.

## What about USB ESP → frame?

The frame’s USB port speaks **ADB as a USB device**. The ESP32 would need to be a **USB host** and run the full ADB protocol — that’s heavy and is **phase 2** (ESP32‑S3 USB OTG only, experimental).

**Practical wiring today:**

| Connection | Purpose |
|------------|---------|
| ESP ↔ your PC (USB) | Flash firmware, serial config |
| ESP ↔ wall/USB power | Leave powered near the frame |
| Frame ↔ Wi‑Fi | Frame runs Wi‑Fi ADB (from our setup) |
| ESP ↔ same Wi‑Fi | Bridge proxies to frame IP |

If the frame’s IP changes, update `frame_ip` once on the ESP web UI — your PC still uses `frame-bridge.local`.

## Initial setup

1. Copy secrets (Wi‑Fi + frame IP — **never commit** `secrets.ini`):

   ```powershell
   copy esp-bridge\secrets.example.ini esp-bridge\secrets.ini
   # edit secrets.ini
   ```

2. Plug ESP32 into this PC via USB.

3. Flash:

   ```powershell
   powershell -ExecutionPolicy Bypass -File esp-bridge\flash.ps1
   ```

4. Connect through the bridge:

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\connect_via_bridge.ps1
   ```

   Or: `adb connect frame-bridge.local:5555`

## secrets.ini

```ini
[secrets]
wifi_ssid = YourNetwork
wifi_password = YourPassword
frame_ip = 192.168.1.86
bridge_port = 5555
frame_adb_port = 5555
```

## First boot without secrets

If Wi‑Fi isn’t configured, the ESP opens **`PictureFrame-Bridge`** (open AP). Join it and open **http://192.168.4.1/** to enter SSID, password, and frame IP.

## Serial commands (USB to PC)

```
set ssid Kutuhala
set pass your-password
set frame 192.168.1.86
show
reboot
```

## Boards

| PlatformIO env | Board |
|----------------|-------|
| `esp32dev` (default) | ESP32‑WROOM dev kits, many NodeMCU‑32S |
| `esp32-s3-devkitc-1` | ESP32‑S3 (future USB host experiments) |

```powershell
pio run -e esp32-s3-devkitc-1 -t upload
```

## Split to its own repo?

This folder is self‑contained. You can copy `esp-bridge/` to a new GitHub repo anytime; the main picture frame repo treats it as an optional companion.

## Security note

The bridge exposes ADB on your LAN. Use only on a trusted home network. Do not port‑forward 5555 to the internet.
