@echo off
chcp 65001 >nul 2>&1
:: iOS VCAM Launcher - perma unlock
:: This batch file starts the iOS VCAM streaming server

:: Launcher selection (use EXE unless script is newer or forced)
set "EXE_PATH=%~dp0iOS-VCAM-Launcher.exe"
set "PS1_PATH=%~dp0iOS-VCAM-Launcher.ps1"
set "USE_PS1="
set "EXE_OUTDATED=False"

if /I "%~1"=="--ps1" (
    set "USE_PS1=1"
    shift
)

if "%USE_PS1%"=="" if exist "%EXE_PATH%" if exist "%PS1_PATH%" (
    for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "(Get-Item '%EXE_PATH%').LastWriteTime -lt (Get-Item '%PS1_PATH%').LastWriteTime"`) do set "EXE_OUTDATED=%%I"
    if /I "%EXE_OUTDATED%"=="True" set "USE_PS1=1"
)

if "%USE_PS1%"=="1" (
    echo.
    echo [INFO] Launching PowerShell script.
    if /I "%EXE_OUTDATED%"=="True" (
        echo [WARN] EXE is older than PS1. Run compile-v4.1.ps1 to rebuild.
    )
    powershell -NoExit -ExecutionPolicy Bypass -File "%PS1_PATH%" %*
    if errorlevel 1 (
        echo.
        echo Launcher exited with error. Press any key to close.
        pause >nul
    )
) else (
    if exist "%EXE_PATH%" (
        "%EXE_PATH%" %*
        if errorlevel 1 (
            echo.
            echo Launcher exited with error. Press any key to close.
            pause >nul
        )
    ) else (
        powershell -NoExit -ExecutionPolicy Bypass -File "%PS1_PATH%" %*
        if errorlevel 1 (
            echo.
            echo Launcher exited with error. Press any key to close.
            pause >nul
        )
    )
)
