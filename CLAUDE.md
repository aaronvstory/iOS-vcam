# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

iOS-VCAM is a Windows RTMP streaming server distribution for jailbroken iPhones. It bundles SRS (Simple Realtime Server) v5.0.213 with a PowerShell launcher, iPhone-optimized configurations, and iOS `.deb` package tools for IP injection and debranding.

## Commands

### Build & Run
```powershell
# Compile launcher to EXE (auto-downloads ps2exe)
pwsh -ExecutionPolicy Bypass -File compile-v4.2.ps1

# Run launcher (any of these)
.\iOS-VCAM-Launcher.bat
.\iOS-VCAM-Launcher.exe
powershell -ExecutionPolicy Bypass -File iOS-VCAM-Launcher.ps1

# Flask auth server (for iOS app pairing)
python server.py --host 0.0.0.0
```

### Testing
```powershell
# Quick smoke test - verify launcher stays alive
pwsh -ExecutionPolicy Bypass -File tests/quick-test.ps1

# Structural verification (EXE, configs, binaries)
pwsh -ExecutionPolicy Bypass -File tests/test-launcher.ps1

# Validate .deb package structure
python ios/validate_deb.py ios/modified_debs/<file>.deb
```

### iOS Package Operations
```bash
# Generate IP-customized .deb package
python ios/ios_deb_ip_changer_final.py --base ios/iosvcam_base.deb 192.168.1.100

# Full debranding workflow
python ios/ios_debrand_end_to_end.py --ip 192.168.1.100
```

### Stream Testing
```bash
# Publish test stream via ffmpeg
ffmpeg -re -i test.mp4 -c copy -f flv rtmp://localhost:1935/live/srs

# Check SRS API
curl http://localhost:1985/api/v1/versions
```

## Architecture

### Core Components

1. **PowerShell Launcher (`iOS-VCAM-Launcher.ps1`)** - ~3550 lines
   - Network adapter detection with IP monitoring
   - Dynamic IP replacement via regex in configs
   - Interactive menu with server status (options: A, B, 1, 3-9, U, C, Q)
   - Process management for SRS/Monibuca and Flask

2. **SRS Media Server (`objs/srs.exe`)**
   - RTMP: 1935, HTTP/HLS: 8080, API: 1985

3. **Flask Auth Server (`server.py`)** - iOS app authentication on port 80

4. **iOS Tools (`ios/`)**
   - `ios_deb_ip_changer_final.py` - IP injection into .deb packages
   - `ios_debrand_end_to_end.py` - Full debranding workflow
   - `deb_packer.py` - AR archive creation
   - `validate_deb.py` - Package structure validation

### Key Launcher Functions
| Function | Line | Purpose |
|----------|------|---------|
| `Get-NetworkInfo` | ~399 | WMI network detection |
| `Update-SRSConfigForNewIP` | ~570 | IP placeholder replacement |
| `Show-MainMenu` | ~605 | Interactive menu display |
| `Start-CombinedFlaskAndSRS` | ~740 | Main streaming launcher |
| `Start-MonibucaViaSshUsb` | ~1312 | USB streaming via SSH tunnel (option U) |
| `Show-ConfigSelector` | ~1880 | Configuration profile picker |
| `Show-iOSDebCreator` | ~2630 | iOS .deb builder (option 8) |
| `Show-ConfigurationSettings` | ~3200 | Settings menu (option C) |

### Configuration System

Configs in `config/active/` have hardcoded IPs that get replaced at runtime by `Update-SRSConfigForNewIP`. The `_dynamic.conf` variants use port-only bindings for universal compatibility.

**Recommended**: `srs_iphone_ultra_smooth_dynamic.conf` - works with any IP/localhost

Key parameters:
```conf
hls_fragment    1-5;     # Seconds per segment (lower = less latency)
hls_window      3-6;     # Segments in playlist (lower = less buffer)
queue_length    1-3;     # RTMP buffer depth
mw_latency      100-500; # Target latency in ms
```

### USB Streaming via SSH Tunnel (Option U)

Stream RTMP from iPhone to PC over USB cable using SSH reverse tunneling. Eliminates WiFi dependency for stable, low-latency streaming.

**Prerequisites:**
- `iproxy.exe` and `idevice_id.exe` at `C:\iProxy\` (libimobiledevice)
- `plink.exe` in project root (PuTTY suite)
- OpenSSH installed on jailbroken iPhone
- iPhone .deb patched with `127.10.10.10` IP address

**How it works:**
1. iproxy forwards `localhost:2222 → iPhone:22` over USB
2. SSH reverse tunnel makes iPhone's port 1935 route back to PC's Monibuca
3. iPhone app connects to `rtmp://127.10.10.10:1935/live/srs`
4. Traffic flows: iPhone → SSH tunnel → USB → PC Monibuca

**Files:**
- Pre-built .deb: `ios/modified_debs/iosvcam_base_127_10_10_10.deb`
- Full docs: `tasks/USB-SSH-STREAMING-GUIDE.md`

### iOS .deb Package System

The debranding workflow:
1. **Extract**: AR archive → control.tar.gz + data.tar.lzma
2. **Patch**: Binary replacement preserving byte lengths
3. **Repack**: LZMA-alone compression (not XZ - iOS requirement)
4. **Validate**: Member order: debian-binary, control.tar.gz, data.tar.lzma

Debranding patterns:
- `www.bkatm.com` → `localhost` (padded)
- `https://www.bkatm.com` → `http://localhost` (padded)

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
- Prefer port-only bindings for universal compatibility

## Common Issues

1. **Port conflicts**: `netstat -an | findstr :1935`
2. **Bad deb error**: Ensure LZMA-alone compression, verify AR member order
3. **Network detection fails**: Manually select adapter in launcher menu
4. **Execution policy**: Always use `-ExecutionPolicy Bypass`

## Debug Mode

Enable verbose SRS logging:
```conf
srs_log_tank    console;
srs_log_level   trace;
```

## Documentation (KEEP UPDATED)

User-facing wiki documentation lives in `docs/`:

| File | Purpose |
|------|---------|
| `Home.md` | Wiki index with navigation |
| `Installation.md` | Prerequisites and setup guide |
| `Configuration.md` | SRS config profiles and parameters |
| `Streaming-Guide.md` | WiFi/USB streaming howto |
| `Troubleshooting.md` | Common issues and fixes |
| `Advanced-Features.md` | SSH, debranding, Frida, architecture |

**Maintenance Rules:**
- When menu options change, update references in docs (e.g., "Option [3]")
- When adding features, update relevant wiki page
- Keep `Home.md` ToC in sync with actual pages
- Review docs after any launcher refactoring

## Commit Guidelines

Follow imperative, present-tense style: `Fix Flask server to use port 80`. Reference affected paths and note any configs/binaries that must be regenerated.
