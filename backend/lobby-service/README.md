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
- `MIN_PLAYERS_TO_START` (default `1`)
- `MATCH_ENDPOINT` (default `127.0.0.1:7000`)

## API
- `GET /healthz`
- `POST /v1/hello`
- `POST /v1/auth`
- `POST /v1/queue/join`
- `POST /v1/queue/leave`
- `GET /v1/queue/status?session_id=<id>&mode=<mixed|human_only>`

This scaffold keeps state in-memory only and is intended for local integration work.
