#!/usr/bin/env python3
"""Minimal lobby + match assignment service (in-memory, no dependencies).

Endpoints:
- GET  /healthz
- POST /v1/hello
- POST /v1/auth
- POST /v1/queue/join
- POST /v1/queue/leave
- GET  /v1/queue/status?session_id=<id>&mode=<mixed|human_only>
"""

from __future__ import annotations

import json
import hmac
import hashlib
import base64
import os
import secrets
import threading
import time
import uuid
from collections import deque
from dataclasses import dataclass, field
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Deque, Dict, List, Tuple
from urllib.parse import parse_qs, urlsplit

HOST = os.environ.get("LOBBY_HOST", "127.0.0.1")
PORT = int(os.environ.get("LOBBY_PORT", "8080"))
ACTIVE_MATCH_CAP = int(os.environ.get("ACTIVE_MATCH_CAP", "10"))
MAX_ACTIVE_MATCHES = int(os.environ.get("MAX_ACTIVE_MATCHES", "1"))
MIN_PLAYERS_TO_START = int(os.environ.get("MIN_PLAYERS_TO_START", "1"))
MIN_PLAYERS_TO_START_MIXED = int(os.environ.get("MIN_PLAYERS_TO_START_MIXED", str(MIN_PLAYERS_TO_START)))
MIN_PLAYERS_TO_START_HUMAN_ONLY = int(
    os.environ.get("MIN_PLAYERS_TO_START_HUMAN_ONLY", str(max(MIN_PLAYERS_TO_START, 2)))
)
MATCH_ENDPOINT = os.environ.get("MATCH_ENDPOINT", "127.0.0.1:7000")
ASSIGNMENT_TTL_MS = int(os.environ.get("ASSIGNMENT_TTL_MS", "20000"))
MATCH_TOKEN_TTL_MS = int(os.environ.get("MATCH_TOKEN_TTL_MS", "14400000"))
QUEUE_JOIN_COOLDOWN_MS = int(os.environ.get("QUEUE_JOIN_COOLDOWN_MS", "1200"))
PLAYTEST_KEY = os.environ.get("PLAYTEST_KEY", "")
TRUST_PROXY_HEADERS = os.environ.get("TRUST_PROXY_HEADERS", "0") == "1"
RATE_LIMIT_WINDOW_SEC = float(os.environ.get("RATE_LIMIT_WINDOW_SEC", "10"))
RATE_LIMIT_HELLO = int(os.environ.get("RATE_LIMIT_HELLO", "60"))
RATE_LIMIT_AUTH = int(os.environ.get("RATE_LIMIT_AUTH", "30"))
RATE_LIMIT_QUEUE_JOIN = int(os.environ.get("RATE_LIMIT_QUEUE_JOIN", "20"))
RATE_LIMIT_QUEUE_STATUS = int(os.environ.get("RATE_LIMIT_QUEUE_STATUS", "60"))
RATE_LIMIT_QUEUE_LEAVE = int(os.environ.get("RATE_LIMIT_QUEUE_LEAVE", "20"))
RATE_LIMIT_MAX_TRACKED_KEYS = int(os.environ.get("RATE_LIMIT_MAX_TRACKED_KEYS", "5000"))
RATE_LIMIT_PRUNE_INTERVAL_MS = int(os.environ.get("RATE_LIMIT_PRUNE_INTERVAL_MS", "30000"))
MAX_REQUEST_BODY_BYTES = int(os.environ.get("MAX_REQUEST_BODY_BYTES", "16384"))
MAX_IDENTIFIER_LENGTH = int(os.environ.get("MAX_IDENTIFIER_LENGTH", "128"))
MAX_TRACKED_SESSIONS = int(os.environ.get("MAX_TRACKED_SESSIONS", "10000"))
MATCH_TOKEN_SECRET = os.environ.get("MATCH_TOKEN_SECRET", "")
MATCH_ID_SUFFIX = os.environ.get("MATCH_ID_SUFFIX", "")


@dataclass
class PendingAssignment:
    session_id: str
    mode: str
    match_id: str
    endpoint: str
    match_token: str
    actor_id: str
    created_ms: int
    expires_ms: int
    token_expires_ms: int
    accepted: bool = False


@dataclass
class QueueState:
    waiting: Deque[str] = field(default_factory=deque)
    active_matches: Dict[str, List[str]] = field(default_factory=dict)
    pending_assignments: Dict[str, PendingAssignment] = field(default_factory=dict)
    last_join_ms: Dict[str, int] = field(default_factory=dict)


QUEUES: Dict[str, QueueState] = {
    "mixed": QueueState(),
    "human_only": QueueState(),
}
SESSIONS: Dict[str, str] = {}
LOCK = threading.Lock()
RATE_LIMIT_STATE: Dict[Tuple[str, str], Tuple[int, int]] = {}
RATE_LIMIT_LAST_PRUNE_MS = 0


def _timestamp_ms() -> int:
    return int(time.time() * 1000)


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _issue_match_token(session_id: str, player_id: str, match_id: str, actor_id: str, expires_ms: int) -> str:
    if not MATCH_TOKEN_SECRET:
        raise RuntimeError("MATCH_TOKEN_SECRET must be configured before allocating matches")
    claims = json.dumps({
        "session_id": session_id,
        "player_id": player_id,
        "match_id": match_id,
        "actor_id": actor_id,
        "expires_at_ms": expires_ms,
    }, separators=(",", ":"), sort_keys=True).encode("utf-8")
    encoded = _b64url(claims)
    signature = hmac.new(MATCH_TOKEN_SECRET.encode("utf-8"), encoded.encode("ascii"), hashlib.sha256).digest()
    return f"{encoded}.{_b64url(signature)}"


def _json(handler: BaseHTTPRequestHandler, code: int, payload: dict) -> None:
    body = json.dumps(payload).encode("utf-8")
    handler.send_response(code)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Cache-Control", "no-store")
    handler.send_header("X-Content-Type-Options", "nosniff")
    handler.end_headers()
    handler.wfile.write(body)


def _client_ip(handler: BaseHTTPRequestHandler) -> str:
    if TRUST_PROXY_HEADERS:
        forwarded = handler.headers.get("X-Forwarded-For", "")
        if forwarded:
            parts = [part.strip() for part in forwarded.split(",") if part.strip()]
            if parts:
                return parts[0]
    host, _ = handler.client_address
    return host


def _is_playtest_key_valid(handler: BaseHTTPRequestHandler) -> bool:
    if not PLAYTEST_KEY:
        return True
    provided_key = handler.headers.get("X-Playtest-Key", "")
    return hmac.compare_digest(provided_key, PLAYTEST_KEY)


def _rate_limit_max_for_path(path: str) -> int:
    if path.startswith("/v1/queue/status"):
        return max(RATE_LIMIT_QUEUE_STATUS, 1)
    if path == "/v1/hello":
        return max(RATE_LIMIT_HELLO, 1)
    if path == "/v1/auth":
        return max(RATE_LIMIT_AUTH, 1)
    if path == "/v1/queue/join":
        return max(RATE_LIMIT_QUEUE_JOIN, 1)
    if path == "/v1/queue/leave":
        return max(RATE_LIMIT_QUEUE_LEAVE, 1)
    return 0


def _check_rate_limit(ip: str, path: str) -> int:
    global RATE_LIMIT_LAST_PRUNE_MS
    max_requests = _rate_limit_max_for_path(path)
    if max_requests <= 0:
        return 0
    window_sec = max(RATE_LIMIT_WINDOW_SEC, 1.0)
    now_ms = _timestamp_ms()
    window_ms = int(window_sec * 1000.0)
    if now_ms - RATE_LIMIT_LAST_PRUNE_MS >= max(RATE_LIMIT_PRUNE_INTERVAL_MS, 1000):
        RATE_LIMIT_LAST_PRUNE_MS = now_ms
        stale_keys: List[Tuple[str, str]] = []
        for state_key, state_val in RATE_LIMIT_STATE.items():
            state_window_start_ms = int(state_val[0])
            if now_ms - state_window_start_ms >= window_ms:
                stale_keys.append(state_key)
        for stale_key in stale_keys:
            RATE_LIMIT_STATE.pop(stale_key, None)
        max_keys = max(RATE_LIMIT_MAX_TRACKED_KEYS, 1)
        if len(RATE_LIMIT_STATE) > max_keys:
            oldest_entries = sorted(RATE_LIMIT_STATE.items(), key=lambda item: int(item[1][0]))
            overflow = len(RATE_LIMIT_STATE) - max_keys
            for idx in range(overflow):
                RATE_LIMIT_STATE.pop(oldest_entries[idx][0], None)
    key = (ip, path.split("?", 1)[0])
    window_start_ms, count = RATE_LIMIT_STATE.get(key, (now_ms, 0))
    if now_ms - window_start_ms >= window_ms:
        window_start_ms = now_ms
        count = 0
    if count >= max_requests:
        retry_ms = max(0, window_ms - (now_ms - window_start_ms))
        return retry_ms if retry_ms > 0 else 1
    RATE_LIMIT_STATE[key] = (window_start_ms, count + 1)
    return 0


def _read_json(handler: BaseHTTPRequestHandler) -> tuple[dict | None, str | None]:
    try:
        length = int(handler.headers.get("Content-Length", "0"))
    except (TypeError, ValueError):
        return None, "invalid_content_length"
    if length <= 0:
        return {}, None
    if length > max(MAX_REQUEST_BODY_BYTES, 1):
        return None, "request_body_too_large"
    data = handler.rfile.read(length)
    try:
        payload = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None, "invalid_json"
    if not isinstance(payload, dict):
        return None, "json_object_required"
    return payload, None


def _valid_identifier(value: object) -> bool:
    return isinstance(value, str) and 0 < len(value) <= max(MAX_IDENTIFIER_LENGTH, 1)


def _require_mode(mode: str) -> bool:
    return mode in QUEUES


def _allocate_match(mode: str) -> dict | None:
    state = QUEUES[mode]
    if not state.waiting:
        return None
    cap = max(ACTIVE_MATCH_CAP, 1)
    match_id = ""
    players: List[str] | None = None
    for active_match_id, active_players in state.active_matches.items():
        if len(active_players) < cap:
            match_id = active_match_id
            players = active_players
            break
    if players is None:
        if len(state.active_matches) >= max(MAX_ACTIVE_MATCHES, 1):
            return None
        if len(state.waiting) < _min_players_to_start_for_mode(mode):
            return None
        match_id = f"{mode}_{MATCH_ID_SUFFIX}" if MATCH_ID_SUFFIX else f"{mode}_{uuid.uuid4().hex}"
        players = []
        state.active_matches[match_id] = players
    starting_index = len(players)
    assigned_players: List[str] = []
    while state.waiting and len(players) < cap:
        session_id = state.waiting.popleft()
        players.append(session_id)
        assigned_players.append(session_id)
    if not assigned_players:
        return None
    now_ms = _timestamp_ms()
    expires_ms = now_ms + max(ASSIGNMENT_TTL_MS, 1000)
    token_expires_ms = now_ms + max(MATCH_TOKEN_TTL_MS, 1000)
    for idx, session_id in enumerate(assigned_players, start=starting_index):
        session_suffix = session_id[-8:] if len(session_id) > 8 else session_id
        actor_id = f"{mode}_{session_suffix}_{idx + 1}"
        state.pending_assignments[session_id] = PendingAssignment(
            session_id=session_id,
            mode=mode,
            match_id=match_id,
            endpoint=MATCH_ENDPOINT,
            match_token=_issue_match_token(session_id, SESSIONS.get(session_id, session_id), match_id, actor_id, token_expires_ms),
            actor_id=actor_id,
            created_ms=now_ms,
            expires_ms=expires_ms,
            token_expires_ms=token_expires_ms,
        )
    return {
        "match_id": match_id,
        "endpoint": MATCH_ENDPOINT,
        "players": assigned_players,
    }


def _min_players_to_start_for_mode(mode: str) -> int:
    if mode == "human_only":
        return max(MIN_PLAYERS_TO_START_HUMAN_ONLY, 1)
    if mode == "mixed":
        return max(MIN_PLAYERS_TO_START_MIXED, 1)
    return max(MIN_PLAYERS_TO_START, 1)


def _find_queue_position(mode: str, session_id: str) -> int:
    state = QUEUES[mode]
    try:
        return list(state.waiting).index(session_id) + 1
    except ValueError:
        return 0


def _eta_bucket_for_position(position: int) -> str:
    if position <= 1:
        return "now"
    if position <= 3:
        return "<30s"
    if position <= 8:
        return "30-120s"
    return "2m+"


def _build_assignment_payload(pending: PendingAssignment) -> dict:
    return {
        "msg_type": "match_assigned",
        "mode": pending.mode,
        "match_id": pending.match_id,
        "endpoint": pending.endpoint,
        "match_token": pending.match_token,
        "actor_id": pending.actor_id,
        "timestamp_ms": _timestamp_ms(),
        "expires_at_ms": pending.token_expires_ms,
    }


def _expire_assignments(mode: str) -> None:
    state = QUEUES[mode]
    now_ms = _timestamp_ms()
    expired_sessions: List[str] = []
    for session_id, pending in state.pending_assignments.items():
        expiry_ms = pending.token_expires_ms if pending.accepted else pending.expires_ms
        if expiry_ms <= now_ms:
            expired_sessions.append(session_id)
    for session_id in expired_sessions:
        pending = state.pending_assignments.pop(session_id, None)
        if not pending:
            continue
        _remove_player_from_match(state, pending.match_id, session_id)
        # An assignment that was never acknowledged by a fresh queue request is
        # abandoned. Re-enqueueing it creates ghost players after clients have
        # entered a match, died, or disconnected with no lobby process polling.


def _remove_player_from_match(state: QueueState, match_id: str, session_id: str) -> None:
    players = state.active_matches.get(match_id)
    if players is None:
        return
    remaining = [player for player in players if player != session_id]
    if remaining:
        state.active_matches[match_id] = remaining
    else:
        state.active_matches.pop(match_id, None)


class LobbyHandler(BaseHTTPRequestHandler):
    server_version = "LobbyService/0.1"

    def log_message(self, fmt: str, *args) -> None:
        return

    def do_GET(self) -> None:  # noqa: N802
        parsed_url = urlsplit(self.path)
        if parsed_url.path == "/healthz":
            _json(self, HTTPStatus.OK, {"ok": True, "time_ms": _timestamp_ms()})
            return
        if not _is_playtest_key_valid(self):
            _json(self, HTTPStatus.UNAUTHORIZED, {"error": "invalid_playtest_key"})
            return
        with LOCK:
            retry_ms = _check_rate_limit(_client_ip(self), self.path)
        if retry_ms > 0:
            _json(
                self,
                HTTPStatus.TOO_MANY_REQUESTS,
                {"error": "rate_limited", "retry_in_ms": retry_ms, "timestamp_ms": _timestamp_ms()},
            )
            return

        if parsed_url.path == "/v1/queue/status":
            params = parse_qs(parsed_url.query, keep_blank_values=True)
            session_id = params.get("session_id", [""])[0]
            mode = params.get("mode", ["mixed"])[0]
            if not _valid_identifier(session_id):
                _json(self, HTTPStatus.BAD_REQUEST, {"error": "invalid_session_id"})
                return
            if not _require_mode(mode):
                _json(self, HTTPStatus.BAD_REQUEST, {"error": "invalid_mode"})
                return
            with LOCK:
                if session_id not in SESSIONS:
                    _json(self, HTTPStatus.UNAUTHORIZED, {"error": "unknown_session"})
                    return
                state = QUEUES[mode]
                _expire_assignments(mode)
                pending = state.pending_assignments.get(session_id)
                if pending is not None:
                    _json(self, HTTPStatus.OK, _build_assignment_payload(pending))
                    return
                _allocate_match(mode)
                pending = state.pending_assignments.get(session_id)
                if pending is not None:
                    _json(self, HTTPStatus.OK, _build_assignment_payload(pending))
                    return
                pos = _find_queue_position(mode, session_id)
                payload = {
                    "msg_type": "queue_status",
                    "queue": mode,
                    "position": pos,
                    "position_estimate": pos,
                    "queue_size": len(state.waiting),
                    "eta_bucket": _eta_bucket_for_position(pos),
                    "active_matches": len(state.active_matches),
                    "match_capacity": ACTIVE_MATCH_CAP,
                    "timestamp_ms": _timestamp_ms(),
                }
            _json(self, HTTPStatus.OK, payload)
            return

        _json(self, HTTPStatus.NOT_FOUND, {"error": "not_found"})

    def do_POST(self) -> None:  # noqa: N802
        if not _is_playtest_key_valid(self):
            _json(self, HTTPStatus.UNAUTHORIZED, {"error": "invalid_playtest_key"})
            return
        with LOCK:
            retry_ms = _check_rate_limit(_client_ip(self), self.path)
        if retry_ms > 0:
            _json(
                self,
                HTTPStatus.TOO_MANY_REQUESTS,
                {"error": "rate_limited", "retry_in_ms": retry_ms, "timestamp_ms": _timestamp_ms()},
            )
            return
        payload, read_error = _read_json(self)
        if read_error is not None:
            status = HTTPStatus.REQUEST_ENTITY_TOO_LARGE if read_error == "request_body_too_large" else HTTPStatus.BAD_REQUEST
            _json(self, status, {"error": read_error})
            return
        assert payload is not None

        if self.path == "/v1/hello":
            _json(
                self,
                HTTPStatus.OK,
                {
                    "msg_type": "hello",
                    "protocol_version": "net.v1",
                    "timestamp_ms": _timestamp_ms(),
                },
            )
            return

        if self.path == "/v1/auth":
            session_id = str(payload.get("session_id", ""))
            player_id = str(payload.get("player_id", ""))
            if not _valid_identifier(session_id) or not _valid_identifier(player_id):
                _json(self, HTTPStatus.BAD_REQUEST, {"error": "invalid_session_or_player"})
                return
            with LOCK:
                if session_id not in SESSIONS and len(SESSIONS) >= max(MAX_TRACKED_SESSIONS, 1):
                    # The service is intentionally in-memory. Bound attacker-controlled
                    # session cardinality instead of allowing indefinite process growth.
                    oldest_session = next(iter(SESSIONS))
                    SESSIONS.pop(oldest_session, None)
                SESSIONS[session_id] = player_id
            _json(self, HTTPStatus.OK, {"ok": True, "timestamp_ms": _timestamp_ms()})
            return

        if self.path == "/v1/queue/join":
            session_id = str(payload.get("session_id", ""))
            mode = str(payload.get("mode", "mixed"))
            if not _valid_identifier(session_id):
                _json(self, HTTPStatus.BAD_REQUEST, {"error": "invalid_session_id"})
                return
            if not _require_mode(mode):
                _json(self, HTTPStatus.BAD_REQUEST, {"error": "invalid_mode"})
                return
            with LOCK:
                if session_id not in SESSIONS:
                    _json(self, HTTPStatus.UNAUTHORIZED, {"error": "unknown_session"})
                    return
                state = QUEUES[mode]
                now_ms = _timestamp_ms()
                last_join_ms = int(state.last_join_ms.get(session_id, 0))
                cooldown_ms = max(QUEUE_JOIN_COOLDOWN_MS, 0)
                if cooldown_ms > 0 and now_ms - last_join_ms < cooldown_ms:
                    retry_ms = cooldown_ms - (now_ms - last_join_ms)
                    _json(
                        self,
                        HTTPStatus.TOO_MANY_REQUESTS,
                        {
                            "error": "queue_join_cooldown",
                            "retry_in_ms": retry_ms,
                            "timestamp_ms": now_ms,
                        },
                    )
                    return
                state.last_join_ms[session_id] = now_ms
                _expire_assignments(mode)
                pending = state.pending_assignments.get(session_id)
                if pending is not None:
                    _json(self, HTTPStatus.OK, _build_assignment_payload(pending))
                    return
                if session_id not in state.waiting:
                    state.waiting.append(session_id)
                _allocate_match(mode)
                pending = state.pending_assignments.get(session_id)
                if pending is not None:
                    _json(self, HTTPStatus.OK, _build_assignment_payload(pending))
                    return
                _json(
                    self,
                    HTTPStatus.OK,
                    {
                        "msg_type": "queue_status",
                        "mode": mode,
                        "position": _find_queue_position(mode, session_id),
                        "position_estimate": _find_queue_position(mode, session_id),
                        "queue_size": len(state.waiting),
                        "eta_bucket": _eta_bucket_for_position(_find_queue_position(mode, session_id)),
                        "timestamp_ms": _timestamp_ms(),
                    },
                )
            return

        if self.path == "/v1/match/accept":
            session_id = str(payload.get("session_id", ""))
            mode = str(payload.get("mode", "mixed"))
            match_id = str(payload.get("match_id", ""))
            match_token = str(payload.get("match_token", ""))
            if not _valid_identifier(session_id) or not _require_mode(mode):
                _json(self, HTTPStatus.BAD_REQUEST, {"error": "invalid_assignment"})
                return
            with LOCK:
                if session_id not in SESSIONS:
                    _json(self, HTTPStatus.UNAUTHORIZED, {"error": "unknown_session"})
                    return
                pending = QUEUES[mode].pending_assignments.get(session_id)
                if (
                    pending is None
                    or pending.match_id != match_id
                    or not hmac.compare_digest(pending.match_token, match_token)
                    or pending.token_expires_ms <= _timestamp_ms()
                ):
                    _json(self, HTTPStatus.CONFLICT, {"error": "assignment_invalid_or_expired"})
                    return
                pending.accepted = True
            _json(self, HTTPStatus.OK, {"ok": True, "timestamp_ms": _timestamp_ms()})
            return

        if self.path == "/v1/queue/leave":
            session_id = str(payload.get("session_id", ""))
            mode = str(payload.get("mode", "mixed"))
            if not _require_mode(mode):
                _json(self, HTTPStatus.BAD_REQUEST, {"error": "invalid_mode"})
                return
            if not _valid_identifier(session_id):
                _json(self, HTTPStatus.BAD_REQUEST, {"error": "invalid_session_id"})
                return
            with LOCK:
                if session_id not in SESSIONS:
                    _json(self, HTTPStatus.UNAUTHORIZED, {"error": "unknown_session"})
                    return
                state = QUEUES[mode]
                state.waiting = deque([s for s in state.waiting if s != session_id])
                pending = state.pending_assignments.pop(session_id, None)
                if pending is not None:
                    _remove_player_from_match(state, pending.match_id, session_id)
            _json(self, HTTPStatus.OK, {"ok": True, "timestamp_ms": _timestamp_ms()})
            return

        _json(self, HTTPStatus.NOT_FOUND, {"error": "not_found"})


def main() -> None:
    if not MATCH_TOKEN_SECRET:
        raise SystemExit("MATCH_TOKEN_SECRET is required and must also be configured on match servers")
    server = ThreadingHTTPServer((HOST, PORT), LobbyHandler)
    print(f"[lobby-service] listening on http://{HOST}:{PORT} cap={ACTIVE_MATCH_CAP}")
    server.serve_forever()


if __name__ == "__main__":
    main()
