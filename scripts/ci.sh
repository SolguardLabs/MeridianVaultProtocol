#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v forge >/dev/null 2>&1; then
  if command -v powershell.exe >/dev/null 2>&1 && command -v wslpath >/dev/null 2>&1; then
    POWERSHELL_BIN="$(command -v powershell.exe)"
    if [[ -x /init ]]; then
      exec /init "$POWERSHELL_BIN" -NoProfile -ExecutionPolicy Bypass \
        -File "$(wslpath -w "$ROOT_DIR/scripts/ci.ps1")"
    fi
    exec "$POWERSHELL_BIN" -NoProfile -ExecutionPolicy Bypass \
      -File "$(wslpath -w "$ROOT_DIR/scripts/ci.ps1")"
  fi
  echo "forge no está disponible en PATH" >&2
  exit 127
fi

cd "$ROOT_DIR"
forge fmt --check
forge build --sizes
FOUNDRY_PROFILE=ci forge test -vvv
