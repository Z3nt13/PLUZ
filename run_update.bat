@echo off
title PLUZ Engine Core Launcher
cd /d "%~dp0"

set "PORTABLE_MODE=false"
set "PORTABLE_PWSH_PATH=D:\portapps\PowerShell\pwsh.exe"

if exist .env (
    for /f "usebackq tokens=1,* delims==" %%A in (".env") do (
        if /i "%%A"=="PORTABLE_MODE" set "PORTABLE_MODE=%%~B"
        if /i "%%A"=="PORTABLE_PWSH_PATH" set "PORTABLE_PWSH_PATH=%%~B"
    )
)

if /i "%PORTABLE_MODE%"=="true" (
    if exist "%PORTABLE_PWSH_PATH%" (
        echo [INFO] Launching via Portable PowerShell Core...
        "%PORTABLE_PWSH_PATH%" -NoProfile -ExecutionPolicy Bypass -File .\update_manifest.ps1
        goto END
    )
)

echo [INFO] Launching via System PowerShell...
powershell -NoProfile -ExecutionPolicy Bypass -File .\update_manifest.ps1

:END
echo ----------------------------------------------------
pause