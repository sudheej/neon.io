# Lobby Service (Scaffold)

In-memory prototype backend for queueing and basic match assignment.

## Run

```bash
cd backend/lobby-service
python3 app.py
```

Optional env vars:
- `LOBBY_HOST` (default `127.0.0.1`)
- `LOBBY_PORT` (default `8080`)
- `ACTIVE_MATCH_CAP` (default `10`)
- `MIN_PLAYERS_TO_START` (global fallback, default `1`)
- `MIN_PLAYERS_TO_START_MIXED` (default inherits `MIN_PLAYERS_TO_START`)
- `MIN_PLAYERS_TO_START_HUMAN_ONLY` (default `2`)
- `MATCH_ENDPOINT` (default `127.0.0.1:7000`)
- `PLAYTEST_KEY` (default empty; if set, clients must send `X-Playtest-Key`)
- `TRUST_PROXY_HEADERS` (default `0`; set `1` only behind a trusted proxy to honor `X-Forwarded-For`)
- `RATE_LIMIT_WINDOW_SEC` (default `10`)
- `RATE_LIMIT_HELLO` (default `60` requests per IP per window)
- `RATE_LIMIT_AUTH` (default `30` requests per IP per window)
- `RATE_LIMIT_QUEUE_JOIN` (default `20` requests per IP per window)
- `RATE_LIMIT_QUEUE_STATUS` (default `60` requests per IP per window)
- `RATE_LIMIT_QUEUE_LEAVE` (default `20` requests per IP per window)
- `RATE_LIMIT_MAX_TRACKED_KEYS` (default `5000`)
- `RATE_LIMIT_PRUNE_INTERVAL_MS` (default `30000`)

## API
- `GET /healthz`
- `POST /v1/hello`
- `POST /v1/auth`
- `POST /v1/queue/join`
- `POST /v1/queue/leave`
- `GET /v1/queue/status?session_id=<id>&mode=<mixed|human_only>`

This scaffold keeps state in-memory only and is intended for local integration work.

## Playtest Key

If `PLAYTEST_KEY` is set, every lobby request except `/healthz` must include header:

`X-Playtest-Key: <your-key>`

Godot clients can send this by setting:

`NEON_PLAYTEST_KEY=<your-key>`
