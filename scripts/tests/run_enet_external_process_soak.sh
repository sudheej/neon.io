#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ITERATIONS="${NEON_SOAK_ITERATIONS:-3}"
BASE_PORT="${NEON_SOAK_BASE_PORT:-17330}"
PROCESS_TIMEOUT="${NEON_SOAK_PROCESS_TIMEOUT:-15}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/neon-enet-soak.XXXXXX")"
PIDS=()

cleanup() {
  local pid
  for pid in "${PIDS[@]:-}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT INT TERM

fail_with_logs() {
  local message="$1"
  echo "[enet_external_soak] FAIL: $message" >&2
  local log
  for log in "$WORK_DIR"/*.log; do
    [[ -e "$log" ]] || continue
    echo "--- $log ---" >&2
    tail -n 80 "$log" >&2 || true
  done
  exit 1
}

wait_for_marker() {
  local log="$1"
  local marker="$2"
  local attempts=$((PROCESS_TIMEOUT * 10))
  local attempt
  for ((attempt = 0; attempt < attempts; attempt++)); do
    if grep -Fq "$marker" "$log" 2>/dev/null; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

wait_for_process() {
  local pid="$1"
  local label="$2"
  local attempts=$((PROCESS_TIMEOUT * 10))
  local attempt
  for ((attempt = 0; attempt < attempts; attempt++)); do
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid" || fail_with_logs "$label exited unsuccessfully"
      return 0
    fi
    sleep 0.1
  done
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  fail_with_logs "$label exceeded ${PROCESS_TIMEOUT}s"
}

run_peer() {
  local role="$1"
  local port="$2"
  local log="$3"
  shift 3
  env NEON_TEST_ROLE="$role" NEON_PORT="$port" "$@" \
    ./run_game.sh --headless --script res://scripts/tests/enet_external_process_peer.gd \
    >"$log" 2>&1 &
  local pid=$!
  PIDS+=("$pid")
  LAST_PID="$pid"
}

cd "$ROOT_DIR"

for ((iteration = 1; iteration <= ITERATIONS; iteration++)); do
  port=$((BASE_PORT + iteration))
  server_log="$WORK_DIR/server-${iteration}.log"
  client_log="$WORK_DIR/client-${iteration}.log"

  run_peer server "$port" "$server_log"
  server_pid="$LAST_PID"
  wait_for_marker "$server_log" "[enet_external] SERVER_READY" || fail_with_logs "server did not become ready (iteration $iteration)"
  run_peer client "$port" "$client_log"
  client_pid="$LAST_PID"

  wait_for_process "$client_pid" "client iteration $iteration"
  wait_for_process "$server_pid" "server iteration $iteration"
  grep -Fq "[enet_external] CLIENT_PASS" "$client_log" || fail_with_logs "client success marker missing (iteration $iteration)"
  grep -Fq "[enet_external] SERVER_PASS" "$server_log" || fail_with_logs "server success marker missing (iteration $iteration)"
  if grep -Eq 'SCRIPT ERROR|ERROR:|FAIL:' "$server_log" "$client_log"; then
    fail_with_logs "unexpected error in successful session logs (iteration $iteration)"
  fi
  echo "[enet_external_soak] session $iteration/$ITERATIONS PASS"
done

# A second server on an occupied port must report a handled transport failure
# and exit successfully rather than hanging or crashing.
failure_port=$((BASE_PORT + ITERATIONS + 100))
blocker_log="$WORK_DIR/failure-port-owner.log"
failure_log="$WORK_DIR/expected-failure.log"
run_peer server "$failure_port" "$blocker_log"
blocker_pid="$LAST_PID"
wait_for_marker "$blocker_log" "[enet_external] SERVER_READY" || fail_with_logs "failure-path port owner did not become ready"
run_peer server "$failure_port" "$failure_log" NEON_TEST_EXPECT_FAILURE=1
failure_pid="$LAST_PID"
wait_for_process "$failure_pid" "expected bind failure"
grep -Fq "[enet_external] EXPECTED_TRANSPORT_FAILURE_PASS" "$failure_log" || fail_with_logs "expected failure marker missing"
kill "$blocker_pid" 2>/dev/null || true
wait "$blocker_pid" 2>/dev/null || true

echo "[enet_external_soak] PASS sessions=$ITERATIONS failure_path=PASS"
