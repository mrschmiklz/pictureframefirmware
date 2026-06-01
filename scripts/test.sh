#!/usr/bin/env bash
# Health check (Linux/macOS host).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/frame_common.sh
source "$SCRIPT_DIR/lib/frame_common.sh"

if command -v pwsh >/dev/null 2>&1; then
  exec pwsh -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_DIR/test_frame.ps1" "$@"
fi
if command -v powershell >/dev/null 2>&1; then
  exec powershell -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_DIR/test_frame.ps1" "$@"
fi

ADB="$(find_adb)"
read_frame_conf
echo "=== Picture Frame System Test ==="
echo "Host: $(host_os)"
echo "NAS photos: $(nas_smb_path "$NAS_PHOTOS_PATH")"
echo "Frame IP: $FRAME_IP"
echo "Device profile: ${DEVICE_PROFILE:-auto}"

if serial="$(connect_frame "$ADB" 2>/dev/null || true)"; then
  echo "[PASS] ADB connected: $serial"
  detect_with_python "$ADB" 0
else
  echo "[WARN] ADB not connected"
  exit 1
fi
