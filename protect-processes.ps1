# Protect vcam and VNC processes from iOS jetsam
# Run this after starting USB streaming to prevent camera-triggered crashes

Set-Location $PSScriptRoot
$fp = 'SHA256:+NIn/a3vfRHPWJdMb6zcN0sxIlkXwajZl3270sGKk0A'
$plinkCmd = ".\plink.exe -4 -hostkey $fp -ssh -batch -P 2222 -pw icemat root@127.0.0.1"

Write-Host "=== JETSAM PROTECTION FOR VCAM/VNC ===" -ForegroundColor Cyan
Write-Host ""

# Step 1: Check if jetsamctl exists
Write-Host "[1] Checking for jetsamctl..." -ForegroundColor Yellow
$jetsamCheck = Invoke-Expression "$plinkCmd 'which jetsamctl 2>/dev/null || echo NOT_FOUND'"
if ($jetsamCheck -match "NOT_FOUND") {
    Write-Host "  jetsamctl not found! Checking alternatives..." -ForegroundColor Red
    $memoryCheck = Invoke-Expression "$plinkCmd 'which memory_pressure 2>/dev/null || echo NOT_FOUND'"
    Write-Host "  Note: May need to install jetsamctl from Cydia/Sileo" -ForegroundColor Yellow
} else {
    Write-Host "  Found: $jetsamCheck" -ForegroundColor Green
}

# Step 2: Find VNC processes
Write-Host ""
Write-Host "[2] Finding VNC processes..." -ForegroundColor Yellow
$vncProcs = Invoke-Expression "$plinkCmd '/bin/ps aux 2>/dev/null | /usr/bin/grep -i vnc | /usr/bin/grep -v grep'"
if ($vncProcs) {
    Write-Host $vncProcs -ForegroundColor Cyan
} else {
    Write-Host "  No VNC processes found" -ForegroundColor Gray
}

# Step 3: Find vcam/streaming processes
Write-Host ""
Write-Host "[3] Finding vcam/streaming processes..." -ForegroundColor Yellow
$vcamProcs = Invoke-Expression "$plinkCmd '/bin/ps aux 2>/dev/null | /usr/bin/grep -iE \"vcam|rtmp|stream\" | /usr/bin/grep -v grep'"
if ($vcamProcs) {
    Write-Host $vcamProcs -ForegroundColor Cyan
} else {
    Write-Host "  No vcam processes found" -ForegroundColor Gray
}

# Step 4: Find mediaserverd (might be relevant)
Write-Host ""
Write-Host "[4] Finding mediaserverd..." -ForegroundColor Yellow
$mediaProcs = Invoke-Expression "$plinkCmd '/bin/ps aux 2>/dev/null | /usr/bin/grep mediaserverd | /usr/bin/grep -v grep'"
if ($mediaProcs) {
    Write-Host $mediaProcs -ForegroundColor Cyan
} else {
    Write-Host "  mediaserverd not found (unusual)" -ForegroundColor Gray
}

# Step 5: List all processes to find what to protect
Write-Host ""
Write-Host "[5] All user processes (looking for vcam tweak)..." -ForegroundColor Yellow
$allProcs = Invoke-Expression "$plinkCmd '/bin/ps aux 2>/dev/null | /usr/bin/head -30'"
Write-Host $allProcs -ForegroundColor Gray

Write-Host ""
Write-Host "=== MANUAL PROTECTION COMMANDS ===" -ForegroundColor Cyan
Write-Host "If you identify PIDs to protect, run:" -ForegroundColor Yellow
Write-Host "  jetsamctl -p <PID> -m -1 -P 18" -ForegroundColor White
Write-Host ""
Write-Host "Or via SSH:" -ForegroundColor Yellow
Write-Host "  .\plink.exe -4 -hostkey $fp -ssh -P 2222 -pw icemat root@127.0.0.1 'jetsamctl -p <PID> -m -1 -P 18'" -ForegroundColor White
Write-Host ""
