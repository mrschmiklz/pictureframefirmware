#!/usr/bin/env bash
# Shared helpers for Linux/macOS host scripts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

host_os() {
  case "$(uname -s)" in
    Darwin) echo macos ;;
    Linux) echo linux ;;
    MINGW*|MSYS*|CYGWIN*) echo windows ;;
    *) echo unknown ;;
  esac
}

find_adb() {
  if [[ -n "${ADB:-}" && -x "$ADB" ]]; then
    echo "$ADB"
    return 0
  fi
  if command -v adb >/dev/null 2>&1; then
    command -v adb
    return 0
  fi
  local candidates=(
    "$HOME/Library/Android/sdk/platform-tools/adb"
    "$HOME/Android/Sdk/platform-tools/adb"
    "/usr/local/bin/adb"
    "/opt/homebrew/bin/adb"
  )
  local path
  for path in "${candidates[@]}"; do
    if [[ -x "$path" ]]; then
      echo "$path"
      return 0
    fi
  done
  cat >&2 <<'EOF'
adb not found.

Install Android platform-tools:
  macOS: brew install --cask android-platform-tools
  Linux: sudo apt install adb

Or set ADB=/path/to/adb
EOF
  return 1
}

frame_conf_path() {
  echo "$SCRIPT_DIR/frame.conf"
}

read_frame_conf() {
  FRAME_IP="${FRAME_IP:-192.168.1.85}"
  FRAME_ADB_PORT="${FRAME_ADB_PORT:-5555}"
  NAS_HOST="${NAS_HOST:-192.168.1.23}"
  NAS_SHARE="${NAS_SHARE:-nas}"
  NAS_PHOTOS_PATH="${NAS_PHOTOS_PATH:-framepics}"
  NAS_DEPLOY_PATH="${NAS_DEPLOY_PATH:-frame-deploy}"
  NAS_CONSOLE_PATH="${NAS_CONSOLE_PATH:-frame-console}"
  DEVICE_PROFILE="${DEVICE_PROFILE:-}"
  AGENT_PORT="${AGENT_PORT:-8080}"
  AGENT_TOKEN="${AGENT_TOKEN:-frame-local}"
  BOOT_SOURCE="${BOOT_SOURCE:-//$NAS_HOST/$NAS_SHARE/boot.png}"

  local conf
  conf="$(frame_conf_path)"
  [[ -f "$conf" ]] || return 0

  while IFS='=' read -r key value; do
    [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
    key="$(echo "$key" | tr -d '[:space:]')"
    value="$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    case "$key" in
      FRAME_IP) FRAME_IP="$value" ;;
      FRAME_ADB_PORT) FRAME_ADB_PORT="$value" ;;
      NAS_HOST) NAS_HOST="$value" ;;
      NAS_SHARE) NAS_SHARE="$value" ;;
      NAS_PHOTOS_PATH) NAS_PHOTOS_PATH="$value" ;;
      NAS_DEPLOY_PATH) NAS_DEPLOY_PATH="$value" ;;
      NAS_CONSOLE_PATH) NAS_CONSOLE_PATH="$value" ;;
      DEVICE_PROFILE) DEVICE_PROFILE="$value" ;;
      AGENT_PORT) AGENT_PORT="$value" ;;
      AGENT_TOKEN) AGENT_TOKEN="$value" ;;
      BOOT_SOURCE) BOOT_SOURCE="$value" ;;
    esac
  done < "$conf"
}

nas_smb_path() {
  local subpath="$1"
  if [[ "$(host_os)" == "windows" ]]; then
    echo "\\\\${NAS_HOST}\\${NAS_SHARE}\\${subpath}"
  else
    echo "//${NAS_HOST}/${NAS_SHARE}/${subpath}"
  fi
}

connected_serial() {
  local adb="$1"
  "$adb" devices | awk '/\tdevice$/{print $1; exit}'
}

connect_frame() {
  local adb="$1"
  read_frame_conf

  local serial
  serial="$(connected_serial "$adb" || true)"
  if [[ -n "$serial" ]]; then
    echo "$serial"
    return 0
  fi

  local target="${FRAME_IP}:${FRAME_ADB_PORT}"
  echo "No USB device. Trying Wi-Fi ADB at $target ..." >&2
  "$adb" connect "$target" >/dev/null 2>&1 || true
  sleep 2
  serial="$(connected_serial "$adb" || true)"
  if [[ -n "$serial" ]]; then
    echo "$serial"
    return 0
  fi

  echo "Could not reach picture frame over USB or Wi-Fi ADB." >&2
  echo "Run ./setup.sh from the repo root with USB connected." >&2
  return 1
}

get_wifi_ip() {
  local adb="$1"
  local serial="$2"
  local ip
  ip="$("$adb" -s "$serial" shell "ip -f inet addr show wlan0 2>/dev/null | awk '/inet / {print \$2}' | cut -d/ -f1" 2>/dev/null | tr -d '\r')"
  if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "$ip"
    return 0
  fi
  ip="$("$adb" -s "$serial" shell getprop dhcp.wlan0.ipaddress 2>/dev/null | tr -d '\r')"
  if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "$ip"
  fi
}

write_frame_conf() {
  read_frame_conf
  cat > "$(frame_conf_path)" <<EOF
# Generated/managed by pictureframefirmware setup
FRAME_IP=${FRAME_IP}
FRAME_ADB_PORT=${FRAME_ADB_PORT}
DEVICE_PROFILE=${DEVICE_PROFILE}

NAS_HOST=${NAS_HOST}
NAS_SHARE=${NAS_SHARE}
NAS_PHOTOS_PATH=${NAS_PHOTOS_PATH}
NAS_DEPLOY_PATH=${NAS_DEPLOY_PATH}
NAS_CONSOLE_PATH=${NAS_CONSOLE_PATH}

AGENT_PORT=${AGENT_PORT}
AGENT_TOKEN=${AGENT_TOKEN}

BOOT_SOURCE=${BOOT_SOURCE}
EOF
}

detect_with_python() {
  local adb="$1"
  local write="${2:-0}"
  python3 - "$adb" "$write" "$REPO_ROOT" "$SCRIPT_DIR" <<'PY'
import json, re, subprocess, sys
from pathlib import Path

adb, write_flag, repo_root, script_dir = sys.argv[1:5]
write = write_flag == "1"
repo = Path(repo_root)
catalog = json.loads((repo / "config" / "devices.json").read_text(encoding="utf-8"))

def sh(*args):
    return subprocess.check_output([adb, *args], text=True, stderr=subprocess.DEVNULL).strip()

def connected_serial():
    out = subprocess.check_output([adb, "devices"], text=True)
    for line in out.splitlines():
        if line.endswith("\tdevice"):
            return line.split("\t")[0]
    return ""

serial = connected_serial()
props = {}
packages = []
if serial:
    for name in [
        "ro.product.brand", "ro.product.manufacturer", "ro.product.model",
        "ro.es_frame.product", "ro.board.platform", "ro.sys.cputype", "ro.build.version.release"
    ]:
        props[name] = sh("-s", serial, "shell", "getprop", name)
    packages = [
        line.split(":", 1)[1]
        for line in sh("-s", serial, "shell", "pm", "list", "packages").splitlines()
        if line.startswith("package:")
    ]

def match_pattern(actual, expected):
    actual = actual or ""
    if "*" in expected:
        return re.fullmatch(expected.replace("*", ".*"), actual) is not None
    return actual == expected

def props_match(prop_set):
    return all(match_pattern(props.get(k, ""), v) for k, v in prop_set.items())

def profile_matches(profile):
    m = profile.get("match", {})
    if m.get("fallback"):
        return True
    for pkg in m.get("packages", []):
        if pkg not in packages:
            return False
    any_of = m.get("any_of") or []
    if any_of and not any(props_match(s) for s in any_of):
        return False
    all_props = m.get("all_props") or {}
    if all_props and not props_match(all_props):
        return False
    return True

chosen = None
for profile in catalog["profiles"]:
    if profile.get("match", {}).get("fallback"):
        fallback = profile
        continue
    if profile_matches(profile):
        chosen = profile
        break
if not chosen:
    chosen = fallback

conf_path = Path(script_dir) / "frame.conf"
frame_ip = "192.168.1.85"
if conf_path.exists():
    for line in conf_path.read_text(encoding="utf-8").splitlines():
        if line.startswith("FRAME_IP="):
            frame_ip = line.split("=", 1)[1].strip()

if serial:
    ip = sh("-s", serial, "shell", "ip -f inet addr show wlan0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1")
    if re.fullmatch(r"\d+\.\d+\.\d+\.\d+", ip or ""):
        frame_ip = ip

print(f"Detected: {chosen['name']} [{chosen['id']}]")
for k in ("ro.product.brand", "ro.product.manufacturer", "ro.product.model", "ro.es_frame.product"):
    if props.get(k):
        print(f"  {k}={props[k]}")
print(f"Frame IP: {frame_ip}")

if write:
    nas_host = "192.168.1.23"
    nas_share = "nas"
    if conf_path.exists():
        for line in conf_path.read_text(encoding="utf-8").splitlines():
            if line.startswith("NAS_HOST="):
                nas_host = line.split("=", 1)[1].strip()
            if line.startswith("NAS_SHARE="):
                nas_share = line.split("=", 1)[1].strip()
    dev = chosen["device"]
    conf_path.write_text(f"""# Generated/managed by pictureframefirmware setup
FRAME_IP={frame_ip}
FRAME_ADB_PORT=5555
DEVICE_PROFILE={chosen['id']}

NAS_HOST={nas_host}
NAS_SHARE={nas_share}
NAS_PHOTOS_PATH=framepics
NAS_DEPLOY_PATH=frame-deploy
NAS_CONSOLE_PATH=frame-console

AGENT_PORT=8080
AGENT_TOKEN=frame-local

BOOT_SOURCE=//{nas_host}/{nas_share}/boot.png
""", encoding="utf-8")
    nas_conf = Path(script_dir) / "nas.conf"
    nas_conf.write_text(f"""# NAS picture sync configuration (generated for {chosen['name']})
DEVICE_PROFILE={chosen['id']}
NAS_HOST={nas_host}
NAS_SHARE={nas_share}
NAS_PATH=framepics
DEPLOY_PATH=frame-deploy
CONSOLE_PATH=frame-console
AGENT_PORT=8080
AGENT_TOKEN=frame-local
NAS_USER=
NAS_PASS=
AIMOR_PKG={dev['aimor_package']}
AIMOR_DB={dev['aimor_db']}
IMAGE_DIR={dev['image_dir']}
PHOTO_WIDTH={dev['photo_width']}
PHOTO_HEIGHT={dev['photo_height']}
SYNC_INTERVAL=300
MIRROR_MODE=1
""", encoding="utf-8")
    print(f"Wrote {conf_path} and {nas_conf}")
PY
}
