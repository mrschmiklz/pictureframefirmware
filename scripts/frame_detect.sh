#!/usr/bin/env bash
# Auto-detect picture frame model; optionally write scripts/frame.conf + nas.conf.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/frame_common.sh
source "$SCRIPT_DIR/lib/frame_common.sh"

WRITE=0
ADB_BIN=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --write-config) WRITE=1; shift ;;
    -Adb) ADB_BIN="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

ADB="$(find_adb)"
[[ -n "$ADB_BIN" ]] && ADB="$ADB_BIN"
"$ADB" start-server >/dev/null 2>&1 || true
detect_with_python "$ADB" "$WRITE"
