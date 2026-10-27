#!/usr/bin/env sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if command -v cygpath >/dev/null 2>&1; then
  PS_SCRIPT=$(cygpath -w "$SCRIPT_DIR/stop-local.ps1")
elif command -v wslpath >/dev/null 2>&1; then
  PS_SCRIPT=$(wslpath -w "$SCRIPT_DIR/stop-local.ps1")
else
  PS_SCRIPT="$SCRIPT_DIR/stop-local.ps1"
fi
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT"
