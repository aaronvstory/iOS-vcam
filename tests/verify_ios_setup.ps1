# iOS Setup Verification Script
Write-Host "`n======================================================================" -ForegroundColor Cyan
Write-Host "iOS VCAM Setup Verification" -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor Cyan

$allPassed = $true

# Check 1: iOS folder exists
Write-Host "`nCheck 1: iOS folder structure" -ForegroundColor Cyan
if (Test-Path ".\ios") {
    Write-Host "  ✓ iOS folder exists" -ForegroundColor Green
} else {
    Write-Host "  ✗ iOS folder missing" -ForegroundColor Red
    $allPassed = $false
}

# Check 2: Base .deb exists
Write-Host "`nCheck 2: Base .deb file" -ForegroundColor Cyan
if (Test-Path ".\ios\iosvcam_base.deb") {
    Write-Host "  ✓ iosvcam_base.deb exists (non-branded)" -ForegroundColor Green
    $size = (Get-Item ".\ios\iosvcam_base.deb").Length
    Write-Host "    Size: $($size / 1KB) KB" -ForegroundColor Gray
} else {
    Write-Host "  ✗ iosvcam_base.deb missing" -ForegroundColor Red
    $allPassed = $false
}

# Check 3: IP changer script exists
Write-Host "`nCheck 3: IP changer script" -ForegroundColor Cyan
if (Test-Path ".\ios\ios_deb_ip_changer_final.py") {
    Write-Host "  ✓ ios_deb_ip_changer_final.py exists" -ForegroundColor Green
    
    # Check if it references the correct base file
    $content = Get-Content ".\ios\ios_deb_ip_changer_final.py" -Raw
    if ($content -match 'iosvcam_base.deb') {
        Write-Host "  ✓ Script uses non-branded base" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Script not updated for non-branded base" -ForegroundColor Red
        $allPassed = $false
    }
} else {
    Write-Host "  ✗ ios_deb_ip_changer_final.py missing" -ForegroundColor Red
    $allPassed = $false
}

# Check 4: Modified_debs directory
Write-Host "`nCheck 4: Output directory" -ForegroundColor Cyan
if (Test-Path ".\ios\modified_debs") {
    Write-Host "  ✓ modified_debs directory exists" -ForegroundColor Green
} else {
    Write-Host "  ✗ modified_debs directory missing" -ForegroundColor Red
    $allPassed = $false
}

# Check 5: Launcher configuration
Write-Host "`nCheck 5: Launcher configuration" -ForegroundColor Cyan
$launcherContent = Get-Content ".\iOS-VCAM-Launcher.ps1" -Raw
if ($launcherContent -match 'ios\\ios_deb_ip_changer_final.py') {
    Write-Host "  ✓ Launcher configured for ios subdirectory" -ForegroundColor Green
} else {
    Write-Host "  ✗ Launcher not configured correctly" -ForegroundColor Red
    $allPassed = $false
}

# Check 6: No duplicate headers
if ($launcherContent -match '# Show-SRSAsciiArt # Commented') {
    Write-Host "  ✓ Duplicate header issue fixed" -ForegroundColor Green
} else {
    Write-Host "  ⚠ May have duplicate headers" -ForegroundColor Yellow
}

# Check 7: Python availability
Write-Host "`nCheck 6: Python availability" -ForegroundColor Cyan
$pythonCheck = Get-Command python -ErrorAction SilentlyContinue
if ($pythonCheck) {
    $pythonVersion = & python --version 2>&1
    Write-Host "  ✓ Python installed: $pythonVersion" -ForegroundColor Green
} else {
    Write-Host "  ✗ Python not found" -ForegroundColor Red
    $allPassed = $false
}

# Summary
Write-Host "`n======================================================================" -ForegroundColor Cyan
if ($allPassed) {
    Write-Host "✅ All checks passed! The iOS configurator should work properly." -ForegroundColor Green
    Write-Host "`nYou can now:" -ForegroundColor Yellow
    Write-Host "  1. Run iOS-VCAM-Launcher.ps1 or .exe" -ForegroundColor White
    Write-Host "  2. Select option [6] for iOS package modification" -ForegroundColor White
    Write-Host "  3. All generated .deb files will be non-branded" -ForegroundColor White
} else {
    Write-Host "⚠️ Some checks failed. Please review the issues above." -ForegroundColor Red
}
Write-Host "======================================================================`n" -ForegroundColor Cyan