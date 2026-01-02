@echo off
REM Shutdown iOS-VCAM streaming components
REM Kills processes by name, not PID (PIDs are ephemeral)

echo Stopping iOS-VCAM components...

REM Kill monibuca RTMP server
taskkill /f /im monibuca.exe 2>nul && echo Stopped monibuca || echo monibuca not running

REM Kill iproxy USB forwarding
taskkill /f /im iproxy.exe 2>nul && echo Stopped iproxy || echo iproxy not running

REM Kill plink SSH tunnel
taskkill /f /im plink.exe 2>nul && echo Stopped plink || echo plink not running

REM Kill Flask auth server (python)
taskkill /f /im python.exe /fi "WINDOWTITLE eq Flask*" 2>nul

echo Done.
