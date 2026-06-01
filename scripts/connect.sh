#!/usr/bin/env bash
# Connect to the picture frame over Wi-Fi ADB.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/frame_common.sh
source "$SCRIPT_DIR/lib/frame_common.sh"

ADB="$(find_adb)"
read_frame_conf
serial="$(connected_serial "$ADB" || true)"
if [[ -n "$serial" && "$serial" != *:* ]]; then
  echo "Already connected over USB: $serial"
  exit 0
fi

serial="$(connect_frame "$ADB")"
model="$("$ADB" -s "$serial" shell getprop ro.product.model | tr -d '\r')"
echo "Connected: $model at $serial"
