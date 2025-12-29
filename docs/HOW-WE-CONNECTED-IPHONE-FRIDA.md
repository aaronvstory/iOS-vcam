# How We Successfully Connected iPhone to Frida - Complete Guide

**IMPORTANT:** Save this file! This eliminates all the trial-and-error for future sessions.

---

## 🎯 The Setup That Works

### What We're Using:
- **iPhone:** iPhone SE2, iOS 16.3.1, Dopamine RootHide jailbreak
- **PC:** Windows (MSYS_NT-10.0-26100)
- **Connection:** Direct USB cable (NO SSH tunnel needed!)
- **Frida Server:** Pre-installed on iPhone via Sileo/Cydia

### What We're NOT Using:
- ❌ **plink** - Not needed for USB connection!
- ❌ **3uTools SSH tunnel** - Not needed for USB connection!
- ❌ **SSH at all** - Not needed for Frida over USB!

**Key Discovery:** Frida connects directly via USB using `frida.get_usb_device()` - no SSH tunnel required!

---

## 📋 Prerequisites (One-Time Setup)

### On iPhone (Already Done):
1. ✅ Jailbreak with Dopamine (RootHide mode)
2. ✅ Install Frida server from Sileo/Cydia
3. ✅ Frida server runs automatically on boot

### On PC (Already Installed):
```bash
pip install frida-tools frida colorama
```

### Physical Connection:
- Connect iPhone to PC via USB cable
- Trust computer on iPhone when prompted
- iPhone should be unlocked during Frida operations

---

## 🚀 Quick Start - Connect Every Time

### Step 1: Connect iPhone via USB
```
Physical USB cable connection
iPhone → Trust Computer → Unlocked screen
```

### Step 2: Verify Frida Connection
```bash
cd "C:\claude\ios frida"
python -m frida_tools.ps -U
```

**Expected output:**
```
PID  Name
---  ----
123  SpringBoard
456  backboardd
789  DasherApp
...
```

If you see processes listed = ✅ Connection successful!

### Step 3: Launch Monitored App
```bash
# General format:
python frida-monitor-ios.py <app_bundle_id> <script.js>

# Example - DoorDash Dasher:
python frida-monitor-ios.py com.doordash.dasher frida-interception-and-unpinning/client-side-403-bypass.js
```

---

## 📱 Target Apps We Work With

### DoorDash Dasher (Driver App):
- **Bundle ID:** `com.doordash.dasher`
- **Display Name:** DasherApp
- **Purpose:** Driver delivery app (NOT customer app)

### Finding Bundle IDs:
```bash
# List all installed apps:
python -m frida_tools.ps -Uai

# Search for specific app:
python -m frida_tools.ps -Uai | grep -i doordash
```

---

## 🔧 Common Operations

### Kill Running App (Before Fresh Start):
```bash
# Method 1: Manual PID lookup
python -m frida_tools.ps -U | grep DasherApp
# Note the PID, then:
kill <PID>

# Method 2: Quick kill (if you know process name)
ps aux | grep DasherApp | awk '{print $2}' | xargs kill -9
```

### Spawn Fresh App Instance:
```bash
python frida-monitor-ios.py com.doordash.dasher <your-script.js>
```

**What happens:**
1. App launches fresh (logged out state)
2. Script loads immediately
3. All traffic captured from start
4. ✅ Most reliable for bypasses

### Attach to Running App:
```bash
# Find PID first:
python -m frida_tools.ps -U | grep DasherApp

# Attach:
python frida-attach.py <PID> <your-script.js>
```

**Known Issue:** DoorDash Dasher app times out on attach (possible anti-Frida). Use spawning instead!

---

## 🎬 Complete Workflow Example

### Scenario: Test Red Card bypass on DoorDash

```bash
# 1. Navigate to project
cd "C:\claude\ios frida"

# 2. Verify iPhone connected
python -m frida_tools.ps -U
# See processes? Good!

# 3. Kill any running DasherApp
ps aux | grep DasherApp | awk '{print $2}' | xargs kill -9

# 4. Launch with bypass script
python frida-monitor-ios.py com.doordash.dasher frida-interception-and-unpinning/client-side-403-bypass.js

# 5. Wait for "[✓] CLIENT-SIDE 403 BYPASS READY"

# 6. Use app normally - script monitors in background

# 7. Watch terminal for hook messages
```

---

## 🐛 Troubleshooting

### "Failed to enumerate devices"
**Cause:** iPhone not connected or not trusted
**Fix:**
```bash
# Check USB connection:
python -c "import frida; print(frida.enumerate_devices())"

# Should show: [Device(id="...", name="iPhone", type='usb')]
```

### "Process not found"
**Cause:** App not running or wrong bundle ID
**Fix:**
```bash
# List all apps:
python -m frida_tools.ps -Uai | grep -i <app_name>
```

### "Timeout was reached"
**Cause:** DoorDash has anti-Frida or app crashed
**Fix:** Use spawning instead of attaching

### "Script loaded but no hooks trigger"
**Cause:** Button uses SwiftUI/gesture recognizers, not hooked methods
**Fix:** Create broader hooks (like our 403 bypass)

---

## 📝 Key Script Files

### Core Infrastructure:
- `frida-monitor-ios.py` - Main spawning script (spawns fresh app)
- `frida-attach.py` - Attach to running process
- `frida-attach-robust.py` - Attach with extended timeout

### Analysis Scripts (Python):
- `analyze-har.py` - Parse HTTP Toolkit HAR files
- `analyze-403-details.py` - Extract headers from blocked requests

### Injection Scripts (JavaScript):
- `client-side-403-bypass.js` - ⭐ Force 403 → 200 responses
- `app-attest-enumeration.js` - Document App Attest usage
- `doordash-wallet-button-hook-simplified.js` - Hook 2,104 wallet methods
- `passkit-corrected-bypass.js` - PassKit jailbreak bypass (iOS 16.3.1)

---

## 🌐 HTTP Toolkit Setup (For HAR Capture)

**IMPORTANT:** HTTP Toolkit does NOT require Frida! Works on ANY iPhone (jailbroken or not).

### What HTTP Toolkit Is:
- Proxy server running on your PC
- MITM proxy that decrypts HTTPS traffic
- Just needs WiFi proxy configuration + CA certificate

### Setup on Non-Jailbroken iPhone:

**1. On PC:**
```
Open HTTP Toolkit
Click "iOS" or "Existing Connection"
Note proxy settings: e.g., 192.168.50.9:8000
```

**2. On iPhone:**
```
Settings → Wi-Fi
Tap your network name
Scroll down → Configure Proxy
Select "Manual"
Server: 192.168.50.9 (your PC IP)
Port: 8000
Save
```

**3. Install Certificate:**
```
On iPhone Safari: Visit URL shown in HTTP Toolkit
Download and install profile
Settings → General → VPN & Device Management
Install downloaded profile

Settings → General → About
Scroll to bottom → Certificate Trust Settings
Enable full trust for HTTP Toolkit certificate
```

**4. Capture Traffic:**
```
Open app (DoorDash, etc.)
All HTTPS traffic appears in HTTP Toolkit
File → Export → HAR format
```

**5. Cleanup:**
```
iPhone Settings → Wi-Fi → Your Network
Configure Proxy → Off
Settings → General → VPN & Device Management
Remove HTTP Toolkit profile
```

---

## 🔒 Security Notes

### Default iPhone Credentials (If SSH Needed):
- **Username:** root
- **Password:** alpine (change on production devices!)

### SSH Access (Not Needed for Frida USB):
If you ever need SSH:
```bash
ssh root@<iphone_ip> -p 22
# or via 3uTools SSH tunnel:
ssh root@127.0.0.1 -p 22
```

### Frida Detection:
- Some apps detect Frida and crash/block
- DoorDash Dasher: Spawning works, attaching times out
- Use fresh spawns for best compatibility

---

## ✅ Quick Checklist - "Is It Working?"

Before every session:
- [ ] iPhone connected via USB
- [ ] iPhone unlocked
- [ ] `python -m frida_tools.ps -U` lists processes
- [ ] App you want to hook is NOT already running
- [ ] Correct bundle ID for target app
- [ ] Python script exists and path is correct

---

## 🎯 Common Commands Quick Reference

```bash
# Verify connection
python -m frida_tools.ps -U

# Find app bundle ID
python -m frida_tools.ps -Uai | grep -i <name>

# Kill app
ps aux | grep <AppName> | awk '{print $2}' | xargs kill -9

# Spawn with script
python frida-monitor-ios.py <bundle.id> <script.js>

# Attach to running (PID required)
python frida-attach.py <PID> <script.js>

# Analyze HAR file
python analyze-har.py "path/to/file.har"
```

---

## 💾 This Session's Success

**Device ID:** 308e6361884208deb815e12efc230a028ddc4b1a
**Connection Method:** Direct USB with `frida.get_usb_device()`
**Working Scripts:** All spawning-based operations
**Known Issues:** DoorDash attach times out (use spawn)
**Key Discovery:** App Attest blocks Red Card with 403

---

## 📚 Related Documentation

- `INVESTIGATION-FINDINGS.md` - Complete Red Card App Attest analysis
- `NEXT-STEPS-ACTION-GUIDE.md` - Testing roadmap and bypass strategies
- `CLAUDE.md` - Project overview and Frida framework guide

---

**Save this file! Copy commands from here for future sessions. No more guessing!** 🎉
