# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

iOS-VCAM-v4.1 is a Windows RTMP streaming server distribution for jailbroken iPhones. It bundles SRS (Simple Realtime Server) v5.0.213 with a PowerShell launcher, iPhone-optimized configurations, and iOS .deb package tools for IP injection and debranding.

## Commands

### Building & Running
```powershell
# Compile launcher to EXE (downloads ps2exe if needed)
pwsh -ExecutionPolicy Bypass -File compile-v4.1.ps1

# Run launcher
.\iOS-VCAM-Launcher.bat              # Primary method
.\iOS-VCAM-Launcher.exe              # Compiled EXE
powershell -ExecutionPolicy Bypass -File iOS-VCAM-Launcher.ps1

# Flask auth server (required for iOS app pairing)
python server.py --host 0.0.0.0
```

### Testing
```powershell
# Quick smoke test - verify launcher stays alive
pwsh -ExecutionPolicy Bypass -File misc/test-scripts/quick-test.ps1

# Structural verification (EXE, configs, binaries)
pwsh -ExecutionPolicy Bypass -File misc/test-scripts/test-launcher.ps1

# Validate .deb package structure
python ios/validate_deb.py ios/modified_debs/<file>.deb
```

### iOS Package Operations
```bash
# Create debranded base + IP variant
python ios/ios_debrand_end_to_end.py --ip 192.168.1.100

# Generate IP variant from existing base
python ios/ios_deb_ip_changer_final.py --base ios/iosvcam_base.deb 192.168.1.100
```

### Stream Testing
```bash
# Publish test stream
ffmpeg -re -i test.mp4 -c copy -f flv rtmp://localhost:1935/live/srs

# Web player
start http://localhost:8080/players/srs_player.html
```

## Architecture

### Core Components

1. **PowerShell Launcher (`iOS-VCAM-Launcher.ps1`)** - ~2150 lines
   - Network adapter detection with IP monitoring
   - Dynamic IP replacement (regex-based, replaces hardcoded IPs in configs)
   - Interactive menu with server status
   - Process management for SRS and Flask

2. **SRS Media Server (`objs/srs.exe`)**
   - RTMP input: port 1935
   - HLS/HTTP: port 8080
   - API: port 1985

3. **Flask Auth Server (`server.py`)** - Returns encrypted responses for iOS app auth on port 80

4. **iOS Tools (`ios/`)**
   - `ios_debrand_end_to_end.py` - Full debranding workflow
   - `ios_deb_ip_changer_final.py` - IP injection into .deb packages
   - `deb_packer.py` - AR archive creation
   - `validate_deb.py` - Package structure validation

### Key Launcher Functions
- `Get-NetworkInfo` (line ~399) - WMI network detection
- `Update-SRSConfigForNewIP` (line ~570) - IP placeholder replacement
- `Show-MainMenu` (line ~605) - Interactive menu loop
- `Start-SRSServer` (line ~1107) - Process lifecycle management
- `Invoke-DebrandedIOSBuild` (line ~1319) - Calls Python debranding tools
- `Show-ConfigSelector` (line ~1646) - Configuration profile picker

### Configuration Profiles (`config/active/`)
- `srs_iphone_ultra_smooth_dynamic.conf` - **Recommended** - Port-only bindings, works with any IP/localhost
- `srs_iphone_optimized_smooth.conf` - Balanced 2s fragments, hardcoded IP
- `srs_iphone_ultra_smooth.conf` - 1s fragments for low latency, hardcoded IP
- `srs_iphone_max_smooth.conf` - 5s fragments for poor networks
- `srs_iphone_motion_smooth.conf` - High-motion content

**IP Handling**: Most configs have hardcoded IPs that get replaced via regex at runtime by `Update-SRSConfigForNewIP`. The `_dynamic.conf` variant uses port-only bindings (no IP) for universal compatibility.

### iOS .deb Package System
The debranding workflow:
1. **Extract**: AR archive → control.tar.gz + data.tar.lzma
2. **Patch**: Binary replacement preserving byte lengths
3. **Repack**: LZMA-alone compression (not XZ - iOS requirement)
4. **Validate**: Member order: debian-binary, control.tar.gz, data.tar.lzma

Debranding patterns:
- `www.bkatm.com` → `localhost` (padded)
- `https://www.bkatm.com` → `http://localhost` (padded)

## Directory Structure

```
├── iOS-VCAM-Launcher.{ps1,exe,bat}  # Launcher files
├── server.py                         # Flask auth server
├── compile-v4.1.ps1                  # Build script
├── objs/
│   ├── srs.exe                       # SRS binary
│   └── nginx/html/                   # Web console
├── config/
│   ├── active/                       # iPhone-optimized configs
│   └── archived/                     # Reference configs
├── ios/
│   ├── ios_debrand_end_to_end.py    # Debranding workflow
│   ├── ios_deb_ip_changer_final.py  # IP injection
│   ├── iosvcam_base.deb             # Debranded base package
│   ├── modified_debs/               # Generated packages
│   └── tools/                        # Original branded packages
├── dist/                             # Full distribution package
├── dist-min/                         # Minimal distribution
└── misc/
    ├── test-scripts/                 # Validation scripts
    └── docs/                         # Additional documentation
```

## Network Ports

| Port | Service |
|------|---------|
| 1935 | RTMP input |
| 8080 | HTTP/HLS output, web console |
| 1985 | SRS HTTP API |
| 80   | Flask auth (optional) |

## Coding Conventions

### PowerShell
- Verb-Noun naming, 4-space indentation
- `Write-Host` with existing emoji vocabulary for status
- Comment-based help blocks

### Python
- `snake_case`, f-strings for logging
- Black-compatible (88-char lines)
- `if __name__ == "__main__":` guards

### Configs
- Lowercase with underscores, `srs_iphone_*` prefix
- Prefer port-only bindings (e.g., `listen 1935;`) for universal compatibility
- IPs in existing configs get replaced via regex by launcher

## USB/Localhost Streaming (Experimental)

For more reliable streaming than WiFi, use USB port forwarding:

### Setup with iproxy (libimobiledevice)
```bash
# Install libimobiledevice (via chocolatey or manual)
choco install libimobiledevice

# Forward ports over USB (run in separate terminals)
iproxy 1935 1935    # RTMP
iproxy 8080 8080    # HLS/HTTP
iproxy 80 80        # Flask auth (if needed)
```

### Setup with 3utools
1. Connect iPhone via USB
2. Open 3utools → Toolbox → SSH Tunnel or Real-time Desktop
3. Configure port forwarding for 1935, 8080, 80

### .deb Package for Localhost
```bash
# Generate .deb pointing to 127.0.0.1
python ios/ios_deb_ip_changer_final.py --base ios/iosvcam_base.deb 127.0.0.1
# Or padded format: 127.000.0.001 (12 chars)
```

### Server Config
Use `srs_iphone_ultra_smooth_dynamic.conf` which binds to ports only (no IP), making it work for both WiFi and localhost.

## Choppy Streaming Troubleshooting

### Quick Fixes
1. **Switch config**: Try `srs_iphone_ultra_smooth_dynamic.conf` (lowest latency) or `srs_iphone_max_smooth.conf` (more buffering)
2. **Use 5GHz WiFi** instead of 2.4GHz
3. **Reduce OBS bitrate**: Try 2000-2500 kbps instead of 3000+
4. **Check WiFi signal**: Move closer to router

### Config Tuning
Key parameters in config files:
```conf
hls_fragment    1-5;     # Higher = more buffer, smoother but more latency
hls_window      3-6;     # Number of fragments in playlist
queue_length    1-3;     # RTMP buffer (1 = aggressive, 3 = stable)
mw_latency      100-500; # Target latency in ms
chunk_size      4096-60000; # Smaller = lower latency, larger = efficiency
```

### Network Diagnostics
```powershell
# Check SRS API
Invoke-WebRequest http://localhost:1985/api/v1/streams

# Monitor active connections
netstat -an | findstr :1935

# Test from iPhone (via SSH)
ping [server-ip]
curl http://[server-ip]:8080/live/srs.m3u8
```

## Common Issues

1. **Port conflicts**: Check `netstat -an | findstr :1935`
2. **Bad deb error**: Ensure LZMA-alone compression, verify AR member order with `validate_deb.py`
3. **Network detection fails**: Manually select adapter in launcher menu
4. **PowerShell execution policy**: Always use `-ExecutionPolicy Bypass`
5. **Choppy over WiFi**: See USB streaming section above, or try different config profile

## SSH to Jailbroken iPhones (Windows)

### Prerequisites
1. **Enable SSH on iPhone**: In Dopamine/roothide, set root password via `passwd` command
2. **USB Tunnel**: Use 3utools SSH Tunnel to forward port 22 to `127.0.0.1:22`

### Fix Windows SSH Permission Error
If you get `Bad owner or permissions on C:\\Users\\.../.ssh/config`:
```powershell
# Run as Admin - fix .ssh folder permissions
icacls "$env:USERPROFILE\.ssh" /inheritance:r
icacls "$env:USERPROFILE\.ssh" /grant:r "$($env:USERNAME):(OI)(CI)F"
icacls "$env:USERPROFILE\.ssh\config" /inheritance:r
icacls "$env:USERPROFILE\.ssh\config" /grant:r "$($env:USERNAME):F"
```

### Connect via SSH
```powershell
# From PowerShell (not Git Bash - use native Windows ssh)
ssh root@127.0.0.1
# Password: your root password (e.g., "icemat" or "alpine")
```

### Useful iPhone Commands
```bash
# Check dylib hash (md5sum available on some jailbreaks)
md5sum /Library/MobileSubstrate/DynamicLibraries/vcamera.dylib

# List vcamera files
ls -la /Library/MobileSubstrate/DynamicLibraries/vcamera*

# Check tweak injection
launchctl list | grep mediaserverd

# Restart mediaserverd (reloads tweaks)
killall -9 mediaserverd

# Full userspace reboot
ldrestart
```

### Note on Different Devices
Each iPhone has a different SSH host key. When switching USB tunnels between devices, you may need to accept the new key or clear known_hosts.

## Debug Mode

Enable verbose SRS logging in any .conf:
```conf
srs_log_tank    console;
srs_log_level   trace;
```

Check SRS status:
```powershell
Invoke-WebRequest http://localhost:1985/api/v1/versions
```
