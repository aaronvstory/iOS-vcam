# Streaming Guide

This guide covers how to stream video from your PC to your iPhone using iOS-VCAM-Server.

## 📡 Method 1: WiFi Streaming (Easiest)

1.  **Connect Devices:** Ensure your PC and iPhone are on the **same WiFi network**. (5GHz recommended).
2.  **Start Server:** Run `iOS-VCAM-Launcher.exe`.
3.  **Select Profile:** Choose **Option [Q]** (Quick Start) or select a profile like `srs_iphone_ultra_smooth_dynamic.conf`.
4.  **Get URL:** The launcher will display an RTMP URL, e.g., `rtmp://192.168.1.50:1935/live/srs`.
5.  **Configure Source:**
    *   **OBS Studio:** Set "Stream" > "Service" to Custom. Server: `rtmp://192.168.1.50:1935/live/`, Key: `srs`.
    *   **FFmpeg:** `ffmpeg -re -i video.mp4 -c:v libx264 -f flv rtmp://192.168.1.50:1935/live/srs`
6.  **Configure iPhone:**
    *   Open your VCAM app/tweak settings.
    *   Enter the RTMP URL or the HLS URL (`http://192.168.1.50:8080/live/srs.m3u8`).
    *   Start the "Camera" app. The video feed should appear.

---

## 🔌 Method 2: USB Streaming (Lowest Latency)

For professional or long-term use, USB is superior due to zero interference and high bandwidth.

### Prerequisites
*   `libimobiledevice` (specifically `iproxy.exe`) installed on PC.
*   iPhone connected via USB.

### Setup Steps
1.  **Port Forwarding:**
    Open a command prompt and run:
    ```cmd
    iproxy.exe 1935 1935
    ```
    *Open a second terminal for HTTP if needed:*
    ```cmd
    iproxy.exe 8080 8080
    ```

2.  **Server Config:**
    *   In the Launcher, select **Option [3]** -> `srs_usb_smooth_playback.conf`.
    *   **Crucial:** This config is tuned for ultra-low latency.

3.  **iPhone Config:**
    *   Set the URL in your tweak to `rtmp://127.0.0.1:1935/live/srs`.
    *   *Note:* The iPhone connects to *itself* (localhost), which `iproxy` forwards to your PC via USB.

### Advanced USB (Reverse SSH)
If standard `iproxy` is unstable, use Reverse SSH.
1.  **Tunnel:** `ssh -R 1935:localhost:1935 root@localhost -p 2222` (assuming port 22 is forwarded to 2222 via iproxy).
2.  See [Advanced Features](Advanced-Features.md) for detailed SSH tunneling.

---

## 🎥 Using OBS Studio

1.  **Output Settings:**
    *   **Encoder:** Hardware (NVENC/QSV) preferred.
    *   **Bitrate:** 2000 Kbps - 4000 Kbps (WiFi), up to 8000 Kbps (USB).
    *   **Keyframe Interval:** **1 second** (Important for low latency).
    *   **Profile:** baseline or main.
    *   **Tune:** zerolatency.

2.  **Canvas:**
    *   Set Base/Output Resolution to match your iPhone's camera aspect ratio (usually 9:16, e.g., 1080x1920) if you are simulating a vertical camera.

---

## 📱 Viewing the Stream

*   **HLS (Safari):** `http://<IP>:8080/live/srs.m3u8`
*   **RTMP (Apps):** `rtmp://<IP>:1935/live/srs`
*   **Web Console:** `http://<IP>:8080/` (Click "SRS Player")

Next Step: [Troubleshooting](Troubleshooting.md)
