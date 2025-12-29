# Quick validation test for iOS-VCAM-Launcher.exe
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "             iOS-VCAM LAUNCHER - VALIDATION TEST" -ForegroundColor Yellow
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""

$errors = @()
$warnings = @()
$success = @()

# Test 1: Check EXE exists
Write-Host "[TEST 1] Checking EXE file..." -ForegroundColor Yellow
if (Test-Path ".\iOS-VCAM-Launcher.exe") {
    $success += "✓ EXE file exists"
    $exeSize = (Get-Item ".\iOS-VCAM-Launcher.exe").Length / 1KB
    $success += "✓ EXE size: $([math]::Round($exeSize, 2)) KB"
} else {
    $errors += "✗ EXE file not found"
}
Write-Host ""

# Test 2: Check config directory structure
Write-Host "[TEST 2] Checking configuration files..." -ForegroundColor Yellow
if (Test-Path ".\config\active") {
    $success += "✓ Config directory exists (config\active)"
    $configs = Get-ChildItem ".\config\active\srs_iphone*.conf" -ErrorAction SilentlyContinue
    if ($configs.Count -gt 0) {
        $success += "✓ Found $($configs.Count) iPhone-optimized configs"
    } else {
        $errors += "✗ No iPhone configs found in config\active"
    }
} else {
    $errors += "✗ Config directory not found (config\active)"
}
Write-Host ""

# Test 3: Check SRS binary
Write-Host "[TEST 3] Checking SRS server binary..." -ForegroundColor Yellow
if (Test-Path ".\objs\srs.exe") {
    $success += "✓ SRS binary exists (objs\srs.exe)"
    $srsSize = (Get-Item ".\objs\srs.exe").Length / 1MB
    $success += "✓ SRS size: $([math]::Round($srsSize, 2)) MB"
} else {
    $errors += "✗ SRS binary not found (objs\srs.exe)"
}
Write-Host ""

# Test 4: Check Flask server
Write-Host "[TEST 4] Checking Flask authentication server..." -ForegroundColor Yellow
if (Test-Path ".\server.py") {
    $success += "✓ Flask server exists (server.py)"
} else {
    $warnings += "⚠ Flask server not found (server.py)"
}
Write-Host ""

# Test 5: Check icon file
Write-Host "[TEST 5] Checking icon file..." -ForegroundColor Yellow
if (Test-Path ".\iOS-VCAM.ico") {
    $success += "✓ Icon file exists (iOS-VCAM.ico)"
} else {
    $warnings += "⚠ Icon file not found (iOS-VCAM.ico)"
}
Write-Host ""

# Test 6: Check specific config files referenced in code
Write-Host "[TEST 6] Checking referenced configuration files..." -ForegroundColor Yellow
$requiredConfigs = @(
    "config\active\srs_iphone_ultra_smooth_dynamic.conf",
    "config\active\srs_iphone_ultra_smooth.conf",
    "config\active\srs_iphone_optimized_smooth.conf"
)

foreach ($config in $requiredConfigs) {
    if (Test-Path $config) {
        $success += "✓ Found: $config"
    } else {
        $errors += "✗ Missing: $config"
    }
}
Write-Host ""

# Display results
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "                           TEST RESULTS" -ForegroundColor White
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""

if ($success.Count -gt 0) {
    Write-Host "SUCCESS ($($success.Count)):" -ForegroundColor Green
    foreach ($item in $success) {
        Write-Host "  $item" -ForegroundColor Green
    }
    Write-Host ""
}

if ($warnings.Count -gt 0) {
    Write-Host "WARNINGS ($($warnings.Count)):" -ForegroundColor Yellow
    foreach ($item in $warnings) {
        Write-Host "  $item" -ForegroundColor Yellow
    }
    Write-Host ""
}

if ($errors.Count -gt 0) {
    Write-Host "ERRORS ($($errors.Count)):" -ForegroundColor Red
    foreach ($item in $errors) {
        Write-Host "  $item" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "RESULT: FAILED - Please fix errors before using the launcher" -ForegroundColor Red
} else {
    Write-Host "============================================================================" -ForegroundColor Green
    Write-Host "               ✓ ALL CRITICAL TESTS PASSED!" -ForegroundColor Green
    Write-Host "============================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "The iOS-VCAM Launcher is ready to use!" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "To launch:" -ForegroundColor Yellow
    Write-Host "  - Double-click: iOS-VCAM-Launcher.exe" -ForegroundColor White
    Write-Host "  - Or run: iOS-VCAM-Launcher.bat" -ForegroundColor White
}

Write-Host ""
Read-Host "Press Enter to exit"
