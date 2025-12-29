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

## 🔐 SSH & Installation Issues

### SSH Connection Fails (Option [9])
*   **Cause:** Tunnel not active or wrong credentials.
*   **Fix:**
    *   **3uTools:** Ensure "SSH Tunnel" is OPEN in Toolbox. Port 22 should be mapped to local port (usually 22 or 2222).
    *   **Credentials:** If you changed the root password from `alpine`, choose "No" when asked to use defaults, and enter your custom password.
    *   **USB:** Disconnect and reconnect the Lightning cable.

### "dpkg: error processing archive"
*   **Cause:** Corrupt .deb file or architecture mismatch.
*   **Fix:**
    *   Regenerate the .deb using `ios_deb_ip_changer_final.py`.
    *   Ensure the iPhone has enough storage space (`df -h`).
    *   Try installing manually via Filza on the device to see the exact error message.

### "Host key verification failed"
*   **Cause:** The SSH key fingerprint of the iPhone changed (common after re-jailbreaking).
*   **Fix:**
    *   Delete the cached key from the registry or `known_hosts`.
    *   Run the command manually in CMD to accept the new key: `.\plink.exe -ssh -P 2222 root@127.0.0.1`

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
