#!/usr/bin/env bash
# One-click picture frame setup (Linux/macOS)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if command -v pwsh >/dev/null 2>&1; then
  exec pwsh -NoProfile -ExecutionPolicy Bypass -File "$ROOT/scripts/setup_wizard.ps1" "$@"
fi
if command -v powershell >/dev/null 2>&1; then
  exec powershell -NoProfile -ExecutionPolicy Bypass -File "$ROOT/scripts/setup_wizard.ps1" "$@"
fi

exec bash "$ROOT/scripts/setup_frame.sh" "$@"
