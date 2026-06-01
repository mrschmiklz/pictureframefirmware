#!/usr/bin/env bash
# Deploy NAS sync tooling to the picture frame over USB/ADB (Linux/macOS host).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/frame_common.sh
source "$SCRIPT_DIR/lib/frame_common.sh"

ADB="$(find_adb)"
read_frame_conf
serial="$(connect_frame "$ADB")"
echo "Connected: $serial"

if command -v pwsh >/dev/null 2>&1; then
  pwsh -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_DIR/install.ps1" -Adb "$ADB"
  exit $?
fi
if command -v powershell >/dev/null 2>&1; then
  powershell -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_DIR/install.ps1" -Adb "$ADB"
  exit $?
fi

# Pure bash fallback
PROFILE="${DEVICE_PROFILE:-pf109_aimor}"
RCLONE="$REPO_ROOT/tools/rclone-v1.74.2-linux-arm/rclone"
if [[ ! -x "$RCLONE" ]]; then
  echo "rclone not found at $RCLONE" >&2
  echo "Download linux-arm rclone from https://rclone.org/downloads/" >&2
  exit 1
fi

detect_with_python "$ADB" 1 >/dev/null

"$ADB" -s "$serial" shell "mkdir -p /data/local/frame-sync/bin"
echo "Pushing rclone..."
"$ADB" -s "$serial" push "$RCLONE" /data/local/frame-sync/bin/rclone

scripts=(nas.conf sync_nas.sh start_sync_daemon.sh block_wan.sh boot.sh install_from_nas.sh install_splash.sh restore_usb_adb.sh process_nas_console.sh start_agent.sh)
for name in "${scripts[@]}"; do
  "$ADB" -s "$serial" push "$SCRIPT_DIR/$name" "/data/local/frame-sync/$name"
done

"$ADB" -s "$serial" shell "mkdir -p /data/local/frame-sync/agent"
"$ADB" -s "$serial" push "$REPO_ROOT/frame-agent/agent.conf" /data/local/frame-sync/agent/agent.conf
"$ADB" -s "$serial" push "$REPO_ROOT/frame-agent/start_agent.sh" /data/local/frame-sync/agent/start_agent.sh
"$ADB" -s "$serial" push "$REPO_ROOT/frame-agent/lib" /data/local/frame-sync/agent/lib
"$ADB" -s "$serial" push "$REPO_ROOT/frame-agent/www" /data/local/frame-sync/agent/www

"$ADB" -s "$serial" shell "chmod 755 /data/local/frame-sync/bin/rclone /data/local/frame-sync/sync_nas.sh /data/local/frame-sync/start_sync_daemon.sh /data/local/frame-sync/block_wan.sh /data/local/frame-sync/boot.sh /data/local/frame-sync/install_from_nas.sh /data/local/frame-sync/install_splash.sh /data/local/frame-sync/restore_usb_adb.sh /data/local/frame-sync/process_nas_console.sh /data/local/frame-sync/start_agent.sh /data/local/frame-sync/agent/start_agent.sh /data/local/frame-sync/agent/www/cgi-bin/*.cgi /data/local/frame-sync/agent/lib/*.sh"
"$ADB" -s "$serial" shell "/data/local/frame-sync/start_sync_daemon.sh"
echo "Installed."
