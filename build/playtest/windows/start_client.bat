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
