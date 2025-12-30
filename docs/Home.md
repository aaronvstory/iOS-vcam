# iOS-VCAM-Server Wiki

Welcome to the **iOS-VCAM-Server** documentation. This wiki provides comprehensive guides for installing, configuring, and using the iOS-VCAM streaming server, optimized for jailbroken iOS devices.

## 🆕 What's New (v3.2+)

*   **SSH Installation Tool (Option [9]):** Directly install or update `.deb` packages to your iPhone from the launcher. No more manual file copying! [Read more](Advanced-Features.md#automated-installation-option-9)
*   **Enhanced Debranding:** Improved tools for customizing the iOS package identity.
*   **Stability Fixes:** Solved PowerShell parser errors and improved USB tunneling stability.

## 📚 Table of Contents

### [🚀 Installation Guide](Installation.md)
*   **Prerequisites** (Windows & iOS)
*   **Server Setup** (Launcher, Python, Drivers)
*   **iOS Setup** (Jailbreak, Tweaks, Dependencies)

### [⚙️ Configuration Guide](Configuration.md)
*   **Configuration Profiles** (Ultra Smooth, Low Latency, etc.)
*   **Key Parameters** (HLS fragments, Buffer length)
*   **Network Settings** (Ports, IPs)

### [🎥 Streaming Guide](Streaming-Guide.md)
*   **Quick Start** (Launch & Connect)
*   **WiFi Streaming** (Best practices)
*   **USB Streaming** (High reliability, low latency)
*   **OBS Integration** (Streaming from PC to iPhone)

### [🔧 Troubleshooting](Troubleshooting.md)
*   **Common Issues** (Connection failed, Choppy stream)
*   **Diagnostics** (Using the launcher diagnostics)
*   **Crash Fixes** (Known solutions)

### [🔄 Post-Reboot Checklist](Post-Reboot-Checklist.md)
*   **What Gets Lost** (sshd config, host keys, aliases)
*   **Quick Fix Commands** (One-liner fixes via plink)
*   **Persistence** (Making settings survive reboots)

### [🔍 USB Streaming Debugging](USB-Streaming-Debugging.md)
*   **Quick Diagnostic Commands** (7 essential checks)
*   **Common Error Messages** (With exact solutions)
*   **Debugging Flowchart** (Visual troubleshooting guide)
*   **Lessons Learned** (Avoid repeating mistakes)

### [🧠 Advanced Features](Advanced-Features.md)
*   **SSH & .deb Installation** (Automated package management)
*   **Debranding** (Customizing the iOS package)
*   **Frida & Hooks** (Application analysis)
*   **Architecture** (SRS, Monibuca, Flask)

---

## Project Overview

**iOS-VCAM-Server** is a Windows-based RTMP streaming server solution designed to feed video *into* jailbroken iOS devices (simulating a camera). It bundles:
*   **SRS (Simple Realtime Server)** for high-performance RTMP/HLS streaming.
*   **Monibuca** as an alternative media server.
*   **Python/Flask Auth Server** for app pairing.
*   **PowerShell Launcher** for easy management.
*   **iOS Tools** for creating and injecting custom configuration packages.

## Quick Links
*   [GitHub Repository](https://github.com/ossrs/srs) (SRS Base)
*   [Project README](../README.md)
