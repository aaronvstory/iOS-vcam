# Troubleshooting Guide

## ❌ Connection Issues

### "Connection Refused"
*   **Cause:** Server not running or blocked by firewall.
*   **Fix:**
    *   Ensure `srs.exe` is running in the Task Manager.
    *   Check Windows Firewall: Allow ports `1935` (RTMP), `8080` (HTTP), `1985` (API).
    *   Verify IP address matches your PC's current IP.

### "Stream Offline" on iPhone
*   **Cause:** OBS/Source is not sending data.
*   **Fix:**
    *   Check OBS "Stats" dock. Is it dropping frames?
    *   Verify Stream Key matches (`srs`).
    *   Restart the SRS server (Option [1] in Launcher).

### iPhone Can't Connect via USB
*   **Cause:** `iproxy` not running or cable issue.
*   **Fix:**
    *   Run `idevice_id -l` to confirm detection.
    *   For **Option [U]**: Check all three windows (iProxy, SSH, Monibuca) for errors.
    *   For manual setup: Ensure `iproxy 2222 22` (for SSH) or `iproxy 1935 1935` is running.
    *   Re-plug USB cable and accept "Trust This Computer" on iPhone.

---

## 📉 Quality & Latency Issues

### Stream is Choppy / Lagging
*   **WiFi:**
    *   Switch to 5GHz WiFi.
    *   Reduce Bitrate in OBS (Try 2000 Kbps).
    *   Use a "Higher Buffering" config profile (e.g., `srs_iphone_max_smooth.conf`).
*   **USB:**
    *   Ensure no other heavy USB traffic.
    *   Check CPU usage on PC.

### High Latency (>5 seconds)
*   **Cause:** Large buffer configuration or HLS lag.
*   **Fix:**
    *   Use `srs_iphone_ultra_smooth_dynamic.conf`.
    *   In OBS, set **Keyframe Interval** to **1s** or **2s**.
    *   Switch to **RTMP** ingest on iPhone if supported (lower latency than HLS).

---

## 🛠 Launcher Issues

### "PowerShell Parser Error" (Crash on Start)
*   **Status:** Fixed in v3.2.1.
*   **Fix:** If using an old version, update to v3.2.1+. Use the latest `iOS-VCAM-Launcher.exe`.

### "Port 1935 in use"
*   **Cause:** Another instance of SRS or another server is running.
*   **Fix:**
    *   Use **Option [5]** (Port Cleanup) in the Launcher.
    *   Manually kill `srs.exe` via Task Manager.

---

## 📱 iOS Specific

### App Crashes when Camera Opens
*   **Cause:** Tweak incompatibility or bad config.
*   **Fix:**
    *   Reinstall the VCAM tweak.
    *   Restart `mediaserverd` on iPhone (`killall -9 mediaserverd`).
    *   Ensure the stream resolution matches what the app expects (optional but helpful).

### Frida "Failed to spawn"
*   **Cause:** Device locked or not trusted.
*   **Fix:** Unlock device, trust computer. Check USB connection.

Need more help? Check the [Advanced Features](Advanced-Features.md) for deep dives.
