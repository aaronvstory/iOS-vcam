#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Compile iOS-VCAM-Launcher.ps1 to v4.2 EXE

.DESCRIPTION
    Version 4.2 - Monibuca distribution build.
#>

$ErrorActionPreference = 'Stop'

Write-Host "";
Write-Host "=================================================================================" -ForegroundColor Cyan
Write-Host "         iOS-VCAM Launcher v4.2 - Monibuca Distribution Build" -ForegroundColor Yellow
Write-Host "=================================================================================" -ForegroundColor Cyan
Write-Host "";

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$inputFile = Join-Path $scriptDir "iOS-VCAM-Launcher.ps1"
$outputFile = Join-Path $scriptDir "iOS-VCAM-Launcher4.2.exe"
$compatOutputFile = Join-Path $scriptDir "iOS-VCAM-Launcher.exe"
$iconFile = Join-Path $scriptDir "iOS-VCAM.ico"

if (-not (Test-Path $inputFile)) {
    Write-Host "❌ ERROR: Input file not found: $inputFile" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $iconFile)) {
    Write-Host "⚠ WARNING: Icon file not found: $iconFile" -ForegroundColor Yellow
    $iconFile = $null
}

Write-Host "📁 Input:  $inputFile" -ForegroundColor Cyan
Write-Host "📦 Output: $outputFile" -ForegroundColor Cyan
if ($iconFile) {
    Write-Host "🎨 Icon:   $iconFile" -ForegroundColor Cyan
}
Write-Host "";

$ps2exePath = Join-Path $scriptDir "ps2exe.ps1"
if (-not (Test-Path $ps2exePath)) {
    Write-Host "⬇  Downloading ps2exe..." -ForegroundColor Yellow
    try {
        $url = "https://github.com/MScholtes/PS2EXE/raw/master/Module/ps2exe.ps1"
        Invoke-WebRequest -Uri $url -OutFile $ps2exePath -UseBasicParsing
        Write-Host "✓ Downloaded ps2exe.ps1" -ForegroundColor Green
    } catch {
        Write-Host "❌ Failed to download ps2exe: $_" -ForegroundColor Red
        exit 1
    }
}

Write-Host "🔧 Loading ps2exe..." -ForegroundColor Yellow
. $ps2exePath

if (Test-Path $outputFile) {
    Write-Host "🗑  Removing old EXE..." -ForegroundColor Yellow

    # If the old EXE is running, stop it to avoid "access denied" during rebuild
    try {
        Get-Process "iOS-VCAM-Launcher4.2" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Get-Process "iOS-VCAM-Launcher" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    } catch { }

    Remove-Item $outputFile -Force
}

Write-Host "";
Write-Host "⚙  Compiling..." -ForegroundColor Yellow
Write-Host "  • noConsole = `$false (show console)" -ForegroundColor Gray
Write-Host "  • noOutput = `$false (no dialogs)" -ForegroundColor Gray
Write-Host "  • noError = `$false (show errors)" -ForegroundColor Gray
Write-Host "";

try {
    $compileParams = @{
        inputFile = $inputFile
        outputFile = $outputFile
        noConsole = $false
        noOutput = $false
        noError = $false
        title = "iOS-VCAM Launcher v4.2"
        description = "iOS Virtual Camera Server Launcher - Monibuca Distribution"
        company = "iOS-VCAM"
        product = "iOS-VCAM Monibuca Launcher"
        version = "4.2.0.0"
        copyright = "(c) 2025 iOS-VCAM"
        requireAdmin = $false
    }

    if ($iconFile) {
        $compileParams.iconFile = $iconFile
    }

    Invoke-ps2exe @compileParams

    if (-not (Test-Path $outputFile)) {
        Write-Host "❌ ERROR: Compilation completed but EXE not found!" -ForegroundColor Red
        exit 1
    }

    # Also write the legacy filename for compatibility with existing .bat + test scripts
    Copy-Item -Force $outputFile $compatOutputFile

    $fileInfo = Get-Item $outputFile
    $sizeKB = [math]::Round($fileInfo.Length / 1KB, 2)

    Write-Host "";
    Write-Host "✅ SUCCESS!" -ForegroundColor Green
    Write-Host "  File: $outputFile" -ForegroundColor White
    Write-Host "  Compat: $compatOutputFile" -ForegroundColor White
    Write-Host "  Size: $sizeKB KB" -ForegroundColor White
    Write-Host "  Version: 4.2.0.0" -ForegroundColor White
    Write-Host "  Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
    Write-Host "=================================================================================" -ForegroundColor Cyan
} catch {
    Write-Host "";
    Write-Host "❌ Compilation failed: $_" -ForegroundColor Red
    Write-Host "";
    exit 1
}
