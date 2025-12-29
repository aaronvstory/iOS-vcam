#!/usr/bin/env pwsh
<#
.SYNOPSIS
    iOS-VCAM Launcher - Enhanced PowerShell Edition v4.2 (Monibuca)
.DESCRIPTION
    Clean, reliable launcher for iOS virtual camera streaming with Monibuca (default) or SRS.
    Features automatic IP monitoring, configuration updates, iPhone-optimized streaming settings,
    and flexible streaming server selection between Monibuca and SRS engines.
#>

# Fix console for EXE compilation - must be first!
$ErrorActionPreference = 'Continue'
$script:InitErrors = @()

try {
    # Enable ANSI escape sequences on Windows 10+
    $null = [Console]::SetOut([Console]::Out)

    # Set console mode for ANSI support
    Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;
    public class ConsoleHelper {
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr GetStdHandle(int nStdHandle);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);

        public static void EnableVirtualTerminalProcessing() {
            IntPtr handle = GetStdHandle(-11); // STD_OUTPUT_HANDLE
            uint mode;
            GetConsoleMode(handle, out mode);
            mode |= 0x0004; // ENABLE_VIRTUAL_TERMINAL_PROCESSING
            SetConsoleMode(handle, mode);
        }
    }
"@ -ErrorAction SilentlyContinue
    [ConsoleHelper]::EnableVirtualTerminalProcessing()
} catch {
    $script:InitErrors += "Console initialization warning: $($_.Exception.Message)"
}

# Set console encoding and window
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::InputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {
    $script:InitErrors += "Encoding setup warning: $($_.Exception.Message)"
}

try {
    $Host.UI.RawUI.WindowTitle = "iOS-VCAM Launcher v4.2 - Monibuca Edition"
} catch {
    # This might fail in compiled EXE, ignore
}

# Display any initialization warnings (skip in non-interactive mode and EXE)
# Disabled for EXE compatibility - initialization warnings are non-critical
# if ($script:InitErrors.Count -gt 0 -and [Environment]::UserInteractive) {
#     Write-Host "⚠️ Initialization notices:" -ForegroundColor Yellow
#     foreach ($err in $script:InitErrors) {
#         Write-Host "  • $err" -ForegroundColor Yellow
#     }
#     Write-Host ""
#     Write-Host "These warnings are typically harmless and can be ignored." -ForegroundColor Gray
#     Write-Host "Press Enter to continue..." -ForegroundColor Cyan
#     Read-Host
# }

# Safe clear for compiled EXE
try {
    Clear-Host
} catch {
    # Ignore clear errors in non-interactive environments
}
$ErrorActionPreference = 'Continue'

# System requirements check
if ($PSVersionTable.PSVersion.Major -lt 3) {
    Write-Host "❌ ERROR: PowerShell 3.0 or higher is required" -ForegroundColor Red
    Write-Host "   Current version: $($PSVersionTable.PSVersion)" -ForegroundColor Yellow
    Write-Host "   Please update PowerShell and try again." -ForegroundColor White
    Read-Host "Press Enter to exit"
    exit 1
}

# Initialize variables
$script:CurrentIP = "Unknown"
$script:WiFiAdapter = "Unknown"
$script:NetworkStatus = "Not Connected"
$script:IPList = @()
$script:SelectedConfig = $null  # Currently selected config (file name only)
$script:SelectedConfigPath = $null  # Full path to selected config

# Robust path detection for both script and compiled EXE execution
$script:SRSHome = $null

# Method 1: Try MyInvocation.MyCommand.Path (works for scripts)
if ($MyInvocation.MyCommand.Path) {
    $script:SRSHome = Split-Path -Parent $MyInvocation.MyCommand.Path
}

# Method 2: Try PSScriptRoot (works for scripts in PS 3.0+)
if (-not $script:SRSHome -and $PSScriptRoot) {
    $script:SRSHome = $PSScriptRoot
}

# Method 3: Try to find SRS installation directory (for compiled EXE)
if (-not $script:SRSHome) {
    # Check common locations
    $possiblePaths = @(
        (Get-Location).Path,
        "C:\Program Files (x86)\SRS",
        "C:\Program Files\SRS",
        "$env:ProgramFiles\SRS",
        "${env:ProgramFiles(x86)}\SRS",
        "$env:LOCALAPPDATA\SRS"
    )

    # Try to get path from command line args (for compiled EXE)
    try {
        $cmdPath = [Environment]::GetCommandLineArgs()[0]
        if ($cmdPath) {
            $possiblePaths += (Split-Path -Parent $cmdPath)
        }
    } catch { }

    foreach ($path in $possiblePaths) {
        if ($path -and (Test-Path "$path\objs\srs.exe" -ErrorAction SilentlyContinue)) {
            $script:SRSHome = $path
            break
        }
    }

    # Final fallback - current directory
    if (-not $script:SRSHome) {
        $script:SRSHome = (Get-Location).Path
    }
}

$script:ConfigDir = $script:SRSHome
$script:ConfigFile = Join-Path $script:ConfigDir "config.ini"
# Log files in SRSHome directory for easy debugging (PSScriptRoot doesn't work in EXE)
$script:LogFile = Join-Path $script:SRSHome "debug.log"
$script:CrashLog = Join-Path $script:SRSHome "crash.log"
$script:MaxLogSize = 1MB
$script:IsFirstLaunch = $false

# Verify SRS installation - silently fail for EXE, show error for PS1
if (-not (Test-Path "$script:SRSHome\objs\srs.exe")) {
    if (-not $script:IsCompiledEXE) {
        Write-Host "❌ ERROR: SRS installation not found!" -ForegroundColor Red
        Write-Host "Expected location: $script:SRSHome\objs\srs.exe" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Please ensure:" -ForegroundColor White
        Write-Host "  1. SRS is properly installed" -ForegroundColor Gray
        Write-Host "  2. The launcher is in the SRS installation directory" -ForegroundColor Gray
        Write-Host "  3. The 'objs' folder exists with srs.exe inside" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Current search path: $script:SRSHome" -ForegroundColor Yellow
        Read-Host "Press Enter to exit"
    }
    exit 1
}

# Change to SRS home directory
Set-Location $script:SRSHome

# Logging function
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    # Check log file size and rotate if needed
    if (Test-Path $script:LogFile) {
        $fileInfo = Get-Item $script:LogFile
        if ($fileInfo.Length -gt $script:MaxLogSize) {
            $archiveFile = Join-Path $script:ConfigDir "srs-launcher.old.log"
            Move-Item -Path $script:LogFile -Destination $archiveFile -Force
        }
    }

    # Write to log file
    Add-Content -Path $script:LogFile -Value $logEntry -Encoding UTF8
}

# ASCII Art display function
function Show-SRSAsciiArt {
    Write-Host ""
    Write-Host "    " -NoNewline
    Write-Host "     ██╗  ██████╗  ███████╗    ██╗   ██╗  ██████╗  █████╗  ███╗   ███╗" -ForegroundColor Cyan
    Write-Host "    " -NoNewline
    Write-Host "     ╚═╝ ██╔═══██╗ ██╔════╝    ██║   ██║ ██╔════╝ ██╔══██╗ ████╗ ████║" -ForegroundColor Cyan
    Write-Host "    " -NoNewline
    Write-Host "     ██╗ ██║   ██║ ███████╗    ██║   ██║ ██║      ███████║ ██╔████╔██║" -ForegroundColor Cyan
    Write-Host "    " -NoNewline
    Write-Host "     ██║ ██║   ██║ ╚════██║    ╚██╗ ██╔╝ ██║      ██╔══██║ ██║╚██╔╝██║" -ForegroundColor Cyan
    Write-Host "    " -NoNewline
    Write-Host "     ██║ ╚██████╔╝ ███████║     ╚████╔╝  ╚██████╗ ██║  ██║ ██║ ╚═╝ ██║" -ForegroundColor Cyan
    Write-Host "    " -NoNewline
    Write-Host "     ╚═╝  ╚═════╝  ╚══════╝      ╚═══╝    ╚═════╝ ╚═╝  ╚═╝ ╚═╝     ╚═╝" -ForegroundColor Cyan
    Write-Host ""
}

# Configuration management functions
function Read-Config {
    $config = @{
        "PreferredAdapter" = ""
        "PreferredIP" = ""
        "FirstLaunchCompleted" = "false"
        "AutoDetectNetwork" = "true"
        "LastUsedConfig" = "srs_iphone_ultra_smooth_dynamic.conf"
        "StreamingServer" = "monibuca"  # Options: "monibuca", "srs" - Default to Monibuca
        "MonibucaConfig" = "monibuca_iphone_optimized.yaml"  # Default Monibuca profile
        "SSHPassword" = "alpine"  # Default SSH password for jailbroken devices
    }

    if (Test-Path $script:ConfigFile) {
        $lines = Get-Content $script:ConfigFile
        foreach ($line in $lines) {
            if ($line -match "^(.+?)=(.+)$") {
                $config[$matches[1]] = $matches[2]
            }
        }
    } else {
        $script:IsFirstLaunch = $true
    }

    return $config
}

function Write-Config($config) {
    $content = @()
    foreach ($key in $config.Keys) {
        $content += "$key=$($config[$key])"
    }

    $content | Out-File -FilePath $script:ConfigFile -Encoding UTF8
}

function Show-NetworkAdapterSelection {
    try { Clear-Host } catch { }
    Show-SRSAsciiArt
    Write-Host ""
    Write-Host "    " -NoNewline
    Write-Host "╔═══════════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "    " -NoNewline
    Write-Host "║                           🌐 NETWORK ADAPTER SELECTION                                ║" -BackgroundColor DarkYellow -ForegroundColor Black
    Write-Host "    " -NoNewline
    Write-Host "╚═══════════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  🔍 Scanning available network adapters..." -ForegroundColor Cyan
    Write-Host ""

    # Get all network adapters using our robust detection
    $adapters = @()

    # Method 1: Try WMI first (most reliable on Windows)
    try {
        Write-Log "Attempting WMI network adapter detection"
        $wmiAdapters = Get-WmiObject -Class Win32_NetworkAdapter -Filter "NetEnabled='True'" -ErrorAction Stop
        $wmiConfig = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled='True'" -ErrorAction Stop

        foreach ($adapter in $wmiAdapters) {
            $config = $wmiConfig | Where-Object { $_.Index -eq $adapter.Index }
            if ($config -and $config.IPAddress) {
                $ipv4 = $config.IPAddress | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
                if ($ipv4 -and $ipv4 -notlike "169.254.*" -and $ipv4 -ne "127.0.0.1") {
                    $isWireless = ($adapter.Name -match "Wi-Fi|Wireless|802\.11|WLAN") -or
                                  ($adapter.Description -match "Wi-Fi|Wireless|802\.11|WLAN")

                    $adapters += @{
                        Name = $adapter.Name
                        Description = $adapter.Description
                        IP = $ipv4
                        Status = "Up"
                        IsWireless = $isWireless
                        Index = $adapters.Count + 1
                        Method = "WMI"
                    }
                    Write-Log "Found adapter via WMI: $($adapter.Name) - $ipv4"
                }
            }
        }
    } catch {
        Write-Log "WMI detection failed: $_" "WARN"
        Write-Host "  [WARNING] Primary detection method failed, using fallback..." -ForegroundColor Yellow
    }

    # Method 2: Parse ipconfig as fallback
    if ($adapters.Count -eq 0) {
        Write-Log "Using ipconfig parsing as fallback"
        $ipconfigOutput = ipconfig /all
        $currentAdapter = $null
        $currentIP = $null
        $currentDesc = ""

        foreach ($line in $ipconfigOutput -split "`n") {
            if ($line -match "^[A-Za-z].*adapter (.+):") {
                if ($currentAdapter -and $currentIP) {
                    $isWireless = $currentAdapter -match "Wi-Fi|Wireless|802\.11|WLAN"
                    $adapters += @{
                        Name = $currentAdapter
                        Description = $currentDesc
                        IP = $currentIP
                        Status = "Up"
                        IsWireless = $isWireless
                        Index = $adapters.Count + 1
                        Method = "ipconfig"
                    }
                }
                $currentAdapter = $matches[1].Trim()
                $currentIP = $null
                $currentDesc = $currentAdapter
            }
            elseif ($line -match "Description.*:\s*(.+)") {
                $currentDesc = $matches[1].Trim()
            }
            elseif ($line -match "IPv4 Address.*:\s*(\d+\.\d+\.\d+\.\d+)") {
                if ($matches[1] -notlike "169.254.*" -and $matches[1] -ne "127.0.0.1") {
                    $currentIP = $matches[1]
                }
            }
        }

        # Save last adapter if exists
        if ($currentAdapter -and $currentIP) {
            $isWireless = $currentAdapter -match "Wi-Fi|Wireless|802\.11|WLAN"
            $adapters += @{
                Name = $currentAdapter
                Description = $currentDesc
                IP = $currentIP
                Status = "Up"
                IsWireless = $isWireless
                Index = $adapters.Count + 1
                Method = "ipconfig"
            }
        }
    }

    if ($adapters.Count -eq 0) {
        Write-Host "  ❌ No network adapters with valid IP addresses found!" -ForegroundColor Red
        Write-Host "  💡 Please check your network connections and try again." -ForegroundColor Yellow
        Read-Host "Press Enter to continue"
        return $null
    }

    Write-Host "  📡 Available Network Adapters:" -ForegroundColor Green
    Write-Host ""

    foreach ($adapter in $adapters) {
        $typeIcon = if ($adapter.IsWireless) { "📶" } else { "🔌" }
        $statusColor = if ($adapter.Status -eq "Up") { "White" } else { "Gray" }
        $statusIcon = if ($adapter.Status -eq "Up") { "🟢" } else { "🔴" }

        Write-Host "  [$($adapter.Index)] $typeIcon $($adapter.Name) $statusIcon" -ForegroundColor $statusColor
        Write-Host "      📝 $($adapter.Description)" -ForegroundColor Gray
        Write-Host "      🌐 IP Address: $($adapter.IP)" -ForegroundColor Cyan
        Write-Host "      🔧 Detection: $($adapter.Method)" -ForegroundColor DarkGray
        Write-Host ""
    }

    Write-Host "  [R] 🔄 Refresh adapter list" -ForegroundColor White
    Write-Host "  [Q] ❌ Skip and use auto-detection" -ForegroundColor White
    Write-Host ""
    Write-Host "    " -NoNewline
    Write-Host "╚═══════════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor DarkGray
    Write-Host ""

    do {
        $choice = Read-Host "Select your preferred adapter [1-$($adapters.Count), R, Q]"

        if ($choice -eq "R" -or $choice -eq "r") {
            return Show-NetworkAdapterSelection  # Recursive call to refresh
        } elseif ($choice -eq "Q" -or $choice -eq "q") {
            return $null
        } elseif ($choice -match "^\d+$" -and [int]$choice -ge 1 -and [int]$choice -le $adapters.Count) {
            $selectedAdapter = $adapters[[int]$choice - 1]

            Write-Host ""
            Write-Host "  ✅ Selected: $($selectedAdapter.Name) ($($selectedAdapter.IP))" -ForegroundColor Green
            Start-Sleep -Seconds 1
            return $selectedAdapter
        } else {
            Write-Host "  ❌ Invalid choice. Please try again." -ForegroundColor Red
        }
    } while ($true)
}

function Get-NetworkInfo {
    $config = Read-Config

    # Use preferred adapter if configured
    if ($config.PreferredAdapter -ne "" -and $config.AutoDetectNetwork -eq "false") {
        Write-Host "[CONFIG] Using preferred adapter: $($config.PreferredAdapter)" -ForegroundColor Green
        $script:WiFiAdapter = $config.PreferredAdapter
        $script:CurrentIP = $config.PreferredIP
        $script:NetworkStatus = "Connected (Configured)"
        $script:IPList = @($script:CurrentIP)

        # Verify the adapter still exists and has this IP
        try {
            $verifyIP = $false

            # Try WMI verification
            try {
                $wmiConfig = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled='True'" -ErrorAction Stop
                foreach ($cfg in $wmiConfig) {
                    if ($cfg.IPAddress -contains $config.PreferredIP) {
                        $verifyIP = $true
                        break
                    }
                }
            } catch {
                # WMI failed, try ipconfig
                $ipconfigOutput = ipconfig | Select-String "IPv4 Address"
                foreach ($line in $ipconfigOutput) {
                    if ($line -match $config.PreferredIP) {
                        $verifyIP = $true
                        break
                    }
                }
            }

            if ($verifyIP) {
                Write-Host "[SUCCESS] Verified configured adapter IP: $($script:CurrentIP)" -ForegroundColor Green
                return
            } else {
                Write-Host "[WARNING] Configured IP no longer valid, re-detecting..." -ForegroundColor Yellow
                Start-Sleep -Seconds 2  # Give time to read the warning
            }
        } catch {
            Write-Host "[WARNING] Could not verify configured adapter, re-detecting..." -ForegroundColor Yellow
            Start-Sleep -Seconds 2  # Give time to read the warning
        }
    }

    Write-Host "[DETECTION] Scanning network adapters..." -ForegroundColor Cyan
    Write-Log "Starting network detection"

    # Store previous IP for comparison
    $previousIP = $script:CurrentIP

    # Method 1: Try WMI first (most reliable)
    try {
        $wmiAdapters = Get-WmiObject -Class Win32_NetworkAdapter -Filter "NetEnabled='True'" -ErrorAction Stop
        $wmiConfig = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled='True'" -ErrorAction Stop

        foreach ($adapter in $wmiAdapters) {
            $config = $wmiConfig | Where-Object { $_.Index -eq $adapter.Index }
            if ($config -and $config.IPAddress) {
                $ipv4 = $config.IPAddress | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1

                # Skip loopback and APIPA addresses
                if ($ipv4 -and $ipv4 -notlike "127.*" -and $ipv4 -notlike "169.254.*") {
                    # Prioritize WiFi adapters
                    $isWireless = ($adapter.Name -match "Wi-Fi|Wireless|802\.11|WLAN") -or
                                  ($adapter.Description -match "Wi-Fi|Wireless|802\.11|WLAN")

                    # Prioritize 192.168.50.x network
                    if ($ipv4 -match "^192\.168\.50\.") {
                        $script:CurrentIP = $ipv4
                        $script:WiFiAdapter = $adapter.Name
                        $script:NetworkStatus = "Main WiFi Network (192.168.50.x)"
                        $script:IPList = @($script:CurrentIP)
                        Write-Host "[SUCCESS] Found priority WiFi network: $($script:CurrentIP)" -ForegroundColor Green
                        Write-Log "Found priority network: $ipv4 on $($adapter.Name)"
                        break
                    }
                    # Use WiFi adapter if available
                    elseif ($isWireless -and $script:CurrentIP -eq "Unknown") {
                        $script:CurrentIP = $ipv4
                        $script:WiFiAdapter = $adapter.Name
                        $script:NetworkStatus = "Wi-Fi Connected ($($adapter.Name))"
                        $script:IPList = @($script:CurrentIP)
                        Write-Host "[SUCCESS] Found Wi-Fi adapter: $($adapter.Name) with IP: $($script:CurrentIP)" -ForegroundColor Green
                        Write-Log "Found WiFi adapter: $ipv4 on $($adapter.Name)"
                    }
                    # Use any other adapter as fallback
                    elseif ($script:CurrentIP -eq "Unknown") {
                        $script:CurrentIP = $ipv4
                        $script:WiFiAdapter = $adapter.Name
                        $script:NetworkStatus = "Connected ($($adapter.Name))"
                        $script:IPList = @($script:CurrentIP)
                        Write-Host "[INFO] Using network adapter: $($adapter.Name) with IP: $($script:CurrentIP)" -ForegroundColor Yellow
                        Write-Log "Using adapter: $ipv4 on $($adapter.Name)"
                    }
                }
            }
        }
    } catch {
        Write-Host "[WARNING] WMI detection failed, using fallback" -ForegroundColor Yellow
        Write-Log "WMI detection failed: $_" "WARN"
    }

    # Method 2: Parse ipconfig as fallback
    if ($script:CurrentIP -eq "Unknown") {
        Write-Host "[FALLBACK] Using ipconfig parsing..." -ForegroundColor Yellow
        Write-Log "Using ipconfig fallback"

        $ipconfigOutput = ipconfig | Select-String "IPv4 Address"
        $foundIPs = @()

        foreach ($line in $ipconfigOutput) {
            if ($line -match "192\.168\.(\d+)\.(\d+)") {
                $foundIP = $matches[0]
                # Skip virtual/secondary adapters
                if ($foundIP -notmatch "^192\.168\.(65|176|56|120|86|255)\." ) {
                    $foundIPs += $foundIP
                }
            }
        }

        # Priority 1: Look for 192.168.50.x first
        $priority1 = $foundIPs | Where-Object { $_ -match "^192\.168\.50\." }
        if ($priority1) {
            $script:CurrentIP = $priority1[0]
            $script:NetworkStatus = "Main WiFi (ipconfig)"
            $script:WiFiAdapter = "Wi-Fi Adapter"
            Write-Host "[SUCCESS] Found main WiFi via ipconfig: $($script:CurrentIP)" -ForegroundColor Green
            Write-Log "Found main WiFi via ipconfig: $($script:CurrentIP)"
        }
        # Priority 2: Use first available filtered IP
        elseif ($foundIPs.Count -gt 0) {
            $script:CurrentIP = $foundIPs[0]
            $script:NetworkStatus = "Alternative network (ipconfig)"
            $script:WiFiAdapter = "Network Adapter"
            Write-Host "[INFO] Using alternative network via ipconfig: $($script:CurrentIP)" -ForegroundColor Yellow
            Write-Log "Using alternative network via ipconfig: $($script:CurrentIP)"
        }

        if ($script:CurrentIP -ne "Unknown") {
            $script:IPList = @($script:CurrentIP)
        }
    }

    Write-Host "[INFO] Network detection completed" -ForegroundColor Green
    Write-Host "  Current IP: $script:CurrentIP" -ForegroundColor White
    Write-Host "  Adapter: $script:WiFiAdapter" -ForegroundColor White
    Write-Host "  Status: $script:NetworkStatus" -ForegroundColor White
    Write-Log "Detection complete - IP: $script:CurrentIP, Adapter: $script:WiFiAdapter"

    # Check for IP changes and auto-update config if needed
    if ($previousIP -ne "Unknown" -and $previousIP -ne $script:CurrentIP -and $script:CurrentIP -ne "Unknown") {
        Write-Host ""
        Write-Host "🔄 [IP CHANGE DETECTED]" -ForegroundColor Yellow
        Write-Host "  Previous IP: $previousIP" -ForegroundColor Yellow
        Write-Host "  New IP: $script:CurrentIP" -ForegroundColor Yellow
        Write-Host "  📝 Auto-updating SRS configuration..." -ForegroundColor Cyan

        if (Update-SRSConfigForNewIP -OldIP $previousIP -NewIP $script:CurrentIP) {
            Write-Host "  ✅ Configuration updated successfully!" -ForegroundColor Green
            Write-Host "  📱 New RTMP URL: rtmp://$script:CurrentIP`:1935/live/srs" -ForegroundColor Green
        } else {
            Write-Host "  ❌ Configuration update failed - manual update may be needed" -ForegroundColor Red
        }
        Write-Host ""
    }
}

function Update-SRSConfigForNewIP {
    param(
        [string]$OldIP,
        [string]$NewIP
    )

    try {
        # Update the ultimate auto config if it exists
        $autoConfigPath = Join-Path $script:SRSHome "config\active\srs_ultimate_auto.conf"
        if (Test-Path $autoConfigPath) {
            $content = Get-Content $autoConfigPath -Raw
            $content = $content -replace [regex]::Escape($OldIP), $NewIP
            $content | Set-Content $autoConfigPath -Encoding UTF8
            Write-Host "    Updated: $autoConfigPath" -ForegroundColor Cyan
        }

        # Update any other config files that might contain the old IP
        $configPath = Join-Path $script:SRSHome "config\active"
        $configFiles = Get-ChildItem (Join-Path $configPath "*.conf") -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*iphone*" -or $_.Name -like "*ultimate*" }
        foreach ($configFile in $configFiles) {
            $content = Get-Content $configFile.FullName -Raw -ErrorAction SilentlyContinue
            if ($content -and $content.Contains($OldIP)) {
                $content = $content -replace [regex]::Escape($OldIP), $NewIP
                $content | Set-Content $configFile.FullName -Encoding UTF8
                Write-Host "    Updated: $($configFile.Name)" -ForegroundColor Cyan
            }
        }

        return $true
    } catch {
        Write-Host "    Error updating configs: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Show-MainMenu {
    try { Clear-Host } catch { }
    Show-SRSAsciiArt
    Write-Host ""
    Write-Host "    " -NoNewline
    Write-Host "iOS VCAM - perma unlock" -ForegroundColor Yellow
    Write-Host "    " -NoNewline
    Write-Host "═══════════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    " -NoNewline
    Write-Host "╔═══════════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "    " -NoNewline
    Write-Host "║" -NoNewline -ForegroundColor Cyan
    $systemStatusLabel = "                                 📊 SYSTEM STATUS                                      "
    Write-Host $systemStatusLabel -NoNewline -BackgroundColor DarkCyan -ForegroundColor White
    Write-Host "║" -ForegroundColor Cyan
    Write-Host "    " -NoNewline
    Write-Host "╚═══════════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

    Write-Host ""
    Write-Host "  🌐 Wi-Fi IP Address: $script:CurrentIP" -ForegroundColor White
    Write-Host "  📡 Network Adapter: $script:WiFiAdapter" -ForegroundColor White
    Write-Host "  🔗 Connection Status: $script:NetworkStatus" -ForegroundColor White
    Write-Host "  📁 SRS Directory: $script:SRSHome" -ForegroundColor White
    Write-Host "  📱 RTMP URL: rtmp://$script:CurrentIP`:1935/live/srs" -ForegroundColor Green

    # Read config to determine which engine is active
    $config = Read-Config
    $isMonibuca = ($config.StreamingServer -ne "srs")
    $monibucaProfile = $config.MonibucaConfig
    if ([string]::IsNullOrWhiteSpace($monibucaProfile)) {
        $monibucaProfile = "monibuca_iphone_optimized.yaml"
    }

    # Display currently selected config/profile
    Write-Host ""
    if ($isMonibuca) {
        $profileDisplayName = $monibucaProfile -replace "\.ya?ml$", ""
        Write-Host "  ⚙️  Active Profile: " -NoNewline -ForegroundColor White
        Write-Host "$profileDisplayName" -ForegroundColor Magenta
    } elseif ($script:SelectedConfig) {
        $configDisplayName = $script:SelectedConfig -replace "\.conf$", ""
        Write-Host "  ⚙️  Active Config: " -NoNewline -ForegroundColor White
        Write-Host "$configDisplayName" -ForegroundColor Magenta
    } else {
        Write-Host "  ⚙️  Active Config: " -NoNewline -ForegroundColor White
        Write-Host "srs_iphone_ultra_smooth_dynamic (default)" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host ""
    Write-Host "    " -NoNewline
    Write-Host "─────────────────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
    Write-Host "    💡 Copy this RTMP URL to your iPhone app:" -ForegroundColor Yellow
    Write-Host "    " -NoNewline
    Write-Host "    rtmp://$script:CurrentIP`:1935/live/srs" -ForegroundColor Cyan
    Write-Host "    " -NoNewline
    Write-Host "─────────────────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    " -NoNewline
    Write-Host "╔═══════════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "    " -NoNewline
    Write-Host "║" -NoNewline -ForegroundColor Green
    $launchOptionsLabel = "                                🎮 LAUNCH OPTIONS                                      "
    Write-Host $launchOptionsLabel -NoNewline -BackgroundColor DarkGreen -ForegroundColor Black
    Write-Host "║" -ForegroundColor Green
    Write-Host "    " -NoNewline
    Write-Host "╚═══════════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""

    if ($isMonibuca) {
        Write-Host "  [A] 🚀 MONIBUCA STREAMING SERVER (Default)" -ForegroundColor Magenta
        Write-Host "      • Modern, low-latency media server" -ForegroundColor Gray
        Write-Host "      • Optimized for iPhone WiFi streaming" -ForegroundColor Gray
        Write-Host "      • Uses config: $monibucaProfile" -ForegroundColor Gray
    } else {
        Write-Host "  [A] 🚀 SRS STREAMING SERVER (Active)" -ForegroundColor Cyan
        if ($script:SelectedConfig) {
            $configDisplayName = $script:SelectedConfig -replace "\.conf$", ""
            Write-Host "      • Uses config: $configDisplayName" -ForegroundColor Magenta
        } else {
            Write-Host "      • Uses default: srs_iphone_ultra_smooth_dynamic" -ForegroundColor Gray
        }
    }
    Write-Host "      • Launches Flask auth + streaming server" -ForegroundColor Gray
    Write-Host "      • Streaming runs in new window with live logs" -ForegroundColor Gray
    Write-Host ""

    if ($isMonibuca) {
        Write-Host "  [B] 📺 SRS STREAMING SERVER (Legacy/Fallback)" -ForegroundColor Cyan
        Write-Host "      • Original SRS-based streaming" -ForegroundColor Gray
        Write-Host "      • Use if Monibuca has issues" -ForegroundColor Gray
    } else {
        Write-Host "  [B] 📺 SRS DIRECT (Bypass Dispatcher)" -ForegroundColor DarkCyan
        Write-Host "      • Directly launches SRS (same as [A] when SRS is active)" -ForegroundColor Gray
        Write-Host "      • Tip: Use [A] for normal streaming" -ForegroundColor DarkGray
    }
    Write-Host ""

    Write-Host "  [1] 🔐 FLASK AUTHENTICATION SERVER (Standalone)" -ForegroundColor White
    Write-Host "      • Handles iOS app authentication/validation" -ForegroundColor Gray
    Write-Host "      • Auto-installs Flask if needed" -ForegroundColor Gray
    Write-Host "      • Uses detected IP: $script:CurrentIP" -ForegroundColor Gray
    Write-Host ""
    if ($isMonibuca) {
        Write-Host "  [3] ⚙️  SELECT/CHANGE MONIBUCA PROFILE" -ForegroundColor White
        Write-Host "      • Choose Monibuca profile to use with Option [A]" -ForegroundColor Gray
    } else {
        Write-Host "  [3] ⚙️  SELECT/CHANGE SRS CONFIG (iPhone Optimized)" -ForegroundColor White
        Write-Host "      • Choose SRS config to use with Option [A]" -ForegroundColor Gray
        Write-Host "      • View config properties & compare settings" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "    " -NoNewline
    Write-Host "╔═══════════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "    " -NoNewline
    Write-Host "║                                🔧 SYSTEM TOOLS                                        ║" -ForegroundColor Magenta
    Write-Host "    " -NoNewline
    Write-Host "╚═══════════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  [4] 🔍 SYSTEM DIAGNOSTICS" -ForegroundColor White
    Write-Host "  [5] 🧹 PORT CLEANUP" -ForegroundColor White
    Write-Host "  [6] 🔄 REFRESH NETWORK DETECTION" -ForegroundColor White
    Write-Host "  [7] 📋 COPY RTMP URL TO CLIPBOARD" -ForegroundColor White
    Write-Host "  [8] 📱 CREATE iOS .DEB WITH CUSTOM IP" -ForegroundColor White
    Write-Host "  [9] 🧪 USB SETUP VALIDATION" -ForegroundColor White
    Write-Host ""
    Write-Host "  [U] 🔌 USB STREAMING (SSH Tunnel)" -ForegroundColor Magenta
    Write-Host "      • Streams over USB without WiFi" -ForegroundColor Gray
    Write-Host "      • Requires OpenSSH on iPhone" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  [C] ⚙️  CONFIGURATION SETTINGS" -ForegroundColor White
    Write-Host "  [Q] 🚪 QUIT" -ForegroundColor White
    Write-Host ""
    Write-Host "    " -NoNewline
    Write-Host "╚═══════════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor DarkGray
    Write-Host ""
}

function Start-CombinedFlaskAndSRS {
    # Check which streaming server to use
    $config = Read-Config

    if ($config.StreamingServer -eq "srs") {
        # Use SRS (legacy mode)
        Start-CombinedFlaskAndSRS-SRS
        return
    }

    # Default: Use Monibuca (new default)
    Start-CombinedFlaskAndMonibuca
}

# SRS Version (Legacy) - Renamed from original Start-CombinedFlaskAndSRS
function Start-CombinedFlaskAndSRS-SRS {
    try { Clear-Host } catch { }
    Write-Host ""
    Write-Host "    =====================================================================================" -ForegroundColor Cyan
    Write-Host "                      🚀 COMBINED FLASK + SRS STREAMING SOLUTION (Legacy)             " -ForegroundColor White
    Write-Host "    =====================================================================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "[INFO] Starting SRS streaming solution (legacy mode)..." -ForegroundColor Green
    Write-Host ""

    # Check if Python is installed for Flask
    Write-Host "`[STEP 1/5] 🐍 Checking Python installation..." -ForegroundColor Yellow
    $pythonVersion = $null
    try {
        $pythonVersion = & python --version 2>&1
        if ($pythonVersion -match "Python (\d+\.\d+)") {
            Write-Host "  ✅ Python is installed: $pythonVersion" -ForegroundColor Green
        }
    } catch { }

    if (-not $pythonVersion) {
        Write-Host "  ❌ Python is not installed or not in PATH!" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Please install Python from: https://www.python.org/downloads/" -ForegroundColor Yellow
        Write-Host "  Make sure to check 'Add Python to PATH' during installation." -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to return to menu..."""
        return
    }

    # Check Flask installation
    Write-Host "`[STEP 2/5`] 📦 Checking Flask installation..." -ForegroundColor Yellow
    $flaskInstalled = $false
    try {
        & python -c "import flask" 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $flaskInstalled = $true
            Write-Host "  ✅ Flask is installed" -ForegroundColor Green
        }
    } catch { }

    if (-not $flaskInstalled) {
        Write-Host "  📦 Flask not found. Installing Flask..." -ForegroundColor Yellow
        & python -m pip install flask 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✅ Flask installed successfully!" -ForegroundColor Green
        } else {
            Write-Host "  ❌ Failed to install Flask. Please install manually." -ForegroundColor Red
            Read-Host "Press Enter to return to menu..."""
            return
        }
    }

    # Clean up ports
    Write-Host "`[STEP 3/5] 🧹 Cleaning up conflicting processes..." -ForegroundColor Yellow
    Clear-SRSPorts

    # Start SRS in new window
    Write-Host "`[STEP 4/5] 🚀 Launching SRS server in new window..." -ForegroundColor Yellow

    # LOG: Write config check to file for debugging
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMsg = @"
[$timestamp] START-COMBINED-FLASK-AND-SRS - Config Check
  - SelectedConfig = "$script:SelectedConfig"
  - SelectedConfigPath = "$script:SelectedConfigPath"
  - Path exists = $(if ($script:SelectedConfigPath) { Test-Path $script:SelectedConfigPath } else { 'N/A' })
"@
    Add-Content -Path $script:LogFile -Value $logMsg -Force

    Write-Host ""
    Write-Host "  [DEBUG] Config check logged to: $script:LogFile" -ForegroundColor Yellow
    Write-Host ""

    # Get config path - use selected config if set, otherwise use default
    if ($script:SelectedConfig -and $script:SelectedConfigPath) {
        # Verify the path exists
        if (Test-Path $script:SelectedConfigPath) {
            $configPath = $script:SelectedConfigPath
            $configName = $script:SelectedConfig -replace "\.conf$", ""
            Write-Host "  📄 Using selected config: $configName" -ForegroundColor Cyan
        } else {
            # Path stored but doesn't exist - try to rebuild it
            $rebuildPath = Join-Path $script:SRSHome "config\active\$($script:SelectedConfig)"
            if (Test-Path $rebuildPath) {
                $configPath = $rebuildPath
                $script:SelectedConfigPath = $rebuildPath
                $configName = $script:SelectedConfig -replace "\.conf$", ""
                Write-Host "  📄 Using selected config (rebuilt path): $configName" -ForegroundColor Cyan
            } else {
                Write-Host "  ⚠️ Selected config not found, using default" -ForegroundColor Yellow
                $configPath = Join-Path $script:SRSHome "config\active\srs_iphone_ultra_smooth_dynamic.conf"
            }
        }
    } else {
        $configPath = Join-Path $script:SRSHome "config\active\srs_iphone_ultra_smooth_dynamic.conf"
        if (-not (Test-Path $configPath)) {
            $configPath = Join-Path $script:SRSHome "config\active\srs_iphone_ultra_smooth.conf"
        }
        Write-Host "  📄 Using default config: srs_iphone_ultra_smooth_dynamic" -ForegroundColor Gray
    }

    # LOG: Final config path decision
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMsg = @"
[$timestamp] FINAL CONFIG PATH DECISION
  - configPath = '$configPath'
  - configPath exists = $(Test-Path $configPath)
  - Config file basename = $(Split-Path $configPath -Leaf)
"@
    Add-Content -Path $script:LogFile -Value $logMsg -Force

    # Update IP in config
    if (Update-ConfigIP $configPath) {
        Write-Host "  ✅ IP configuration updated to: $script:CurrentIP" -ForegroundColor Green
    }

    # Create command for new window
    $srsPath = Join-Path $script:SRSHome "objs\srs.exe"
    $configFullPath = (Resolve-Path $configPath).Path

    # Launch SRS in new PowerShell window with colored output
    $psCommand = @"
`$Host.UI.RawUI.WindowTitle = 'SRS Media Server - Live Logs';
Write-Host '========================================' -ForegroundColor Cyan;
Write-Host '       SRS MEDIA SERVER - LIVE LOGS    ' -ForegroundColor White;
Write-Host '========================================' -ForegroundColor Cyan;
Write-Host '';
Write-Host 'Server Starting...' -ForegroundColor Yellow;
Write-Host 'RTMP URL: rtmp://$script:CurrentIP`:1935/live/srs' -ForegroundColor Green;
Write-Host 'Web Console: http://$script:CurrentIP`:8080/' -ForegroundColor Green;
Write-Host '========================================' -ForegroundColor Cyan;
Write-Host 'Config: $configFullPath' -ForegroundColor Gray;
Write-Host '';
& '$srsPath' -c '$configFullPath';
Write-Host '';
Write-Host 'SRS Server stopped. Press any key to close...' -ForegroundColor Yellow;
`$null = `$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
"@

    Start-Process powershell -ArgumentList "-NoExit", "-Command", $psCommand -WindowStyle Normal
    Write-Host "  ✅ SRS server launched in new window!" -ForegroundColor Green

    # Give SRS a moment to start
    Start-Sleep -Seconds 2

    # Start Flask in a new window by default
    Write-Host "`[STEP 5/5] 🔐 Starting Flask authentication server..." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    Write-Host "                     ✅ BOTH SERVERS ARE NOW RUNNING!                          " -ForegroundColor Green
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    Write-Host ""
    Write-Host "📱 Connection Details:" -ForegroundColor Cyan
    Write-Host "   RTMP URL: rtmp://$script:CurrentIP`:1935/live/srs" -ForegroundColor Yellow
    Write-Host "   Web Console: http://$script:CurrentIP`:8080/" -ForegroundColor Yellow
    Write-Host "   Flask Auth: http://$script:CurrentIP`:80/" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "📌 Flask Authentication Server Output (current window):" -ForegroundColor Green
    Write-Host "────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""

    # Check for server.py
    if (-not (Test-Path "server.py")) {
        Write-Host "❌ server.py not found!" -ForegroundColor Red
        Write-Host "Please ensure server.py is in the current directory." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Press Enter to return to menu..."
        Read-Host
        return
    }

    # Create a job for Flask server so we can control it
    $flaskJob = Start-Job -ScriptBlock {
        param($WorkingDir, $CurrentIP)
        Set-Location $WorkingDir
        $env:FLASK_HOST = $CurrentIP
        # Run python with unbuffered output to get real-time logs
        & python -u server.py 2>&1
    } -ArgumentList $script:SRSHome, $script:CurrentIP

    Write-Host "Flask server starting on port 80..." -ForegroundColor Yellow

    # Wait a moment for Flask to initialize
    Start-Sleep -Seconds 1
    Write-Host ""
    Write-Host "Press [S] to stop Flask server and return to menu" -ForegroundColor Cyan
    Write-Host "Press [Q] to quit everything" -ForegroundColor Red
    Write-Host ""
    Write-Host "Flask Server Logs:" -ForegroundColor Green
    Write-Host "──────────────────" -ForegroundColor DarkGray

    # Monitor Flask output and wait for user input
    $stopFlask = $false
    $seenLines = @{}  # Track lines we've already shown to prevent duplicates

    while (-not $stopFlask) {
        # Check if job is still running
        if ($flaskJob.State -eq 'Failed') {
            Write-Host "Flask server failed to start!" -ForegroundColor Red
            Write-Host "Error: $($flaskJob.ChildJobs[0].JobStateInfo.Reason)" -ForegroundColor Red
            break
        }

        # Check for Flask output (without -Keep to consume output)
        $output = Receive-Job -Job $flaskJob -ErrorAction SilentlyContinue
        if ($output) {
            # Process output as array to handle multiple lines properly
            if ($output -is [Array]) {
                foreach ($item in $output) {
                    $line = $item.ToString().Trim()
                    if ($line -and $line -ne "") {
                        # Only show lines we haven't seen before (check first 50 chars)
                        $lineKey = $line.Substring(0, [Math]::Min(50, $line.Length))
                        if (-not $seenLines.ContainsKey($lineKey)) {
                            Write-Host $line -ForegroundColor Gray
                            $seenLines[$lineKey] = $true
                            # Clean up old entries if too many
                            if ($seenLines.Count -gt 100) {
                                $seenLines.Clear()
                            }
                        }
                    }
                }
            } else {
                # Single line output
                $line = $output.ToString().Trim()
                if ($line -and $line -ne "") {
                    $lineKey = $line.Substring(0, [Math]::Min(50, $line.Length))
                    if (-not $seenLines.ContainsKey($lineKey)) {
                        Write-Host $line -ForegroundColor Gray
                        $seenLines[$lineKey] = $true
                    }
                }
            }
        }

        # Check for user input (non-blocking)
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'S' {
                    Write-Host ""
                    Write-Host "Stopping Flask server..." -ForegroundColor Yellow
                    Stop-Job -Job $flaskJob -ErrorAction SilentlyContinue
                    Remove-Job -Job $flaskJob -Force -ErrorAction SilentlyContinue
                    $stopFlask = $true
                    Write-Host "Flask server stopped." -ForegroundColor Green
                    Write-Host ""
                    Write-Host "Note: SRS server is still running in the other window." -ForegroundColor Cyan
                    Write-Host "You can close it manually if needed." -ForegroundColor Cyan
                    Write-Host ""
                    Read-Host "Press Enter to return to main menu"
                }
                'Q' {
                    Write-Host ""
                    Write-Host "Shutting down all servers..." -ForegroundColor Red
                    Stop-Job -Job $flaskJob -ErrorAction SilentlyContinue
                    Remove-Job -Job $flaskJob -Force -ErrorAction SilentlyContinue
                    Clear-SRSPorts
                    Write-Host "All servers stopped. Exiting..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 2
                    exit 0
                }
            }
        }

        # Small delay to prevent CPU spinning
        Start-Sleep -Milliseconds 100
    }
}

function Start-FlaskAuthServer {
    try { Clear-Host } catch { }
    Write-Host ""
    Write-Host "    =====================================================================================" -ForegroundColor Cyan
    Write-Host "                        🔐 FLASK AUTHENTICATION SERVER                                " -ForegroundColor White
    Write-Host "    =====================================================================================" -ForegroundColor Cyan
    Write-Host ""

    # Check if Python is installed
    Write-Host "`[STEP 1/4] 🐍 Checking Python installation..." -ForegroundColor Yellow
    $pythonVersion = $null
    try {
        $pythonVersion = & python --version 2>&1
        if ($pythonVersion -match "Python (\d+\.\d+)") {
            Write-Host "  ✅ Python is installed: $pythonVersion" -ForegroundColor Green
        }
    } catch { }

    if (-not $pythonVersion) {
        Write-Host "  ❌ Python is not installed or not in PATH!" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Please install Python from: https://www.python.org/downloads/" -ForegroundColor Yellow
        Write-Host "  Make sure to check 'Add Python to PATH' during installation." -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to return to menu..."""
        return
    }

    # Check if Flask is installed
    Write-Host "`[STEP 2/4] 📦 Checking Flask installation..." -ForegroundColor Yellow
    $flaskInstalled = $false
    try {
        & python -c "import flask" 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $flaskInstalled = $true
            Write-Host "  ✅ Flask is already installed" -ForegroundColor Green
        }
    } catch { }

    if (-not $flaskInstalled) {
        Write-Host "  ⚠️ Flask is not installed. Installing now..." -ForegroundColor Yellow
        Write-Host "  Running: pip install flask" -ForegroundColor Gray

        try {
            & python -m pip install --upgrade pip 2>&1 | Out-Null
            & python -m pip install flask
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  ✅ Flask installed successfully!" -ForegroundColor Green
            } else {
                Write-Host "  ❌ Failed to install Flask!" -ForegroundColor Red
                Write-Host "  Try running manually: python -m pip install flask" -ForegroundColor Yellow
                Read-Host "Press Enter to return to menu..."""
                return
            }
        } catch {
            Write-Host "  ❌ Error installing Flask: $_" -ForegroundColor Red
            Read-Host "Press Enter to return to menu..."""
            return
        }
    }

    Write-Host "`[STEP 3/4] 🌐 Configuring server with IP: $script:CurrentIP" -ForegroundColor Yellow
    Write-Host "`[STEP 4/4] 🚀 Starting Flask server..." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    -------------------------------------------------------------------------------------" -ForegroundColor Green
    Write-Host "  📱 Flask Server URL: http://$script:CurrentIP`:80" -ForegroundColor Green
    Write-Host "  📝 This handles iOS app authentication/validation" -ForegroundColor Green
    Write-Host "    -------------------------------------------------------------------------------------" -ForegroundColor Green
    Write-Host ""
    Write-Host "  ⚠️ Note: Port 80 may require Administrator privileges" -ForegroundColor Yellow
    Write-Host "  Press Ctrl+C to stop the server and return to menu" -ForegroundColor Yellow
    Write-Host ""

    # Start the Flask server with detected IP on port 80
    try {
        $env:FLASK_HOST = $script:CurrentIP
        & python "$script:SRSHome\server.py" --host $script:CurrentIP
    } catch {
        Write-Host ""
        Write-Host "  ⚠️ Server stopped or interrupted" -ForegroundColor Yellow
    } finally {
        Remove-Item Env:\FLASK_HOST -ErrorAction SilentlyContinue
    }

    Write-Host ""
    Read-Host "Press Enter to return to menu"
}

function Start-FlaskAuthServerWindow {
    param(
        [string]$HostOverride = ""
    )
    # Minimal checks (same as Start-FlaskAuthServer) then spawn new window
    $pythonVersion = $null
    try {
        $pythonVersion = & python --version 2>&1
    } catch { }

    if (-not $pythonVersion) {
        Write-Host "  ❌ Python is not installed or not in PATH!" -ForegroundColor Red
        Write-Host "     Please install Python from: https://www.python.org/downloads/" -ForegroundColor Yellow
        return $false
    }

    $flaskInstalled = $false
    try {
        & python -c "import flask" 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $flaskInstalled = $true
        }
    } catch { }

    if (-not $flaskInstalled) {
        Write-Host "  📦 Flask not found. Installing Flask..." -ForegroundColor Yellow
        & python -m pip install flask 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  ❌ Failed to install Flask. Please install manually." -ForegroundColor Red
            return $false
        }
    }

    $bindHost = $script:CurrentIP
    if (-not [string]::IsNullOrWhiteSpace($HostOverride)) {
        $bindHost = $HostOverride
    }
    $psCommand = @"
`$Host.UI.RawUI.WindowTitle = 'Flask Auth Server - Live Logs';
Set-Location "$script:SRSHome";
`$env:FLASK_HOST = "$bindHost";
Write-Host '========================================' -ForegroundColor Cyan;
Write-Host '     FLASK AUTH SERVER - LIVE LOGS     ' -ForegroundColor White;
Write-Host '========================================' -ForegroundColor Cyan;
Write-Host 'URL: http://$bindHost`:80/' -ForegroundColor Green;
Write-Host '';
python -u server.py --host $bindHost;
Write-Host '';
Write-Host 'Flask Server stopped. Press any key to close...' -ForegroundColor Yellow;
`$null = `$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
"@

    Start-Process powershell -ArgumentList "-NoExit", "-ExecutionPolicy", "Bypass", "-Command", $psCommand -WindowStyle Normal
    Write-Host "  ✅ Flask server launched in new window!" -ForegroundColor Green
    return $true
}

function Start-SRSServerWindow {
    param(
        [string]$ConfigPath,
        [string]$DisplayIP,
        [string]$WindowTitle = "SRS Media Server - Live Logs"
    )

    if (-not (Test-Path $ConfigPath)) {
        Write-Host "  ❌ SRS config not found: $ConfigPath" -ForegroundColor Red
        return $false
    }

    $srsPath = Join-Path $script:SRSHome "objs\\srs.exe"
    if (-not (Test-Path $srsPath)) {
        Write-Host "  ❌ SRS executable not found: $srsPath" -ForegroundColor Red
        return $false
    }

    $configFullPath = (Resolve-Path $ConfigPath).Path
    $rtmpDisplay = $DisplayIP
    if ([string]::IsNullOrWhiteSpace($rtmpDisplay)) {
        $rtmpDisplay = $script:CurrentIP
    }

    $psCommand = @"
`$Host.UI.RawUI.WindowTitle = '$WindowTitle';
Write-Host '========================================' -ForegroundColor Cyan;
Write-Host '       SRS MEDIA SERVER - LIVE LOGS    ' -ForegroundColor White;
Write-Host '========================================' -ForegroundColor Cyan;
Write-Host '';
Write-Host 'Server Starting...' -ForegroundColor Yellow;
Write-Host 'RTMP URL: rtmp://$rtmpDisplay`:1935/live/srs' -ForegroundColor Green;
Write-Host 'Web Console: http://$rtmpDisplay`:8080/' -ForegroundColor Green;
Write-Host '========================================' -ForegroundColor Cyan;
Write-Host 'Config: $configFullPath' -ForegroundColor Gray;
Write-Host '';
& '$srsPath' -c '$configFullPath';
Write-Host '';
Write-Host 'SRS Server stopped. Press any key to close...' -ForegroundColor Yellow;
`$null = `$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
"@

    Start-Process powershell -ArgumentList "-NoExit", "-ExecutionPolicy", "Bypass", "-Command", $psCommand -WindowStyle Normal
    Write-Host "  ✅ SRS server launched in new window!" -ForegroundColor Green
    return $true
}

# ============================================================================
# MONIBUCA STREAMING SERVER FUNCTIONS
# ============================================================================

function Start-MonibucaServerWindow {
    param(
        [string]$ConfigPath,
        [string]$DisplayIP,
        [string]$WindowTitle = "Monibuca Media Server - Live Logs"
    )

    $monibucaPath = Join-Path $script:SRSHome "objs\monibuca.exe"
    if (-not (Test-Path $monibucaPath)) {
        Write-Host "  ❌ Monibuca executable not found: $monibucaPath" -ForegroundColor Red
        return $false
    }

    if (-not (Test-Path $ConfigPath)) {
        Write-Host "  ❌ Monibuca config not found: $ConfigPath" -ForegroundColor Red
        return $false
    }

    $configFullPath = (Resolve-Path $ConfigPath).Path
    $rtmpDisplay = $DisplayIP
    if ([string]::IsNullOrWhiteSpace($rtmpDisplay)) {
        $rtmpDisplay = $script:CurrentIP
    }

    $psCommand = @"
`$Host.UI.RawUI.WindowTitle = '$WindowTitle';
Write-Host '========================================' -ForegroundColor Magenta;
Write-Host '    MONIBUCA MEDIA SERVER - LIVE LOGS  ' -ForegroundColor White;
Write-Host '========================================' -ForegroundColor Magenta;
Write-Host '';
Write-Host 'Server Starting...' -ForegroundColor Yellow;
Write-Host 'RTMP URL: rtmp://$rtmpDisplay`:1935/live/srs' -ForegroundColor Green;
Write-Host 'Web Console: http://$rtmpDisplay`:8081/' -ForegroundColor Green;
Write-Host '========================================' -ForegroundColor Magenta;
Write-Host "Config: $configFullPath" -ForegroundColor Gray;
Write-Host '';
Set-Location "$script:SRSHome";
& "$monibucaPath" -c "$configFullPath";
Write-Host '';
Write-Host 'Monibuca Server stopped. Press any key to close...' -ForegroundColor Yellow;
`$null = `$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
"@

    Start-Process powershell -ArgumentList "-NoExit", "-ExecutionPolicy", "Bypass", "-Command", $psCommand -WindowStyle Normal
    Write-Host "  ✅ Monibuca server launched in new window!" -ForegroundColor Green
    return $true
}

function Update-MonibucaConfigIP {
    param([string]$ConfigPath)

    if (-not (Test-Path $ConfigPath)) {
        Write-Host "  ⚠️ Monibuca config not found: $ConfigPath" -ForegroundColor Yellow
        return $false
    }

    try {
        $content = Get-Content $ConfigPath -Raw -Encoding UTF8

        # Support configs that use "$IP" placeholder (e.g. monibuca_iphone_balanced.yaml)
        $content = $content -replace '\$IP', $script:CurrentIP

        # SAFE IP Replacement: Only replace private IPs that are followed by a port (e.g., "192.168.1.100:8081")
        # This avoids corrupting CIDR ranges like "10.0.0.0/8" or "192.168.0.0/16"
        # Pattern: private IP + colon + port number (server address pattern)
        $ipPortPattern = '(192\.168\.\d{1,3}\.\d{1,3}|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2[0-9]|3[0-1])\.\d{1,3}\.\d{1,3})(?=:\d+)'
        $content = $content -replace $ipPortPattern, $script:CurrentIP

        # Also replace standalone IPs in quotes (e.g., "192.168.1.100" as a value)
        # Pattern: quoted IP that is NOT followed by / (to avoid CIDR in quotes)
        $quotedIpPattern = '(?<=["\x27])(192\.168\.\d{1,3}\.\d{1,3}|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2[0-9]|3[0-1])\.\d{1,3}\.\d{1,3})(?=["\x27])'
        $content = $content -replace $quotedIpPattern, $script:CurrentIP

        $content | Set-Content $ConfigPath -Encoding UTF8
        Write-Host "  ✅ Monibuca IP updated to: $script:CurrentIP" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "  ⚠️ Could not update Monibuca config IP: $_" -ForegroundColor Yellow
        return $false
    }
}

function Stop-UsbStreamingProcesses {
    <#
    .SYNOPSIS
        Stops all USB streaming related processes for a clean restart.
    .DESCRIPTION
        Kills iproxy, plink, Flask (python), and Monibuca processes
        that were started by the USB streaming function.
    #>
    param(
        [switch]$Silent
    )

    if (-not $Silent) {
        Write-Host ""
        Write-Host "  🧹 Stopping all USB streaming processes..." -ForegroundColor Yellow
    }

    $processesKilled = 0

    # Kill iproxy processes
    $iproxyProcs = Get-Process -Name "iproxy" -ErrorAction SilentlyContinue
    if ($iproxyProcs) {
        foreach ($proc in $iproxyProcs) {
            try {
                if (-not $Silent) { Write-Host "  🔥 Stopping iproxy (PID: $($proc.Id))" -ForegroundColor Red }
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                $processesKilled++
            } catch { }
        }
    }

    # Kill plink processes
    $plinkProcs = Get-Process -Name "plink" -ErrorAction SilentlyContinue
    if ($plinkProcs) {
        foreach ($proc in $plinkProcs) {
            try {
                if (-not $Silent) { Write-Host "  🔥 Stopping plink SSH tunnel (PID: $($proc.Id))" -ForegroundColor Red }
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                $processesKilled++
            } catch { }
        }
    }

    # Kill Monibuca processes
    $monibucaProcs = Get-Process -Name "monibuca" -ErrorAction SilentlyContinue
    if ($monibucaProcs) {
        foreach ($proc in $monibucaProcs) {
            try {
                if (-not $Silent) { Write-Host "  🔥 Stopping Monibuca (PID: $($proc.Id))" -ForegroundColor Red }
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                $processesKilled++
            } catch { }
        }
    }

    # Kill Flask processes on ports 80 and 5000 (Flask default)
    foreach ($port in @(80, 5000)) {
        try {
            $connections = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
            if ($connections) {
                foreach ($conn in $connections) {
                    $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
                    if ($proc -and $proc.ProcessName -match 'python|pythonw|py') {
                        try {
                            if (-not $Silent) { Write-Host "  🔥 Stopping Flask/Python on port $port (PID: $($proc.Id))" -ForegroundColor Red }
                            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                            $processesKilled++
                        } catch { }
                    }
                }
            }
        } catch { }
    }

    # Also kill any Python processes on port 1935 (RTMP)
    try {
        $connections = Get-NetTCPConnection -LocalPort 1935 -ErrorAction SilentlyContinue
        if ($connections) {
            foreach ($conn in $connections) {
                $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
                if ($proc) {
                    try {
                        if (-not $Silent) { Write-Host "  🔥 Stopping process on port 1935: $($proc.ProcessName) (PID: $($proc.Id))" -ForegroundColor Red }
                        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                        $processesKilled++
                    } catch { }
                }
            }
        }
    } catch { }

    # Wait for processes to fully terminate
    if ($processesKilled -gt 0) {
        Start-Sleep -Seconds 2
    }

    if (-not $Silent) {
        if ($processesKilled -gt 0) {
            Write-Host "  ✅ Cleanup complete - stopped $processesKilled process(es)" -ForegroundColor Green
        } else {
            Write-Host "  ✅ No USB streaming processes were running" -ForegroundColor Green
        }
        Write-Host ""
    }

    return $processesKilled
}

function Start-MonibucaViaSshUsb {
    <#
    .SYNOPSIS
        Starts complete USB streaming solution with Flask auth + Monibuca via SSH tunnels.
    .DESCRIPTION
        Launches all components needed for USB streaming:
        1. iproxy - USB port forwarding (localhost:2222 -> iPhone:22)
        2. Flask server - HTTP auth on port 80
        3. Monibuca server - RTMP streaming on port 1935
        4. SSH tunnels - Forward ports 80 and 1935 from iPhone to PC
        5. iPhone IP alias - Routes 127.10.10.10 to loopback

        iPhone app connects to rtmp://127.10.10.10:1935/live/srs which tunnels back to PC.
        HTTP auth at http://127.10.10.10/I also tunnels back to Flask on PC.
    #>
    try { Clear-Host } catch { Write-Host "Note: Could not clear console" -ForegroundColor Gray }
    Write-Host ""
    Write-Host "    =====================================================================================" -ForegroundColor Magenta
    Write-Host "                      🔌 USB STREAMING VIA SSH REVERSE TUNNEL                           " -ForegroundColor White
    Write-Host "    =====================================================================================" -ForegroundColor Magenta
    Write-Host ""

    # Sub-menu loop (avoids recursion for stack safety)
    :menuLoop while ($true) {
        # Quick device scan for menu display
        $ideviceIdPath = "C:\iProxy\idevice_id.exe"
        $quickDevices = @()
        try {
            $quickScan = & $ideviceIdPath -l 2>&1
            if ($quickScan -and $LASTEXITCODE -eq 0) {
                $quickDevices = @($quickScan -split "`r`n|`n|`r" | ForEach-Object { $_.Trim() } | Where-Object { $_ -match "^[a-fA-F0-9\-]+$" })
            }
        } catch { }
        $deviceCount = $quickDevices.Count
        $deviceStatus = if ($deviceCount -eq 0) { "❌ No device" } elseif ($deviceCount -eq 1) { "📱 1 device" } else { "📱 $deviceCount devices" }

        # Show sub-menu for USB streaming options
        Write-Host "  Options:                              $deviceStatus" -ForegroundColor Cyan
        Write-Host "     [1] Start USB Streaming (default)" -ForegroundColor White
        Write-Host "     [K] Kill All Processes & Restart Fresh" -ForegroundColor Yellow
        Write-Host "     [S] Status - Show Running Processes" -ForegroundColor Gray
        Write-Host "     [Q] Back to Main Menu" -ForegroundColor Gray
        Write-Host ""
        $usbChoice = Read-Host "     Select option (1/K/S/Q) [1]"
        if ([string]::IsNullOrWhiteSpace($usbChoice)) { $usbChoice = "1" }
        $usbChoice = $usbChoice.ToUpper().Trim()

        switch ($usbChoice) {
            "Q" {
                return
            }
            "K" {
                Write-Host ""
                Stop-UsbStreamingProcesses
                Write-Host "  🔄 Restarting USB streaming..." -ForegroundColor Cyan
                Write-Host ""
                Start-Sleep -Seconds 1
                break menuLoop  # Exit loop to start streaming
            }
            "S" {
                Write-Host ""
                Write-Host "  📊 USB Streaming Process Status:" -ForegroundColor Cyan
                Write-Host ""

                # Check iproxy
                $iproxyProcs = Get-Process -Name "iproxy" -ErrorAction SilentlyContinue
                if ($iproxyProcs) {
                    Write-Host "  ✅ iproxy: Running (PIDs: $($iproxyProcs.Id -join ', '))" -ForegroundColor Green
                } else {
                    Write-Host "  ⬚  iproxy: Not running" -ForegroundColor Gray
                }

                # Check plink
                $plinkProcs = Get-Process -Name "plink" -ErrorAction SilentlyContinue
                if ($plinkProcs) {
                    Write-Host "  ✅ plink: Running (PIDs: $($plinkProcs.Id -join ', '))" -ForegroundColor Green
                } else {
                    Write-Host "  ⬚  plink: Not running" -ForegroundColor Gray
                }

                # Check Monibuca
                $monibucaProcs = Get-Process -Name "monibuca" -ErrorAction SilentlyContinue
                if ($monibucaProcs) {
                    Write-Host "  ✅ Monibuca: Running (PIDs: $($monibucaProcs.Id -join ', '))" -ForegroundColor Green
                } else {
                    Write-Host "  ⬚  Monibuca: Not running" -ForegroundColor Gray
                }

                # Check Flask on port 80 (filter for Listen state)
                try {
                    $flask80 = Get-NetTCPConnection -LocalPort 80 -State Listen -ErrorAction SilentlyContinue
                    if ($flask80) {
                        $proc = Get-Process -Id $flask80[0].OwningProcess -ErrorAction SilentlyContinue
                        Write-Host "  ✅ Port 80: $($proc.ProcessName) (PID: $($flask80[0].OwningProcess))" -ForegroundColor Green
                    } else {
                        Write-Host "  ⬚  Port 80: Not listening" -ForegroundColor Gray
                    }
                } catch {
                    Write-Host "  ⬚  Port 80: Could not check" -ForegroundColor Gray
                }

                # Check RTMP port 1935 (filter for Listen state)
                try {
                    $rtmp = Get-NetTCPConnection -LocalPort 1935 -State Listen -ErrorAction SilentlyContinue
                    if ($rtmp) {
                        $proc = Get-Process -Id $rtmp[0].OwningProcess -ErrorAction SilentlyContinue
                        Write-Host "  ✅ Port 1935: $($proc.ProcessName) (PID: $($rtmp[0].OwningProcess))" -ForegroundColor Green
                    } else {
                        Write-Host "  ⬚  Port 1935: Not listening" -ForegroundColor Gray
                    }
                } catch {
                    Write-Host "  ⬚  Port 1935: Could not check" -ForegroundColor Gray
                }

                Write-Host ""
                Read-Host "Press Enter to continue..."
                try { Clear-Host } catch { }
                Write-Host ""
                Write-Host "    =====================================================================================" -ForegroundColor Magenta
                Write-Host "                      🔌 USB STREAMING VIA SSH REVERSE TUNNEL                           " -ForegroundColor White
                Write-Host "    =====================================================================================" -ForegroundColor Magenta
                Write-Host ""
                continue menuLoop  # Loop back to menu (no recursion!)
            }
            default {
                break menuLoop  # Default "1" - exit loop to start streaming
            }
        }
    }

    # Track verification results for conditional READY banner
    $allReady = $true

    Write-Host "[INFO] Preparing complete USB streaming solution..." -ForegroundColor Green
    Write-Host "       Flask (HTTP auth) + Monibuca (RTMP) + Dual SSH tunnels" -ForegroundColor Gray
    Write-Host ""

    # Set up combined log file
    $logDir = Join-Path $script:SRSHome "logs"
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $script:UsbLogFile = Join-Path $logDir "usb-streaming-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"

    # Helper function to write to both console and log
    function Write-Log {
        param([string]$Message, [string]$Color = "White", [switch]$NoNewline)
        $timestamp = Get-Date -Format "HH:mm:ss"
        $logMessage = "[$timestamp] $Message"
        Add-Content -Path $script:UsbLogFile -Value $logMessage -ErrorAction SilentlyContinue
        if ($NoNewline) {
            Write-Host $Message -ForegroundColor $Color -NoNewline
        } else {
            Write-Host $Message -ForegroundColor $Color
        }
    }

    Write-Log "USB Streaming session started"
    Write-Log "Log file: $script:UsbLogFile"
    Write-Host "  📝 Log: $script:UsbLogFile" -ForegroundColor Gray
    Write-Host ""

    # Check if running as admin (needed for port 80)
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "  ⚠️  WARNING: Not running as Administrator!" -ForegroundColor Yellow
        Write-Host "     Port 80 (Flask HTTP auth) requires admin privileges." -ForegroundColor Gray
        Write-Host ""
        Write-Host "  Options:" -ForegroundColor Cyan
        Write-Host "     [1] Restart launcher as Administrator (recommended)" -ForegroundColor White
        Write-Host "     [2] Continue anyway (Flask may fail)" -ForegroundColor Gray
        Write-Host ""
        $adminChoice = Read-Host "     Select option (1-2)"
        if ($adminChoice -eq "1") {
            Write-Host ""
            Write-Host "  🔄 Restarting as Administrator..." -ForegroundColor Yellow
            Start-Process powershell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
            return
        }
        Write-Host ""
    }

    # ============================================================================
    # STEP 1: Check Prerequisites
    # ============================================================================
    Write-Host "[STEP 1/9] 🔍 Checking prerequisites..." -ForegroundColor Yellow

    # Check for iproxy.exe
    $iproxyPath = "C:\iProxy\iproxy.exe"
    if (-not (Test-Path $iproxyPath)) {
        $iproxyPath = Resolve-ExecutablePath "" "iproxy.exe"
    }
    if (-not $iproxyPath -or -not (Test-Path $iproxyPath)) {
        Write-Host "  ❌ iproxy.exe not found!" -ForegroundColor Red
        Write-Host "     Expected at: C:\iProxy\iproxy.exe" -ForegroundColor Gray
        Write-Host "     Install libimobiledevice: https://libimobiledevice.org/" -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to return to menu..."
        return
    }
    Write-Host "  ✅ iproxy found: $iproxyPath" -ForegroundColor Green

    # Check for idevice_id.exe
    $ideviceIdPath = "C:\iProxy\idevice_id.exe"
    if (-not (Test-Path $ideviceIdPath)) {
        $ideviceIdPath = Resolve-ExecutablePath "" "idevice_id.exe"
    }
    if (-not $ideviceIdPath -or -not (Test-Path $ideviceIdPath)) {
        Write-Host "  ❌ idevice_id.exe not found!" -ForegroundColor Red
        Write-Host "     Expected at: C:\iProxy\idevice_id.exe" -ForegroundColor Gray
        Write-Host ""
        Read-Host "Press Enter to return to menu..."
        return
    }
    Write-Host "  ✅ idevice_id found: $ideviceIdPath" -ForegroundColor Green

    # Check for plink.exe (in project root)
    $plinkPath = Join-Path $script:SRSHome "plink.exe"
    if (-not (Test-Path $plinkPath)) {
        $plinkPath = Resolve-ExecutablePath "" "plink.exe"
    }
    if (-not $plinkPath -or -not (Test-Path $plinkPath)) {
        Write-Host "  ❌ plink.exe not found!" -ForegroundColor Red
        Write-Host "     Expected in project root or PATH" -ForegroundColor Gray
        Write-Host "     Download from: https://www.chiark.greenend.org.uk/~sgtatham/putty/latest.html" -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to return to menu..."
        return
    }
    Write-Host "  ✅ plink found: $plinkPath" -ForegroundColor Green

    # Check for Monibuca
    $monibucaPath = Join-Path $script:SRSHome "objs\monibuca.exe"
    if (-not (Test-Path $monibucaPath)) {
        Write-Host "  ❌ Monibuca executable not found: $monibucaPath" -ForegroundColor Red
        Write-Host ""
        Read-Host "Press Enter to return to menu..."
        return
    }
    Write-Host "  ✅ Monibuca found: $monibucaPath" -ForegroundColor Green

    # Check for server.py (Flask auth server)
    $flaskServerPath = Join-Path $script:SRSHome "server.py"
    if (-not (Test-Path $flaskServerPath)) {
        Write-Host "  ❌ server.py not found: $flaskServerPath" -ForegroundColor Red
        Write-Host "     Flask auth server is required for iOS app authentication" -ForegroundColor Gray
        Write-Host ""
        Read-Host "Press Enter to return to menu..."
        return
    }
    Write-Host "  ✅ Flask server found: $flaskServerPath" -ForegroundColor Green

    # Check Python and Flask
    $pythonOK = $false
    try {
        $pythonVersion = & python --version 2>&1
        if ($pythonVersion -match "Python (\d+\.\d+)") {
            $pythonOK = $true
            Write-Host "  ✅ Python found: $pythonVersion" -ForegroundColor Green
        }
    } catch { }
    if (-not $pythonOK) {
        Write-Host "  ❌ Python not found in PATH!" -ForegroundColor Red
        Write-Host "     Install from: https://www.python.org/downloads/" -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to return to menu..."
        return
    }

    # Check Flask installed
    $flaskOK = $false
    try {
        & python -c "import flask" 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $flaskOK = $true
            Write-Host "  ✅ Flask module installed" -ForegroundColor Green
        }
    } catch { }
    if (-not $flaskOK) {
        Write-Host "  📦 Installing Flask..." -ForegroundColor Yellow
        & python -m pip install flask 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✅ Flask installed successfully" -ForegroundColor Green
        } else {
            Write-Host "  ❌ Failed to install Flask" -ForegroundColor Red
            Read-Host "Press Enter to return to menu..."
            return
        }
    }
    Write-Host ""

    # ============================================================================
    # STEP 2: Detect iPhone via USB
    # ============================================================================
    Write-Host "[STEP 2/9] 📱 Detecting iPhone via USB..." -ForegroundColor Yellow

    $udidOutput = $null
    $ideviceError = $null
    try {
        $udidOutput = & $ideviceIdPath -l 2>&1
        if ($LASTEXITCODE -ne 0) {
            $ideviceError = "Exit code: $LASTEXITCODE"
            $udidOutput = $null
        }
    } catch {
        $ideviceError = $_.Exception.Message
        $udidOutput = $null
    }
    if ($ideviceError) {
        Write-Host "  [DEBUG] idevice_id error: $ideviceError" -ForegroundColor Gray
    }

    if ([string]::IsNullOrWhiteSpace($udidOutput) -or $udidOutput -match "error|ERROR") {
        Write-Host "  ❌ No iPhone detected via USB!" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Troubleshooting:" -ForegroundColor Yellow
        Write-Host "    1. Ensure iPhone is connected via USB cable" -ForegroundColor Gray
        Write-Host "    2. Accept 'Trust This Computer' dialog on iPhone" -ForegroundColor Gray
        Write-Host "    3. Install iTunes (includes Apple USB drivers)" -ForegroundColor Gray
        Write-Host "    4. Try unplugging and reconnecting the cable" -ForegroundColor Gray
        Write-Host ""
        Read-Host "Press Enter to return to menu..."
        return
    }

    # Handle multiple devices - let user choose or use first one
    # Strip carriage returns, newlines and whitespace, filter to valid UDIDs only
    $udidLines = @($udidOutput -split "`r`n|`n|`r" | ForEach-Object { $_.Trim() } | Where-Object { $_ -match "^[a-fA-F0-9\-]+$" })

    # Device name mappings (UDID -> friendly name)
    $deviceNames = @{
        "00008030-001229C01146402E" = "iPhone 8"
        "308e6361884208deb815e12efc230a028ddc4b1a" = "iPhone SE2"
    }

    if ($udidLines.Count -gt 1) {
        Write-Host "  📱 Multiple devices detected:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $udidLines.Count; $i++) {
            $udid = $udidLines[$i]
            $name = if ($deviceNames.ContainsKey($udid)) { " ($($deviceNames[$udid]))" } else { "" }
            Write-Host "     [$($i+1)] $udid$name" -ForegroundColor Gray
        }
        Write-Host ""
        $deviceChoice = Read-Host "     Select device (1-$($udidLines.Count)) or Enter for first"
        if ([string]::IsNullOrWhiteSpace($deviceChoice)) { $deviceChoice = "1" }
        $selectedUDID = $udidLines[[int]$deviceChoice - 1]
    } else {
        $selectedUDID = if ($udidLines.Count -eq 1) { $udidLines[0] } else { $udidOutput.Trim() }
    }
    $deviceFriendlyName = if ($deviceNames.ContainsKey($selectedUDID)) { " ($($deviceNames[$selectedUDID]))" } else { "" }
    Write-Host "  ✅ Using iPhone: $selectedUDID$deviceFriendlyName" -ForegroundColor Green
    Write-Host ""

    # ============================================================================
    # STEP 3: Configure SSH credentials
    # ============================================================================
    Write-Host "[STEP 3/9] 🔐 Configuring SSH credentials..." -ForegroundColor Yellow

    $config = Read-Config
    $savedPassword = $config.SSHPassword
    if ([string]::IsNullOrWhiteSpace($savedPassword)) {
        $savedPassword = "alpine"
    }

    Write-Host ""
    Write-Host "  📝 SSH Password Configuration" -ForegroundColor Cyan
    $maskedPw = if ($savedPassword.Length -gt 0) { $savedPassword[0] + ("*" * ($savedPassword.Length - 1)) } else { "(none)" }
    Write-Host "     Current saved password: $maskedPw" -ForegroundColor Gray
    Write-Host "     (Default for jailbroken devices is 'alpine')" -ForegroundColor Gray
    Write-Host ""
    $passwordInput = Read-Host "     Enter SSH password (or press Enter to use saved)"

    if ([string]::IsNullOrWhiteSpace($passwordInput)) {
        $sshPassword = $savedPassword
        Write-Host "  ✅ Using saved password" -ForegroundColor Green
    } else {
        $sshPassword = $passwordInput
        # Save new password to config
        $config.SSHPassword = $sshPassword
        Write-Config $config
        Write-Host "  ✅ Password updated and saved for future sessions" -ForegroundColor Green
        Write-Host "  ℹ️  Note: Password is stored in config.ini (plaintext)" -ForegroundColor DarkGray
    }
    Write-Host ""

    # ============================================================================
    # STEP 4: Clean up ports
    # ============================================================================
    Write-Host "[STEP 4/9] 🧹 Cleaning up conflicting processes..." -ForegroundColor Yellow

    # Clean up port 80 (Flask)
    $conn80 = Get-NetTCPConnection -LocalPort 80 -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Listen' }
    if ($conn80) {
        foreach ($c in $conn80) {
            $proc = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue
            $pname = if ($proc) { $proc.ProcessName } else { "(unknown)" }
            Write-Host "  🔥 Stopping '$pname' on port 80 (PID: $($c.OwningProcess))" -ForegroundColor Red
            try {
                Stop-Process -Id $c.OwningProcess -Force -ErrorAction Stop
            } catch {
                Write-Host "  ⚠️ Could not stop PID $($c.OwningProcess): $_" -ForegroundColor Yellow
            }
        }
    }

    # Clean up port 1935 (Monibuca RTMP) and other streaming ports
    Clear-SRSPorts

    # Clean up port 2222 (iproxy for SSH)
    $conn2222 = Get-NetTCPConnection -LocalPort 2222 -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Listen' }
    if ($conn2222) {
        foreach ($c in $conn2222) {
            $proc = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue
            $pname = if ($proc) { $proc.ProcessName } else { "(unknown)" }
            Write-Host "  🔥 Stopping '$pname' on port 2222 (PID: $($c.OwningProcess))" -ForegroundColor Red
            try {
                Stop-Process -Id $c.OwningProcess -Force -ErrorAction Stop
            } catch {
                Write-Host "  ⚠️ Could not stop PID $($c.OwningProcess): $_" -ForegroundColor Yellow
            }
        }
    }

    # Kill any existing plink processes for our tunnels
    $existingPlinks = Get-Process -Name "plink" -ErrorAction SilentlyContinue
    if ($existingPlinks) {
        Write-Host "  🔥 Stopping existing plink processes..." -ForegroundColor Red
        $existingPlinks | Stop-Process -Force -ErrorAction SilentlyContinue
    }

    # Kill any existing Monibuca processes (prevents port 50051 conflict)
    $existingMonibuca = Get-Process -Name "monibuca" -ErrorAction SilentlyContinue
    if ($existingMonibuca) {
        Write-Host "  🔥 Stopping existing Monibuca processes..." -ForegroundColor Red
        $existingMonibuca | Stop-Process -Force -ErrorAction SilentlyContinue
    }

    # Clean up port 50051 (Monibuca gRPC)
    $conn50051 = Get-NetTCPConnection -LocalPort 50051 -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Listen' }
    if ($conn50051) {
        foreach ($c in $conn50051) {
            Write-Host "  🔥 Stopping process on port 50051 (PID: $($c.OwningProcess))" -ForegroundColor Red
            try {
                Stop-Process -Id $c.OwningProcess -Force -ErrorAction Stop
            } catch { }
        }
    }

    Start-Sleep -Seconds 2
    Write-Host "  ✅ Ports cleared" -ForegroundColor Green
    Write-Host ""

    # ============================================================================
    # STEP 5: Get Monibuca config
    # ============================================================================
    Write-Host "[STEP 5/9] 📄 Preparing Monibuca configuration..." -ForegroundColor Yellow

    $profile = $config.MonibucaConfig
    if ([string]::IsNullOrWhiteSpace($profile)) {
        $profile = "monibuca_iphone_optimized.yaml"
    }

    $profileBasename = [System.IO.Path]::GetFileName($profile)
    if ($profile -ne $profileBasename -or $profile -match "[/\\]") {
        Write-Host "  ⚠️ Invalid config profile name, using default" -ForegroundColor Yellow
        $profile = "monibuca_iphone_optimized.yaml"
    }

    $configPath = Join-Path $script:SRSHome ("conf\" + $profile)
    if (-not (Test-Path $configPath)) {
        $configPath = Join-Path $script:SRSHome "conf\monibuca_iphone_optimized.yaml"
    }
    if (-not (Test-Path $configPath)) {
        $configPath = Join-Path $script:SRSHome "config.yaml"
    }

    if (-not (Test-Path $configPath)) {
        Write-Host "  ❌ No Monibuca config found!" -ForegroundColor Red
        Write-Host ""
        Read-Host "Press Enter to return to menu..."
        return
    }
    Write-Host "  ✅ Using config: $(Split-Path $configPath -Leaf)" -ForegroundColor Green
    Write-Host ""

    # ============================================================================
    # STEP 6: Launch iproxy (USB SSH forwarding) - HIDDEN
    # ============================================================================
    Write-Host "[STEP 6/9] 🚀 Starting iproxy (USB → SSH forwarding)..." -ForegroundColor Yellow

    # Run iproxy hidden - it just forwards ports, no user interaction needed
    $iproxyCommand = @"
& "$iproxyPath" 2222 22 "$selectedUDID"
"@

    Start-Process powershell -ArgumentList "-ExecutionPolicy", "Bypass", "-Command", $iproxyCommand -WindowStyle Hidden

    # Wait for iproxy process to start (USB forwarding doesn't show as TCP listener)
    $timeout = 10
    $startTime = Get-Date
    $iproxyProc = $null
    do {
        Start-Sleep -Milliseconds 500
        $iproxyProc = Get-Process -Name "iproxy" -ErrorAction SilentlyContinue
    } while (-not $iproxyProc -and ((Get-Date) - $startTime).TotalSeconds -lt $timeout)

    if ($iproxyProc) {
        Write-Host "  ✅ iproxy running (USB forwarding active)" -ForegroundColor Green
        Add-Content -Path $script:UsbLogFile -Value "[$(Get-Date -Format 'HH:mm:ss')] STEP6: iproxy OK - process running"
    } else {
        Write-Host "  ❌ iproxy failed to start!" -ForegroundColor Red
        Add-Content -Path $script:UsbLogFile -Value "[$(Get-Date -Format 'HH:mm:ss')] STEP6: iproxy FAILED - process not found"
        $allReady = $false
    }
    Write-Host ""

    # ============================================================================
    # STEP 7: Launch Flask auth server (port 80)
    # ============================================================================
    Write-Host "[STEP 7/9] 🌐 Starting Flask auth server (port 80)..." -ForegroundColor Yellow

    # Run Flask hidden - just serves HTTP auth, no user interaction needed
    $flaskCommand = @"
Set-Location "$script:SRSHome";
& python server.py --host 0.0.0.0 --port 80
"@

    Start-Process powershell -ArgumentList "-ExecutionPolicy", "Bypass", "-Command", $flaskCommand -WindowStyle Hidden

    # Give Flask time to initialize Python environment
    Start-Sleep -Seconds 3

    # Wait for Flask to start listening on port 80
    $timeout = 20
    $startTime = Get-Date
    $flaskCheck = $null
    do {
        Start-Sleep -Milliseconds 500
        $flaskCheck = Get-NetTCPConnection -LocalPort 80 -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Listen' }
    } while (-not $flaskCheck -and ((Get-Date) - $startTime).TotalSeconds -lt $timeout)

    if ($flaskCheck) {
        # Verify it's actually Python/Flask, not System process (PID 4 = IIS/HTTP.sys)
        $port80Proc = Get-Process -Id $flaskCheck.OwningProcess -ErrorAction SilentlyContinue
        if ($port80Proc -and $port80Proc.ProcessName -match 'python|flask') {
            Write-Host "  ✅ Flask listening on port 80" -ForegroundColor Green
            Add-Content -Path $script:UsbLogFile -Value "[$(Get-Date -Format 'HH:mm:ss')] STEP7: Flask OK - Python listening on port 80"
        } elseif ($flaskCheck.OwningProcess -eq 4) {
            Write-Host "  ❌ Port 80 held by System/IIS (PID 4)!" -ForegroundColor Red
            Write-Host "     Stop IIS: Stop-Service W3SVC -Force" -ForegroundColor Gray
            Add-Content -Path $script:UsbLogFile -Value "[$(Get-Date -Format 'HH:mm:ss')] STEP7: Flask BLOCKED - Port 80 held by System/IIS"
            $allReady = $false
        } else {
            Write-Host "  ⚠️ Port 80 held by: $($port80Proc.ProcessName) (PID: $($flaskCheck.OwningProcess))" -ForegroundColor Yellow
            Add-Content -Path $script:UsbLogFile -Value "[$(Get-Date -Format 'HH:mm:ss')] STEP7: Flask BLOCKED - Port 80 held by $($port80Proc.ProcessName)"
            $allReady = $false
        }
    } else {
        # Check if Python process is at least running (Flask may be starting)
        $pythonProc = Get-Process -Name "python*" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match 'server\.py' -or $_.MainWindowTitle -match 'Flask' }
        if ($pythonProc) {
            Write-Host "  ⚠️ Flask process running but port 80 not yet bound" -ForegroundColor Yellow
            Write-Host "     Check Flask window for errors" -ForegroundColor Gray
            Add-Content -Path $script:UsbLogFile -Value "[$(Get-Date -Format 'HH:mm:ss')] STEP7: Flask process exists but port 80 not bound"
        } else {
            Write-Host "  ❌ Flask failed to start on port 80!" -ForegroundColor Red
            Write-Host "     Port 80 may require admin privileges" -ForegroundColor Gray
            Add-Content -Path $script:UsbLogFile -Value "[$(Get-Date -Format 'HH:mm:ss')] STEP7: Flask FAILED - not listening on port 80"
        }
        $allReady = $false
    }
    Write-Host ""

    # ============================================================================
    # STEP 8: Launch Monibuca server (port 1935)
    # ============================================================================
    Write-Host "[STEP 8/9] 📺 Starting Monibuca RTMP server (port 1935)..." -ForegroundColor Yellow
    $configFullPath = (Resolve-Path $configPath).Path

    $monibucaCommand = @"
`$Host.UI.RawUI.WindowTitle = 'Monibuca - RTMP Server';
Write-Host '========================================' -ForegroundColor Magenta;
Write-Host '    MONIBUCA - RTMP STREAMING SERVER   ' -ForegroundColor White;
Write-Host '========================================' -ForegroundColor Magenta;
Write-Host '';
Write-Host 'Listening for RTMP on port 1935' -ForegroundColor Green;
Write-Host '';
Write-Host 'OBS/Streaming Software:' -ForegroundColor Cyan;
Write-Host '  rtmp://localhost:1935/live/srs' -ForegroundColor White;
Write-Host '';
Write-Host 'Web Console: http://localhost:8081/' -ForegroundColor Green;
Write-Host '========================================' -ForegroundColor Magenta;
Write-Host '';
Set-Location "$script:SRSHome";
& "$monibucaPath" -c "$configFullPath";
Write-Host '';
Write-Host 'Monibuca stopped. Press any key to close...' -ForegroundColor Yellow;
`$null = `$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
"@

    Start-Process powershell -ArgumentList "-NoExit", "-ExecutionPolicy", "Bypass", "-Command", $monibucaCommand -WindowStyle Normal

    # Give Monibuca time to initialize
    Start-Sleep -Seconds 2

    # Wait for Monibuca to start listening on port 1935
    $timeout = 20
    $startTime = Get-Date
    $monibucaCheck = $null
    do {
        Start-Sleep -Milliseconds 500
        $monibucaCheck = Get-NetTCPConnection -LocalPort 1935 -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Listen' }
    } while (-not $monibucaCheck -and ((Get-Date) - $startTime).TotalSeconds -lt $timeout)

    if ($monibucaCheck) {
        Write-Host "  ✅ Monibuca listening on port 1935" -ForegroundColor Green
        Add-Content -Path $script:UsbLogFile -Value "[$(Get-Date -Format 'HH:mm:ss')] STEP8: Monibuca OK - listening on port 1935"
    } else {
        # Check if process is at least running
        $monibucaProc = Get-Process -Name "monibuca" -ErrorAction SilentlyContinue
        if ($monibucaProc) {
            Write-Host "  ⚠️ Monibuca process running but port 1935 not yet bound" -ForegroundColor Yellow
            Write-Host "     Check Monibuca window for errors" -ForegroundColor Gray
            Add-Content -Path $script:UsbLogFile -Value "[$(Get-Date -Format 'HH:mm:ss')] STEP8: Monibuca process exists but port 1935 not bound"
        } else {
            Write-Host "  ❌ Monibuca failed to start!" -ForegroundColor Red
            Add-Content -Path $script:UsbLogFile -Value "[$(Get-Date -Format 'HH:mm:ss')] STEP8: Monibuca FAILED"
        }
        $allReady = $false
    }
    Write-Host ""

    # ============================================================================
    # STEP 9: Launch SSH tunnels + iPhone IP alias
    # ============================================================================
    Write-Host "[STEP 9/9] 🔗 Starting SSH tunnels (ports 80 + 1935)..." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  This step creates reverse tunnels AND sets up iPhone IP alias." -ForegroundColor Gray
    Write-Host "  ⚠️  FIRST TIME: Type 'y' to accept SSH host key when prompted!" -ForegroundColor Yellow
    Write-Host ""

    # Configure iPhone IP alias (GatewayPorts should already be enabled - see USB-STREAMING-WORKING.md)
    Write-Host "  🔧 Setting up iPhone IP alias..." -ForegroundColor Gray
    # Simple command without nested quotes to avoid escaping issues through plink→zsh
    $aliasCmd = 'ifconfig lo0 alias 127.10.10.10 netmask 255.255.255.255; echo ALIAS_OK'
    $aliasResult = & $plinkPath -ssh -batch -pw $sshPassword root@localhost -P 2222 $aliasCmd 2>&1
    if ($aliasResult -match 'ALIAS_OK') {
        Write-Host "  ✅ iPhone IP alias configured (127.10.10.10)" -ForegroundColor Green
        Add-Content -Path $script:UsbLogFile -Value "[$(Get-Date -Format 'HH:mm:ss')] iPhone alias OK"
    } else {
        Write-Host "  ⚠️ iPhone alias may have issues (continuing anyway)" -ForegroundColor Yellow
        Write-Host "     Run manually on iPhone: ifconfig lo0 alias 127.10.10.10" -ForegroundColor Gray
        Add-Content -Path $script:UsbLogFile -Value "[$(Get-Date -Format 'HH:mm:ss')] iPhone alias warning: $aliasResult"
    }

    # Start SSH tunnel with -batch mode and a keep-alive command (tunnel dies without a command!)
    Write-Host "  🔗 Starting SSH reverse tunnel..." -ForegroundColor Gray

    # CRITICAL: plink MUST use -batch AND have a running command or the tunnel won't bind ports!
    # Using 'cat' as keep-alive - it waits forever for input that never comes
    # -batch auto-accepts host keys so it works with different phones without user interaction
    $tunnelCommand = @"
& "$plinkPath" -ssh -batch -R 127.10.10.10:80:localhost:80 -R 127.10.10.10:1935:localhost:1935 -pw $sshPassword root@localhost -P 2222 'echo TUNNEL_ACTIVE; cat'
"@
    Start-Process powershell -ArgumentList "-ExecutionPolicy", "Bypass", "-Command", $tunnelCommand -WindowStyle Hidden

    # Give SSH time to connect and set up tunnels
    Write-Host "  ⏳ Waiting for SSH connection..." -ForegroundColor Gray
    Start-Sleep -Seconds 5

    # Verify plink process started AND stays alive
    $plinkProcs = Get-Process -Name "plink" -ErrorAction SilentlyContinue
    if ($plinkProcs) {
        Write-Host "  ✅ SSH tunnel process started (PID: $($plinkProcs.Id -join ', '))" -ForegroundColor Green

        # Brief liveness check - plink can die immediately if auth fails or host key issues
        Start-Sleep -Seconds 2
        $plinkStillAlive = Get-Process -Name "plink" -ErrorAction SilentlyContinue
        if ($plinkStillAlive) {
            Write-Host "  ✅ SSH tunnel confirmed stable" -ForegroundColor Green
            Add-Content -Path $script:UsbLogFile -Value "[$(Get-Date -Format 'HH:mm:ss')] STEP9: SSH tunnel OK - plink alive after liveness check"
        } else {
            Write-Host "  ⚠️ SSH tunnel died shortly after starting!" -ForegroundColor Yellow
            Write-Host "     Check: iPhone connected? SSH password correct? Host key accepted?" -ForegroundColor Gray
            Add-Content -Path $script:UsbLogFile -Value "[$(Get-Date -Format 'HH:mm:ss')] STEP9: SSH tunnel DIED - plink exited after startup"
            $allReady = $false
        }
    } else {
        Write-Host "  ⚠️ SSH tunnel failed to start" -ForegroundColor Yellow
        Write-Host "     Check: plink.exe exists? iproxy running? iPhone connected?" -ForegroundColor Gray
        Add-Content -Path $script:UsbLogFile -Value "[$(Get-Date -Format 'HH:mm:ss')] STEP9: SSH tunnel FAILED - plink process NOT FOUND"
        $allReady = $false
    }
    Write-Host ""

    # ============================================================================
    # FINAL STATUS
    # ============================================================================
    Write-Host ""
    if ($allReady) {
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
        Write-Host "                    ✅ USB STREAMING SOLUTION READY                         " -BackgroundColor DarkGreen -ForegroundColor White
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
        Add-Content -Path $script:UsbLogFile -Value "[$(Get-Date -Format 'HH:mm:ss')] FINAL: ALL SERVICES READY"
    } else {
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
        Write-Host "              ⚠️ USB STREAMING STARTED WITH WARNINGS                        " -BackgroundColor DarkYellow -ForegroundColor Black
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
        Add-Content -Path $script:UsbLogFile -Value "[$(Get-Date -Format 'HH:mm:ss')] FINAL: STARTED WITH WARNINGS - check log for details"
    }
    Write-Host ""
    Write-Host "  🔌 Services running:" -ForegroundColor White
    Write-Host "     ✅ iProxy      (background) - USB port forwarding" -ForegroundColor Gray
    Write-Host "     ✅ Flask       (background) - HTTP auth on port 80" -ForegroundColor Gray
    Write-Host "     ✅ SSH Tunnel  (background) - Reverse tunnels to iPhone" -ForegroundColor Gray
    Write-Host "     📺 Monibuca   (visible)    - RTMP streaming on port 1935" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  🎬 OBS Stream Settings:" -ForegroundColor White
    Write-Host "     Server: rtmp://localhost:1935/live" -ForegroundColor Cyan
    Write-Host "     Stream Key: srs" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  📱 iPhone App (PULLS stream via tunnel):" -ForegroundColor White
    Write-Host "     Uses: rtmp://127.10.10.10:1935/live/srs" -ForegroundColor Green
    Write-Host "     Open iOS-VCAM app and tap Connect" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  🌐 Monibuca Console: http://localhost:8081/" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  💡 Use Option [K] from menu to kill all & restart fresh" -ForegroundColor Yellow
    Write-Host "  📝 Log: $script:UsbLogFile" -ForegroundColor Gray
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    Write-Host ""
    Read-Host "Press Enter to return to menu..."
}

function Start-CombinedFlaskAndMonibuca {
    try { Clear-Host } catch { }
    Write-Host ""
    Write-Host "    =====================================================================================" -ForegroundColor Magenta
    Write-Host "                      🚀 COMBINED FLASK + MONIBUCA STREAMING SOLUTION                   " -ForegroundColor White
    Write-Host "    =====================================================================================" -ForegroundColor Magenta
    Write-Host ""

    Write-Host "[INFO] Starting Monibuca streaming solution..." -ForegroundColor Green
    Write-Host ""

    # Check if Python is installed for Flask
    Write-Host "[STEP 1/5] 🐍 Checking Python installation..." -ForegroundColor Yellow
    $pythonVersion = $null
    try {
        $pythonVersion = & python --version 2>&1
        if ($pythonVersion -match "Python (\d+\.\d+)") {
            Write-Host "  ✅ Python is installed: $pythonVersion" -ForegroundColor Green
        }
    } catch { }

    if (-not $pythonVersion) {
        Write-Host "  ❌ Python is not installed or not in PATH!" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Please install Python from: https://www.python.org/downloads/" -ForegroundColor Yellow
        Write-Host "  Make sure to check 'Add Python to PATH' during installation." -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to return to menu..."
        return
    }

    # Check Flask installation
    Write-Host "[STEP 2/5] 📦 Checking Flask installation..." -ForegroundColor Yellow
    $flaskInstalled = $false
    try {
        & python -c "import flask" 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $flaskInstalled = $true
            Write-Host "  ✅ Flask is installed" -ForegroundColor Green
        }
    } catch { }

    if (-not $flaskInstalled) {
        Write-Host "  📦 Flask not found. Installing Flask..." -ForegroundColor Yellow
        & python -m pip install flask 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✅ Flask installed successfully!" -ForegroundColor Green
        } else {
            Write-Host "  ❌ Failed to install Flask. Please install manually." -ForegroundColor Red
            Read-Host "Press Enter to return to menu..."
            return
        }
    }

    # Clean up ports
    Write-Host "[STEP 3/5] 🧹 Cleaning up conflicting processes..." -ForegroundColor Yellow
    Clear-SRSPorts

    # Start Monibuca
    Write-Host "[STEP 4/5] 🚀 Launching Monibuca server in new window..." -ForegroundColor Yellow

    # Determine Monibuca config path - use selected profile from config.ini
    $config = Read-Config
    $profile = $config.MonibucaConfig
    if ([string]::IsNullOrWhiteSpace($profile)) {
        $profile = "monibuca_iphone_optimized.yaml"
    }

    $configPath = Join-Path $script:SRSHome ("conf\\" + $profile)
    if (-not (Test-Path $configPath)) {
        # Fallback to optimized profile
        $configPath = Join-Path $script:SRSHome "conf\monibuca_iphone_optimized.yaml"
    }
    if (-not (Test-Path $configPath)) {
        # Final fallback to root config.yaml
        $configPath = Join-Path $script:SRSHome "config.yaml"
    }

    # Verify config exists
    if (-not (Test-Path $configPath)) {
        Write-Host "  ❌ No Monibuca config found! Checked:" -ForegroundColor Red
        Write-Host "     - conf\$profile" -ForegroundColor Gray
        Write-Host "     - conf\monibuca_iphone_optimized.yaml" -ForegroundColor Gray
        Write-Host "     - config.yaml" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  💡 Please ensure Monibuca config files are in place." -ForegroundColor Yellow
        Read-Host "Press Enter to return to menu..."
        return
    }

    Write-Host "  📄 Using Monibuca config: $(Split-Path $configPath -Leaf)" -ForegroundColor Cyan

    # Update IP in Monibuca config
    $ipUpdateResult = Update-MonibucaConfigIP $configPath
    if (-not $ipUpdateResult) {
        Write-Host "  ⚠️ Warning: IP update may have failed. Continuing anyway..." -ForegroundColor Yellow
    }

    # Launch Monibuca in new window
    $monibucaStartResult = Start-MonibucaServerWindow -ConfigPath $configPath -DisplayIP $script:CurrentIP
    if (-not $monibucaStartResult) {
        Write-Host ""
        Write-Host "  ❌ Failed to launch Monibuca server!" -ForegroundColor Red
        Write-Host "     Check that objs\monibuca.exe exists and is executable." -ForegroundColor Gray
        Write-Host ""
        Read-Host "Press Enter to return to menu..."
        return
    }

    # Give Monibuca a moment to start
    Start-Sleep -Seconds 2

    # Start Flask
    Write-Host "[STEP 5/5] 🔐 Starting Flask authentication server..." -ForegroundColor Yellow
    Write-Host ""

    # Update server.py with current IP
    $serverPy = Join-Path $script:SRSHome "server.py"
    if (Test-Path $serverPy) {
        try {
            $content = Get-Content $serverPy -Raw -Encoding UTF8
            # Update IP in server.py - look for host= parameter
            $content = $content -replace "host='[\d\.]+'", "host='$($script:CurrentIP)'"
            $content = $content -replace 'host="[\d\.]+"', "host=`"$($script:CurrentIP)`""
            $content | Set-Content $serverPy -Encoding UTF8 -NoNewline
            Write-Host "  ✅ Flask server.py IP updated to: $script:CurrentIP" -ForegroundColor Green
        } catch {
            Write-Host "  ⚠️ Could not update server.py IP" -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    Write-Host "                    ✅ MONIBUCA STREAMING SOLUTION READY                    " -BackgroundColor DarkGreen -ForegroundColor White
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    Write-Host ""
    Write-Host "  📺 Monibuca is running in separate window (Magenta header)" -ForegroundColor Magenta
    Write-Host "  🔐 Flask will start below for iOS authentication" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  📱 RTMP URL: rtmp://$script:CurrentIP`:1935/live/srs" -ForegroundColor Cyan
    Write-Host "  🌐 Monibuca Console: http://$script:CurrentIP`:8081/" -ForegroundColor Cyan
    Write-Host "  🔐 Flask Auth: http://$script:CurrentIP`:80/" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Press Ctrl+C to stop Flask server" -ForegroundColor Gray
    Write-Host ""

    # Run Flask in this window
    Set-Location $script:SRSHome
    & python $serverPy
}

function Start-UsbListenerWindow {
    param(
        [int]$DevicePort,
        [int]$LocalPort,
        [int]$TargetPort,
        [string]$Label = "USB Listener"
    )

    $usbListener = Join-Path $script:SRSHome "scripts\\usb_usbmux_listener.py"
    if (-not (Test-Path $usbListener)) {
        Write-Host "  ❌ USB listener script not found: $usbListener" -ForegroundColor Red
        return $false
    }

    $psCommand = @"
`$Host.UI.RawUI.WindowTitle = "$Label";
Set-Location "$script:SRSHome";
Write-Host '========================================' -ForegroundColor Cyan;
Write-Host '$Label' -ForegroundColor White;
Write-Host '========================================' -ForegroundColor Cyan;
Write-Host 'Device port: $DevicePort' -ForegroundColor Gray;
Write-Host 'Local port: $LocalPort' -ForegroundColor Gray;
Write-Host 'Target port: $TargetPort' -ForegroundColor Gray;
Write-Host '';
python -u '$usbListener' --device-port $DevicePort --local-port $LocalPort --srs-host 127.0.0.1 --srs-port $TargetPort;
Write-Host '';
Write-Host 'USB Listener stopped. Press any key to close...' -ForegroundColor Yellow;
`$null = `$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
"@

    Start-Process powershell -ArgumentList "-NoExit", "-ExecutionPolicy", "Bypass", "-Command", $psCommand -WindowStyle Normal
    Write-Host "  ✅ $Label launched in new window!" -ForegroundColor Green
    return $true
}

function Start-iPhoneUltraSmooth {
    try { Clear-Host } catch { }
    Write-Host ""
    Write-Host "    =====================================================================================" -ForegroundColor Green
    Write-Host "                          🚀 IPHONE ULTRA-SMOOTH LAUNCHER                             " -ForegroundColor White
    Write-Host "    =====================================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "[INFO] Launching iPhone Ultra-Smooth Dynamic mode" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "`[STEP 1/4] 🧹 Cleaning up conflicting processes..." -ForegroundColor Yellow
    Clear-SRSPorts

    Write-Host "`[STEP 2/4] ⚙️  Using ultra-smooth dynamic configuration..." -ForegroundColor Yellow
    $configPath = Join-Path $script:SRSHome "config\active\srs_iphone_ultra_smooth_dynamic.conf"

    # Check if config exists, fallback to regular ultra smooth
    if (-not (Test-Path $configPath)) {
        $configPath = Join-Path $script:SRSHome "config\active\srs_iphone_ultra_smooth.conf"
        Write-Host "  Using fallback config: $configPath" -ForegroundColor Yellow
    }

    Write-Host "`[STEP 3/4] 🔧 Auto-updating IP addresses..." -ForegroundColor Yellow
    if (Update-ConfigIP $configPath) {
        Write-Host "  ✅ IP configuration updated to: $script:CurrentIP" -ForegroundColor Green
    } else {
        Write-Host "  ⚠️ Using existing IP configuration" -ForegroundColor Yellow
    }

    Write-Host "`[STEP 4/4] 🚀 Starting SRS server..." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    -------------------------------------------------------------------------------------" -ForegroundColor Green
    Write-Host "  📱 RTMP URL: rtmp://$script:CurrentIP`:1935/live/srs" -ForegroundColor Green
    Write-Host "  🌐 Web Console: http://$script:CurrentIP`:8080/" -ForegroundColor Green
    Write-Host "    -------------------------------------------------------------------------------------" -ForegroundColor Green
    Write-Host ""

    # Copy RTMP URL to clipboard automatically
    $rtmpUrl = "rtmp://$script:CurrentIP" + ":1935/live/srs"
    try {
        $rtmpUrl | Set-Clipboard
        Write-Host "  📋 RTMP URL automatically copied to clipboard!" -ForegroundColor Cyan
        Write-Host "     Ready to paste in your iPhone streaming app" -ForegroundColor Gray
    } catch {
        Write-Host "  ⚠️ Could not auto-copy to clipboard" -ForegroundColor Yellow
    }

    Write-Host ""

    Start-SRSServer $configPath
}

function Start-SRSMode($mode, $configFile) {
    try { Clear-Host } catch { }
    Show-SRSAsciiArt
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "                       🚀 $mode LAUNCHER                             " -BackgroundColor DarkCyan -ForegroundColor White
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""

    Clear-SRSPorts
    Start-SRSServer (Join-Path $script:SRSHome "config\active\$configFile")
}

function Clear-SRSPorts {
    $ports = @(1935)  # Only check RTMP port since that's what we need
    $processesKilled = 0

    foreach ($port in $ports) {
        try {
            $connections = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
            if ($connections) {
                foreach ($conn in $connections) {
                    try {
                        $processName = (Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue).ProcessName
                        Write-Host "  🔥 Stopping process '$processName' on port $port (PID: $($conn.OwningProcess))" -ForegroundColor Red
                        Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue
                        $processesKilled++
                    } catch {
                        Write-Host "  ⚠️ Could not stop PID $($conn.OwningProcess) on port $port" -ForegroundColor Yellow
                    }
                }
            } else {
                Write-Host "  ℹ️ Port $port is already free" -ForegroundColor Gray
            }
        } catch {
            Write-Host "  ⚠️ Could not check port $port status" -ForegroundColor Yellow
        }
    }

    if ($processesKilled -gt 0) {
        Start-Sleep -Seconds 2
        Write-Host "  ✅ Port cleanup completed - stopped $processesKilled process(es)" -ForegroundColor Green
    } else {
        Write-Host "  ✅ Port cleanup completed - no processes needed stopping" -ForegroundColor Green
    }
}

function Write-CrashLog {
    param(
        [string]$Message,
        [object]$ErrorRecord
    )

    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $details = ""
        if ($ErrorRecord) {
            $details = $ErrorRecord | Out-String
        }

        $content = @(
            "[$timestamp] $Message",
            $details.Trim(),
            "PSVersion: $($PSVersionTable.PSVersion)",
            "SRSHome: $script:SRSHome",
            "-----"
        ) -join "`r`n"

        if (-not (Test-Path $script:ConfigDir)) {
            New-Item -ItemType Directory -Path $script:ConfigDir -Force | Out-Null
        }
        Add-Content -Path $script:CrashLog -Value $content -Encoding UTF8
    } catch {
        # best-effort logging only
    }
}

function ConvertTo-PlainText {
    param([SecureString]$SecureValue)
    if (-not $SecureValue) { return "" }
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Resolve-ExecutablePath {
    param(
        [string]$Hint,
        [string]$ExeName
    )

    if ($Hint) {
        $Hint = $Hint.Trim('"')
        if (Test-Path $Hint -PathType Leaf) {
            return $Hint
        }
        if (Test-Path $Hint -PathType Container) {
            $candidate = Join-Path $Hint $ExeName
            if (Test-Path $candidate -PathType Leaf) {
                return $candidate
            }
        }
    }

    # Check common local locations first (repo root/tools/bin)
    if ($script:SRSHome) {
        $localCandidates = @(
            (Join-Path $script:SRSHome $ExeName),
            (Join-Path $script:SRSHome "tools\\$ExeName"),
            (Join-Path $script:SRSHome "bin\\$ExeName")
        )
        foreach ($candidate in $localCandidates) {
            if (Test-Path $candidate -PathType Leaf) {
                return $candidate
            }
        }
    }

    $cmd = Get-Command $ExeName -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    return $null
}

function Show-USBValidation {
    param(
        [switch]$Auto
    )

    if (-not $Auto) {
        try { Clear-Host } catch { }
    }
    Show-SRSAsciiArt
    Write-Host ""
    Write-Host "    " -NoNewline
    Write-Host "╔═══════════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "    " -NoNewline
    Write-Host "║                               🧪 USB SETUP VALIDATION                                  ║" -ForegroundColor White
    Write-Host "    " -NoNewline
    Write-Host "╚═══════════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
    Write-Host ""

    $vcamDeb = Join-Path $script:SRSHome "ios\\modified_debs\\iosvcam_base_127_10_10_10.deb"
    $fwdDeb = Join-Path $script:SRSHome "ios\\modified_debs\\vcam_usb_forwarder.deb"
    $usbListener = Join-Path $script:SRSHome "scripts\\usb_usbmux_listener.py"

    Write-Host "  📦 Files:" -ForegroundColor Cyan
    $vcamDebStatus = if (Test-Path $vcamDeb) { "✅" } else { "❌" }
    $fwdDebStatus = if (Test-Path $fwdDeb) { "✅" } else { "❌" }
    $usbListenerStatus = if (Test-Path $usbListener) { "✅" } else { "❌" }
    Write-Host "  $vcamDebStatus VCAM .deb (127.10.10.10): $vcamDeb" -ForegroundColor Gray
    Write-Host "  $fwdDebStatus USB forwarder .deb: $fwdDeb" -ForegroundColor Gray
    Write-Host "  $usbListenerStatus USB listener script: $usbListener" -ForegroundColor Gray
    Write-Host ""

    $pythonOk = $false
    try { & python --version 2>&1 | Out-Null; $pythonOk = $true } catch { }
    $pmd3Ok = $false
    if ($pythonOk) {
        try { & python -c "import pymobiledevice3" 2>&1 | Out-Null; if ($LASTEXITCODE -eq 0) { $pmd3Ok = $true } } catch { }
    }

    Write-Host "  🧰 Dependencies:" -ForegroundColor Cyan
    $pythonStatus = if ($pythonOk) { "✅" } else { "❌" }
    $pmd3Status = if ($pmd3Ok) { "✅" } else { "❌" }
    Write-Host "  $pythonStatus Python installed" -ForegroundColor Gray
    Write-Host "  $pmd3Status pymobiledevice3 installed" -ForegroundColor Gray
    Write-Host ""

    $plinkPath = Resolve-ExecutablePath "" "plink.exe"
    $pscpPath = Resolve-ExecutablePath "" "pscp.exe"
    Write-Host "  🔧 Tools:" -ForegroundColor Cyan
    $plinkStatus = if ($plinkPath) { "✅" } else { "❌" }
    $pscpStatus = if ($pscpPath) { "✅" } else { "❌" }
    $plinkInfo = if ($plinkPath) { " ($plinkPath)" } else { "" }
    $pscpInfo = if ($pscpPath) { " ($pscpPath)" } else { "" }
    Write-Host "  $plinkStatus plink.exe$plinkInfo" -ForegroundColor Gray
    Write-Host "  $pscpStatus pscp.exe$pscpInfo" -ForegroundColor Gray
    Write-Host ""

    $srsRunning = $false
    try { if (Get-Process -Name "srs" -ErrorAction SilentlyContinue) { $srsRunning = $true } } catch { }

    $rtmpListening = $false
    $flaskListening = $false
    $prevProgress = $ProgressPreference
    $ProgressPreference = "SilentlyContinue"
    try { $rtmpListening = [bool](Test-NetConnection -ComputerName 127.0.0.1 -Port 1935 -InformationLevel Quiet -WarningAction SilentlyContinue) } catch { }
    try { $flaskListening = [bool](Test-NetConnection -ComputerName 127.0.0.1 -Port 80 -InformationLevel Quiet -WarningAction SilentlyContinue) } catch { }
    $ProgressPreference = $prevProgress

    Write-Host "  🖥️ Services (PC):" -ForegroundColor Cyan
    $srsStatus = if ($srsRunning) { "✅" } else { "⚠️" }
    $rtmpStatus = if ($rtmpListening) { "✅" } else { "⚠️" }
    $flaskStatus = if ($flaskListening) { "✅" } else { "⚠️" }
    Write-Host "  $srsStatus SRS process running" -ForegroundColor Gray
    Write-Host "  $rtmpStatus RTMP port 1935 listening (127.0.0.1)" -ForegroundColor Gray
    Write-Host "  $flaskStatus Flask port 80 listening (127.0.0.1)" -ForegroundColor Gray
    Write-Host ""

    $usbListenerRunning = $false
    try {
        $proc = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
            $_.CommandLine -and $_.CommandLine -match "usb_usbmux_listener.py"
        }
        if ($proc) { $usbListenerRunning = $true }
    } catch { }

    Write-Host "  🔌 USB Listener:" -ForegroundColor Cyan
    $usbListenerStatus = if ($usbListenerRunning) { "✅" } else { "⚠️" }
    Write-Host "  $usbListenerStatus usb_usbmux_listener.py running" -ForegroundColor Gray
    Write-Host ""

    $sshTunnelOpen = $false
    $prevProgress = $ProgressPreference
    $ProgressPreference = "SilentlyContinue"
    try { $sshTunnelOpen = [bool](Test-NetConnection -ComputerName 127.0.0.1 -Port 2222 -InformationLevel Quiet -WarningAction SilentlyContinue) } catch { }
    $ProgressPreference = $prevProgress
    Write-Host "  📡 3uTools SSH Tunnel:" -ForegroundColor Cyan
    $sshTunnelStatus = if ($sshTunnelOpen) { "✅" } else { "⚠️" }
    Write-Host "  $sshTunnelStatus Tunnel reachable at 127.0.0.1:2222" -ForegroundColor Gray
    Write-Host ""

    Write-Host "  ✅ USB Mode Targets:" -ForegroundColor Green
    Write-Host "     OBS:  rtmp://127.0.0.1:1935/live/srs" -ForegroundColor Yellow
    Write-Host "     VCAM: rtmp://127.10.10.10:1935/live/srs" -ForegroundColor Yellow
    Write-Host "     Flask (USB): http://127.10.10.10:80/" -ForegroundColor Yellow
    Write-Host ""

    if (-not $Auto) {
        Read-Host "Press Enter to return to menu..."
    } else {
        Write-Host ""
        Write-Host "  (Auto-check complete)" -ForegroundColor DarkGray
        Write-Host ""
    }
}

function Start-SRSServer($configPath) {
    if (-not (Test-Path $configPath)) {
        Write-Host "[ERROR] Configuration file not found: $configPath" -ForegroundColor Red
        $configPath = Join-Path $script:SRSHome "config\active\srs_iphone_optimized_smooth.conf"
        Write-Host "[FALLBACK] Using: $configPath" -ForegroundColor Yellow
    }

    $srsExePath = Join-Path $script:SRSHome "objs\srs.exe"
    if (-not (Test-Path $srsExePath)) {
        Write-Host "[ERROR] SRS executable not found: $srsExePath" -ForegroundColor Red
        Read-Host "Press Enter to return to menu..."""
        return
    }

    Write-Host "Starting SRS with configuration: $configPath" -ForegroundColor Cyan
    Write-Host ""
    # Skip duplicate RTMP display when called from iPhone Ultra-Smooth mode
    if ($configPath -notlike "*ultra_smooth*") {
        Write-Host "🎯 Use this RTMP URL in your iPhone app:" -ForegroundColor Yellow
        Write-Host "rtmp://$script:CurrentIP`:1935/live/srs" -ForegroundColor Green
        Write-Host ""
    }

    # Auto-copy RTMP URL to clipboard for all server starts
    $rtmpUrl = "rtmp://$script:CurrentIP" + ":1935/live/srs"
    try {
        $rtmpUrl | Set-Clipboard
        Write-Host "📋 RTMP URL copied to clipboard! Ready to paste in your app." -ForegroundColor Cyan
    } catch {
        Write-Host "⚠️ Could not copy URL to clipboard automatically." -ForegroundColor Yellow
    }
    Write-Host ""

    try {
        & $srsExePath -c "$configPath"
    } catch {
        Write-Host "[ERROR] Failed to start SRS server: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
    Read-Host "Press Enter to return to menu"
}

function Show-SystemDiagnostics {
    try { Clear-Host } catch { }
    Show-SRSAsciiArt
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "                      🔍 SYSTEM DIAGNOSTICS                           " -BackgroundColor DarkCyan -ForegroundColor White
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""

    # Network info
    Write-Host "🌐 Network Configuration:" -ForegroundColor Green
    Write-Host "  Current IP: $script:CurrentIP"
    Write-Host "  Adapter: $script:WiFiAdapter"
    Write-Host "  Status: $script:NetworkStatus"
    Write-Host "  RTMP URL: rtmp://$script:CurrentIP`:1935/live/srs" -ForegroundColor Yellow
    Write-Host ""

    # Port status
    Write-Host "🔌 Port Status:" -ForegroundColor Green
    $ports = @(1935)  # Only check RTMP port since that's what we need
    foreach ($port in $ports) {
        $connections = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
        if ($connections) {
            Write-Host "  Port $port`: OCCUPIED (PID: $($connections[0].OwningProcess))" -ForegroundColor Red
        } else {
            Write-Host "  Port $port`: FREE" -ForegroundColor Green
        }
    }
    Write-Host ""

    # SRS processes
    Write-Host "🔄 SRS Processes:" -ForegroundColor Green
    $srsProcesses = Get-Process -Name "srs" -ErrorAction SilentlyContinue
    if ($srsProcesses) {
        foreach ($proc in $srsProcesses) {
            Write-Host "  SRS running (PID: $($proc.Id))" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  No SRS processes running" -ForegroundColor Green
    }
    Write-Host ""

    Read-Host "Press Enter to return to menu"
}

function Copy-RTMPUrlToClipboard {
    $rtmpUrl = "rtmp://$script:CurrentIP" + ":1935/live/srs"
    try {
        $rtmpUrl | Set-Clipboard
        Write-Host "✅ RTMP URL copied to clipboard!" -ForegroundColor Green
        Write-Host "📱 Paste this in your iPhone streaming app: $rtmpUrl" -ForegroundColor Yellow
    } catch {
        Write-Host "❌ Could not copy to clipboard. Manual copy:" -ForegroundColor Red
        Write-Host "$rtmpUrl" -ForegroundColor Yellow
    }
    Start-Sleep -Seconds 2
}

# Test IP address validity for iOS package
function Test-IPForIOSDeb {
    Clear-Host
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "   TEST IP ADDRESS FOR iOS PACKAGE" -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "  This tool validates if your IP is compatible with iOS packages." -ForegroundColor Gray
    Write-Host "  IP must be exactly 12 characters for binary patching." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  ────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "  Valid examples:" -ForegroundColor Green
    Write-Host "    ✓ 192.168.1.91  (12 chars)" -ForegroundColor White
    Write-Host "    ✓ 10.10.10.100  (12 chars)" -ForegroundColor White
    Write-Host "    ✓ 172.16.10.50  (12 chars)" -ForegroundColor White
    Write-Host ""
    Write-Host "  Invalid examples:" -ForegroundColor Red
    Write-Host "    ✗ 192.168.0.100 (13 chars - too long)" -ForegroundColor Gray
    Write-Host "    ✗ 192.168.1.1   (11 chars - too short)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  ────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""

    $testIP = Read-Host "  Enter IP to test (or 'cancel' to return)"

    if ($testIP -eq 'cancel' -or $testIP -eq '') {
        return
    }

    Write-Host ""
    Write-Host "  Testing IP: $testIP" -ForegroundColor Cyan
    Write-Host ""

    # Validate IP format
    $isValidFormat = $false
    try {
        $ipObj = [System.Net.IPAddress]::Parse($testIP)
        if ($ipObj.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
            $isValidFormat = $true
            Write-Host "  ✓ Valid IP format" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Not a valid IPv4 address" -ForegroundColor Red
        }
    } catch {
        Write-Host "  ✗ Invalid IP format" -ForegroundColor Red
        Write-Host "    Must be in format: xxx.xxx.xxx.xxx" -ForegroundColor Yellow
    }

    # Check length
    $ipLength = $testIP.Length
    Write-Host "  • Length: $ipLength characters" -ForegroundColor Cyan

    if ($ipLength -eq 12) {
        Write-Host "  ✓ Correct length (12 chars)" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Incorrect length (needs exactly 12 chars)" -ForegroundColor Red

        # Suggest valid formats
        if ($ipLength -lt 12) {
            Write-Host ""
            Write-Host "  💡 Suggestions to reach 12 chars:" -ForegroundColor Yellow
            $parts = $testIP -split '\.'
            if ($parts.Count -eq 4) {
                try {
                    $octets = @($parts[0], $parts[1], $parts[2], $parts[3]) | ForEach-Object { [int]$_ }

                    # Try padding last octet
                    if ($octets[3] -lt 10) {
                        $suggested1 = "$($octets[0]).$($octets[1]).$($octets[2]).$($octets[3].ToString().PadLeft(2,'0'))"
                        if ($suggested1.Length -eq 12) {
                            Write-Host "    → $suggested1" -ForegroundColor White
                        }
                    }

                    # Try padding middle octets
                    if ($octets[1] -ge 10 -and $octets[1] -lt 100 -and $octets[2] -lt 100 -and $octets[3] -lt 100) {
                        $suggested2 = "$($octets[0]).$($octets[1].ToString().PadLeft(2,'0')).$($octets[2].ToString().PadLeft(2,'0')).$($octets[3].ToString().PadLeft(2,'0'))"
                        if ($suggested2.Length -eq 12) {
                            Write-Host "    → $suggested2" -ForegroundColor White
                        }
                    }
                } catch {}
            }
        } elseif ($ipLength -gt 12) {
            Write-Host ""
            Write-Host "  ⚠️  IP too long - try using shorter octets:" -ForegroundColor Yellow
            Write-Host "    • Use single digits where possible (e.g., .1 instead of .100)" -ForegroundColor Gray
            Write-Host "    • Use double digits (e.g., .10 instead of .100)" -ForegroundColor Gray
        }
    }

    # Final verdict
    Write-Host ""
    Write-Host "  ────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""

    if ($isValidFormat -and $ipLength -eq 12) {
        Write-Host "  ✅ IP IS COMPATIBLE!" -ForegroundColor Green
        Write-Host "  This IP can be used to generate iOS packages." -ForegroundColor Green
    } else {
        Write-Host "  ❌ IP NOT COMPATIBLE" -ForegroundColor Red
        Write-Host "  Please use a different IP that meets the requirements." -ForegroundColor Red
    }

    Write-Host ""
}

# Helper function for debranded iOS build workflow
function Invoke-DebrandedIOSBuild {
    param(
        [string[]] $IPs
    )
    $iosDir = Join-Path $script:SRSHome "ios"
    Push-Location $iosDir
    try {
        if (-not (Test-Path "$iosDir\ios_debrand_end_to_end.py")) {
            Write-Host "  ❌ Missing ios_debrand_end_to_end.py in $iosDir" -ForegroundColor Red
            return
        }

        # Check if base exists and is valid
        $needsRebuild = $false
        if (-not (Test-Path "$iosDir\iosvcam_base.deb")) {
            Write-Host "  • Debranded base missing, building..." -ForegroundColor Yellow
            $needsRebuild = $true
        } else {
            # Validate base format (check for LZMA-alone vs XZ)
            Write-Host "  • Validating debranded base format..." -ForegroundColor Cyan
            $validateOutput = python .\validate_deb.py iosvcam_base.deb 2>&1 | Out-String
            if ($validateOutput -match "FAIL.*XZ container" -or $LASTEXITCODE -ne 0) {
                Write-Host "  ⚠️  Base exists but uses wrong compression format (XZ instead of LZMA)" -ForegroundColor Yellow
                Write-Host "  • Rebuilding base with correct iOS-compatible format..." -ForegroundColor Yellow
                $needsRebuild = $true
            } else {
                Write-Host "  ✓ Debranded base validated (correct LZMA-alone format)" -ForegroundColor Green
            }
        }

        if ($needsRebuild) {
            python .\ios_debrand_end_to_end.py --force-rebrand
            if ($LASTEXITCODE -ne 0) {
                Write-Host "  ❌ Failed creating debranded base." -ForegroundColor Red
                return
            }
            Write-Host "  ✓ Debranded base created successfully" -ForegroundColor Green
        }

        if (-not $IPs -or $IPs.Count -eq 0) {
            $ipInput = Read-Host "Enter one or more IPs separated by space"
            $IPs = $ipInput -split "\s+" | Where-Object { $_ -ne "" }
        }

        Write-Host "  • Generating variants for: $($IPs -join ', ')"
        python .\ios_debrand_end_to_end.py --ip $IPs
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  ❌ Variant generation failed." -ForegroundColor Red
            return
        }

        $modDir = Join-Path $iosDir "modified_debs"
        if (Test-Path $modDir) {
            $latest = Get-ChildItem $modDir -Filter "iosvcam_base_*.deb" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latest) {
                Write-Host ""
                Write-Host "  ✅ Package generated successfully!" -ForegroundColor Green
                Write-Host ""
                Write-Host "  📦 Package Details:" -ForegroundColor Cyan
                Write-Host "     File: $($latest.Name)" -ForegroundColor White
                $fileSize = [math]::Round(($latest.Length / 1KB), 2)
                Write-Host "     Size: $fileSize KB" -ForegroundColor Gray
                Write-Host "     Path: $($latest.FullName)" -ForegroundColor Gray
                Write-Host ""
                Write-Host "  📱 Installation Instructions:" -ForegroundColor Cyan
                Write-Host "     1. Transfer .deb file to your jailbroken iPhone" -ForegroundColor White
                Write-Host "     2. Install via Cydia, Sileo, Zebra, or Filza" -ForegroundColor White
                Write-Host "     3. Respring your device after installation" -ForegroundColor White
                Write-Host ""
            }
        }
    } finally {
        Pop-Location
    }
}

function Show-iOSDebCreator {
    Clear-Host
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "   CREATE iOS .DEB WITH CUSTOM IP (DEBRANDED MODE)" -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    # Show base status
    $iosDir = Join-Path $script:SRSHome "ios"
    $baseExists = Test-Path "$iosDir\iosvcam_base.deb"
    if ($baseExists) {
        Push-Location $iosDir
        $validateOutput = python .\validate_deb.py iosvcam_base.deb 2>&1 | Out-String
        Pop-Location
        if ($validateOutput -match "OK.*LZMA-alone") {
            Write-Host "  📦 Base Status: " -ForegroundColor Cyan -NoNewline
            Write-Host "Ready (LZMA format ✓)" -ForegroundColor Green
        } else {
            Write-Host "  📦 Base Status: " -ForegroundColor Cyan -NoNewline
            Write-Host "Needs rebuild (wrong format)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  📦 Base Status: " -ForegroundColor Cyan -NoNewline
        Write-Host "Not created yet" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "  ────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "  1) " -ForegroundColor White -NoNewline
    Write-Host "Generate IP-specific packages" -ForegroundColor White
    Write-Host "     Auto-validates & rebuilds base if needed" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  2) " -ForegroundColor White -NoNewline
    Write-Host "Force rebuild debranded base" -ForegroundColor White
    Write-Host "     Only needed if you want to start fresh" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  3) " -ForegroundColor White -NoNewline
    Write-Host "Validate base format" -ForegroundColor White
    Write-Host "     Check if base uses iOS-compatible LZMA" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  4) " -ForegroundColor Cyan -NoNewline
    Write-Host "Test IP address" -ForegroundColor Cyan
    Write-Host "     Check if your IP is compatible (12 chars)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  5) " -ForegroundColor Yellow -NoNewline
    Write-Host "Back" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  ────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    $sub = Read-Host "  Select option"
    switch ($sub) {
        '1' {
            Invoke-DebrandedIOSBuild
        }
        '2' {
            Push-Location (Join-Path $script:SRSHome "ios")
            python .\ios_debrand_end_to_end.py --force-rebrand
            Pop-Location
        }
        '3' {
            Push-Location (Join-Path $script:SRSHome "ios")
            python .\validate_deb.py iosvcam_base.deb
            Pop-Location
        }
        '4' {
            Test-IPForIOSDeb
        }
        default { }
    }
    Read-Host "Press Enter to continue"
}

function Get-CustomIPForDeb {
    Write-Host "📝 Enter Custom IP Address" -ForegroundColor Cyan
    Write-Host "────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "⚠️  IMPORTANT: IP must be EXACTLY 12 characters!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Valid examples:" -ForegroundColor Green
    Write-Host "  ✓ 192.168.0.99  `(12 chars`)" -ForegroundColor White
    Write-Host "  ✓ 192.168.1.50  `(12 chars`)" -ForegroundColor White
    Write-Host "  ✓ 192.168.50.9  `(12 chars - note single digit`)" -ForegroundColor White
    Write-Host ""
    Write-Host "Invalid examples:" -ForegroundColor Red
    Write-Host "  ✗ 192.168.0.100 `(13 chars - too long!`)" -ForegroundColor Gray
    Write-Host "  ✗ 192.168.50.232 `(14 chars - too long!`)" -ForegroundColor Gray
    Write-Host ""

    $customIP = Read-Host "Enter IP address (or 'cancel' to return)"

    if ($customIP -eq 'cancel') {
        return
    }

    # Validate IP format
    if ($customIP -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
        Write-Host ""
        Write-Host "❌ Invalid IP format!" -ForegroundColor Red
        Read-Host "Press Enter to try again"
        Get-CustomIPForDeb
        return
    }

    # Validate IP length
    $ipLength = $customIP.Length
    if ($ipLength -ne 12) {
        Write-Host ""
        Write-Host "❌ IP must be exactly 12 characters!" -ForegroundColor Red
        Write-Host "   Your IP: '$customIP' is $ipLength characters" -ForegroundColor Yellow

        if ($ipLength -lt 12) {
            Write-Host "   Try using two-digit octets (e.g., 192.168.01.01)" -ForegroundColor Cyan
        }
        else {
            Write-Host "   Use a shorter IP (e.g., single/double digit last octet)" -ForegroundColor Cyan
        }

        Read-Host "Press Enter to try again"
        Get-CustomIPForDeb
        return
    }

    # Validate IP octets
    $octets = $customIP -split '\.'
    foreach ($octet in $octets) {
        $num = [int]$octet
        if ($num -lt 0 -or $num -gt 255) {
            Write-Host ""
            Write-Host "❌ Invalid IP: octets must be 0-255!" -ForegroundColor Red
            Read-Host "Press Enter to try again"
            Get-CustomIPForDeb
            return
        }
    }

    Create-iOSDeb -IP $customIP
}

function Create-iOSDeb {
    param([string]$IP)

    Write-Host ""
    Write-Host "🔧 Creating iOS Package" -ForegroundColor Cyan
    Write-Host "────────────────────────" -ForegroundColor DarkGray
    Write-Host "Target IP: $IP" -ForegroundColor Yellow
    Write-Host ""

    # Show progress
    Write-Host "Processing:" -ForegroundColor White
    Write-Host "  • Extracting original package..." -ForegroundColor Gray -NoNewline

    # Run Python script with proper error handling
    $pythonOutput = ""
    $pythonError = ""

    try {
        # Use the scriptPath already determined in Show-iOSDebCreator
        $scriptPath = Join-Path $script:SRSHome "ios\ios_deb_ip_changer_final.py"
        if (-not (Test-Path $scriptPath)) {
            $scriptPath = Join-Path $script:SRSHome "ios_tools\ios_deb_ip_changer_final.py"
        }

        # Change to the script's directory for execution
        $scriptDir = Split-Path -Parent $scriptPath
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = "python"
        $processInfo.Arguments = "`"$scriptPath`" $IP"
        $processInfo.WorkingDirectory = $scriptDir
        $processInfo.UseShellExecute = $false
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.CreateNoWindow = $true

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        $process.Start() | Out-Null
        $process.WaitForExit()

        $pythonOutput = $process.StandardOutput.ReadToEnd()
        $pythonError = $process.StandardError.ReadToEnd()
        $exitCode = $process.ExitCode
    } catch {
        $pythonError = $_.Exception.Message
        $exitCode = 1
    }

    if ($exitCode -eq 0) {
        Write-Host " ✓" -ForegroundColor Green

        $safeName = $IP.Replace('.', '_')
        # Check multiple possible output locations
        $outputFile = Join-Path $scriptDir "modified_debs\iosvcam_base_$safeName.deb"
        if (-not (Test-Path $outputFile)) {
            # Try packages\modified_debs as fallback
            $outputFile = Join-Path $scriptDir "packages\modified_debs\iosvcam_base_$safeName.deb"
        }

        if (Test-Path $outputFile) {
            $fileSize = (Get-Item $outputFile).Length
            $fileSizeKB = [math]::Round($fileSize / 1024, 2)

            Write-Host ""
            Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
            Write-Host "                          ✅ SUCCESS!                                          " -ForegroundColor Green
            Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
            Write-Host ""
            Write-Host "📦 Package Details:" -ForegroundColor Cyan
            Write-Host "   File: iosvcam_base_$safeName.deb" -ForegroundColor White
            Write-Host "   Size: $fileSizeKB KB" -ForegroundColor Gray
            Write-Host "   Location: $outputFile" -ForegroundColor Gray
            Write-Host ""
            Write-Host "📱 Installation Instructions:" -ForegroundColor Cyan
            Write-Host "   1. Transfer the .deb file to your jailbroken iOS device" -ForegroundColor White
            Write-Host "   2. Install via Cydia, Sileo, Zebra, or dpkg" -ForegroundColor White
            Write-Host "   3. Configure your streaming app to use:" -ForegroundColor White
            Write-Host "      • Server IP: $IP" -ForegroundColor Yellow
            Write-Host "      • Port: 1935" -ForegroundColor Yellow
            Write-Host "      • RTMP URL: rtmp://$($IP):1935/live/srs" -ForegroundColor Yellow
        }
        else {
            Write-Host ""
            Write-Host "⚠️  Package created but file not found at expected location" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host " ✗" -ForegroundColor Red
        Write-Host ""
        Write-Host "❌ Failed to create package!" -ForegroundColor Red
        Write-Host ""

        if ($pythonError) {
            Write-Host "Error details:" -ForegroundColor Yellow
            Write-Host $pythonError -ForegroundColor Gray
        }
        if ($pythonOutput) {
            Write-Host "Output:" -ForegroundColor Yellow
            Write-Host $pythonOutput -ForegroundColor Gray
        }

        if ($pythonOutput -match "Could not find current IP" -or $pythonError -match "Could not find current IP") {
            Write-Host ""
            Write-Host "⚠️  The original package may be corrupted or incompatible" -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Read-Host "Press Enter to return to menu"
}

function Show-ConfigSelector {
    $config = Read-Config
    if ($config.StreamingServer -ne "srs") {
        return Show-MonibucaConfigSelector
    }

    do {
        try { Clear-Host } catch { }
        Show-SRSAsciiArt
        Write-Host ""
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Magenta
        Write-Host "                   ⚙️  IPHONE CONFIG SELECTOR                          " -BackgroundColor DarkMagenta -ForegroundColor White
        Write-Host "                    Select Config for Option [A]                       " -BackgroundColor DarkMagenta -ForegroundColor White
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Magenta
        Write-Host ""

        # Show currently selected config
        if ($script:SelectedConfig) {
            $currentConfigName = $script:SelectedConfig -replace "\.conf$", ""
            Write-Host "  ✅ Currently Selected: " -NoNewline -ForegroundColor Green
            Write-Host "$currentConfigName" -ForegroundColor Cyan
        } else {
            Write-Host "  ℹ️  Currently Selected: " -NoNewline -ForegroundColor Gray
            Write-Host "srs_iphone_ultra_smooth_dynamic (default)" -ForegroundColor Gray
        }
        Write-Host ""

        # Get iPhone-optimized configs
        $iphoneConfigs = @()
        $configPath = Join-Path $script:SRSHome "config\active"
        $configFiles = Get-ChildItem (Join-Path $configPath "srs_iphone*.conf") -ErrorAction SilentlyContinue

        if ($configFiles.Count -eq 0) {
            Write-Host "❌ No iPhone-optimized configs found in config\active\ directory" -ForegroundColor Red
            Read-Host "Press Enter to return to main menu"
            return
        }

        Write-Host "📱 Available iPhone-optimized configurations:" -ForegroundColor Cyan
        Write-Host ""

        # Analyze and display configs with descriptions
        for ($i = 0; $i -lt $configFiles.Count; $i++) {
            $config = $configFiles[$i]
            $description = Get-ConfigDescription $config.FullName
            $iphoneConfigs += @{
                Index = $i + 1
                File = $config.Name
                FullPath = $config.FullName
                Description = $description
            }

            $indexText = "[$($i + 1)]"
            $nameText = $config.Name -replace "\.conf$", ""
            
            # Highlight currently selected config
            if ($script:SelectedConfig -eq $config.Name) {
                Write-Host "    $($indexText.PadRight(4)) 📄 $nameText" -ForegroundColor Green -NoNewline
                Write-Host " ✓ SELECTED" -ForegroundColor Green
            } else {
                Write-Host "    $($indexText.PadRight(4)) 📄 $nameText" -ForegroundColor Yellow
            }
            Write-Host "         $description" -ForegroundColor Gray
            Write-Host ""
        }

        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
        Write-Host "                         🎮 OPTIONS                                  " -BackgroundColor DarkGray -ForegroundColor White
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  [1-$($configFiles.Count)] Select a config to view/choose" -ForegroundColor White
        Write-Host "  [F] 🔄 AUTO-FIX IP ADDRESSES in all configs" -ForegroundColor White
        Write-Host "  [B] ← BACK to main menu" -ForegroundColor White
        Write-Host ""
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
        Write-Host ""

        $choice = Read-Host "Enter your choice"

        if ([string]::IsNullOrEmpty($choice)) {
            $choice = "B"
        }

        # Handle numeric choices - show config details submenu
        if ($choice -match "^\d+$") {
            $index = [int]$choice - 1
            if ($index -ge 0 -and $index -lt $configFiles.Count) {
                $selectedConfig = $iphoneConfigs[$index]
                Show-ConfigDetailsMenu $selectedConfig
            } else {
                Write-Host "❌ Invalid selection. Choose 1-$($configFiles.Count)" -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
            continue
        }

        # Handle letter choices
        switch ($choice.ToUpper()) {
            "F" {
                Write-Host "🔧 Auto-fixing IP addresses in all iPhone configs..." -ForegroundColor Yellow
                Fix-AllConfigIPs $configFiles
                Write-Host ""
                Read-Host "Press Enter to continue"
            }
            "B" { return }
            default {
                Write-Host "❌ Invalid choice. Try again." -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    } while ($true)
}

function Show-MonibucaConfigSelector {
    do {
        try { Clear-Host } catch { }
        Show-SRSAsciiArt
        Write-Host ""
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Magenta
        Write-Host "                   ⚙️  MONIBUCA PROFILE SELECTOR                        " -BackgroundColor DarkMagenta -ForegroundColor White
        Write-Host "                    Select Profile for Option [A]                       " -BackgroundColor DarkMagenta -ForegroundColor White
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Magenta
        Write-Host ""

        $config = Read-Config
        $currentProfile = $config.MonibucaConfig
        if ([string]::IsNullOrWhiteSpace($currentProfile)) {
            $currentProfile = "monibuca_iphone_optimized.yaml"
        }

        Write-Host "  ✅ Currently Selected: " -NoNewline -ForegroundColor Green
        Write-Host ($currentProfile -replace "\.ya?ml$", "") -ForegroundColor Cyan
        Write-Host ""

        $profiles = @(
            @{ Key = "1"; File = "monibuca_iphone_optimized.yaml"; Desc = "Smooth (more buffer/lag)" },
            @{ Key = "2"; File = "monibuca_iphone_balanced.yaml"; Desc = "Balanced" },
            @{ Key = "3"; File = "monibuca_iphone_low_latency.yaml"; Desc = "Low latency (more stutter risk)" }
        )

        Write-Host "📱 Available Monibuca profiles:" -ForegroundColor Cyan
        Write-Host ""

        foreach ($p in $profiles) {
            $path = Join-Path $script:SRSHome ("conf\\" + $p.File)
            $nameText = $p.File -replace "\.ya?ml$", ""
            if ($p.File -eq $currentProfile) {
                Write-Host "    [$($p.Key)] 📄 $nameText" -ForegroundColor Green -NoNewline
                Write-Host " ✓ SELECTED" -ForegroundColor Green
            } else {
                Write-Host "    [$($p.Key)] 📄 $nameText" -ForegroundColor Yellow
            }
            Write-Host "         $($p.Desc)" -ForegroundColor Gray
            if (-not (Test-Path $path)) {
                Write-Host "         (missing file: conf\\$($p.File))" -ForegroundColor DarkYellow
            }
            Write-Host ""
        }

        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
        Write-Host "                         🎮 OPTIONS                                  " -BackgroundColor DarkGray -ForegroundColor White
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  [1-3] Select a profile" -ForegroundColor White
        Write-Host "  [B] ← BACK to main menu" -ForegroundColor White
        Write-Host ""

        $choice = Read-Host "Enter your choice"
        if ([string]::IsNullOrEmpty($choice)) {
            $choice = "B"
        }

        switch ($choice.ToUpper()) {
            "1" { $selected = $profiles[0].File }
            "2" { $selected = $profiles[1].File }
            "3" { $selected = $profiles[2].File }
            "B" { return }
            default {
                Write-Host "❌ Invalid choice. Try again." -ForegroundColor Red
                Start-Sleep -Seconds 1
                continue
            }
        }

        $selectedPath = Join-Path $script:SRSHome ("conf\\" + $selected)
        if (-not (Test-Path $selectedPath)) {
            Write-Host "❌ Missing profile file: conf\\$selected" -ForegroundColor Red
            Read-Host "Press Enter to continue"
            continue
        }

        $config.MonibucaConfig = $selected
        Write-Config $config
        Write-Host "";
        Write-Host "✅ Monibuca profile set to: $($selected -replace '\\.ya?ml$', '')" -ForegroundColor Green
        Read-Host "Press Enter to return to main menu"
        return
    } while ($true)
}

function Show-ConfigDetailsMenu {
    param($configInfo)
    
    do {
        try { Clear-Host } catch { }
        Show-SRSAsciiArt
        Write-Host ""
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
        Write-Host "                    📋 CONFIG DETAILS                                   " -BackgroundColor DarkCyan -ForegroundColor White
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
        Write-Host ""
        
        $configName = $configInfo.File -replace "\.conf$", ""
        Write-Host "  📄 Config: " -NoNewline -ForegroundColor White
        Write-Host "$configName" -ForegroundColor Yellow
        Write-Host "  📝 Description: $($configInfo.Description)" -ForegroundColor Gray
        Write-Host ""
        
        # Check if this is currently selected
        if ($script:SelectedConfig -eq $configInfo.File) {
            Write-Host "  ✅ This config is CURRENTLY SELECTED" -ForegroundColor Green
        }
        Write-Host ""
        
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
        Write-Host "                         🎮 OPTIONS                                  " -BackgroundColor DarkGray -ForegroundColor White
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  [S] ✅ SELECT this config (for use with Option [A])" -ForegroundColor Green
        Write-Host "  [V] 📊 VIEW detailed properties table" -ForegroundColor White
        Write-Host "  [T] 🧪 TEST this config (launches SRS immediately)" -ForegroundColor Yellow
        Write-Host "  [B] ← BACK to config list" -ForegroundColor White
        Write-Host ""
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
        Write-Host ""
        
        $choice = Read-Host "Enter your choice"
        
        switch ($choice.ToUpper()) {
            "S" {
                # Select this config
                $script:SelectedConfig = $configInfo.File
                $script:SelectedConfigPath = $configInfo.FullPath

                # Update and persist config
                $config = Read-Config
                $config.LastUsedConfig = $script:SelectedConfig
                Write-Config $config

                # LOG: Write to file for debugging
                $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                $logMsg = @"
[$timestamp] CONFIG SELECTION
  - SelectedConfig = "$script:SelectedConfig"
  - SelectedConfigPath = "$script:SelectedConfigPath"
  - Path exists = $(Test-Path $script:SelectedConfigPath)
  - Config persisted to = $script:ConfigFile
"@
                Add-Content -Path $script:LogFile -Value $logMsg -Force

                Write-Host ""
                Write-Host "  [DEBUG] Config selection logged to: $script:LogFile" -ForegroundColor Yellow
                Write-Host ""

                Write-Host ""
                Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
                Write-Host "  ✅ CONFIG SELECTED & SAVED SUCCESSFULLY!" -ForegroundColor Green
                Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
                Write-Host ""
                Write-Host "  Selected: $configName" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "  This config will be used when you launch Option [A]" -ForegroundColor White
                Write-Host "  (Combined Flask + SRS Server)" -ForegroundColor Gray
                Write-Host ""
                Read-Host "Press Enter to return to main menu"
                return "SELECTED"
            }
            "V" {
                # Show detailed properties
                Show-ConfigProperties $configInfo.FullPath
            }
            "T" {
                # Test config (old behavior - launches SRS)
                Test-ConfigWithIPFix $configInfo
                return "TESTED"
            }
            "B" { return "BACK" }
            default {
                Write-Host "❌ Invalid choice. Try again." -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    } while ($true)
}

function Show-ConfigProperties {
    param([string]$configPath)
    
    try { Clear-Host } catch { }
    Show-SRSAsciiArt
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "                    📊 CONFIG PROPERTIES TABLE                            " -BackgroundColor DarkCyan -ForegroundColor White
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""
    
    $configName = (Split-Path -Leaf $configPath) -replace "\.conf$", ""
    $description = Get-ConfigDescription $configPath

    Write-Host "  📄 Config: $configName" -ForegroundColor Yellow
    Write-Host "  📝 Description: $description" -ForegroundColor Gray
    Write-Host ""
    
    try {
        $content = Get-Content $configPath -Raw -ErrorAction Stop
        
        # Parse key settings
        $settings = @{
            "HLS Fragment" = if ($content -match "hls_fragment\s+(\d+(\.\d+)?)") { "$($matches[1])s" } else { "N/A" }
            "HLS Window" = if ($content -match "hls_window\s+(\d+)") { "$($matches[1]) fragments" } else { "N/A" }
            "Queue Length" = if ($content -match "queue_length\s+(\d+)") { "$($matches[1]) frames" } else { "N/A" }
            "Target Latency" = if ($content -match "mw_latency\s+(\d+)") { "$($matches[1])ms" } else { "N/A" }
            "Chunk Size" = if ($content -match "chunk_size\s+(\d+)") { "$($matches[1]) bytes" } else { "N/A" }
            "GOP Cache" = if ($content -match "gop_cache\s+(on|off)") { $matches[1] } else { "N/A" }
            "TCP No Delay" = if ($content -match "tcp_nodelay\s+(on|off)") { $matches[1] } else { "N/A" }
            "Min Latency Mode" = if ($content -match "min_latency\s+(on|off)") { $matches[1] } else { "N/A" }
            "Time Jitter" = if ($content -match "time_jitter\s+(\w+)") { $matches[1] } else { "N/A" }
            "ATC Mode" = if ($content -match "atc\s+(on|off)") { $matches[1] } else { "N/A" }
            "Mix Correct" = if ($content -match "mix_correct\s+(on|off)") { $matches[1] } else { "N/A" }
            "First Pkt Timeout" = if ($content -match "firstpkt_timeout\s+(\d+)") { "$($matches[1])ms" } else { "N/A" }
            "Normal Timeout" = if ($content -match "normal_timeout\s+(\d+)") { "$($matches[1])ms" } else { "N/A" }
            "Parse SPS" = if ($content -match "parse_sps\s+(on|off)") { $matches[1] } else { "N/A" }
            "Merged Read" = if ($content -match "\bmr\s+(on|off)") { $matches[1] } else { "N/A" }
            "MW Msgs" = if ($content -match "mw_msgs\s+(\d+)") { "$($matches[1])" } else { "N/A" }
            "Timestamp Correct" = if ($content -match "timestamp_correct\s+(on|off)") { $matches[1] } else { "N/A" }
            "Ack Size" = if ($content -match "in_ack_size\s+(\d+)") { "$($matches[1])" } else { "N/A" }
        }
        
        # Display as table
        Write-Host "  ┌─────────────────────────┬──────────────────┐" -ForegroundColor Gray
        Write-Host "  │       SETTING           │      VALUE       │" -ForegroundColor White
        Write-Host "  ├─────────────────────────┼──────────────────┤" -ForegroundColor Gray
        
        foreach ($key in ($settings.Keys | Sort-Object)) {
            $value = $settings[$key]
            # Skip N/A values to keep table clean, or keep them? 
            # User output had some N/A, so we keep them if important or skip?
            # User output had "ATC Mode N/A", so we keep.
            
            $keyPadded = $key.PadRight(23)
            $valuePadded = $value.PadRight(16)
            
            # Color code based on latency impact
            $valueColor = "White"
            if ($key -eq "Queue Length") {
                if ($value -match "^\d+") {
                    $num = [int]($value -replace "[^\d]", "")
                    if ($num -le 1) { $valueColor = "Yellow" }  # Ultra-low latency
                    elseif ($num -le 5) { $valueColor = "Cyan" }  # Low latency
                    else { $valueColor = "Green" }  # Stable/smooth
                }
            }
            if ($key -eq "Target Latency") {
                if ($value -match "^\d+") {
                    $num = [int]($value -replace "[^\d]", "")
                    if ($num -le 100) { $valueColor = "Yellow" }
                    elseif ($num -le 300) { $valueColor = "Cyan" }
                    else { $valueColor = "Green" }
                }
            }
            if ($key -eq "GOP Cache" -and $value -eq "on") { $valueColor = "Green" }
            if ($key -eq "Min Latency Mode" -and $value -eq "on") { $valueColor = "Yellow" }
            if ($key -eq "Parse SPS" -and $value -eq "on") { $valueColor = "Green" }
            
            Write-Host "  │ " -NoNewline -ForegroundColor Gray
            Write-Host "$keyPadded" -NoNewline -ForegroundColor White
            Write-Host "│ " -NoNewline -ForegroundColor Gray
            Write-Host "$valuePadded" -NoNewline -ForegroundColor $valueColor
            Write-Host "│" -ForegroundColor Gray
        }
        
        Write-Host "  └─────────────────────────┴──────────────────┘" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  🎨 Color Legend:" -ForegroundColor White
        Write-Host "     Yellow = Ultra-low latency (may be choppy)" -ForegroundColor Yellow
        Write-Host "     Cyan   = Low latency (balanced)" -ForegroundColor Cyan
        Write-Host "     Green  = Smooth/stable (higher latency)" -ForegroundColor Green
        
    } catch {
        Write-Host "  ❌ Error reading config: $_" -ForegroundColor Red
    }
    
    Write-Host ""
    Read-Host "Press Enter to go back"
}

function Get-ConfigDescription($configPath) {
    try {
        $content = Get-Content $configPath -First 10 -ErrorAction SilentlyContinue
        $comment = $content | Where-Object { $_ -match "^#.*" } | Select-Object -First 1

        # Extract description from comment or analyze config
        if ($comment) {
            $desc = $comment -replace "^#\s*", "" -replace "SRS Configuration\s*-?\s*", ""
            if ($desc.Length -gt 60) { $desc = $desc.Substring(0, 60) + "..." }
            return $desc
        }

        # Analyze key settings if no comment
        $fullContent = Get-Content $configPath -Raw -ErrorAction SilentlyContinue
        if ($fullContent -match "queue_length\s+(\d+)") {
            $queueLength = $matches[1]
            if ([int]$queueLength -le 1) { return "🏎️ Ultra-low latency (aggressive settings)" }
            elseif ([int]$queueLength -le 5) { return "⚡ Low latency optimized" }
            elseif ([int]$queueLength -le 10) { return "⚖️ Balanced latency vs stability" }
            else { return "🛡️ Maximum stability (high buffering)" }
        }

        return "📄 iPhone optimized configuration"
    } catch {
        return "📄 Configuration file"
    }
}

function Test-ConfigWithIPFix($configInfo) {
    try { Clear-Host } catch { }
    Show-SRSAsciiArt
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    Write-Host "                    🧪 TESTING CONFIGURATION                           " -BackgroundColor DarkGreen -ForegroundColor White
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    Write-Host ""
    Write-Host "🔧 Config: $($configInfo.File)" -ForegroundColor Cyan
    Write-Host "📝 Description: $($configInfo.Description)" -ForegroundColor White
    Write-Host ""

    # Check if config has correct IP
    Write-Host "`[STEP 1/4] 🔍 Checking IP configuration..." -ForegroundColor Yellow
    $configNeedsUpdate = Test-ConfigIPUpdate $configInfo.FullPath

    if ($configNeedsUpdate) {
        Write-Host "  ⚠️ Config has outdated IP addresses" -ForegroundColor Yellow
        Write-Host "  🔧 Auto-fixing IP to current: $script:CurrentIP" -ForegroundColor Cyan

        if (Update-ConfigIP $configInfo.FullPath) {
            Write-Host "  ✅ IP addresses updated successfully" -ForegroundColor Green
        } else {
            Write-Host "  ❌ Failed to update IP - proceeding with existing config" -ForegroundColor Red
        }
    } else {
        Write-Host "  ✅ IP configuration is current" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "`[STEP 2/4] 🧹 Cleaning up ports..." -ForegroundColor Yellow
    Clear-SRSPorts

    Write-Host "`[STEP 3/4] 📋 Configuration summary..." -ForegroundColor Yellow
    Show-ConfigSummary $configInfo.FullPath

    Write-Host "`[STEP 4/4] 🚀 Starting SRS server..." -ForegroundColor Yellow
    Write-Host ""

    Start-SRSServer $configInfo.FullPath
}

function Test-ConfigIPUpdate($configPath) {
    try {
        $content = Get-Content $configPath -Raw -ErrorAction SilentlyContinue
        # Check if config contains different IP than current
        if ($content -match "listen\s+(\d+\.\d+\.\d+\.\d+):") {
            $configIP = $matches[1]
            return ($configIP -ne $script:CurrentIP)
        }
        # If no IP found, assume it needs updating
        return $true
    } catch {
        return $true
    }
}

function Update-ConfigIP($configPath) {
    try {
        $content = Get-Content $configPath -Raw -Encoding UTF8
        $originalContent = $content

        # Replace IP addresses in listen directives
        $content = $content -replace 'listen\s+(\d+\.\d+\.\d+\.\d+):', "listen              $script:CurrentIP:"
        $content = $content -replace 'listen\s+(\d+\.\d+\.\d+\.\d+);', "listen              $script:CurrentIP;"

        # Replace IP addresses in http_api and http_server sections
        $content = $content -replace 'listen\s+(\d+\.\d+\.\d+\.\d+):(\d+);', "listen          $script:CurrentIP:`$2;"

        # Also handle any standalone IP addresses
        $content = $content -replace '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b', $script:CurrentIP

        # Only write if content actually changed
        if ($content -ne $originalContent) {
            $content | Set-Content $configPath -Encoding UTF8 -NoNewline
        }
        return $true
    } catch {
        Write-Host "    Error details: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Show-ConfigSummary($configPath) {
    try {
        $content = Get-Content $configPath -Raw -ErrorAction SilentlyContinue

        # Extract key settings
        $settings = @{}
        if ($content -match "queue_length\s+(\d+)") { $settings["Buffer Size"] = "$($matches[1]) frames" }
        if ($content -match "mw_latency\s+(\d+)") { $settings["Target Latency"] = "$($matches[1])ms" }
        if ($content -match "hls_fragment\s+(\d+)") { $settings["HLS Fragment"] = "$($matches[1])s" }
        if ($content -match "chunk_size\s+(\d+)") { $settings["Chunk Size"] = "$($matches[1]) bytes" }
        if ($content -match "gop_cache\s+(on|off)") { $settings["GOP Cache"] = $matches[1] }
        if ($content -match "min_latency\s+(on|off)") { $settings["Low Latency Mode"] = $matches[1] }

        Write-Host "  📊 Key Settings:" -ForegroundColor Cyan
        foreach ($setting in $settings.GetEnumerator()) {
            Write-Host "     $($setting.Key): $($setting.Value)" -ForegroundColor White
        }
    } catch {
        Write-Host "  ⚠️ Could not analyze config settings" -ForegroundColor Yellow
    }
}

function Fix-AllConfigIPs($configFiles) {
    $fixed = 0
    foreach ($config in $configFiles) {
        if (Test-ConfigIPUpdate $config.FullPath) {
            if (Update-ConfigIP $config.FullPath) {
                Write-Host "  ✅ Fixed: $($config.Name)" -ForegroundColor Green
                $fixed++
            } else {
                Write-Host "  ❌ Failed: $($config.Name)" -ForegroundColor Red
            }
        } else {
            Write-Host "  ℹ️ Current: $($config.Name)" -ForegroundColor Gray
        }
    }
    Write-Host ""
    Write-Host "🎯 Fixed $fixed configuration files with IP: $script:CurrentIP" -ForegroundColor Green
}

function Show-ConfigurationSettings {
    try { Clear-Host } catch { }
    Show-SRSAsciiArt
    Write-Host ""
    Write-Host "    " -NoNewline
    Write-Host "╔═══════════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Blue
    Write-Host "    " -NoNewline
    Write-Host "║                             ⚙️  CONFIGURATION SETTINGS                                ║" -BackgroundColor DarkBlue -ForegroundColor White
    Write-Host "    " -NoNewline
    Write-Host "╚═══════════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Blue
    Write-Host ""

    $config = Read-Config

    Write-Host "  📊 Current Configuration:" -ForegroundColor Green
    Write-Host ""
    Write-Host "  🌐 Preferred Adapter: " -NoNewline -ForegroundColor White
    if ($config.PreferredAdapter -ne "") {
        Write-Host "$($config.PreferredAdapter)" -ForegroundColor Cyan
    } else {
        Write-Host "Auto-detect" -ForegroundColor Yellow
    }

    Write-Host "  📍 Preferred IP: " -NoNewline -ForegroundColor White
    if ($config.PreferredIP -ne "") {
        Write-Host "$($config.PreferredIP)" -ForegroundColor Cyan
    } else {
        Write-Host "Auto-detect" -ForegroundColor Yellow
    }

    Write-Host "  🔄 Auto Network Detection: " -NoNewline -ForegroundColor White
    if ($config.AutoDetectNetwork -eq "true") {
        Write-Host "Enabled" -ForegroundColor Green
    } else {
        Write-Host "Disabled" -ForegroundColor Red
    }

    Write-Host "  📁 Last Used Config: " -NoNewline -ForegroundColor White
    Write-Host "$($config.LastUsedConfig)" -ForegroundColor Cyan

    Write-Host "  📺 Streaming Server: " -NoNewline -ForegroundColor White
    if ($config.StreamingServer -eq "srs") {
        Write-Host "SRS (Legacy)" -ForegroundColor Cyan
    } else {
        Write-Host "MONIBUCA (Default)" -ForegroundColor Magenta
    }
    Write-Host ""

    Write-Host "    " -NoNewline
    Write-Host "╔═══════════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "    " -NoNewline
    Write-Host "║                                🔧 CONFIGURATION OPTIONS                               ║" -BackgroundColor DarkGreen -ForegroundColor White
    Write-Host "    " -NoNewline
    Write-Host "╚═══════════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""

    Write-Host "  [1] 🌐 SELECT NETWORK ADAPTER" -ForegroundColor White
    Write-Host "      • Choose your preferred network adapter" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  [2] 🔄 TOGGLE AUTO-DETECTION" -ForegroundColor White
    Write-Host "      • Enable/disable automatic network detection" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  [3] 🧹 RESET TO DEFAULTS" -ForegroundColor White
    Write-Host "      • Clear all saved preferences" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  [4] 📺 STREAMING SERVER ENGINE" -ForegroundColor White
    Write-Host "      • Switch between Monibuca and SRS" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  [B] ← BACK TO MAIN MENU" -ForegroundColor White
    Write-Host ""
    Write-Host "    " -NoNewline
    Write-Host "╚═══════════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor DarkGray
    Write-Host ""

    do {
        $choice = Read-Host "Choose option [1-4, B]"

        switch ($choice.ToUpper()) {
            "1" {
                $selectedAdapter = Show-NetworkAdapterSelection
                if ($selectedAdapter) {
                    $config.PreferredAdapter = $selectedAdapter.Name
                    $config.PreferredIP = $selectedAdapter.IP
                    $config.AutoDetectNetwork = "false"
                    Write-Config $config

                    # Update current session
                    $script:WiFiAdapter = $selectedAdapter.Name
                    $script:CurrentIP = $selectedAdapter.IP
                    $script:NetworkStatus = "Connected ($($selectedAdapter.Name))"

                    Write-Host ""
                    Write-Host "  ✅ Network adapter preference saved!" -ForegroundColor Green
                    Read-Host "Press Enter to continue"
                }
                return Show-ConfigurationSettings
            }
            "2" {
                if ($config.AutoDetectNetwork -eq "true") {
                    $config.AutoDetectNetwork = "false"
                    Write-Host ""
                    Write-Host "  🔒 Auto-detection disabled. Using preferred adapter." -ForegroundColor Yellow
                } else {
                    $config.AutoDetectNetwork = "true"
                    Write-Host ""
                    Write-Host "  🔄 Auto-detection enabled. Will scan for network adapter." -ForegroundColor Green
                }
                Write-Config $config
                Read-Host "Press Enter to continue"
                return Show-ConfigurationSettings
            }
            "3" {
                Write-Host ""
                Write-Host "  ⚠️  This will reset all configuration settings to defaults." -ForegroundColor Yellow
                $confirm = Read-Host "Are you sure? [Y/N]"
                if ($confirm.ToUpper() -eq "Y") {
                    if (Test-Path $script:ConfigFile) {
                        Remove-Item $script:ConfigFile
                    }
                    Write-Host "  ✅ Configuration reset to defaults!" -ForegroundColor Green
                    Read-Host "Press Enter to continue"
                    return
                }
                return Show-ConfigurationSettings
            }
            "4" {
                Write-Host ""
                Write-Host "  📺 SELECT STREAMING SERVER ENGINE:" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "  [M] 🚀 MONIBUCA (Recommended)" -ForegroundColor Magenta
                Write-Host "      • Modern, low-latency media server" -ForegroundColor Gray
                Write-Host "      • Better performance for iPhone streaming" -ForegroundColor Gray
                Write-Host ""
                Write-Host "  [S] 📺 SRS (Legacy)" -ForegroundColor Cyan
                Write-Host "      • Original SRS-based streaming" -ForegroundColor Gray
                Write-Host "      • Use if you encounter issues with Monibuca" -ForegroundColor Gray
                Write-Host ""

                $engineChoice = Read-Host "Select engine [M/S]"

                switch ($engineChoice.ToUpper()) {
                    "M" {
                        $config.StreamingServer = "monibuca"
                        Write-Config $config
                        Write-Host ""
                        Write-Host "  ✅ Streaming engine set to MONIBUCA" -ForegroundColor Green
                    }
                    "S" {
                        $config.StreamingServer = "srs"
                        Write-Config $config
                        Write-Host ""
                        Write-Host "  ✅ Streaming engine set to SRS" -ForegroundColor Green
                    }
                    default {
                        Write-Host "  ❌ Invalid choice" -ForegroundColor Red
                    }
                }
                Read-Host "Press Enter to continue"
                return Show-ConfigurationSettings
            }
            "B" {
                return
            }
            default {
                Write-Host "  ❌ Invalid choice. Please try again." -ForegroundColor Red
            }
        }
    } while ($true)
}

# Main execution
try {
    Write-Log "=== SRS Launcher Started ==="
    Write-Log "PowerShell Version: $($PSVersionTable.PSVersion)"
    Write-Log "Operating System: $([System.Environment]::OSVersion.VersionString)"

    # Check for first launch
    $config = Read-Config
    
    # Restore last used config
    if ($config.LastUsedConfig) {
        $script:SelectedConfig = $config.LastUsedConfig
        # Try to resolve full path
        $potentialPath = Join-Path $script:SRSHome "config\active\$($script:SelectedConfig)"
        if (Test-Path $potentialPath) {
            $script:SelectedConfigPath = $potentialPath
        }
    }

    if ($script:IsFirstLaunch -or $config.FirstLaunchCompleted -eq "false") {
        try { Clear-Host } catch { }
        Show-SRSAsciiArt
        Write-Host ""
        Write-Host "    " -NoNewline
        Write-Host "╔═══════════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "    " -NoNewline
        Write-Host "║                               🎉 WELCOME TO SRS LAUNCHER!                             ║" -BackgroundColor DarkGreen -ForegroundColor White
        Write-Host "    " -NoNewline
        Write-Host "╚═══════════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
        Write-Host ""
        Write-Host "  🎯 This appears to be your first time running SRS Launcher!" -ForegroundColor Cyan
        Write-Host "  📡 Let's configure your preferred network adapter for optimal streaming." -ForegroundColor White
        Write-Host ""
        Write-Host "  💡 You can change these settings anytime from the Configuration menu." -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to continue with network setup"

        $selectedAdapter = Show-NetworkAdapterSelection
        if ($selectedAdapter) {
            $config.PreferredAdapter = $selectedAdapter.Name
            $config.PreferredIP = $selectedAdapter.IP
            $config.AutoDetectNetwork = "false"
            $config.FirstLaunchCompleted = "true"
            Write-Config $config

            try { Clear-Host } catch { }
            Show-SRSAsciiArt
            Write-Host ""
            Write-Host "    " -NoNewline
            Write-Host "╔═══════════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
            Write-Host "    " -NoNewline
            Write-Host "║                                ✅ SETUP COMPLETE!                                     ║" -BackgroundColor DarkGreen -ForegroundColor White
            Write-Host "    " -NoNewline
            Write-Host "╚═══════════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
            Write-Host ""
            Write-Host "  🎉 Network adapter configured successfully!" -ForegroundColor Green
            Write-Host "  📡 Selected: $($selectedAdapter.Name)" -ForegroundColor Cyan
            Write-Host "  🌐 IP Address: $($selectedAdapter.IP)" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  🚀 SRS Launcher is now ready to use!" -ForegroundColor White
            Write-Host ""
            Read-Host "Press Enter to continue to main menu"
        } else {
            $config.FirstLaunchCompleted = "true"
            $config.AutoDetectNetwork = "true"
            Write-Config $config
        }
    }

    Get-NetworkInfo

    do {
        Show-MainMenu
        $choice = Read-Host "Choose option [A, B, 1, 3-9, U, C, Q]"

        if ([string]::IsNullOrEmpty($choice)) {
            $choice = "Q"
        }

        try {
            switch ($choice.ToUpper()) {
                "A" { Start-CombinedFlaskAndSRS }
                "B" { Start-CombinedFlaskAndSRS-SRS }  # Legacy SRS mode (direct, bypasses engine check)
                "1" { Start-FlaskAuthServer }
                "3" { Show-ConfigSelector }
                "4" { Show-SystemDiagnostics }
                "5" {
                    Write-Host "Cleaning up ports..." -ForegroundColor Yellow
                    Clear-SRSPorts
                    Read-Host "Press Enter to continue"
                }
                "6" { Get-NetworkInfo; Read-Host "Network detection refreshed. Press Enter to continue" }
                "7" { Copy-RTMPUrlToClipboard }
                "8" { Show-iOSDebCreator }
                "9" { Show-USBValidation }
                "U" { Start-MonibucaViaSshUsb }
                "C" { Show-ConfigurationSettings }
                "Q" {
                    Write-Host ""
                    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
                    Write-Host "                     🎉 Thank you for using SRS Ultimate Launcher!                      " -BackgroundColor DarkGreen -ForegroundColor White
                    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
                    Write-Host ""
                    exit 0
                }
                default {
                    Write-Host ""
                    Write-Host "  ❌ Invalid choice '$choice'. Please select a valid option." -ForegroundColor Red
                    Write-Host ""
                    Start-Sleep -Seconds 2
                }
            }
        } catch {
            Write-Host ""
            Write-Host "  ⚠️ Error executing menu option '$choice':" -ForegroundColor Yellow
            Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ""
            Write-Host "  💡 Try selecting a different option or restart the launcher." -ForegroundColor Cyan
            Write-Host ""
            Read-Host "Press Enter to continue"
        }
    } while ($true)

} catch {
    Write-CrashLog "CRITICAL ERROR" $_
    try { Clear-Host } catch { }
    Show-SRSAsciiArt
    Write-Host ""
    Write-Host "    ╔═══════════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "    ║                                ❌ CRITICAL ERROR                                       ║" -BackgroundColor DarkRed -ForegroundColor White
    Write-Host "    ╚═══════════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host ""
    Write-Host "  🚨 An unexpected error occurred in the SRS Launcher:" -ForegroundColor Red
    Write-Host ""
    Write-Host "  📝 Error Details:" -ForegroundColor Yellow
    Write-Host "     $($_.Exception.Message)" -ForegroundColor White
    Write-Host ""
    Write-Host "  🧾 Crash log: $script:CrashLog" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  💡 Troubleshooting Tips:" -ForegroundColor Cyan
    Write-Host "     • Try running the launcher as Administrator" -ForegroundColor White
    Write-Host "     • Ensure all SRS files are in the correct directory" -ForegroundColor White
    Write-Host "     • Check that no antivirus is blocking the launcher" -ForegroundColor White
    Write-Host "     • Verify PowerShell execution policy allows scripts" -ForegroundColor White
    Write-Host ""
    Write-Host "  🔧 Quick Fix Commands:" -ForegroundColor Cyan
    Write-Host "     PowerShell execution policy: Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  📧 If the problem persists, report this error with the details above." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    ╚═══════════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor DarkGray
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}
