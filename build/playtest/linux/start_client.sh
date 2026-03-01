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
