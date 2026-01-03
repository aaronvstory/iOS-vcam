# USB Streaming Quick Diagnostic Script
# Run this from the project directory to diagnose USB streaming issues
# Usage: powershell -ExecutionPolicy Bypass -File test-usb-streaming.ps1

param(
    [string]$Password = "icemat"
)

$ErrorActionPreference = "SilentlyContinue"

Write-Host ""
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host "                    USB STREAMING DIAGNOSTIC                                   " -ForegroundColor Cyan
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Check connected devices
Write-Host "[1] CONNECTED iOS DEVICES:" -ForegroundColor Yellow
$devices = & "C:\iProxy\idevice_id.exe" -l 2>&1
if ($devices) {
    $deviceCount = ($devices -split "`n" | Where-Object { $_ -match '\S' }).Count
    Write-Host "  Found $deviceCount device(s):" -ForegroundColor Gray
    $devices -split "`n" | Where-Object { $_ -match '\S' } | ForEach-Object { Write-Host "    $_" -ForegroundColor White }
    if ($deviceCount -gt 1) {
        Write-Host "  WARNING: Multiple devices connected - ensure iproxy uses -u flag!" -ForegroundColor Yellow
    }
} else {
    Write-Host "  NO DEVICES FOUND!" -ForegroundColor Red
    exit 1
}

# 2. Check processes
Write-Host ""
Write-Host "[2] RUNNING PROCESSES:" -ForegroundColor Yellow
$procs = Get-Process -Name plink,python,monibuca,iproxy -ErrorAction SilentlyContinue
if ($procs) {
    $procs | ForEach-Object { Write-Host "  $($_.Name) (PID $($_.Id))" -ForegroundColor Green }
} else {
    Write-Host "  No USB streaming processes running!" -ForegroundColor Red
}

# 3. Check command lines (critical for multi-device)
Write-Host ""
Write-Host "[3] PROCESS COMMAND LINES:" -ForegroundColor Yellow
$cimProcs = Get-CimInstance Win32_Process -Filter "Name='iproxy.exe' OR Name='plink.exe'"
if ($cimProcs) {
    foreach ($p in $cimProcs) {
        Write-Host "  $($p.Name) (PID $($p.ProcessId)):" -ForegroundColor Cyan
        Write-Host "    $($p.CommandLine)" -ForegroundColor Gray

        # Check for -u flag in iproxy
        if ($p.Name -eq "iproxy.exe" -and $p.CommandLine -notmatch '-u\s+\S+') {
            Write-Host "    WARNING: iproxy missing -u flag - may target wrong device!" -ForegroundColor Yellow
        }

        # Check for tunnel args in plink
        if ($p.Name -eq "plink.exe") {
            if ($p.CommandLine -notmatch '127\.10\.10\.10:80') {
                Write-Host "    WARNING: plink missing port 80 tunnel!" -ForegroundColor Yellow
            }
            if ($p.CommandLine -notmatch '127\.10\.10\.10:1935') {
                Write-Host "    WARNING: plink missing port 1935 tunnel!" -ForegroundColor Yellow
            }
        }
    }
} else {
    Write-Host "  No iproxy/plink processes found!" -ForegroundColor Red
}

# 4. Get SSH fingerprint
Write-Host ""
Write-Host "[4] SSH CONNECTION:" -ForegroundColor Yellow
$fpOut = (.\plink.exe -4 -ssh -batch -P 2222 -pw $Password root@127.0.0.1 exit 2>&1) | Out-String
if ($fpOut -match 'SHA256:[A-Za-z0-9+/=]+') {
    $fp = $Matches[0]
    Write-Host "  Fingerprint: $fp" -ForegroundColor Green
} else {
    Write-Host "  FAILED to connect via SSH!" -ForegroundColor Red
    Write-Host "  Output: $fpOut" -ForegroundColor Gray
    exit 1
}

# 5. Check which device we're connected to
Write-Host ""
Write-Host "[5] CONNECTED TO DEVICE:" -ForegroundColor Yellow
$device = (.\plink.exe -4 -hostkey $fp -ssh -batch -P 2222 -pw $Password root@127.0.0.1 'uname -n' 2>&1) | Out-String
$deviceName = $device.Trim()
Write-Host "  Hostname: $deviceName" -ForegroundColor Cyan

# 6. Check sshd config
Write-Host ""
Write-Host "[6] SSHD CONFIG:" -ForegroundColor Yellow
$sshdConfig = (.\plink.exe -4 -hostkey $fp -ssh -batch -P 2222 -pw $Password root@127.0.0.1 'sshd -T 2>/dev/null | grep -E "^gatewayports|^allowtcpforwarding"' 2>&1) | Out-String
if ($sshdConfig -match 'gatewayports clientspecified') {
    Write-Host "  GatewayPorts: clientspecified" -ForegroundColor Green
} else {
    Write-Host "  GatewayPorts: NOT SET - tunnels will be refused!" -ForegroundColor Red
}
if ($sshdConfig -match 'allowtcpforwarding yes') {
    Write-Host "  AllowTcpForwarding: yes" -ForegroundColor Green
} else {
    Write-Host "  AllowTcpForwarding: NOT SET!" -ForegroundColor Red
}

# 7. Check loopback alias
Write-Host ""
Write-Host "[7] LOOPBACK ALIAS:" -ForegroundColor Yellow
$loopback = (.\plink.exe -4 -hostkey $fp -ssh -batch -P 2222 -pw $Password root@127.0.0.1 'ifconfig lo0 | grep "127.10.10.10"' 2>&1) | Out-String
if ($loopback -match '127\.10\.10\.10') {
    Write-Host "  127.10.10.10 alias: CONFIGURED" -ForegroundColor Green
} else {
    Write-Host "  127.10.10.10 alias: MISSING!" -ForegroundColor Red
}

# 8. THE KEY TEST - Check iPhone listeners
Write-Host ""
Write-Host "[8] iPHONE TUNNEL LISTENERS (THE KEY TEST):" -ForegroundColor Yellow
$listeners = (.\plink.exe -4 -hostkey $fp -ssh -batch -P 2222 -pw $Password root@127.0.0.1 'netstat -an | grep "127.10.10.10.*LISTEN"' 2>&1) | Out-String

$has80 = $listeners -match '127\.10\.10\.10\.80\s'
$has1935 = $listeners -match '127\.10\.10\.10\.1935\s'

if ($has80 -and $has1935) {
    Write-Host "  Port 80:   LISTENING" -ForegroundColor Green
    Write-Host "  Port 1935: LISTENING" -ForegroundColor Green
    Write-Host ""
    Write-Host "  === TUNNEL IS WORKING! ===" -ForegroundColor Green -BackgroundColor DarkGreen
} else {
    if (-not $has80) {
        Write-Host "  Port 80:   NOT LISTENING!" -ForegroundColor Red
    }
    if (-not $has1935) {
        Write-Host "  Port 1935: NOT LISTENING!" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "  === TUNNEL NOT WORKING - iOS app will show Network Error ===" -ForegroundColor Red -BackgroundColor DarkRed
}

Write-Host ""
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host ""
