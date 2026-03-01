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
