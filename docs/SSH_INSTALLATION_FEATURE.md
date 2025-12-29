# iOS-VCAM Launcher v3.2.0 - SSH Installation Feature

## New Feature: Option [9] - Install .deb to iPhone via SSH

### Overview
The iOS-VCAM Launcher now includes an automated SSH installation feature that allows users to directly install modified .deb packages to their jailbroken iPhone without manual file transfer.

### Prerequisites
- Jailbroken iPhone with SSH access
- SSH tunnel active (via 3utools or similar)
- Default connection: localhost:22, root/alpine
- PuTTY tools (plink.exe and pscp.exe) installed

### How It Works

1. **Select Option [9]** from the main menu: "📲 INSTALL .DEB TO IPHONE (SSH)"

2. **SSH Connection Test**
   - Automatically tests SSH connectivity to iPhone
   - Verifies network connectivity from iPhone to laptop
   - Tests RTMP port accessibility

3. **File Selection**
   - Lists all available .deb files from `ios\modified_debs\` directory
   - Shows file sizes and creation timestamps
   - User selects which .deb to install

4. **Installation Process**
   - Transfers .deb file to iPhone via pscp
   - Installs package using `dpkg --force-architecture --force-depends`
   - Optionally restarts iPhone services (mediaserverd, SpringBoard)

5. **Verification**
   - Confirms installation success
   - Provides next steps for streaming

### Custom SSH Configuration
The feature supports custom SSH settings:
- Different SSH host (not just localhost)
- Custom port (not just 22)
- Different username (not just root)
- Custom password (not just alpine)

### Files Modified

1. **iOS-VCAM-Launcher.ps1**
   - Added `Install-iPhoneDeb` function (lines 2170-2400)
   - Updated `Show-Menu` to display option [9] (line 673)
   - Added case "9" to main switch (line 2486)

2. **iOS-VCAM-Launcher.exe**
   - Recompiled with ps2exe to include new feature
   - Version updated to 3.2.0

### Usage Example

```
1. Connect iPhone via USB
2. Open 3utools and enable SSH tunnel
3. Run iOS-VCAM-Launcher.exe
4. Select option [9]
5. Choose a .deb file (e.g., iosvcam_base_192_168_50_9.deb)
6. Confirm installation
7. Optionally restart services
8. Start streaming from iPhone camera app
```

### Benefits
- **Streamlined Workflow**: No manual file copying or SSH commands needed
- **Error Handling**: Automatic detection of connection issues
- **User-Friendly**: Interactive prompts guide through the process
- **Integrated**: Works seamlessly with existing launcher features

### Troubleshooting

If SSH connection fails:
- Ensure SSH tunnel is active in 3utools
- Check iPhone is connected via USB
- Verify SSH credentials (default: root/alpine)
- Try custom SSH settings option

If installation fails:
- Check if iPhone has enough storage
- Ensure .deb file was created successfully
- Try manual installation to diagnose issues

### Technical Details

The function uses:
- **plink.exe**: For SSH command execution
- **pscp.exe**: For secure file transfer
- Installation path: `/var/mobile/Documents/`
- Installation command: `dpkg --force-architecture --force-depends -i [deb_file]`

### Version History
- v3.2.0 (2024): Added SSH installation feature (Option 9)
- v3.1.0: Previous version without SSH installation

### Related Features
- Option [8]: Create iOS .deb with custom IP
- Option [F]: Fix iPhone connection (SSH utility for troubleshooting)