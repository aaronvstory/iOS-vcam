#!/usr/bin/env python3
"""
iOS VCAM USBMux Listener (Host Side)
===================================
Creates a USB mux connection to the iPhone forwarder port and bridges it to
local SRS (127.0.0.1:1935).

This uses pymobiledevice3 to expose a local TCP port that forwards to a device
port over usbmuxd. No SSH encryption.

Usage:
  python usb_usbmux_listener.py
  python usb_usbmux_listener.py --device-port 62000 --local-port 62001
  python usb_usbmux_listener.py --no-usbmux-forward
"""

import argparse
import os
import socket
import subprocess
import sys
import threading
import time
from typing import Optional

DEFAULT_DEVICE_PORT = 62000
DEFAULT_LOCAL_PORT = 62001
DEFAULT_SRS_HOST = "127.0.0.1"
DEFAULT_SRS_PORT = 1935
RETRY_DELAY = 2.0
CONNECT_TIMEOUT = 5.0


def get_first_device_serial() -> Optional[str]:
    """Auto-detect the first connected iOS device serial/UDID."""
    try:
        import json
        result = subprocess.run(
            [sys.executable, "-m", "pymobiledevice3", "usbmux", "list"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode == 0 and result.stdout.strip():
            devices = json.loads(result.stdout)
            if devices and len(devices) > 0:
                return devices[0].get("Identifier") or devices[0].get("UniqueDeviceID")
    except Exception as e:
        print(f"Warning: Could not auto-detect device: {e}")
    return None


class USBMuxForwarder:
    def __init__(self, local_port: int, device_port: int, python_exe: str, serial: Optional[str] = None):
        self.local_port = local_port
        self.device_port = device_port
        self.python_exe = python_exe
        self.serial = serial
        self.proc: Optional[subprocess.Popen] = None

    def start(self) -> None:
        if self.proc and self.proc.poll() is None:
            return

        # Auto-detect serial if not provided
        serial = self.serial
        if not serial:
            print("Auto-detecting iOS device...")
            serial = get_first_device_serial()
            if not serial:
                print("ERROR: No iOS device found. Connect iPhone via USB.")
                return
            print(f"Found device: {serial}")

        cmd = [
            self.python_exe,
            "-m",
            "pymobiledevice3",
            "usbmux",
            "forward",
            "--serial",
            serial,
            str(self.local_port),
            str(self.device_port),
        ]

        self.proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

    def stop(self) -> None:
        if self.proc and self.proc.poll() is None:
            try:
                self.proc.terminate()
                self.proc.wait(timeout=5)
            except Exception:
                self.proc.kill()
        self.proc = None

    def is_running(self) -> bool:
        return self.proc is not None and self.proc.poll() is None


class USBMuxListener:
    def __init__(
        self,
        local_port: int,
        device_port: int,
        srs_host: str,
        srs_port: int,
        use_usbmux_forward: bool,
        serial: Optional[str] = None,
    ):
        self.local_port = local_port
        self.device_port = device_port
        self.srs_host = srs_host
        self.srs_port = srs_port
        self.use_usbmux_forward = use_usbmux_forward
        self._stop = False
        self.forwarder = USBMuxForwarder(local_port, device_port, sys.executable, serial)

    def stop(self) -> None:
        self._stop = True
        if self.forwarder:
            self.forwarder.stop()

    def _connect_local(self) -> socket.socket:
        return socket.create_connection(("127.0.0.1", self.local_port), timeout=CONNECT_TIMEOUT)

    def _connect_srs(self) -> socket.socket:
        return socket.create_connection((self.srs_host, self.srs_port), timeout=CONNECT_TIMEOUT)

    @staticmethod
    def _pipe(src: socket.socket, dst: socket.socket) -> None:
        try:
            while True:
                data = src.recv(16384)
                if not data:
                    break
                dst.sendall(data)
        except Exception:
            pass

    def _bridge(self, dev_sock: socket.socket, srs_sock: socket.socket) -> None:
        t1 = threading.Thread(target=self._pipe, args=(dev_sock, srs_sock), daemon=True)
        t2 = threading.Thread(target=self._pipe, args=(srs_sock, dev_sock), daemon=True)
        t1.start()
        t2.start()
        t1.join()
        t2.join()

    def run(self) -> None:
        print("USBMux Listener starting...")
        print(f"Device port: {self.device_port}")
        print(f"Local forward port: {self.local_port}")
        print(f"SRS target: {self.srs_host}:{self.srs_port}")
        print("")

        while not self._stop:
            dev_sock = None
            srs_sock = None
            try:
                if self.use_usbmux_forward:
                    if not self.forwarder.is_running():
                        print("Starting pymobiledevice3 usbmux forward...")
                        self.forwarder.start()

                print("Connecting to iPhone forwarder...")
                while not self._stop:
                    try:
                        dev_sock = self._connect_local()
                        break
                    except Exception:
                        print("Waiting for usbmux forward to become ready...")
                        time.sleep(RETRY_DELAY)
                if dev_sock is None:
                    continue

                print("Connecting to local SRS...")
                srs_sock = self._connect_srs()

                print("Bridge active. Waiting for stream...")
                self._bridge(dev_sock, srs_sock)
                print("Bridge ended. Reconnecting...")

            except KeyboardInterrupt:
                self.stop()
                break
            except Exception as exc:
                print(f"Error: {exc}")
                time.sleep(RETRY_DELAY)
            finally:
                try:
                    dev_sock.close()
                except Exception:
                    pass
                try:
                    srs_sock.close()
                except Exception:
                    pass

        self.stop()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="iOS VCAM USBMux Listener")
    parser.add_argument("--device-port", type=int, default=DEFAULT_DEVICE_PORT)
    parser.add_argument("--local-port", type=int, default=DEFAULT_LOCAL_PORT)
    parser.add_argument("--srs-host", type=str, default=DEFAULT_SRS_HOST)
    parser.add_argument("--srs-port", type=int, default=DEFAULT_SRS_PORT)
    parser.add_argument(
        "--serial",
        type=str,
        default=None,
        help="iOS device serial/UDID (auto-detected if not provided)",
    )
    parser.add_argument(
        "--no-usbmux-forward",
        action="store_true",
        help="Do not spawn pymobiledevice3 usbmux forward (assume already running)",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    if not args.no_usbmux_forward:
        # Basic dependency check
        try:
            import pymobiledevice3  # noqa: F401
        except Exception:
            print("pymobiledevice3 not found. Install with:")
            print("  python -m pip install pymobiledevice3")
            sys.exit(1)

    listener = USBMuxListener(
        local_port=args.local_port,
        device_port=args.device_port,
        srs_host=args.srs_host,
        srs_port=args.srs_port,
        use_usbmux_forward=not args.no_usbmux_forward,
        serial=args.serial,
    )

    listener.run()


if __name__ == "__main__":
    main()
