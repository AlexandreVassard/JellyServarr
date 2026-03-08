@echo off
setlocal enabledelayedexpansion

if not defined APP_BASE_DIR set "APP_BASE_DIR=C:\jellyservarr"

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%i in ("%SCRIPT_DIR%\..") do set "REPOSITORY_DIR=%%~fi"

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [%date% %time%] This script must be run as Administrator.
    echo [%date% %time%] Right-click install.bat and select "Run as administrator".
    exit /b 1
)

echo [%date% %time%] Checking configuration files...

if not exist "%APP_BASE_DIR%\config\" (
    echo [%date% %time%] Creating Jellyfin WebDAV configuration folder...
    mkdir "%APP_BASE_DIR%\config"
) else (
    echo [%date% %time%] Jellyfin WebDAV configuration folder exists, don't need to create it.
)

set "RCLONE_CONF_FILE=%APP_BASE_DIR%\config\rclone.conf"
if not exist "%RCLONE_CONF_FILE%" (
    echo [%date% %time%] No rclone configuration file found: %RCLONE_CONF_FILE%
    echo [%date% %time%] Please create this file from the example:
    echo [%date% %time%]    copy "%REPOSITORY_DIR%\rclone.conf.example" "%RCLONE_CONF_FILE%"
    echo [%date% %time%] Then edit it to match your WebDAV provider settings.
    exit /b 1
)
echo [%date% %time%] "%RCLONE_CONF_FILE%" found.

echo [%date% %time%] Creating mount and data directories...
mkdir "%APP_BASE_DIR%\mnt\webdav" 2>nul
mkdir "%APP_BASE_DIR%\mnt\movies" 2>nul
mkdir "%APP_BASE_DIR%\mnt\series" 2>nul
mkdir "%APP_BASE_DIR%\data\traefik\letsencrypt" 2>nul
mkdir "%APP_BASE_DIR%\data\jellyfin\config" 2>nul
mkdir "%APP_BASE_DIR%\data\prowlarr\config" 2>nul
mkdir "%APP_BASE_DIR%\data\radarr\config" 2>nul
mkdir "%APP_BASE_DIR%\data\sonarr\config" 2>nul
mkdir "%APP_BASE_DIR%\data\jellyseerr\config" 2>nul
mkdir "%APP_BASE_DIR%\data\tautulli\config" 2>nul
mkdir "%APP_BASE_DIR%\data\rdtclient\db" 2>nul
mkdir "%APP_BASE_DIR%\data\rdtclient\downloads" 2>nul
mkdir "%APP_BASE_DIR%\data\rclone\cache" 2>nul

echo [%date% %time%] Building and starting Docker Compose stack...
docker compose -f "%REPOSITORY_DIR%\compose.yml" build
if %errorlevel% neq 0 exit /b %errorlevel%
docker compose -f "%REPOSITORY_DIR%\compose.yml" up -d
if %errorlevel% neq 0 exit /b %errorlevel%

echo [%date% %time%] Installation complete.
