# Configuration Guide

The iOS-VCAM-Server comes with multiple pre-tuned configuration profiles for SRS. These are located in `config/active/`.

## ⚙️ Selecting a Profile

You can switch profiles using the **Launcher (Option [3])** or by manually editing the startup arguments.

| Profile Name | Description | Best For |
| :--- | :--- | :--- |
| **`srs_iphone_ultra_smooth_dynamic.conf`** | **(Recommended)** Balanced config with dynamic adjustments. | General WiFi streaming. |
| **`srs_iphone_optimized_smooth.conf`** | Standard 2s latency, medium buffer. | Stable home WiFi. |
| **`srs_iphone_max_smooth.conf`** | High buffer (5s), high latency. | Poor/Unstable networks. |
| **`srs_iphone_motion_smooth.conf`** | Low buffer, optimized for frame rate. | Gaming, high-motion video. |
| **`srs_usb_smooth_playback.conf`** | Ultra-low latency (<0.5s), minimal buffer. | **USB Streaming** (wired). |
| **`srs_iphone_ultra_smooth.conf`** | 3s fragment size, very stable. | Moderate WiFi. |

---

## 📝 Key Configuration Parameters

If you want to create a custom config, these are the most critical parameters in the `.conf` files:

### HLS / HTTP Streaming
These control the latency and stability for the iPhone client (which often uses HLS/HTTP).

```nginx
vhost __defaultVhost__ {
    hls {
        enabled         on;
        hls_fragment    2.0;    # Seconds per segment. Lower = Lower Latency, Higher CPU.
        hls_window      4.0;    # Total seconds in playlist. Lower = Less Buffer.
        hls_wait_keyframe on;   # Wait for keyframe to cut segment (Critical for sync).
    }
}
```

### RTMP Queue
Controls the buffer on the ingest side.

```nginx
vhost __defaultVhost__ {
    queue_length    3000;   # Milliseconds of buffer.
    mw_latency      100;    # Merge write latency (ms).
}
```

### Dynamic IP Injection
The launcher automatically injects your PC's local IP address into these configs at runtime. You will see placeholders or updated IPs in the files managed by the launcher.

---

## 🔧 Editing Configurations

1.  Navigate to `config/active/`.
2.  Duplicate an existing `.conf` file.
3.  Edit with a text editor (VS Code, Notepad++).
4.  Restart the server (Launcher Option [1]) to apply changes.

**Note:** The launcher overwrites certain temp files. It is best to keep your custom configs with a unique name in `config/active/`.

Next Step: [Streaming Guide](Streaming-Guide.md)
