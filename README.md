# iOS-VCAM Server

**Windows RTMP streaming server optimized for jailbroken iOS devices.**

A complete distribution package bundling [SRS (Simple Realtime Server)](https://github.com/ossrs/srs) v5.0.213 with an interactive PowerShell launcher, iPhone-optimized streaming configurations, and iOS `.deb` package tools for customization.

![Version](https://img.shields.io/badge/version-4.2-blue)
![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11-lightgrey)
![License](https://img.shields.io/badge/license-MIT-green)

---

## Quick Start

### 1. Launch the Server

```batch
:: Double-click or run from command line:
iOS-VCAM-Launcher.bat
```

The launcher will:
1. Auto-detect your network adapter and IP address
2. Display an interactive menu with server controls
3. Show your RTMP URL for iPhone connection
4. Optionally start the Flask authentication server

### 2. Connect Your iPhone

Configure your iOS RTMP streaming app with:

| Setting | Value |
|---------|-------|
| **RTMP URL** | `rtmp://YOUR-IP:1935/live/srs` |
| **Stream Key** | `srs` (or any name) |

### 3. View the Stream

- **Web Player**: `http://YOUR-IP:8080/players/srs_player.html`
- **HLS URL**: `http://YOUR-IP:8080/live/srs.m3u8`

---

## Features

- **Interactive Launcher** - Menu-driven server management with real-time status
- **Auto IP Detection** - Automatically finds and configures your network adapter
- **iPhone-Optimized Configs** - 11 pre-tuned profiles for different streaming scenarios
- **iOS Package Tools** - Python utilities to customize `.deb` packages with your server IP
- **USB Streaming Support** - Documentation and configs for reliable USB-over-iproxy streaming
- **Flask Auth Server** - Optional authentication endpoint for iOS app pairing (port 80)
- **SSH Tools** - Bundled `plink.exe` and `pscp.exe` for iPhone file transfers

---

## Directory Structure

```
iOS-VCAM-v4.2-Distribution/
│
├── iOS-VCAM-Launcher.{bat,exe,ps1}   # Main launcher (run any of these)
├── iOS-VCAM.ico                       # Application icon
├── server.py                          # Flask authentication server
├── compile-v4.2.ps1                   # Build script (regenerate EXE)
│
├── objs/                              # Server binaries
│   ├── srs.exe                        # SRS streaming server (34MB)
│   ├── monibuca.exe                   # Alternative media server (65MB)
│   ├── *.dll                          # Cygwin runtime libraries
│   └── nginx/html/                    # Web console & players
│       ├── console/                   # SRS admin console
│       ├── players/                   # Web-based stream players
│       └── demos/                     # WebRTC demos
│
├── config/                            # SRS configuration profiles
│   ├── active/                        # Production-ready configs
│   │   ├── srs_iphone_ultra_smooth_dynamic.conf  # Recommended
│   │   ├── srs_iphone_max_smooth.conf            # High buffering
│   │   └── srs_usb_smooth_playback.conf          # USB streaming
│   └── archived/                      # Legacy/experimental configs
│
├── ios/                               # iOS package tools
│   ├── ios_deb_ip_changer_final.py   # Inject server IP into .deb
│   ├── ios_debrand_end_to_end.py     # Full debranding workflow
│   ├── iosvcam_base.deb              # Base iOS package (pre-debranded)
│   ├── tools/                         # Additional iOS utilities
│   └── validate_deb.py               # Package validation
│
├── docs/                              # Documentation
├── tests/                             # Test scripts
├── scripts/                           # USB monitoring utilities
├── plink.exe / pscp.exe               # PuTTY SSH tools
└── conf/                              # Alternative config location
```

---

## Configuration Profiles

Located in `config/active/`:

| Profile | Use Case | Latency | Buffering |
|---------|----------|---------|-----------|
| `srs_iphone_ultra_smooth_dynamic.conf` | **Recommended** - Universal compatibility | <1s | Minimal |
| `srs_iphone_max_smooth.conf` | Poor network conditions | 3-5s | High |
| `srs_iphone_motion_smooth.conf` | High-motion content | 1-2s | Medium |
| `srs_iphone_optimized_smooth.conf` | Balanced performance | 2s | Medium |
| `srs_usb_smooth_playback.conf` | USB/localhost streaming | <0.5s | Minimal |
| `srs_ultimate_auto.conf` | Auto-tuning experimental | Variable | Adaptive |

### Key Config Parameters

```conf
hls_fragment    1-5;     # Seconds per segment (lower = less latency)
hls_window      3-6;     # Segments in playlist (lower = less buffer)
queue_length    1-3;     # RTMP buffer depth
mw_latency      100-500; # Target latency in ms
```

---

## Network Ports

| Port | Protocol | Service |
|------|----------|---------|
| 1935 | TCP | RTMP input (from iPhone) |
| 8080 | TCP | HTTP/HLS output, web console |
| 1985 | TCP | SRS HTTP API |
| 80 | TCP | Flask auth server (optional) |

---

## iOS Package Tools

### Generate IP-Customized Package

```bash
# Create .deb with your server IP embedded
python ios/ios_deb_ip_changer_final.py --base ios/iosvcam_base.deb 192.168.1.100

# Output: ios/modified_debs/iosvcam_192_168_1_100.deb
```

### Validate Package Structure

```bash
python ios/validate_deb.py ios/modified_debs/your_package.deb
```

### Full Debranding Workflow

```bash
python ios/ios_debrand_end_to_end.py --ip 192.168.1.100
```

---

## USB Streaming (More Reliable than WiFi)

For consistent low-latency streaming over USB:

### 1. Install iproxy (libimobiledevice)

```powershell
# Via Chocolatey
choco install libimobiledevice
```

### 2. Forward Ports Over USB

```bash
# Run in separate terminals
iproxy 1935 1935    # RTMP
iproxy 8080 8080    # HLS/HTTP
iproxy 80 80        # Flask auth (if needed)
```

### 3. Generate Localhost Package

```bash
python ios/ios_deb_ip_changer_final.py --base ios/iosvcam_base.deb 127.0.0.1
```

### 4. Use USB-Optimized Config

Select `srs_usb_smooth_playback.conf` in the launcher menu.

---

## Building from Source

### Regenerate the Launcher EXE

```powershell
pwsh -ExecutionPolicy Bypass -File compile-v4.2.ps1
```

Requirements:
- PowerShell 5.1+ or PowerShell 7+
- The script auto-downloads `ps2exe` if needed

### Running Tests

```powershell
# Quick smoke test
pwsh -ExecutionPolicy Bypass -File tests/quick-test.ps1

# Full structural verification
pwsh -ExecutionPolicy Bypass -File tests/test-launcher.ps1

# iOS setup validation
pwsh -ExecutionPolicy Bypass -File tests/verify_ios_setup.ps1
```

---

## Troubleshooting

### Stream is Choppy

1. **Switch config profile** - Try `srs_iphone_max_smooth.conf` for more buffering
2. **Use 5GHz WiFi** - Avoid 2.4GHz interference
3. **Reduce bitrate** - Target 2000-2500 kbps instead of 3000+
4. **Try USB streaming** - See USB section above

### Port Already in Use

```powershell
# Find process using port
netstat -ano | findstr :1935

# Kill by PID
taskkill /F /PID <pid>
```

### iPhone Can't Connect

1. Check Windows Firewall allows ports 1935, 8080
2. Verify both devices on same network
3. Test with `ping YOUR-IP` from iPhone (via SSH)
4. Try the Flask auth server if app requires pairing

### SRS Won't Start

```powershell
# Check SRS status
Invoke-WebRequest http://localhost:1985/api/v1/versions

# View logs in console mode
.\objs\srs.exe -c config\active\srs_iphone_ultra_smooth_dynamic.conf
```

---

## SSH to Jailbroken iPhone

### Via USB Tunnel (3uTools)

1. Connect iPhone via USB
2. Open 3uTools → Toolbox → SSH Tunnel
3. Forward port 22 to `127.0.0.1:22`

### Connect

```powershell
ssh root@127.0.0.1
# Default password: alpine (or your custom password)
```

### Useful Commands

```bash
# Check vcamera dylib
ls -la /Library/MobileSubstrate/DynamicLibraries/vcamera*

# Restart mediaserverd (reloads tweaks)
killall -9 mediaserverd

# Full userspace reboot
ldrestart
```

---

## Requirements

- **OS**: Windows 10/11 (64-bit)
- **PowerShell**: 3.0+ (5.1+ recommended)
- **Python**: 3.8+ (for iOS tools)
- **Network**: WiFi or Ethernet adapter
- **iOS Device**: Jailbroken with RTMP streaming capability

---

## Contributing

See [AGENTS.md](AGENTS.md) for coding standards and PR guidelines.

### Quick Guidelines

- PowerShell: Verb-Noun naming, 4-space indent, comment-based help
- Python: snake_case, f-strings, Black-compatible (88 chars)
- Configs: lowercase with underscores, `srs_iphone_*` prefix

---

## License

MIT License - See [LICENSE](LICENSE) for details.

---

## Acknowledgments

- [SRS (Simple Realtime Server)](https://github.com/ossrs/srs) - Core streaming engine
- [Monibuca](https://github.com/langhuihui/monibuca) - Alternative media server
- [PuTTY](https://www.putty.org/) - SSH tools (plink, pscp)
