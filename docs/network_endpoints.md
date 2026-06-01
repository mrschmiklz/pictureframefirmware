# Picture frame outbound connections

Captured from live traffic (Wi‑Fi connected) and logcat on the AEEZO / Aimor frame.

## Live connections observed

| Remote | Port | Likely purpose |
|--------|------|----------------|
| `100.27.172.104` (`imsdevice.efercro.com`) | 10546 | YHK / Efercro cloud backend (HTTPS) |
| `23.45.123.26` | 443 | Main Aimor API (device login, ping, cloud sync) |
| `52.202.24.174` | 7806 | AWS (Kinesis Video — cloud video / WebRTC) |

Frame LAN IP when tested: `192.168.1.85`

## Known URLs (from logcat)

| URL | App / service |
|-----|----------------|
| `https://imsdevice.efercro.com:10546/edu` | OTA base (`com.yhk.qeota`) |
| `https://imsdevice.efercro.com:10546/edu/device/version/get?...` | App update checks |
| Device login API (HTTPS :443) | `CommunicationPresenter.deviceLogin` → JWT token |

OTA check sends: `deviceId=PF10090019014351`, model SN, package name, app version.

## Background services that phone home

| Component | Package | Behavior |
|-----------|---------|----------|
| `CommunicationService` | `com.efercro.os.aimor` | Cloud login, ping, photo sync, WLAN file server |
| `DownLoadService` | `com.yhk.qeota` | OTA firmware/app updates |
| `WeatherAlarmReceiver` | `com.efercro.os.aimor` | Scheduled weather fetch |
| AWS Kinesis Video JNI | `com.efercro.os.aimor` | Cloud video streaming stack |
| WebRTC | `com.efercro.os.aimor` | Video call feature (disabled in build props but libraries present) |

## Device identifiers sent to cloud

- Serial: `9a70ad88873700000000`
- VUID: `PF10090019014351`
- Brand/model: AEEZO Frame / YHK PF109

## Blocking WAN

Use `scripts/lockdown_network.ps1` to:

1. Apply iptables rules allowing only RFC1918 LAN + DNS to your router
2. Disable `com.yhk.qeota` (OTA updater)

Re-run after every reboot (iptables rules are not persistent on this device).

Optional router-side block list: `imsdevice.efercro.com`, `*.efercro.com`, and outbound to AWS from the frame’s MAC/IP.
