@echo off
title PLUZ GitHub Synchronizer
cd /d "%~dp0"

echo ====================================================
echo        Synchronizing PLUZ Workspace to GitHub       
echo ====================================================

:: Parse Portable Credentials from .env
if exist .env (
    for /f "usebackq tokens=1,* delims==" %%A in (".env") do (
        if "%%A"=="GH_USER" set "GH_USER=%%~B"
        if "%%A"=="GH_REPO" set "GH_REPO=%%~B"
        if "%%A"=="GH_BRANCH" set "GH_BRANCH=%%~B"
        if "%%A"=="GH_TOKEN" set "GH_TOKEN=%%~B"
        if "%%A"=="PORTABLE_GIT_PATH" set "PORTABLE_GIT_PATH=%%~B"
    )
)

:: Set Default Fallbacks
if not defined GH_BRANCH set "GH_BRANCH=main"
if not defined GH_USER set "GH_USER=Z3nt13"
if not defined GH_REPO set "GH_REPO=PLUZ"

:: Portable Git Executable Fallback
if defined PORTABLE_GIT_PATH (
    if exist "%PORTABLE_GIT_PATH%" set "GIT_CMD=%PORTABLE_GIT_PATH%"
)
if not defined GIT_CMD set "GIT_CMD=git"

:: Ensure .gitignore exists so .env is never pushed
if not exist .gitignore (
    echo .env> .gitignore
    echo logs/>> .gitignore
    echo temp_*>> .gitignore
)

:: Initialize Git Repository if missing
if not exist .git (
    echo [+] Initializing Git Repository...
    "%GIT_CMD%" init
)

:: Silence GUI Credential Helper Popups
"%GIT_CMD%" config credential.helper ""
"%GIT_CMD%" config user.name "%GH_USER%"
"%GIT_CMD%" config user.email "%GH_USER%@users.noreply.github.com"
"%GIT_CMD%" branch -M %GH_BRANCH%

:: Ensure .env is untracked locally if previously indexed
"%GIT_CMD%" rm --cached .env 2>nul

:: Configure Remote URL with Personal Access Token
if defined GH_TOKEN (
    "%GIT_CMD%" remote set-url origin https://%GH_USER%:%GH_TOKEN%@github.com/%GH_USER%/%GH_REPO%.git 2>nul
    if errorlevel 1 (
        "%GIT_CMD%" remote add origin https://%GH_USER%:%GH_TOKEN%@github.com/%GH_USER%/%GH_REPO%.git
    )
)

echo [+] Staging Workspace Changes...
"%GIT_CMD%" add .

for /f "delims=" %%A in ('powershell -Command "Get-Date -Format 'dd.MM.yyyy-HH:mm'"') do set "TIMESTAMP=%%A"

echo [+] Committing Build Changes [%TIMESTAMP%]...
"%GIT_CMD%" commit -m "PLUZ Auto-Update Payload Sync [%TIMESTAMP%]" 2>nul
if errorlevel 1 (
    "%GIT_CMD%" commit --amend -m "PLUZ Auto-Update Payload Sync [%TIMESTAMP%]"
)

echo [+] Pushing to GitHub (%GH_BRANCH%)...
"%GIT_CMD%" push -u origin %GH_BRANCH% --force

echo ====================================================
echo [+] Remote Repository Successfully Synchronized!
echo ====================================================
pause