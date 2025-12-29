# USB Streaming - WORKING Configuration

**Date Verified:** 2025-12-29 02:40
**Status:** ✅ FULLY WORKING
**Launcher Version:** 4.2.0.0

---

## Quick Start

1. **Run launcher as Administrator**
2. **Select Option [U]** - USB Streaming via SSH Tunnel
3. **Sub-menu options:**
   - `[1]` Start USB Streaming (default)
   - `[K]` Kill All Processes & Restart Fresh
   - `[S]` Status - Show Running Processes
   - `[Q]` Back to Main Menu
4. **In OBS:** Stream to `rtmp://localhost:1935/live/srs`
5. **On iPhone:** Open iOS-VCAM app → receives the OBS stream as virtual camera

---

## Architecture Overview

**Data Flow:** OBS → PC Monibuca → SSH Tunnel → iPhone App (virtual camera)

```
┌─────────────────────────────────────────────────────────────────────┐
│                         WINDOWS PC                                   │
│                                                                      │
│  ┌─────────────┐      ┌─────────────────────────────────────────┐   │
│  │     OBS     │─────▶│           Monibuca RTMP Server          │   │
│  │  (Source)   │ RTMP │              port 1935                   │   │
│  └─────────────┘      └──────────────────┬──────────────────────┘   │
│                                          │                          │
│  ┌─────────────┐  ┌─────────────┐        │     ┌─────────────┐      │
│  │   iProxy    │  │    Flask    │        │     │    plink    │      │
│  │  USB→SSH    │  │  HTTP Auth  │        │     │ SSH Tunnel  │      │
│  │  port 2222  │  │   port 80   │        │     │  reverse    │      │
│  └──────┬──────┘  └──────┬──────┘        │     └──────┬──────┘      │
│         │                │               │            │             │
│         │                └───────────────┴────────────┘             │
│         │                         │                                  │
│         │              SSH Reverse Tunnels                          │
│         │         -R 127.10.10.10:80:localhost:80                   │
│         │         -R 127.10.10.10:1935:localhost:1935               │
│         │                         │                                  │
└─────────┼─────────────────────────┼──────────────────────────────────┘
          │                         │
          │      USB Cable          │ (Stream flows TO iPhone)
          │                         ▼
┌─────────┼─────────────────────────┼──────────────────────────────────┐
│         │                         │                                  │
│  ┌──────▼──────┐           ┌──────▼──────┐                          │
│  │   OpenSSH   │           │ 127.10.10.10 │                          │
│  │   port 22   │◄──────────│  :80  (Auth) │                          │
│  │             │           │  :1935 (RTMP)│                          │
│  └─────────────┘           └──────┬──────┘                          │
│                                   │                                  │
│                         iPHONE (Jailbroken)                         │
│  ┌────────────────────────────────┼────────────────────────────┐    │
│  │                      iOS-VCAM App                            │    │
│  │                                ▼                             │    │
│  │  1. HTTP Auth: http://127.10.10.10/I                        │    │
│  │  2. RTMP Pull: rtmp://127.10.10.10:1935/live/srs            │    │
│  │  3. Displays as Virtual Camera in other apps                │    │
│  └─────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────┘
```

---

## PC Side Components

### 1. iProxy (USB Port Forwarding)
- **Binary:** `C:\iProxy\iproxy.exe`
- **Function:** Forwards `localhost:2222` → iPhone port 22 over USB
- **Command:** `iproxy.exe 2222 22 <UDID>`

### 2. Flask Auth Server
- **Script:** `server.py`
- **Port:** 80 (requires admin)
- **Function:** Handles iOS app authentication before streaming

### 3. Monibuca RTMP Server
- **Binary:** `objs\monibuca.exe`
- **Config:** `conf\monibuca_iphone_optimized.yaml`
- **Ports:** 1935 (RTMP), 8081 (Web Console)
- **Function:** Receives RTMP from OBS, serves it to iPhone via tunnel

### 4. SSH Reverse Tunnel (plink)
- **Binary:** `plink.exe`
- **Function:** Creates reverse tunnels so iPhone can reach PC services

**Critical Command:**
```bash
plink.exe -ssh -batch \
  -R 127.10.10.10:80:localhost:80 \
  -R 127.10.10.10:1935:localhost:1935 \
  -pw <password> root@localhost -P 2222 \
  'echo TUNNEL_ACTIVE; cat'
```

**Key Points:**
- Uses `-R 127.10.10.10:PORT` NOT `-R 0.0.0.0:PORT`
- MUST use `-batch` flag
- MUST have a keep-alive command (`cat`) or tunnel dies immediately
- Password stored in `config.ini` under `SSHPassword=`

---

## iPhone Side Prerequisites

### 1. OpenSSH Installed
Install via Cydia/Sileo/Zebra

### 2. GatewayPorts Enabled
Edit `/etc/ssh/sshd_config`:
```
GatewayPorts clientspecified
```
Then restart sshd: `killall -HUP sshd`

### 3. IP Alias Configured
The launcher does this automatically, but manual command:
```bash
ifconfig lo0 alias 127.10.10.10 netmask 255.255.255.255
```

### 4. Correct .deb Installed
- **Required:** `ios/modified_debs/iosvcam_base_127_10_10_10.deb`
- This patches the app to use `127.10.10.10` instead of WiFi IP

---

## iPhone App Configuration

| Setting | Value |
|---------|-------|
| RTMP URL (Pull) | `rtmp://127.10.10.10:1935/live/srs` |
| HTTP Auth | `http://127.10.10.10/I` |

**Note:** The iPhone app RECEIVES the stream from OBS (pull model), it doesn't send/push.

---

## Verification Commands

### On PC (PowerShell)
```powershell
# Check all services running
Get-Process -Name iproxy,python,monibuca,plink -ErrorAction SilentlyContinue

# Check ports listening
netstat -ano | Select-String ':80\s|:1935\s|:2222\s'
```

### On iPhone (via SSH)
```bash
# Check tunnel ports are bound
netstat -an | grep 127.10.10.10

# Expected output:
# tcp4  127.10.10.10.80    LISTEN
# tcp4  127.10.10.10.1935  LISTEN
```

---

## Troubleshooting

### "NETWORK ERROR" on iPhone App
1. Check tunnel is running (plink window should show `TUNNEL_ACTIVE`)
2. Verify ports on iPhone: `netstat -an | grep 127.10.10.10`
3. Ensure GatewayPorts is enabled in sshd_config
4. Try killing and restarting all processes

### Flask Won't Start on Port 80
- **Cause:** Port 80 requires admin privileges
- **Fix:** Run launcher as Administrator
- **Alt:** Check if IIS/Apache is using port 80: `Stop-Service W3SVC -Force`

### SSH Tunnel Ports Not Binding
- **Cause:** GatewayPorts not enabled
- **Fix:** Add `GatewayPorts clientspecified` to iPhone's `/etc/ssh/sshd_config`

### Tunnel Dies Immediately
- **Cause:** plink needs a running command to keep session alive
- **Fix:** Command must include keep-alive like `'echo TUNNEL_ACTIVE; cat'`

### "Connection Reset" Errors
- Use **Option [K]** in the USB streaming menu to kill all processes and restart fresh
- Ensure iPhone is unlocked and USB is connected

### Stream Not Flowing / Clogged
- Use **Option [K]** to kill all processes and restart fresh
- Use **Option [S]** to check which processes are running
- Restart OBS and re-connect the stream

---

## Bug Fix History (2025-12-29)

### PowerShell Here-String Variable Expansion Bug

**Problem:** Variables in PowerShell here-strings weren't expanding because they were wrapped in single quotes.

**Root Cause:** In double-quoted here-strings (`@"..."@`):
- `$variable` → expands ✅
- `"$variable"` → expands ✅
- `'$variable'` → does NOT expand ❌ (literal text)

**Symptoms:**
- Flask window showed "Set-Location: Cannot find path '$script:SRSHome'"
- Monibuca couldn't find config file
- SSH tunnel command failed to find plink.exe

**Fix Applied (13 instances):**

| Line | Before | After |
|------|--------|-------|
| 824 | `'$script:SelectedConfig'` | `"$script:SelectedConfig"` |
| 825 | `'$script:SelectedConfigPath'` | `"$script:SelectedConfigPath"` |
| 1161 | `'$script:SRSHome'` | `"$script:SRSHome"` |
| 1162 | `'$bindHost'` | `"$bindHost"` |
| 1266 | `'$script:SRSHome'` | `"$script:SRSHome"` |
| 1267 | `'$monibucaPath'` + `'$configFullPath'` | `"$monibucaPath"` + `"$configFullPath"` |
| 1750 | `'$script:SRSHome'` | `"$script:SRSHome"` |
| 1823 | `'$script:SRSHome'` | `"$script:SRSHome"` |
| 1824 | `'$monibucaPath'` + `'$configFullPath'` | `"$monibucaPath"` + `"$configFullPath"` |
| 1899 | `'$plinkPath'` | `"$plinkPath"` |
| 2130 | `'$script:SRSHome'` | `"$script:SRSHome"` |
| 3236 | `'$script:SelectedConfig'` | `"$script:SelectedConfig"` |
| 3237 | `'$script:SelectedConfigPath'` | `"$script:SelectedConfigPath"` |

### SSH Tunnel Keep-Alive Bug

**Problem:** plink tunnel would connect but not bind ports on iPhone.

**Root Cause:** SSH reverse tunnels require an active session. Without a command, the tunnel setup completes but the session closes immediately, dropping the port bindings.

**Fix:** Added keep-alive command to plink:
```bash
# Before (broken):
plink.exe -ssh -R ... root@localhost -P 2222

# After (working):
plink.exe -ssh -batch -R ... root@localhost -P 2222 'echo TUNNEL_ACTIVE; cat'
```

The `cat` command waits forever for input, keeping the SSH session alive.

---

## Files Reference

| File | Purpose |
|------|---------|
| `iOS-VCAM-Launcher.ps1` | Main launcher script |
| `iOS-VCAM-Launcher.exe` | Compiled launcher |
| `server.py` | Flask auth server |
| `plink.exe` | PuTTY SSH client |
| `objs/monibuca.exe` | RTMP server |
| `conf/monibuca_iphone_optimized.yaml` | Monibuca config |
| `config.ini` | Saved settings (SSHPassword) |
| `ios/modified_debs/iosvcam_base_127_10_10_10.deb` | iPhone app patch |

---

## Verified By

- **Codex CLI (gpt-5.2-codex):** Identified variable expansion issues
- **Agent Zero:** Verified all 13 broken instances, confirmed fix
- **Manual Testing:** User confirmed working 2025-12-29 02:40
