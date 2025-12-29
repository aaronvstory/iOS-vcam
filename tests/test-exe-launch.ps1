# Test EXE Launch - Verifies the compiled EXE actually runs
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "                  iOS-VCAM LAUNCHER EXE TEST" -ForegroundColor Yellow
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""

$exePath = ".\iOS-VCAM-Launcher.exe"

if (-not (Test-Path $exePath)) {
    Write-Host "[ERROR] EXE not found: $exePath" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "[TEST] Launching iOS-VCAM-Launcher.exe..." -ForegroundColor Yellow
Write-Host "  - The launcher will open in a new window" -ForegroundColor Gray
Write-Host "  - If you see the menu, the EXE is working correctly!" -ForegroundColor Gray
Write-Host "  - Close the launcher window to return here" -ForegroundColor Gray
Write-Host ""

# Launch the EXE and wait for it to start
try {
    $process = Start-Process -FilePath $exePath -PassThru -WindowStyle Normal

    # Wait a moment to see if it crashes immediately
    Start-Sleep -Seconds 2

    if ($process.HasExited) {
        Write-Host "[FAILED] ❌ EXE crashed immediately!" -ForegroundColor Red
        Write-Host "  Exit Code: $($process.ExitCode)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "The EXE is NOT working. There may be runtime errors." -ForegroundColor Red
    } else {
        Write-Host "[SUCCESS] ✅ EXE launched successfully!" -ForegroundColor Green
        Write-Host "  Process ID: $($process.Id)" -ForegroundColor Cyan
        Write-Host "  Status: Running" -ForegroundColor Green
        Write-Host ""
        Write-Host "The launcher window is now open. Check if you can see the menu." -ForegroundColor Yellow
        Write-Host "Close the launcher window when you're done testing." -ForegroundColor Gray
        Write-Host ""

        # Wait for the process to exit (user closes it)
        Write-Host "Waiting for you to close the launcher window..." -ForegroundColor Cyan
        $process.WaitForExit()

        Write-Host ""
        Write-Host "Launcher closed. Exit Code: $($process.ExitCode)" -ForegroundColor Gray
    }
} catch {
    Write-Host "[ERROR] Failed to launch EXE: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Read-Host "Press Enter to exit"
