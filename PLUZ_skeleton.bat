@echo off
title PLUZ Environment Workspace Builder
cd /d "%~dp0"

echo ====================================================
echo       Initializing PLUZ Workspace Skeleton           
echo ====================================================

:: Directories
if not exist payloads mkdir payloads
if not exist logs mkdir logs
if not exist .github\workflows mkdir .github\workflows

:: Environment Files
if exist .env (
    echo [!] Existing .env detected! Preserving active settings.
    echo [+] Deploying .env.example template...
    (
        echo GH_USER="Z3nt13"
        echo GH_REPO="PLUZ"
        echo GH_BRANCH="main"
        echo GH_TOKEN="YOUR_GITHUB_TOKEN_HERE"
        echo PORTABLE_MODE="true"
        echo PORTABLE_GIT_PATH="D:\portapps\git\cmd\git.exe"
        echo PORTABLE_PWSH_PATH="D:\portapps\PowerShell\pwsh.exe"
    ) > .env.example
) else (
    echo [+] Creating fresh .env configuration...
    (
        echo GH_USER="Z3nt13"
        echo GH_REPO="PLUZ"
        echo GH_BRANCH="main"
        echo GH_TOKEN=""
        echo PORTABLE_MODE="true"
        echo PORTABLE_GIT_PATH="D:\portapps\git\cmd\git.exe"
        echo PORTABLE_PWSH_PATH="D:\portapps\PowerShell\pwsh.exe"
    ) > .env
)

:: Placeholders
if not exist Z3nT1s-PLUZ.json type NUL > Z3nT1s-PLUZ.json
if not exist Z3nT1s-PLUZ-Hosted.json type NUL > Z3nT1s-PLUZ-Hosted.json
if not exist update_manifest.ps1 type NUL > update_manifest.ps1
if not exist run_update.bat type NUL > run_update.bat
if not exist Push_to_GitHub.bat type NUL > Push_to_GitHub.bat
if not exist .github\workflows\scrape.yml type NUL > .github\workflows\scrape.yml

echo ====================================================
echo [+] Base workspace complete!
echo ====================================================
pause