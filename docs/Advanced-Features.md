# Advanced Features

## 🔐 SSH & .deb Installation

The launcher includes a powerful feature (Option [9]) to install `.deb` packages directly to your iPhone.

### How it works
1.  **Discovery:** Scans `ios/modified_debs/` for packages.
2.  **Transport:** Uses `pscp.exe` (PuTTY SCP) to copy the file to `/var/mobile/Documents/`.
3.  **Installation:** Uses `plink.exe` to execute `dpkg -i` on the device.
4.  **Respring:** Can optionally restart SpringBoard or `mediaserverd`.

### Customizing SSH
If you changed your root password (recommended!):
*   The launcher prompts for credentials on first use (default: `alpine`). Your password is saved to `config.ini`.
*   You can also configure custom ports if you are using non-standard forwarding.

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

