#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERBOSE_FLAG=""
EXTRA_ARGS=()
TEST_HUMAN_MODE=0
for arg in "$@"; do
  case "$arg" in
    --verbose)
      VERBOSE_FLAG="--verbose"
      ;;
    --test-human-mode)
      TEST_HUMAN_MODE=1
      ;;
    --hud-shot|--hud-shot-delay=*|--hud-shot-path=*)
      EXTRA_ARGS+=("$arg")
      ;;
    *)
      EXTRA_ARGS+=("$arg")
      ;;
  esac
done

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

LOBBY_URL="${NEON_LOBBY_URL:-http://127.0.0.1:8080}"
LOBBY_HEALTH="${LOBBY_URL%/}/healthz"
LOBBY_HOST_DEFAULT="${LOBBY_HOST:-127.0.0.1}"
LOBBY_PORT_DEFAULT="${LOBBY_PORT:-8080}"

is_headless_request() {
  for arg in "${EXTRA_ARGS[@]}"; do
    if [[ "$arg" == "--headless" || "$arg" == "--server" || "$arg" == "--script" || "$arg" == --script=* ]]; then
      return 0
    fi
  done
  return 1
}

is_lobby_healthy() {
  curl -fsS -m 1 "$LOBBY_HEALTH" >/dev/null 2>&1
}

start_lobby_service() {
  echo "[run_game] Starting lobby service at ${LOBBY_HOST_DEFAULT}:${LOBBY_PORT_DEFAULT}"
  local min_human="${MIN_PLAYERS_TO_START_HUMAN_ONLY:-2}"
  local min_mixed="${MIN_PLAYERS_TO_START_MIXED:-1}"
  (
    cd "$ROOT_DIR/backend/lobby-service"
    LOBBY_HOST="$LOBBY_HOST_DEFAULT" \
    LOBBY_PORT="$LOBBY_PORT_DEFAULT" \
    MIN_PLAYERS_TO_START_HUMAN_ONLY="$min_human" \
    MIN_PLAYERS_TO_START_MIXED="$min_mixed" \
    nohup python3 app.py >/tmp/neon_lobby.log 2>&1 &
    echo $! >/tmp/neon_lobby.pid
  )
}

stop_managed_lobby_service() {
  if [[ -f /tmp/neon_lobby.pid ]]; then
    local pid
    pid="$(cat /tmp/neon_lobby.pid 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" >/dev/null 2>&1 || true
      sleep 0.2
    fi
    rm -f /tmp/neon_lobby.pid
  fi
}

stop_existing_test_servers() {
  echo "[run_game] Stopping existing lobby/match server processes"
  pkill -f "backend/lobby-service/app.py" >/dev/null 2>&1 || true
  pkill -f "NEON_NETWORK_ROLE=server" >/dev/null 2>&1 || true
  pkill -f "NEON_SERVER=1" >/dev/null 2>&1 || true
  pkill -f "NEON_MODE=human_only" >/dev/null 2>&1 || true
  pkill -f -- "--skip-mode-select" >/dev/null 2>&1 || true
  pkill -f "/tmp/neon_human_client_" >/dev/null 2>&1 || true
  if command -v fuser >/dev/null 2>&1; then
    fuser -k 7000/udp >/dev/null 2>&1 || true
    fuser -k "${LOBBY_PORT_DEFAULT}/tcp" >/dev/null 2>&1 || true
  fi
  rm -f /tmp/neon_lobby.pid /tmp/neon_human_server.pid
  sleep 0.3
}

ensure_lobby_service() {
  if is_lobby_healthy; then
    return 0
  fi
  start_lobby_service
  for _ in {1..25}; do
    if is_lobby_healthy; then
      return 0
    fi
    sleep 0.2
  done
  echo "[run_game] ERROR: lobby service did not become healthy at $LOBBY_HEALTH" >&2
  if [[ -f /tmp/neon_lobby.log ]]; then
    echo "[run_game] /tmp/neon_lobby.log (last 40 lines):" >&2
    tail -n 40 /tmp/neon_lobby.log >&2 || true
  fi
  return 1
}

is_match_server_listening() {
  ss -lun 2>/dev/null | rg -q ':7000\b'
}

start_human_mode_server() {
  echo "[run_game] Starting human_only match server on udp:7000"
  nohup env \
    NEON_SERVER=1 \
    NEON_MODE=human_only \
    NEON_NETWORK_ROLE=server \
    NEON_TRANSPORT=enet \
    NEON_NET_LOG=1 \
    NEON_PORT=7000 \
    NEON_MAX_PLAYERS=10 \
    "$BIN" $VERBOSE_FLAG --headless --path "$ROOT_DIR" >/tmp/neon_human_server.log 2>&1 &
  echo $! >/tmp/neon_human_server.pid
}

launch_human_mode_clients() {
  local client_resolution="${NEON_TEST_CLIENT_RESOLUTION:-960x540}"
  local left_position="${NEON_TEST_CLIENT_LEFT_POS:-0,0}"
  local right_position="${NEON_TEST_CLIENT_RIGHT_POS:-970,0}"
  local positions=("$left_position" "$right_position")
  for idx in 1 2; do
    local pos="${positions[$((idx - 1))]}"
    echo "[run_game] Launching human_only client ${idx}"
    nohup env \
      NEON_MODE=human_only \
      NEON_AUTO_START=1 \
      NEON_LOBBY_URL="$LOBBY_URL" \
      NEON_NET_DEBUG_HUD=1 \
      NEON_NET_LOG=1 \
      "$BIN" $VERBOSE_FLAG \
      --path "$ROOT_DIR" \
      --windowed \
      --resolution "$client_resolution" \
      --position "$pos" \
      --net-debug-hud \
      --skip-mode-select >/tmp/neon_human_client_${idx}.log 2>&1 &
  done
}

if [[ "$TEST_HUMAN_MODE" -eq 1 ]]; then
  stop_existing_test_servers
  ensure_lobby_service
  if ! is_match_server_listening; then
    start_human_mode_server
    sleep 1
  fi
  launch_human_mode_clients
  echo "[run_game] human mode test started."
  echo "[run_game] If clients are in lobby, press Enter in both windows to queue."
  echo "[run_game] Client window layout: res=${NEON_TEST_CLIENT_RESOLUTION:-960x540}, left=${NEON_TEST_CLIENT_LEFT_POS:-0,0}, right=${NEON_TEST_CLIENT_RIGHT_POS:-970,0}"
  exit 0
fi

if ! is_headless_request; then
  ensure_lobby_service
fi

exec "$BIN" $VERBOSE_FLAG --path "$ROOT_DIR" "${EXTRA_ARGS[@]}"
