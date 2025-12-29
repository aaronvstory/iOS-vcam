# Advanced Features

## 🔐 SSH & .deb Installation

> **Security Note:** This tool is designed for **personal use on your own devices** over a direct USB connection. The SSH credentials (default: `alpine`) connect only to your locally-attached iPhone—there is no network exposure. Password-based authentication is used for simplicity; advanced users who prefer key-based auth can configure their iPhone's OpenSSH accordingly and disable the password prompt in `config.ini`.

The launcher includes a powerful feature (**Option [9]**) to install `.deb` packages directly to your iPhone without manual file transfer.

### Automated Installation (Option [9])
This feature streamlines the process of updating your VCAM tweak or installing modified packages.

**How it works:**
1.  **Discovery:** Scans `ios/modified_debs/` for available packages.
2.  **Connection Test:** Automatically verifies SSH connectivity to the device before attempting transfer.
3.  **Transport:** Uses `pscp.exe` (PuTTY SCP) to securely copy the selected file to `/var/mobile/Documents/`.
4.  **Installation:** Uses `plink.exe` to execute `dpkg --force-architecture --force-depends -i [file]` on the device.
5.  **Respring:** Can optionally restart SpringBoard or `mediaserverd` to apply changes immediately.

### Customizing SSH
The launcher uses default credentials but fully supports custom configurations.

*   **Default:** `localhost:22` (via USB tunnel) or local IP, User: `root`, Password: `alpine`.
*   **Custom:** If you have changed your root password (highly recommended) or use a non-standard port:
    *   The launcher will prompt for credentials if the default fails.
    *   Your custom password and port settings are saved to `config.ini` for future use.

### Manual SSH Tools
The distribution includes `plink.exe` and `pscp.exe` in the root directory. You can use these for your own scripting:
```powershell
# Run a command
.\plink.exe -ssh root@localhost -P 2222 -pw alpine "ls -la"

# Copy a file
.\pscp.exe -P 2222 -pw alpine myfile.deb root@localhost:/var/mobile/Documents/
```

---

## 🎨 Debranding

You can modify the iOS package to inject your server's IP address, making the installation "Plug & Play" for the device.

**Tool:** `ios/ios_deb_ip_changer_final.py`

**Usage:**
```bash
python ios/ios_deb_ip_changer_final.py --base ios/iosvcam_base.deb 192.168.1.50
```
This creates a new `.deb` file with `192.168.1.50` hardcoded as the default control server.

---

## 🕵️ Frida & App Analysis

For advanced users analyzing target applications (e.g., for bypassing jailbreak detection or SSL pinning), we use **Frida**.

### Setup
1.  Install `frida-tools` on PC: `pip install frida-tools`.
2.  Install Frida Server on iPhone (via Sileo).

### USB Connection (No SSH needed)
Frida can communicate directly over USB mux.
```bash
frida-ps -U  # List processes on USB device
```

### Hooking
Use the scripts in the `ios/` or `frida/` folders (if available) to spawn apps with hooks:
```bash
frida -U -f com.example.targetapp -l my_hook.js
```

See [HOW-WE-CONNECTED-IPHONE-FRIDA.md](HOW-WE-CONNECTED-IPHONE-FRIDA.md) for a detailed walkthrough.

---

## 🚇 Reverse SSH Tunneling (USB)

If you cannot use `iproxy` for the stream (e.g., Windows firewall issues), you can use a **Reverse SSH Tunnel**.

**Command:**
```bash
ssh -R 1935:localhost:1935 root@localhost -p 2222
```

**Explanation:**
*   `-R 1935:localhost:1935`: Listen on iPhone port 1935. Forward traffic to PC (localhost relative to SSH client) port 1935.
*   `root@localhost -p 2222`: Connect to iPhone via local forwarded port 2222.

This makes the iPhone "think" it has a local service on 1935, which is actually your PC's SRS server.

---

## 🏗 System Architecture

### Components
1.  **SRS (C++)**: Handles RTMP ingest, HLS segmentation, and HTTP delivery.
2.  **Flask (Python)**: Provides a lightweight API and authentication endpoint (`/auth`).
3.  **Nginx (Optional)**: Can be used as a reverse proxy (bundled in some distributions).
4.  **Launcher (PowerShell)**: Orchestrator. Checks network, updates configs, manages processes.

### Data Flow
1.  **PC (OBS)** --[RTMP]--> **SRS (Port 1935)**
2.  **SRS** --[HLS/RTMP]--> **Internal Buffer**
3.  **iPhone (Tweak)** --[Request]--> **SRS (Port 8080/1935)**
4.  **iPhone (App)** <--[Video Feed]-- **Camera Driver**

