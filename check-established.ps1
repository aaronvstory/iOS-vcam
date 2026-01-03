Set-Location $PSScriptRoot
$fp = 'SHA256:+NIn/a3vfRHPWJdMb6zcN0sxIlkXwajZl3270sGKk0A'

Write-Host "=== ESTABLISHED CONNECTIONS ===" -ForegroundColor Cyan
Write-Host ""

Write-Host "[1] All 127.10.10.10 connections:" -ForegroundColor Yellow
.\plink.exe -4 -hostkey $fp -ssh -batch -P 2222 -pw icemat root@127.0.0.1 '/usr/sbin/netstat -an | /usr/bin/grep 127.10.10.10'

Write-Host ""
Write-Host "[2] VNC 5901 connections:" -ForegroundColor Yellow
.\plink.exe -4 -hostkey $fp -ssh -batch -P 2222 -pw icemat root@127.0.0.1 '/usr/sbin/netstat -an | /usr/bin/grep 5901'

Write-Host ""
Write-Host "[3] Is vcam app connected to RTMP?" -ForegroundColor Yellow
.\plink.exe -4 -hostkey $fp -ssh -batch -P 2222 -pw icemat root@127.0.0.1 '/usr/sbin/netstat -an | /usr/bin/grep ESTABLISHED | /usr/bin/grep 1935'

Write-Host ""
Write-Host "=== END ===" -ForegroundColor Cyan
