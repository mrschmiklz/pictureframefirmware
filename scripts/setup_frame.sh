#!/usr/bin/env bash
# Complete picture frame setup (Linux/macOS). USB required for first run.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/frame_common.sh
source "$SCRIPT_DIR/lib/frame_common.sh"

if command -v pwsh >/dev/null 2>&1; then
  exec pwsh -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_DIR/setup_wizard.ps1" "$@"
fi
if command -v powershell >/dev/null 2>&1; then
  exec powershell -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_DIR/setup_wizard.ps1" "$@"
fi

ADB="$(find_adb)"
"$ADB" start-server >/dev/null 2>&1 || true
read_frame_conf

if [[ ! -f "$(frame_conf_path)" ]]; then
  echo "No frame.conf — enter NAS details:"
  read -r -p "NAS IP or hostname [$NAS_HOST]: " ans
  [[ -n "$ans" ]] && NAS_HOST="$ans"
  read -r -p "NAS share name [$NAS_SHARE]: " ans
  [[ -n "$ans" ]] && NAS_SHARE="$ans"
  BOOT_SOURCE="$(nas_smb_path boot.png)"
  write_frame_conf
fi

echo "Detecting frame..."
detect_with_python "$ADB" 1

serial="$(connect_frame "$ADB")"
echo "Using device $serial"

bash "$SCRIPT_DIR/install.sh"
if [[ -f "$SCRIPT_DIR/install_persistent.ps1" ]] && command -v python3 >/dev/null 2>&1; then
  echo "Persistent boot hook: run from Windows once, or manually push setmacaddr_wrapper.sh"
fi

echo ""
echo "Setup core deploy complete."
echo "For persistent boot hook + splash on Allwinner/Aimor frames, run ./setup.sh on Windows once"
echo "or use Wi-Fi ADB + scripts from a Windows host with SETUP_FRAME.cmd."
echo "Test: bash scripts/test.sh"
