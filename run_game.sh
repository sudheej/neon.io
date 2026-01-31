#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERBOSE_FLAG=""
if [[ "${1:-}" == "--verbose" ]]; then
  VERBOSE_FLAG="--verbose"
fi

if [[ -n "${GODOT_BIN:-}" ]]; then
  BIN="$GODOT_BIN"
elif [[ -x "$HOME/Downloads/Godot_v4.5.1-stable_linux.x86_64" ]]; then
  BIN="$HOME/Downloads/Godot_v4.5.1-stable_linux.x86_64"
elif command -v godot4 >/dev/null 2>&1; then
  BIN="godot4"
elif command -v godot >/dev/null 2>&1; then
  BIN="godot"
else
  echo "Godot executable not found. Set GODOT_BIN or install godot4." >&2
  exit 1
fi

exec "$BIN" $VERBOSE_FLAG --path "$ROOT_DIR"
