# iOS-VCAM-Launcher EXE Compiler
# Creates a self-contained EXE with SSH installation features

Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "                    iOS-VCAM LAUNCHER EXE COMPILER" -ForegroundColor Yellow
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""

# Check if ps2exe module is installed
if (!(Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "[INFO] Installing ps2exe module..." -ForegroundColor Yellow
    try {
        Install-Module -Name ps2exe -Force -Scope CurrentUser -AllowClobber
        Write-Host "[OK] ps2exe module installed successfully" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Failed to install ps2exe. Trying alternative method..." -ForegroundColor Red

        # Alternative: Download ps2exe directly
        Write-Host "[INFO] Downloading standalone ps2exe..." -ForegroundColor Yellow
        $ps2exeUrl = "https://github.com/MScholtes/PS2EXE/releases/download/v1.0.13/ps2exe.ps1"
        $ps2exePath = "$PSScriptRoot\ps2exe.ps1"

        try {
            Invoke-WebRequest -Uri $ps2exeUrl -OutFile $ps2exePath
            Write-Host "[OK] Downloaded ps2exe.ps1" -ForegroundColor Green
        } catch {
            Write-Host "[ERROR] Could not download ps2exe. Please install manually:" -ForegroundColor Red
            Write-Host "Run: Install-Module -Name ps2exe -Force" -ForegroundColor Yellow
            Read-Host "Press Enter to exit"
            exit 1
        }
    }
}

Write-Host ""
Write-Host "[INFO] Compiling iOS-VCAM-Launcher.ps1 to EXE..." -ForegroundColor Yellow

# Compile parameters
$inputFile = "$PSScriptRoot\iOS-VCAM-Launcher.ps1"
$outputFile = "$PSScriptRoot\iOS-VCAM-Launcher.exe"
$iconFile = "$PSScriptRoot\iOS-VCAM.ico"

# Check if files exist
if (!(Test-Path $inputFile)) {
    Write-Host "[ERROR] iOS-VCAM-Launcher.ps1 not found!" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Compile command
try {
    if (Test-Path "$PSScriptRoot\ps2exe.ps1") {
        # Use downloaded version
        . "$PSScriptRoot\ps2exe.ps1"
    }

    $compileParams = @{
        inputFile = $inputFile
        outputFile = $outputFile
        noConsole = $false
        title = "iOS-VCAM Ultimate Launcher"
        description = "iOS Virtual Camera Server Launcher with SSH Installation"
        company = "iOS-VCAM"
        product = "iOS-VCAM Ultimate Launcher"
        version = "3.2.0.0"
        copyright = "(c) 2024 iOS-VCAM"
        requireAdmin = $false
        noOutput = $false
        noError = $false
    }

    # Add icon if it exists
    if (Test-Path $iconFile) {
        $compileParams.iconFile = $iconFile
    }

    # Compile
    Invoke-ps2exe @compileParams -verbose

    Write-Host ""
    Write-Host "[SUCCESS] EXE created successfully!" -ForegroundColor Green
    Write-Host "Location: $outputFile" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "The EXE file:" -ForegroundColor Yellow
    Write-Host "  - Includes SSH installation features (Option 9)" -ForegroundColor White
    Write-Host "  - Works without PowerShell execution policy restrictions" -ForegroundColor White
    Write-Host "  - Is completely self-contained" -ForegroundColor White
    Write-Host "  - Can be distributed to any Windows system" -ForegroundColor White
    Write-Host ""
    Write-Host "New Features in v3.2.0:" -ForegroundColor Cyan
    Write-Host "  - Install .deb to iPhone via SSH (Option 9)" -ForegroundColor Green
    Write-Host "  - Automatic .deb file selection from modified_debs" -ForegroundColor Green
    Write-Host "  - SSH connection testing and validation" -ForegroundColor Green
    Write-Host "  - Service restart after installation" -ForegroundColor Green
    Write-Host ""

} catch {
    Write-Host "[ERROR] Compilation failed: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Alternative: Run the PowerShell script directly:" -ForegroundColor Yellow
    Write-Host "powershell -ExecutionPolicy Bypass -File iOS-VCAM-Launcher.ps1" -ForegroundColor Cyan
}

Read-Host "Press Enter to exit"