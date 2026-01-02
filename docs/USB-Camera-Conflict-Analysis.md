# USB Streaming Camera Conflict - Deep Analysis

**Date:** 2026-01-02
**Status:** Investigation complete, solutions identified
**Next Steps:** Implement jetsamctl protection for vcam and VNC processes

---

## Problem Statement

After adding USB streaming (Option U) to iOS-VCAM, a new issue appeared:
- When streaming via USB and another app requests camera access, either vcam OR VNC crashes
- This did NOT happen with WiFi streaming (Option A)
- After crash + reconnect, everything coexists perfectly (vcam + VNC + camera apps)

**Key Constraint:** Cannot change from `127.10.10.10` to `127.0.0.1` because the .deb IP patching requires exact character count.

---

## Architecture Comparison

### WiFi Streaming (Option A) - STABLE
```
iPhone vcam tweak → WiFi (en0) → Router → PC (192.168.x.x:1935)
```
- Direct socket to external IP
- No local dependencies on iPhone
- Survives iOS internal state changes

### USB Streaming (Option U) - FRAGILE ON FIRST ACCESS
```
iPhone vcam tweak → lo0 alias (127.10.10.10) → SSH tunnel → sshd → USB → PC
```
- Uses loopback interface with manual alias
- SSH reverse tunnel binds to 127.10.10.10:80 and :1935
- Multiple local components that can break

---

## Root Cause Analysis

### Gemini Analysis
1. **Network Interface Reconfiguration**: When AVCaptureSession starts, iOS may refresh network interfaces, potentially affecting manual loopback aliases
2. **Jetsam Memory Pressure**: Camera is high-priority; iOS may kill background processes (sshd, VNC) to free memory
3. **Sandbox Policies**: 127.10.10.10 may be treated differently than 127.0.0.1 in iOS policies

### Codex Analysis
1. **Camera Session Interruption**: Only one active AVCaptureSession allowed; when another app requests camera, vcam's session is interrupted
2. **Loopback Path Fragility**: The path `local → SSH tunnel → USB → host` has multiple failure points
3. **127.10.10.10 vs 127.0.0.1**: Non-standard loopback addresses may have different treatment under iOS policies
4. **Process Lifecycle**: If tunnel is tied to app lifecycle, backgrounding/jetsam can kill it

### Combined Hypothesis
When a 3rd party camera app (especially Safari) requests camera access:
1. iOS triggers system-level camera initialization
2. iOS jetsam/resource manager decides to kill ONE process to free resources
3. Either vcam's network connection OR VNC gets sacrificed
4. After reconnection, the system is "settled" and everything coexists

**Critical Evidence:** After crash + reconnect, vcam + VNC + camera apps all work together perfectly. This proves it's NOT a fundamental architecture incompatibility - it's an iOS resource management issue on FIRST camera access.

---

## Diagnostic Findings (Captured During Crash State)

### PC Side (All OK)
```
Process     Status    Details
---------   --------  --------------------------
plink       RUNNING   PID 85312, SSH tunnel active
monibuca    RUNNING   PID 69872, RTMP server on 1935
iproxy      RUNNING   PID 52408/76656, USB forwarding
```

### iPhone Side (After VNC Crashed, vcam Survived)
```
Component              Status    Evidence
---------------------  --------  ----------------------------------
Loopback alias         OK        inet 127.10.10.10 on lo0
SSH tunnel listeners   OK        127.10.10.10:80 LISTEN
                                 127.10.10.10:1935 LISTEN
vcam RTMP connection   OK        127.10.10.10:1935 ESTABLISHED
VNC server             OK        Port 5901 LISTEN (no clients)
VNC client (PC)        CRASHED   "Connection gracefully closed"
```

**Key Finding:** The loopback architecture works fine! The tunnel stayed up, vcam stayed connected. iOS just killed the VNC connection.

---

## Behavioral Patterns

| Trigger | Result | Pattern |
|---------|--------|---------|
| Built-in Camera app | Usually OK | Doesn't cause crashes |
| Safari camera access | Often crashes | Especially on first access |
| 3rd party camera app | Variable | "One or the other" - vcam OR VNC dies |
| After reconnect | Stable | Everything coexists perfectly |

---

## Proposed Solutions

### Solution 1: Protect Processes with Jetsamctl (PRIMARY)

Raise the jetsam priority of vcam and VNC processes so iOS won't kill them for resources:

```bash
# SSH into iPhone first (see MOBILE-DEVICES-QUICKSTART.md)
# Find process PIDs
ps aux | grep -E "vcam|vnc|TrollVNC" | grep -v grep

# Protect them from jetsam (replace <PID> with actual)
jetsamctl -p <VCAM_PID> -m -1 -P 18
jetsamctl -p <VNC_PID> -m -1 -P 18
```

**Note:** This needs to be done after each reboot. Could be automated via LaunchDaemon.

### Solution 2: Pre-Warm Camera (WORKAROUND)

Trigger camera access BEFORE starting USB streaming:
1. Start USB tunnel (Option U)
2. Open Safari camera briefly
3. Close Safari
4. Start vcam - should be stable

This "primes" the system so the initialization conflict is avoided.

### Solution 3: Auto-Reconnect Logic (ENHANCEMENT)

Since recovery always works, add auto-reconnect to the launcher:
- Detect vcam disconnect
- Wait 2 seconds
- Restart streaming automatically

---

## Files Modified/Created During Investigation

| File | Purpose |
|------|---------|
| `check-iphone.ps1` | Diagnostic script for iPhone state |
| `check-established.ps1` | Check established connections |
| `docs/USB-Camera-Conflict-Analysis.md` | This document |

---

## Diagnostic Commands Reference

### PC Side
```powershell
# Check all USB streaming processes
Get-Process plink,monibuca,iproxy -ErrorAction SilentlyContinue | Select Id,ProcessName,StartTime

# Check port listeners
Get-NetTCPConnection -LocalPort 1935,2222 -ErrorAction SilentlyContinue
```

### iPhone Side (via SSH)
```bash
# Check loopback alias exists
ifconfig lo0 | grep inet

# Check tunnel listeners
netstat -an | grep "127.10.10.10.*LISTEN"

# Check established RTMP connections
netstat -an | grep "127.10.10.10.*ESTABLISHED"

# Check VNC
netstat -an | grep 5901

# Find vcam/VNC process PIDs for jetsamctl
ps aux | grep -E "vcam|vnc|TrollVNC" | grep -v grep
```

---

## SSH Connection Guide

Reference: `C:\claude\MOBILE-DEVICES-QUICKSTART.md`

Quick connect via USB:
```powershell
# From iOS-VCAM-v4.2-Distribution directory
# Assumes iproxy is running on port 2222

# Get fingerprint
$fp = (.\plink.exe -4 -ssh -batch -P 2222 -pw icemat root@127.0.0.1 exit 2>&1 | Select-String 'SHA256:').Matches.Value

# Connect
.\plink.exe -4 -hostkey $fp -ssh -P 2222 -pw icemat root@127.0.0.1
```

---

## Next Steps (For New Chat)

1. **Read this document** to restore context
2. **Connect to iPhone via SSH** using MOBILE-DEVICES-QUICKSTART.md
3. **Find vcam and VNC process PIDs** on iPhone
4. **Apply jetsamctl protection** to both processes
5. **Test** if camera apps still cause crashes
6. **If working**, create LaunchDaemon to auto-apply protection on boot

---

## Technical Details

### Why 127.10.10.10 (Not 127.0.0.1)
The .deb IP patching uses binary string replacement with exact character count:
- Original: `www.bkatm.com` (13 chars) or IP like `192.168.50.9` (12 chars)
- `127.10.10.10` = 12 chars (matches common IP length)
- `127.0.0.1` = 9 chars (too short, would break binary)

### SSH Tunnel Architecture
```
PC                          USB Cable                 iPhone
-----------------------     ----------               ----------------------
iproxy:2222 ──────────────> iPhone:22 (SSH)
plink ────────────────────> sshd
  -R 127.10.10.10:80  ────> lo0:80 (Flask auth)
  -R 127.10.10.10:1935 ───> lo0:1935 (RTMP)
Monibuca:1935 <───────────< vcam tweak RTMP stream
Flask:80 <────────────────< vcam tweak HTTP auth
```

### VNC Coexistence
Both VNC and vcam use iproxy for USB forwarding:
- VNC: ports 5901, 5902
- vcam: port 2222 (SSH)

They should NOT conflict at the iproxy level - the conflict is at the iOS resource management level.

---

## Implementation Status (2026-01-02)

### Jetsam Protection Applied

| Component | Protection Added | Keys Added |
|-----------|------------------|------------|
| TrollVNC | ✅ YES | `JetsamMemoryLimit=-1`, `JetsamPriority=18` |
| sshd | ✅ YES | `JetsamMemoryLimit=-1`, `JetsamPriority=18`, `EnablePressuredExit=false` |
| vcamera | ❌ N/A | Substrate tweak - injects into mediaserverd/SpringBoard |

### Why vcamera Can't Be Protected Directly

The vcamera tweak is NOT a standalone daemon. It's a `.dylib` that gets injected via Substrate/Substitute into:
- `com.apple.mediaserverd` (camera handling)
- `com.apple.springboard` (home screen)
- `com.apple.lskdd`

Since mediaserverd is a core system process, iOS already gives it high priority. The RTMP connection vcamera makes should now be more stable because:
1. **sshd** won't be killed (protects the SSH tunnel)
2. **TrollVNC** won't be killed (protects VNC streaming)
3. **mediaserverd** is a system process with inherent protection

### Scripts Created

| Script | Purpose |
|--------|---------|
| `fix_jetsam_lf.sh` | Adds jetsam protection to TrollVNC plist |
| `fix_sshd_lf.sh` | Adds jetsam protection to sshd plist |

### Testing Needed

After protection applied, test by:
1. Start USB streaming (Option U in launcher)
2. Connect VNC client
3. Open Safari and allow camera access
4. Verify vcam stream AND VNC both survive

If either still crashes, investigate:
- Check if mediaserverd is being reset (not killed, but restarted)
- Consider if the issue is socket-level rather than process-level

---

## Version Info

- iOS-VCAM-Launcher: v4.2
- iPhone .deb: `iosvcam_base_127_10_10_10.deb`
- SSH Password: `icemat`
- Project Path: `F:\claude\iOS-Vcam-server\iOS-VCAM-v4.2-Distribution`
- Branch: `fix/jetsam-protection`
