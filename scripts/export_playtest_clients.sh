#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$ROOT_DIR/build/playtest}"

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

PRESETS_FILE="$ROOT_DIR/export_presets.cfg"
if [[ ! -f "$PRESETS_FILE" ]]; then
  cat >"$PRESETS_FILE" <<'EOF'
[preset.0]
name="Linux/X11"
platform="Linux/X11"
runnable=true
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path="build/playtest/linux/neon_client.x86_64"
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false
script_export_mode=1

[preset.0.options]
binary_format/embed_pck=true

[preset.1]
name="Windows Desktop"
platform="Windows Desktop"
runnable=true
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path="build/playtest/windows/neon_client.exe"
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false
script_export_mode=1

[preset.1.options]
binary_format/embed_pck=true
EOF
  echo "[export] Created default export presets at $PRESETS_FILE"
fi

LINUX_DIR="$OUT_DIR/linux"
WINDOWS_DIR="$OUT_DIR/windows"
LINUX_BIN_PATH="$LINUX_DIR/neon_client.x86_64"
WINDOWS_BIN_PATH="$WINDOWS_DIR/neon_client.exe"

mkdir -p "$LINUX_DIR" "$WINDOWS_DIR"

echo "[export] Exporting Linux client -> $LINUX_BIN_PATH"
"$BIN" --headless --path "$ROOT_DIR" --export-release "Linux/X11" "$LINUX_BIN_PATH"

echo "[export] Exporting Windows client -> $WINDOWS_BIN_PATH"
"$BIN" --headless --path "$ROOT_DIR" --export-release "Windows Desktop" "$WINDOWS_BIN_PATH"

chmod +x "$LINUX_BIN_PATH"

cat >"$LINUX_DIR/start_client.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$SCRIPT_DIR/neon_client.x86_64"

NEON_MODE="${NEON_MODE:-mixed}"
NEON_AUTO_START="${NEON_AUTO_START:-1}"
NEON_LOBBY_SCHEME="${NEON_LOBBY_SCHEME:-http}"
NEON_LOBBY_HOST="${NEON_LOBBY_HOST:-127.0.0.1}"
NEON_LOBBY_PORT="${NEON_LOBBY_PORT:-8080}"

if [[ -z "${NEON_LOBBY_URL:-}" ]]; then
  export NEON_LOBBY_URL="${NEON_LOBBY_SCHEME}://${NEON_LOBBY_HOST}:${NEON_LOBBY_PORT}"
fi

export NEON_MODE
export NEON_AUTO_START
exec "$BIN" --skip-mode-select "$@"
EOF

chmod +x "$LINUX_DIR/start_client.sh"

cat >"$WINDOWS_DIR/start_client.bat" <<'EOF'
@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "BIN=%SCRIPT_DIR%neon_client.exe"

if "%NEON_MODE%"=="" set "NEON_MODE=mixed"
if "%NEON_AUTO_START%"=="" set "NEON_AUTO_START=1"
if "%NEON_LOBBY_SCHEME%"=="" set "NEON_LOBBY_SCHEME=http"
if "%NEON_LOBBY_HOST%"=="" set "NEON_LOBBY_HOST=127.0.0.1"
if "%NEON_LOBBY_PORT%"=="" set "NEON_LOBBY_PORT=8080"
if "%NEON_LOBBY_URL%"=="" set "NEON_LOBBY_URL=%NEON_LOBBY_SCHEME%://%NEON_LOBBY_HOST%:%NEON_LOBBY_PORT%"

"%BIN%" --skip-mode-select %*
EOF

cat >"$OUT_DIR/README-playtest.txt" <<'EOF'
Playtest client exports
=======================

Linux:
  1) cd linux
  2) ./start_client.sh

Windows:
  1) Open windows\start_client.bat

Server targeting:
  - Set either:
      NEON_LOBBY_URL=http://<host>:<port>
    or:
      NEON_LOBBY_SCHEME=http
      NEON_LOBBY_HOST=<host>
      NEON_LOBBY_PORT=<port>

Examples:
  Linux:
    NEON_LOBBY_URL=http://10.0.0.15:8080 ./start_client.sh
  Windows (cmd):
    set NEON_LOBBY_HOST=10.0.0.15
    set NEON_LOBBY_PORT=8080
    start_client.bat
EOF

echo "[export] Done."
echo "[export] Linux launcher:   $LINUX_DIR/start_client.sh"
echo "[export] Windows launcher: $WINDOWS_DIR/start_client.bat"
echo "[export] Notes: $OUT_DIR/README-playtest.txt"
