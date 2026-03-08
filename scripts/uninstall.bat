@echo off
setlocal enabledelayedexpansion

if not defined APP_BASE_DIR set "APP_BASE_DIR=C:\jellyservarr"

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%i in ("%SCRIPT_DIR%\..") do set "REPOSITORY_DIR=%%~fi"

set "CONFIG_DIR=%APP_BASE_DIR%\config"

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [%date% %time%] This script must be run as Administrator.
    echo [%date% %time%] Right-click uninstall.bat and select "Run as administrator".
    exit /b 1
)

echo [%date% %time%] Stopping Docker Compose stack...
docker compose -f "%REPOSITORY_DIR%\compose.yml" down
if %errorlevel% neq 0 echo [%date% %time%] Stack not running.

if exist "%CONFIG_DIR%\" (
    set /p "CONFIRM=Do you also want to delete the config directory at %CONFIG_DIR%? [y/N]: "
    if /i "!CONFIRM!"=="y" (
        echo [%date% %time%] Removing configuration directory...
        rmdir /s /q "%CONFIG_DIR%"
    ) else (
        echo [%date% %time%] Configuration directory preserved.
    )
) else (
    echo [%date% %time%] Configuration directory not found, nothing to remove.
)

echo.
echo [%date% %time%] Uninstallation complete.
