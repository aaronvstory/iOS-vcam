Set-Location $PSScriptRoot
Write-Host "=== iPHONE DIAGNOSTICS ===" -ForegroundColor Cyan
Write-Host ""

# Get fingerprint
$out = .\plink.exe -4 -ssh -batch -P 2222 -pw icemat root@127.0.0.1 exit 2>&1 | Out-String
$fpMatch = [regex]::Match($out, 'SHA256:[A-Za-z0-9+/=]+')
if ($fpMatch.Success) {
    $fp = $fpMatch.Value
    Write-Host "[1] SSH Connected - Fingerprint: $fp" -ForegroundColor Green
} else {
    Write-Host "[1] SSH Connection FAILED" -ForegroundColor Red
    Write-Host $out
    exit 1
}

Write-Host ""
Write-Host "[2] LOOPBACK ALIAS (127.10.10.10):" -ForegroundColor Yellow
.\plink.exe -4 -hostkey $fp -ssh -batch -P 2222 -pw icemat root@127.0.0.1 'ifconfig lo0 | grep inet'

Write-Host ""
Write-Host "[3] LISTENERS ON 127.10.10.10:" -ForegroundColor Yellow
$listeners = .\plink.exe -4 -hostkey $fp -ssh -batch -P 2222 -pw icemat root@127.0.0.1 'netstat -an | grep "127.10.10.10.*LISTEN"'
if ($listeners) {
    $listeners
} else {
    Write-Host "  (none)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "[4] ESTABLISHED TO 127.10.10.10:" -ForegroundColor Yellow
$estab = .\plink.exe -4 -hostkey $fp -ssh -batch -P 2222 -pw icemat root@127.0.0.1 'netstat -an | grep "127.10.10.10.*ESTABLISHED"'
if ($estab) {
    $estab
} else {
    Write-Host "  (none)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "[5] VNC PROCESSES:" -ForegroundColor Yellow
.\plink.exe -4 -hostkey $fp -ssh -batch -P 2222 -pw icemat root@127.0.0.1 'ps aux | grep -i vnc | grep -v grep'

Write-Host ""
Write-Host "[6] MEDIASERVERD:" -ForegroundColor Yellow
.\plink.exe -4 -hostkey $fp -ssh -batch -P 2222 -pw icemat root@127.0.0.1 'ps aux | grep mediaserverd | grep -v grep'

Write-Host ""
Write-Host "[7] ALL LOOPBACK LISTENERS:" -ForegroundColor Yellow
.\plink.exe -4 -hostkey $fp -ssh -batch -P 2222 -pw icemat root@127.0.0.1 '/usr/sbin/netstat -an 2>/dev/null | /usr/bin/grep LISTEN | /usr/bin/head -20'

Write-Host ""
Write-Host "[8] VNC PORT 5901:" -ForegroundColor Yellow
.\plink.exe -4 -hostkey $fp -ssh -batch -P 2222 -pw icemat root@127.0.0.1 '/usr/sbin/netstat -an 2>/dev/null | /usr/bin/grep 5901'

Write-Host ""
Write-Host "[9] SSH TUNNEL PORTS (80, 1935):" -ForegroundColor Yellow
.\plink.exe -4 -hostkey $fp -ssh -batch -P 2222 -pw icemat root@127.0.0.1 '/usr/sbin/netstat -an 2>/dev/null | /usr/bin/grep -E ":80|:1935"'

Write-Host ""
Write-Host "=== END DIAGNOSTICS ===" -ForegroundColor Cyan
