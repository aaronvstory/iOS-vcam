#!/usr/bin/env python3
"""
iOS VCAM USB Tethering Monitor
==============================
Monitors USB tethering connection and manages SRS server for USB streaming.

Requirements:
- Windows 10/11
- iTunes installed (for Apple Mobile Device drivers)
- iPhone with Personal Hotspot enabled and connected via USB

Usage:
    python usb_tethering_monitor.py [--srs-home PATH] [--debug]

Author: Claude Code
Version: 1.0.0
"""

import socket
import subprocess
import time
import logging
import json
import sys
import threading
import os
from pathlib import Path
from typing import Optional, Callable
from dataclasses import dataclass
from enum import Enum

# =============================================================================
# LOGGING CONFIGURATION
# =============================================================================

def setup_logging(debug: bool = False, log_file: str = "usb_tethering.log"):
    """Configure logging with both console and file handlers."""
    log_level = logging.DEBUG if debug else logging.INFO

    # Create formatter
    formatter = logging.Formatter(
        '%(asctime)s [%(levelname)s] %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )

    # Get root logger
    logger = logging.getLogger()
    logger.setLevel(log_level)

    # Clear existing handlers
    logger.handlers.clear()

    # Console handler
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(log_level)
    console_handler.setFormatter(formatter)
    logger.addHandler(console_handler)

    # File handler
    try:
        file_handler = logging.FileHandler(log_file, encoding='utf-8')
        file_handler.setLevel(log_level)
        file_handler.setFormatter(formatter)
        logger.addHandler(file_handler)
    except Exception as e:
        logger.warning(f"Could not create log file: {e}")

    return logger

logger = logging.getLogger(__name__)

# =============================================================================
# DATA CLASSES AND ENUMS
# =============================================================================

class ConnectionState(Enum):
    """Connection state machine states."""
    DISCONNECTED = "disconnected"
    DETECTING = "detecting"
    CONNECTED = "connected"
    STREAMING = "streaming"
    RECONNECTING = "reconnecting"
    ERROR = "error"


@dataclass
class USBTetheringInfo:
    """Information about USB tethering connection."""
    adapter_name: str
    pc_ip: str
    iphone_ip: str
    subnet_mask: str
    gateway: str


# =============================================================================
# USB TETHERING MONITOR
# =============================================================================

class USBTetheringMonitor:
    """
    Monitors Windows network adapters for iPhone USB tethering connection.
    Detects when iPhone is connected and provides IP information.
    """

    # Known adapter name patterns for iPhone USB tethering
    ADAPTER_PATTERNS = [
        "Apple Mobile Device Ethernet",
        "iPhone USB",
        "Apple.*Ethernet",
    ]

    # Expected IP range for Personal Hotspot
    HOTSPOT_SUBNET = "172.20.10."

    def __init__(self):
        self.state = ConnectionState.DISCONNECTED
        self.tethering_info: Optional[USBTetheringInfo] = None
        self._stop_event = threading.Event()

    def detect_tethering_adapter(self) -> Optional[USBTetheringInfo]:
        """
        Detect iPhone USB tethering adapter using PowerShell.
        Returns USBTetheringInfo if found, None otherwise.
        """
        try:
            # Get network adapter information via PowerShell
            ps_command = '''
            Get-NetAdapter | Where-Object {
                $_.Status -eq "Up" -and
                ($_.Name -like "*Apple*" -or $_.InterfaceDescription -like "*Apple*" -or $_.Name -like "*iPhone*")
            } | ForEach-Object {
                $adapter = $_
                $ipconfig = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
                $gateway = Get-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
                if ($ipconfig) {
                    [PSCustomObject]@{
                        Name = $adapter.Name
                        Description = $adapter.InterfaceDescription
                        IP = $ipconfig.IPAddress
                        PrefixLength = $ipconfig.PrefixLength
                        Gateway = if ($gateway) { $gateway.NextHop } else { "" }
                    }
                }
            } | ConvertTo-Json
            '''

            result = subprocess.run(
                ["powershell", "-NoProfile", "-Command", ps_command],
                capture_output=True,
                text=True,
                timeout=15
            )

            if result.returncode != 0 or not result.stdout.strip():
                logger.debug("No Apple network adapter found")
                return None

            adapters = json.loads(result.stdout)

            # Handle single adapter (not a list)
            if isinstance(adapters, dict):
                adapters = [adapters]

            for adapter in adapters:
                ip = adapter.get("IP", "")
                if ip.startswith(self.HOTSPOT_SUBNET):
                    # Calculate iPhone IP (usually .1)
                    ip_parts = ip.split(".")
                    iphone_ip = f"{ip_parts[0]}.{ip_parts[1]}.{ip_parts[2]}.1"

                    # Calculate subnet mask from prefix length
                    prefix = int(adapter.get("PrefixLength", 24))
                    subnet_mask = self._prefix_to_netmask(prefix)

                    return USBTetheringInfo(
                        adapter_name=adapter.get("Name", "Unknown"),
                        pc_ip=ip,
                        iphone_ip=iphone_ip,
                        subnet_mask=subnet_mask,
                        gateway=adapter.get("Gateway", iphone_ip)
                    )

            return None

        except json.JSONDecodeError as e:
            logger.debug(f"JSON decode error: {e}")
            return None
        except subprocess.TimeoutExpired:
            logger.warning("PowerShell command timed out")
            return None
        except Exception as e:
            logger.error(f"Error detecting tethering adapter: {e}")
            return None

    def _prefix_to_netmask(self, prefix: int) -> str:
        """Convert CIDR prefix to dotted netmask."""
        mask = (0xffffffff >> (32 - prefix)) << (32 - prefix)
        return f"{(mask >> 24) & 0xff}.{(mask >> 16) & 0xff}.{(mask >> 8) & 0xff}.{mask & 0xff}"

    def test_iphone_connectivity(self, iphone_ip: str, timeout: float = 2.0) -> bool:
        """
        Test TCP connectivity to iPhone on expected ports.
        """
        test_ports = [62078, 22, 44, 80]  # lockdownd, SSH, checkra1n SSH, HTTP

        for port in test_ports:
            try:
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(timeout)
                result = sock.connect_ex((iphone_ip, port))
                sock.close()
                if result == 0:
                    logger.debug(f"iPhone reachable on port {port}")
                    return True
            except Exception:
                pass

        # Try ICMP ping as fallback
        try:
            result = subprocess.run(
                ["ping", "-n", "1", "-w", str(int(timeout * 1000)), iphone_ip],
                capture_output=True,
                timeout=timeout + 2
            )
            return result.returncode == 0
        except Exception:
            return False

    def wait_for_connection(self, poll_interval: float = 2.0) -> USBTetheringInfo:
        """
        Block until USB tethering connection is detected.
        Returns USBTetheringInfo when connected.
        """
        self.state = ConnectionState.DETECTING
        logger.info("Waiting for iPhone USB tethering connection...")
        logger.info("")
        logger.info("  SETUP INSTRUCTIONS:")
        logger.info("  1. On iPhone: Settings -> Personal Hotspot")
        logger.info("  2. Enable 'Allow Others to Join'")
        logger.info("  3. Connect iPhone to PC via USB cable")
        logger.info("  4. Wait for Windows to detect adapter...")
        logger.info("")

        dots = 0
        while not self._stop_event.is_set():
            info = self.detect_tethering_adapter()

            if info:
                # Verify connectivity
                logger.debug(f"Adapter found: {info.adapter_name}, testing connectivity...")
                if self.test_iphone_connectivity(info.iphone_ip):
                    self.tethering_info = info
                    self.state = ConnectionState.CONNECTED
                    logger.info("")
                    logger.info("USB Tethering connected!")
                    logger.info(f"  Adapter: {info.adapter_name}")
                    logger.info(f"  PC IP: {info.pc_ip}")
                    logger.info(f"  iPhone IP: {info.iphone_ip}")
                    return info
                else:
                    logger.debug(f"Adapter found but iPhone not responding on {info.iphone_ip}")

            # Progress indicator
            dots = (dots + 1) % 4
            print(f"\r  Scanning{'.' * dots}{'   ' * (3 - dots)}", end="", flush=True)
            time.sleep(poll_interval)

        raise InterruptedError("Connection wait interrupted")

    def monitor_connection(self, callback: Optional[Callable] = None, poll_interval: float = 5.0):
        """
        Continuously monitor connection status.
        Calls callback(connected: bool, info: USBTetheringInfo) on state changes.
        """
        last_connected = False
        reconnect_start_time = None
        RECONNECT_GRACE_PERIOD = 30  # seconds

        while not self._stop_event.is_set():
            info = self.detect_tethering_adapter()
            connected = info is not None and self.test_iphone_connectivity(info.iphone_ip)

            if connected != last_connected:
                if connected:
                    # Connection restored
                    self.state = ConnectionState.CONNECTED
                    self.tethering_info = info
                    reconnect_start_time = None

                    if callback:
                        callback(True, info)

                    logger.info(f"USB Tethering: CONNECTED (PC: {info.pc_ip}, iPhone: {info.iphone_ip})")
                else:
                    # Connection lost - start grace period
                    if reconnect_start_time is None:
                        reconnect_start_time = time.time()
                        self.state = ConnectionState.RECONNECTING
                        logger.warning("USB connection interrupted, attempting reconnect...")

                    elapsed = time.time() - reconnect_start_time
                    if elapsed < RECONNECT_GRACE_PERIOD:
                        logger.debug(f"Reconnect attempt... ({int(elapsed)}s / {RECONNECT_GRACE_PERIOD}s)")
                        # Don't update last_connected yet - give it time to reconnect
                        time.sleep(poll_interval)
                        continue
                    else:
                        # Grace period expired
                        self.state = ConnectionState.DISCONNECTED
                        self.tethering_info = None
                        reconnect_start_time = None

                        if callback:
                            callback(False, None)

                        logger.warning("USB Tethering: DISCONNECTED (grace period expired)")

                last_connected = connected

            time.sleep(poll_interval)

    def stop(self):
        """Stop monitoring."""
        self._stop_event.set()


# =============================================================================
# SRS SERVER MANAGER
# =============================================================================

class SRSServerManager:
    """
    Manages SRS server process for USB streaming.
    """

    def __init__(self, srs_home: Path):
        self.srs_home = srs_home
        self.srs_exe = srs_home / "objs" / "srs.exe"
        self.config_dir = srs_home / "config" / "active"
        self.process: Optional[subprocess.Popen] = None

    def get_usb_config(self) -> Path:
        """Get or create USB-optimized config."""
        # Use dynamic config which binds to all interfaces
        config_path = self.config_dir / "srs_iphone_ultra_smooth_dynamic.conf"
        if config_path.exists():
            return config_path

        # Fallback to standard config
        config_path = self.config_dir / "srs_iphone_ultra_smooth.conf"
        if config_path.exists():
            return config_path

        # Last resort - any .conf file
        conf_files = list(self.config_dir.glob("*.conf"))
        if conf_files:
            return conf_files[0]

        raise FileNotFoundError(f"No config files found in {self.config_dir}")

    def start(self, bind_ip: str = "0.0.0.0") -> bool:
        """
        Start SRS server bound to specified IP.
        """
        if self.process and self.process.poll() is None:
            logger.info("SRS already running (PID: {})".format(self.process.pid))
            return True

        if not self.srs_exe.exists():
            logger.error(f"SRS executable not found: {self.srs_exe}")
            return False

        try:
            config_path = self.get_usb_config()
            logger.info(f"Starting SRS with config: {config_path.name}")

            self.process = subprocess.Popen(
                [str(self.srs_exe), "-c", str(config_path)],
                cwd=str(self.srs_home),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
            )

            # Wait a moment and check if started
            time.sleep(2)
            if self.process.poll() is not None:
                # Process exited - read output for error
                output, _ = self.process.communicate()
                logger.error(f"SRS failed to start: {output[:500] if output else 'Unknown error'}")
                return False

            logger.info(f"SRS server started (PID: {self.process.pid})")
            return True

        except FileNotFoundError as e:
            logger.error(f"Config error: {e}")
            return False
        except Exception as e:
            logger.error(f"Failed to start SRS: {e}")
            return False

    def stop(self):
        """Stop SRS server."""
        if self.process:
            logger.info("Stopping SRS server...")
            try:
                self.process.terminate()
                self.process.wait(timeout=5)
                logger.info("SRS server stopped")
            except subprocess.TimeoutExpired:
                logger.warning("SRS did not stop gracefully, killing...")
                self.process.kill()
            except Exception as e:
                logger.error(f"Error stopping SRS: {e}")
            finally:
                self.process = None

    def is_running(self) -> bool:
        """Check if SRS is running."""
        return self.process is not None and self.process.poll() is None


# =============================================================================
# USB STREAMING CONTROLLER
# =============================================================================

class USBStreamingController:
    """
    Main controller for USB streaming workflow.
    """

    def __init__(self, srs_home: Path):
        self.monitor = USBTetheringMonitor()
        self.srs_manager = SRSServerManager(srs_home)
        self._running = False
        self.current_rtmp_url = None

    def generate_rtmp_url(self, tethering_info: USBTetheringInfo) -> str:
        """Generate RTMP URL for iPhone to connect to."""
        return f"rtmp://{tethering_info.pc_ip}:1935/live/srs"

    def copy_to_clipboard(self, text: str) -> bool:
        """Copy text to Windows clipboard."""
        try:
            subprocess.run(
                ["powershell", "-Command", f"Set-Clipboard -Value '{text}'"],
                capture_output=True,
                timeout=5
            )
            return True
        except Exception:
            return False

    def on_connection_change(self, connected: bool, info: Optional[USBTetheringInfo]):
        """Handle connection state changes."""
        if connected and info:
            self.current_rtmp_url = self.generate_rtmp_url(info)
            logger.info("")
            logger.info("=" * 60)
            logger.info("  USB STREAMING READY!")
            logger.info(f"  RTMP URL: {self.current_rtmp_url}")
            logger.info("=" * 60)
            logger.info("")

            # Copy to clipboard
            if self.copy_to_clipboard(self.current_rtmp_url):
                logger.info("  RTMP URL copied to clipboard!")

            logger.info("  Configure your iPhone VCAM app to connect to this URL")
            logger.info("  Or use .deb with IP: {}".format(info.pc_ip.replace(".", "_")))
            logger.info("")
        else:
            self.current_rtmp_url = None
            logger.warning("")
            logger.warning("USB connection lost - streaming may be interrupted")
            logger.warning("Waiting for reconnection...")
            logger.warning("")

    def run(self):
        """
        Main run loop:
        1. Wait for USB tethering connection
        2. Start SRS server
        3. Monitor connection and provide RTMP URL
        4. Handle reconnection on disconnect
        """
        self._running = True

        print("")
        print("=" * 60)
        print("  iOS VCAM USB Streaming Controller")
        print("  ----------------------------------")
        print("  Stream via USB cable (no WiFi needed)")
        print("  Press Ctrl+C to stop")
        print("=" * 60)
        print("")

        try:
            while self._running:
                # Wait for connection
                try:
                    info = self.monitor.wait_for_connection()
                except InterruptedError:
                    break

                # Start SRS if not running
                if not self.srs_manager.is_running():
                    if not self.srs_manager.start():
                        logger.error("Failed to start SRS, retrying in 5s...")
                        time.sleep(5)
                        continue

                # Show connection info
                self.on_connection_change(True, info)

                # Monitor connection (blocks until stop or disconnect)
                self.monitor.monitor_connection(
                    callback=self.on_connection_change,
                    poll_interval=3.0
                )

        except KeyboardInterrupt:
            logger.info("")
            logger.info("Shutting down (Ctrl+C)...")
        finally:
            self.stop()

    def stop(self):
        """Stop controller and cleanup."""
        self._running = False
        self.monitor.stop()
        self.srs_manager.stop()
        logger.info("USB Streaming Controller stopped")


# =============================================================================
# MAIN ENTRY POINT
# =============================================================================

def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="iOS VCAM USB Streaming Controller",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python usb_tethering_monitor.py
    python usb_tethering_monitor.py --srs-home "C:\\path\\to\\iOS-VCAM"
    python usb_tethering_monitor.py --debug

Setup Instructions:
    1. On iPhone: Settings -> Personal Hotspot -> Enable
    2. Connect iPhone to PC via USB cable
    3. Run this script
    4. Install .deb with USB IP on iPhone
    5. Start streaming!
        """
    )
    parser.add_argument(
        "--srs-home",
        type=Path,
        default=Path("."),
        help="Path to iOS-VCAM installation directory (default: current directory)"
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Enable debug logging"
    )
    parser.add_argument(
        "--log-file",
        type=str,
        default="usb_tethering.log",
        help="Log file path (default: usb_tethering.log)"
    )

    args = parser.parse_args()

    # Setup logging
    setup_logging(debug=args.debug, log_file=args.log_file)

    # Validate SRS installation
    srs_exe = args.srs_home / "objs" / "srs.exe"
    if not srs_exe.exists():
        # Try parent directories
        for parent in [args.srs_home.parent, args.srs_home.parent.parent]:
            test_exe = parent / "objs" / "srs.exe"
            if test_exe.exists():
                args.srs_home = parent
                srs_exe = test_exe
                break

    if not srs_exe.exists():
        logger.error(f"SRS not found at: {srs_exe}")
        logger.error("Please run from iOS-VCAM directory or specify --srs-home")
        logger.error("")
        logger.error("Example:")
        logger.error('  python usb_tethering_monitor.py --srs-home "F:\\iOS-VCAM"')
        sys.exit(1)

    logger.info(f"SRS Home: {args.srs_home.absolute()}")

    # Run controller
    controller = USBStreamingController(args.srs_home)
    controller.run()


if __name__ == "__main__":
    main()
