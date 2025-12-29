$proc = Start-Process -FilePath ".\iOS-VCAM-Launcher.exe" -PassThru
Start-Sleep -Seconds 3
if ($proc.HasExited) {
    Write-Host "FAILED: EXE crashed with exit code $($proc.ExitCode)" -ForegroundColor Red
    exit 1
} else {
    Write-Host "SUCCESS: EXE is running (PID $($proc.Id))" -ForegroundColor Green
    Stop-Process -Id $proc.Id -Force
    exit 0
}
