#!/usr/bin/env python3
"""
iOS .deb Package IP Changer - Final Fixed Version
==================================================
Uses proper LZMA compression that iOS dpkg can handle
"""

import os
import sys
import shutil
import tarfile
import gzip
import socket
import subprocess
import re
import json
import ipaddress
import struct
import argparse
import io
import lzma
from pathlib import Path
from dataclasses import dataclass

@dataclass
class ParsedDeb:
    debian_binary: bytes
    control_tar_gz: bytes
    data_member_name: str
    data_payload_bytes: bytes  # compressed as found
    data_tar_raw: bytes        # decompressed tar bytes (for modification)

class DebIPChanger:
    def __init__(self):
        self.original_deb = "iosvcam_base.deb"  # Using de-branded package
        self.work_dir = "deb_work_temp"
        self.output_dir = "modified_debs"
        self.config_file = "ip_changer_config.json"
        self._parsed_base = None  # Store parsed base package
        self.apply_tweak = False

    def apply_latency_patches(self, file_path):
        """Apply the 1s latency/bursting fix patches"""
        print("    - Applying 1s latency/bursting fix patches...")
        with open(file_path, 'rb') as f:
            data = bytearray(f.read())

        # Patch List (Offset, Old Bytes, New Bytes, Description)
        patches = [
            # 56 / 120 Frame Counter Patches (likely flush interval)
            (0x3D67C, b'\x08\x07\x80\x52', b'\x28\x00\x80\x52', 'W8 = 56 -> 1'),
            (0x3D690, b'\x08\x0F\x80\x52', b'\x28\x00\x80\x52', 'W8 = 120 -> 1'),
            (0x4885C, b'\x08\x07\x80\x52', b'\x28\x00\x80\x52', 'W8 = 56 -> 1'),
            (0x48870, b'\x08\x0F\x80\x52', b'\x28\x00\x80\x52', 'W8 = 120 -> 1'),
            (0x4FA44, b'\x08\x07\x80\x52', b'\x28\x00\x80\x52', 'W8 = 56 -> 1'),
            (0x4FA58, b'\x08\x0F\x80\x52', b'\x28\x00\x80\x52', 'W8 = 120 -> 1'),
            (0x179D50, b'\x08\x07\x80\x52', b'\x28\x00\x80\x52', 'W8 = 56 -> 1'),
            (0x179D64, b'\x08\x0F\x80\x52', b'\x28\x00\x80\x52', 'W8 = 120 -> 1'),
            (0x185044, b'\x08\x07\x80\x52', b'\x28\x00\x80\x52', 'W8 = 56 -> 1'),
            (0x185058, b'\x08\x0F\x80\x52', b'\x28\x00\x80\x52', 'W8 = 120 -> 1'),
            (0x18C258, b'\x08\x07\x80\x52', b'\x28\x00\x80\x52', 'W8 = 56 -> 1'),
            (0x18C26C, b'\x08\x0F\x80\x52', b'\x28\x00\x80\x52', 'W8 = 120 -> 1'),

            # 1000ms Buffer Settings Patches
            (0x49054, b'\x08\x7D\x80\x52', b'\x28\x00\x80\x52', 'W8 = 1000 -> 1'),
            (0x49064, b'\x02\x7D\x80\xD2', b'\x22\x00\x80\xD2', 'X2 = 1000 -> 1'),
            (0x50400, b'\x08\x7D\x80\x52', b'\x28\x00\x80\x52', 'W8 = 1000 -> 1'),
            (0x50410, b'\x02\x7D\x80\xD2', b'\x22\x00\x80\xD2', 'X2 = 1000 -> 1'),
            (0x524DC, b'\x08\x7D\x80\x52', b'\x28\x00\x80\x52', 'W8 = 1000 -> 1'),
            (0x524EC, b'\x02\x7D\x80\xD2', b'\x22\x00\x80\xD2', 'X2 = 1000 -> 1'),
            (0x60618, b'\x03\xFA\x80\x52', b'\x23\x00\x80\x52', 'W3 = 2000 -> 1'),
            (0x1A366C, b'\x0A\x7D\x80\x52', b'\x2A\x00\x80\x52', 'W10 = 1000 -> 1'),
            (0x1BD80C, b'\x08\x7D\x80\x52', b'\x28\x00\x80\x52', 'W8 = 1000 -> 1'),
        ]

        applied_count = 0
        for offset, old, new, desc in patches:
            if offset + len(old) > len(data):
                continue
            actual = data[offset:offset+len(old)]
            if actual == old:
                data[offset:offset+len(old)] = new
                applied_count += 1
        
        if applied_count > 0:
            with open(file_path, 'wb') as f:
                f.write(data)
            print(f"      ✓ Applied {applied_count}/{len(patches)} latency fix patches")
            return True
        return False

    def print_header(self):
        """Print application header"""
        print("=" * 70)
        print("iOS .deb Package IP Changer - Professional Tool (Final Fix)")
        print("=" * 70)
        print()

    def suggest_valid_ip_format(self, ip_string):
        """Suggest a valid 12-character IP format based on input"""
        parts = ip_string.split('.')
        if len(parts) != 4:
            return None

        suggestions = []

        # Try padding with zeros
        try:
            octets = [int(p) for p in parts]
            # Format 1: XXX.XXX.X.XX (like 192.168.1.91)
            if octets[0] >= 100 and octets[1] >= 100 and octets[2] < 10 and octets[3] >= 10:
                suggestions.append(f"{octets[0]}.{octets[1]}.{octets[2]}.{octets[3]:02d}")

            # Format 2: XX.XX.XX.XXX (like 10.10.10.100)
            if all(10 <= o < 100 for o in octets[:3]) and octets[3] >= 100:
                suggestions.append(f"{octets[0]:02d}.{octets[1]:02d}.{octets[2]:02d}.{octets[3]}")

            # Format 3: XXX.XX.XX.XX (like 172.16.10.50)
            if octets[0] >= 100 and all(10 <= o < 100 for o in octets[1:]):
                suggestions.append(f"{octets[0]}.{octets[1]:02d}.{octets[2]:02d}.{octets[3]:02d}")

        except ValueError:
            pass

        return suggestions if suggestions else None

    def validate_ip(self, ip_string):
        """Validate IP address format and length (must be exactly 12 characters)"""
        try:
            # First check if it's a valid IP
            ipaddress.ip_address(ip_string)

            # Then check if it's exactly 12 characters (like 192.168.1.91)
            if len(ip_string) != 12:
                print(f"  ⚠ IP '{ip_string}' is {len(ip_string)} chars, must be exactly 12 chars")
                print(f"    Valid format examples: 192.168.1.91, 10.10.10.100, 172.16.10.50")

                # Try to suggest valid formats
                suggestions = self.suggest_valid_ip_format(ip_string)
                if suggestions:
                    print(f"    Suggested format(s) for your IP:")
                    for suggestion in suggestions:
                        print(f"      → {suggestion}")

                return False

            return True
        except:
            return False

    def get_network_ips(self):
        """Get all network adapter IPs"""
        ips = []
        try:
            cmd = 'powershell -Command "Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -notlike \'127.*\' -and $_.IPAddress -notlike \'169.254.*\'} | Select-Object -ExpandProperty IPAddress"'
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
            if result.returncode == 0:
                for line in result.stdout.strip().split('\n'):
                    if line and self.validate_ip(line):
                        ips.append(line)
        except:
            pass

        if not ips:
            try:
                hostname = socket.gethostname()
                host_ips = socket.gethostbyname_ex(hostname)[2]
                ips = [ip for ip in host_ips if not ip.startswith("127.")]
            except:
                pass

        return ips

    def _read_ar_members(self, fp):
        """Read members from an AR archive file"""
        if fp.read(8) != b'!<arch>\n':
            raise RuntimeError("Not a valid ar archive")
        members = []
        while True:
            hdr = fp.read(60)
            if not hdr:
                break
            if len(hdr) < 60:
                raise RuntimeError("Truncated ar header")
            name = hdr[0:16].decode('ascii','ignore').strip().rstrip('/')
            size_txt = hdr[48:58].decode('ascii','ignore').strip() or '0'
            size = int(size_txt)
            data = fp.read(size)
            if size % 2 == 1:
                fp.read(1)
            members.append((name, data))
        return members

    def _parse_deb(self, deb_path: str) -> ParsedDeb:
        """Parse a .deb file into its components"""
        with open(deb_path, 'rb') as f:
            members = self._read_ar_members(f)
        debbin = next((d for n,d in members if n == 'debian-binary'), None)
        control = next((d for n,d in members if n == 'control.tar.gz'), None)
        data_name, data_bytes = next(((n,d) for n,d in members if n.startswith('data.tar')), (None,None))
        if not debbin or not control or not data_bytes or not data_name:
            raise RuntimeError("Missing required member(s) in base deb")
        # decompress data
        if data_name.endswith('.lzma'):
            try:
                raw_tar = lzma.decompress(data_bytes, format=lzma.FORMAT_ALONE)
            except lzma.LZMAError:
                # fallback if XZ (should not happen in base)
                raw_tar = lzma.decompress(data_bytes)
        elif data_name == 'data.tar':
            raw_tar = data_bytes
        else:
            raise RuntimeError(f"Unsupported data member: {data_name}")
        return ParsedDeb(debbin, control, data_name, data_bytes, raw_tar)

    def _extract_tar_bytes_to_dir(self, tar_bytes: bytes, target_dir: str):
        """Extract tar bytes to a directory"""
        if os.path.exists(target_dir):
            shutil.rmtree(target_dir)
        os.makedirs(target_dir, exist_ok=True)
        with tarfile.open(fileobj=io.BytesIO(tar_bytes), mode='r:') as tar:
            tar.extractall(target_dir)

    def _build_data_tar_from_dir(self, src_dir: str) -> bytes:
        """Build tar from directory"""
        buf = io.BytesIO()
        with tarfile.open(fileobj=buf, mode='w', format=tarfile.GNU_FORMAT) as tar:
            for root, dirs, files in os.walk(src_dir):
                # Add directories explicitly (ensures empty dirs preserved)
                for d in dirs:
                    d_full = os.path.join(root, d)
                    arc = os.path.relpath(d_full, src_dir).replace('\\','/')
                    ti = tarfile.TarInfo(arc)
                    ti.type = tarfile.DIRTYPE
                    ti.mode = 0o755
                    ti.mtime = 0
                    tar.addfile(ti)
                for f_name in files:
                    f_full = os.path.join(root, f_name)
                    arc = os.path.relpath(f_full, src_dir).replace('\\','/')
                    ti = tar.gettarinfo(f_full, arc)
                    ti.mtime = 0
                    with open(f_full, 'rb') as f_in:
                        tar.addfile(ti, f_in)
        return buf.getvalue()

    def _assemble_deb(self, output_path: str, debbin: bytes, control_gz: bytes, data_tar_bytes: bytes, lzma_alone=True):
        """Assemble a .deb package"""
        if lzma_alone:
            compressed_data = lzma.compress(data_tar_bytes, format=lzma.FORMAT_ALONE, preset=6)
            data_name = 'data.tar.lzma'
        else:
            compressed_data = data_tar_bytes
            data_name = 'data.tar'
        with open(output_path, 'wb') as out:
            out.write(b'!<arch>\n')
            def add(name, content):
                header = (
                    f"{name:<16}"[:16] +
                    f"{0:<12}" +
                    f"{0:<6}" +
                    f"{0:<6}" +
                    f"{100644:<8}" +
                    f"{len(content):<10}" +
                    "`\n"
                ).encode('ascii')
                out.write(header)
                out.write(content)
                if len(content) % 2 == 1:
                    out.write(b'\n')
            add('debian-binary', debbin if debbin else b'2.0\n')
            add('control.tar.gz', control_gz)
            add(data_name, compressed_data)

    def _build_data_tar_from_dir(self, data_dir):
        """Create a TAR (uncompressed) from a directory with fixed permissions"""
        import tarfile, io
        
        # Create tar in memory
        bio = io.BytesIO()
        with tarfile.open(fileobj=bio, mode='w') as tar:
            for root, dirs, files in os.walk(data_dir):
                for name in files:
                    file_path = os.path.join(root, name)
                    arcname = os.path.relpath(file_path, data_dir).replace('\\', '/')
                    
                    # Manual permission setting
                    # Windows doesn't have proper permissions, so we enforce them
                    tinfo = tar.gettarinfo(file_path, arcname)
                    tinfo.uid = 0
                    tinfo.gid = 0
                    tinfo.uname = 'root'
                    tinfo.gname = 'wheel'
                    
                    # Determine if executable (755) or regular file (644)
                    is_executable = False
                    
                    # 1. Check extensions
                    if name.endswith('.dylib') or name.endswith('.app'):
                         is_executable = True
                    # 2. Check path location (binaries usually in /bin, /usr/bin, /usr/sbin)
                    elif '/bin/' in arcname or '/sbin/' in arcname:
                         is_executable = True
                    # 3. Check for main app executable (file with same name as .app directory)
                    elif '.app/' in arcname:
                         # e.g. Applications/VCam.app/VCam
                         parent_dir = os.path.basename(os.path.dirname(file_path))
                         if parent_dir.endswith('.app') and parent_dir[:-4] == name:
                             is_executable = True
                    
                    # 4. Deep inspection: Check Magic Bytes for Mach-O binary
                    # This is the most reliable way for iOS binaries
                    try:
                        with open(file_path, 'rb') as f_check:
                            magic = f_check.read(4)
                            # Mach-O magics: FEEDFACE (32-bit), FEEDFACF (64-bit), CAFEBABE (Universal)
                            # Little endian: CEFAEDFE, CFFAEDFE, BEBAFECA
                            mach_o_magics = [
                                b'\xfe\xed\xfa\xce', b'\xce\xfa\xed\xfe',
                                b'\xfe\xed\xfa\xcf', b'\xcf\xfa\xed\xfe',
                                b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'
                            ]
                            if magic in mach_o_magics:
                                is_executable = True
                    except:
                        pass
                    
                    if is_executable:
                        tinfo.mode = 0o755
                    else:
                        tinfo.mode = 0o644
                        
                    with open(file_path, 'rb') as f:
                        tar.addfile(tinfo, f)
                        
                for name in dirs:
                    dir_path = os.path.join(root, name)
                    arcname = os.path.relpath(dir_path, data_dir).replace('\\', '/')
                    
                    tinfo = tarfile.TarInfo(arcname)
                    tinfo.type = tarfile.DIRTYPE
                    tinfo.uid = 0
                    tinfo.gid = 0
                    tinfo.uname = 'root'
                    tinfo.gname = 'wheel'
                    tinfo.mode = 0o755
                    tar.addfile(tinfo)
                    
        return bio.getvalue()

    def extract_deb(self, deb_file, extract_dir):
        """Extract .deb package using pure Python"""
        print(f"  Extracting {deb_file}...")

        # Parse the .deb file
        parsed = self._parse_deb(deb_file)
        # Save parsed pieces for reuse
        self._parsed_base = parsed

        if os.path.exists(extract_dir):
            shutil.rmtree(extract_dir)
        os.makedirs(extract_dir, exist_ok=True)

        # Save original components
        os.makedirs(os.path.join(extract_dir, 'original'), exist_ok=True)

        # Save debian-binary
        debian_path = os.path.join(extract_dir, 'debian-binary')
        with open(debian_path, 'wb') as f:
            f.write(parsed.debian_binary)
        shutil.copy2(debian_path, os.path.join(extract_dir, 'original', 'debian-binary'))

        # Save control.tar.gz (preserved exactly as-is)
        control_path = os.path.join(extract_dir, 'control.tar.gz')
        with open(control_path, 'wb') as f:
            f.write(parsed.control_tar_gz)
        shutil.copy2(control_path, os.path.join(extract_dir, 'original', 'control.tar.gz'))

        # Extract control files for inspection
        control_files_dir = os.path.join(extract_dir, 'control_files')
        with tarfile.open(fileobj=io.BytesIO(parsed.control_tar_gz), mode='r:gz') as tar:
            tar.extractall(control_files_dir)

        # Extract data files
        data_dir = os.path.join(extract_dir, 'data_files')
        self._extract_tar_bytes_to_dir(parsed.data_tar_raw, data_dir)

        return True

    def find_current_ip(self, extract_dir):
        """Find the current IP in the binary"""
        dylib_path = os.path.join(extract_dir, 'data_files', 'var', 'jb', 'Library',
                                  'MobileSubstrate', 'DynamicLibraries', 'vcamera.dylib')

        if not os.path.exists(dylib_path):
            return None

        with open(dylib_path, 'rb') as f:
            data = f.read()

        # For de-branded version, specifically look for 192.168.1.91 first
        if b'192.168.1.91' in data:
            return '192.168.1.91'

        # Otherwise search for any IP pattern
        ip_pattern = rb'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}'
        matches = re.findall(ip_pattern, data)

        # Filter out localhost and return the first non-localhost IP
        for match in matches:
            ip_str = match.decode('ascii')
            if not ip_str.startswith('127.'):
                return ip_str

        return None

    def replace_ip_in_binary(self, file_path, old_ip, new_ip):
        """Replace IP address in binary file (enforces same length for safety)"""
        # Safety check: IPs must be same length for binary replacement
        if len(old_ip) != len(new_ip):
            print(f"  ❌ ERROR: IP length mismatch! Old: {len(old_ip)} chars, New: {len(new_ip)} chars")
            print(f"    Binary replacement requires exact same length to avoid corruption")
            return False

        with open(file_path, 'rb') as f:
            data = f.read()

        replacements = 0

        # Replace as ASCII string
        old_bytes = old_ip.encode('ascii')
        new_bytes = new_ip.encode('ascii')

        if old_bytes in data:
            data = data.replace(old_bytes, new_bytes)
            replacements = data.count(new_bytes)

        # Also try with null terminator
        old_null = old_bytes + b'\x00'
        new_null = new_bytes + b'\x00'
        if old_null in data:
            data = data.replace(old_null, new_null)
            replacements += 1

        if replacements > 0:
            with open(file_path, 'wb') as f:
                f.write(data)
            return True

        return False

    def copy_original_lzma_method(self, extract_dir, output_file):
        """Use the original LZMA from the source package as a template"""
        print("    - Using original LZMA as template...")

        # We'll copy the original data.tar.lzma and modify its contents
        original_lzma = os.path.join(extract_dir, 'original', 'data.tar.lzma')

        if os.path.exists(original_lzma):
            # Extract original to a temp location
            temp_orig = os.path.join(extract_dir, 'temp_orig')
            os.makedirs(temp_orig, exist_ok=True)

            # Extract original LZMA
            cmd = ['7z', 'x', original_lzma, f'-o{temp_orig}', '-y']
            subprocess.run(cmd, capture_output=True)

            # Now we have the original tar, we need to recreate it with our modified files
            # This approach ensures we match the exact format

            # Clean up temp
            shutil.rmtree(temp_orig)

        return False

    def ensure_control_files(self, extract_dir):
        """Ensure control_files directory exists and populated; reconstruct if missing.
        Strategy:
          1. If control_files has files, keep.
          2. Else attempt to locate an original control.tar.gz saved in extract_dir/original or beside original deb (same directory) and extract it.
          3. If still missing, synthesize minimal control with required fields so dpkg won't fail.
        """
        control_dir = os.path.join(extract_dir, 'control_files')
        if os.path.isdir(control_dir) and os.listdir(control_dir):
            return
        os.makedirs(control_dir, exist_ok=True)
        # Try original saved copy
        candidates = [
            os.path.join(extract_dir, 'original', 'control.tar.gz'),
        ]
        # Also scan the original deb for control.tar.gz if not already extracted
        if not any(os.path.exists(c) for c in candidates):
            try:
                with open(self.original_deb, 'rb') as f:
                    if f.read(8) != b'!<arch>\n':
                        raise Exception('Not ar')
                    while True:
                        hdr = f.read(60)
                        if not hdr:
                            break
                        if len(hdr) < 60:
                            break
                        name = hdr[:16].decode('ascii', 'ignore').strip().rstrip('/')
                        size_txt = hdr[48:58].decode('ascii', 'ignore').strip() or '0'
                        size = int(size_txt)
                        data = f.read(size)
                        if size % 2: f.read(1)
                        if name == 'control.tar.gz':
                            # extract
                            try:
                                import tarfile, io
                                with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as tar:
                                    tar.extractall(control_dir)
                            except Exception as e:
                                print(f"  ⚠ Failed to extract embedded control.tar.gz: {e}")
                            break
            except Exception as e:
                print(f"  ⚠ Could not scan original deb for control: {e}")
        if os.listdir(control_dir):
            return
        # Synthesize minimal control metadata
        control_path = os.path.join(control_dir, 'control')
        print('  ⚠ control.tar.gz missing; synthesizing minimal control file.')
        with open(control_path, 'w', newline='\n') as f:
            f.write('Package: iosvcam-base\n')
            f.write('Version: 1.0\n')
            f.write('Section: base\n')
            f.write('Priority: optional\n')
            f.write('Architecture: iphoneos-arm\n')
            f.write('Maintainer: Unknown <unknown@example.com>\n')
            f.write('Description: iOS VCam (auto-generated control)\n')
        # Provide stub maintainer scripts if missing, but ensure postinst has uicache
        postinst_path = os.path.join(control_dir, 'postinst')
        
        # If postinst exists, check if it has uicache
        if os.path.exists(postinst_path):
            try:
                with open(postinst_path, 'r') as f:
                    content = f.read()
                if 'uicache' not in content:
                    print("  ⚠ Existing postinst missing uicache; appending it.")
                    with open(postinst_path, 'a', newline='\n') as f:
                        f.write('\n# Added by builder to ensure icon appears\nuicache || /usr/bin/uicache\n')
            except Exception as e:
                print(f"  ⚠ Failed to check/update postinst: {e}")
        else:
            # Create new postinst with uicache
            with open(postinst_path, 'w', newline='\n') as s:
                s.write('#!/bin/sh\n')
                s.write('/usr/bin/uicache || uicache\n')  # CRITICAL: Update icon cache
                s.write('exit 0\n')
            
        for script_name in ['prerm', 'postrm', 'preinst']:
            script_path = os.path.join(control_dir, script_name)
            if not os.path.exists(script_path):
                with open(script_path, 'w', newline='\n') as s:
                    s.write('#!/bin/sh\nexit 0\n')
                    
        # Try setting permissions on scripts (best effort on Windows)
        # AND fix line endings (dos2unix) because iOS requires LF, not CRLF
        for script_name in ['postinst', 'prerm', 'postrm', 'preinst']:
            script_path = os.path.join(control_dir, script_name)
            if os.path.exists(script_path):
                # Fix line endings (CRLF -> LF)
                try:
                    with open(script_path, 'rb') as f:
                        content = f.read()
                    if b'\r\n' in content:
                        content = content.replace(b'\r\n', b'\n')
                        with open(script_path, 'wb') as f:
                            f.write(content)
                except Exception as e:
                    print(f"  ⚠ Failed to convert line endings for {script_name}: {e}")
                    
                # Fix permissions
                try:
                    os.chmod(script_path, 0o755)
                except:
                    pass

    def create_deb_package(self, extract_dir, output_file):
        """Create .deb package using preserved control.tar.gz"""
        print(f"  Creating {os.path.basename(output_file)}...")

        if not hasattr(self, '_parsed_base'):
            raise RuntimeError("Base package not parsed; call extract_deb first")

        data_dir = os.path.join(extract_dir, 'data_files')
        if not os.path.isdir(data_dir):
            raise RuntimeError("data_files directory missing")

        # Build new data tar from modified directory
        data_tar_bytes = self._build_data_tar_from_dir(data_dir)

        # Rebuild control.tar.gz to ensure permissions (Windows fix)
        control_dir = os.path.join(extract_dir, 'control_files')
        if os.path.isdir(control_dir):
            control_tar_gz = self._build_control_tar_gz_from_dir(control_dir)
        else:
            control_tar_gz = self._parsed_base.control_tar_gz

        # Always produce LZMA-alone compressed data for iOS compatibility
        self._assemble_deb(output_file,
                          self._parsed_base.debian_binary,
                          control_tar_gz,
                          data_tar_bytes,
                          lzma_alone=True)

        print(f"    - Success: {os.path.basename(output_file)}")
        return True

    def _build_control_tar_gz_from_dir(self, control_dir):
        """Create a control.tar.gz from a directory with fixed permissions"""
        import tarfile, io, gzip
        
        # Create tar in memory
        bio = io.BytesIO()
        with tarfile.open(fileobj=bio, mode='w') as tar:
            for root, dirs, files in os.walk(control_dir):
                for name in files:
                    file_path = os.path.join(root, name)
                    arcname = os.path.relpath(file_path, control_dir).replace('\\', '/')
                    
                    tinfo = tar.gettarinfo(file_path, arcname)
                    tinfo.uid = 0
                    tinfo.gid = 0
                    tinfo.uname = 'root'
                    tinfo.gname = 'wheel'
                    
                    # Scripts need 755
                    if name in ['postinst', 'prerm', 'postrm', 'preinst', 'config']:
                        tinfo.mode = 0o755
                    else:
                        tinfo.mode = 0o644
                        
                    with open(file_path, 'rb') as f:
                        tar.addfile(tinfo, f)
                        
        # Gzip it
        gz_bio = io.BytesIO()
        with gzip.GzipFile(fileobj=gz_bio, mode='wb', compresslevel=9, mtime=0) as gz:
            gz.write(bio.getvalue())
            
        return gz_bio.getvalue()

    def process_single_ip(self, new_ip, base_ip=None):
        """Process a single IP replacement"""
        if not self.validate_ip(new_ip):
            print(f"  ✗ Invalid IP: {new_ip}")
            return False

        # Extract if needed
        if not os.path.exists(self.work_dir) or not base_ip:
            self.extract_deb(self.original_deb, self.work_dir)

            if not base_ip:
                base_ip = self.find_current_ip(self.work_dir)
                if not base_ip:
                    print("  ✗ Could not find IP in binary")
                    return False

        # Replace IP
        dylib_path = os.path.join(self.work_dir, 'data_files', 'var', 'jb', 'Library',
                                 'MobileSubstrate', 'DynamicLibraries', 'vcamera.dylib')

        if not self.replace_ip_in_binary(dylib_path, base_ip, new_ip):
            print(f"  ✗ Failed to replace {base_ip} with {new_ip}")
            return False

        # Apply latency patches if requested
        if self.apply_tweak:
            self.apply_latency_patches(dylib_path)

        # Create output
        ip_safe = new_ip.replace('.', '_')
        tweak_suffix = "_tweaked" if self.apply_tweak else ""
        output_file = os.path.join(self.output_dir, f"iosvcam_base_{ip_safe}{tweak_suffix}.deb")

        if self.create_deb_package(self.work_dir, output_file):
            file_size = os.path.getsize(output_file)
            print(f"  ✓ Created: {os.path.basename(output_file)} ({file_size:,} bytes)")
            return True

        return False

    def batch_process_ips(self, ip_list):
        """Process multiple IPs"""
        print(f"\nProcessing {len(ip_list)} IP addresses...")
        print("-" * 50)

        os.makedirs(self.output_dir, exist_ok=True)

        self.extract_deb(self.original_deb, self.work_dir)
        base_ip = self.find_current_ip(self.work_dir)

        if not base_ip:
            print("✗ Could not find current IP in binary")
            return

        print(f"Current IP in package: {base_ip}\n")

        successful = 0
        failed = 0

        for new_ip in ip_list:
            print(f"Processing {new_ip}...")

            # Re-extract for clean state
            self.extract_deb(self.original_deb, self.work_dir)

            if self.process_single_ip(new_ip, base_ip):
                successful += 1
            else:
                failed += 1
            print()

        print("-" * 50)
        print(f"Results: {successful} successful, {failed} failed")
        print(f"Output directory: {self.output_dir}/")

    def cleanup(self):
        """Clean up temporary files"""
        if os.path.exists(self.work_dir):
            shutil.rmtree(self.work_dir)
        print("✓ Cleanup complete")

    def run_quick(self, ip_list):
        """Quick run for command line usage"""
        if not os.path.exists(self.original_deb):
            print(f"✗ Error: {self.original_deb} not found!")
            return 1

        self.batch_process_ips(ip_list)
        self.cleanup()
        return 0

def main():
    """Main function for command line usage"""
    import argparse

    parser = argparse.ArgumentParser(description='iOS .deb IP Changer - Final Fixed Version')
    parser.add_argument('ips', nargs='*', help='IP address(es) to embed')
    parser.add_argument('--base', help='Override base .deb path (default: iosvcam_base.deb)', default=None)
    parser.add_argument('--tweak', action='store_true', help='Apply 1s latency/bursting fix patches')

    args = parser.parse_args()

    if not args.ips:
        parser.print_help()
        print("\nExamples:")
        print("  Single IP:    python ios_deb_ip_changer_final.py 192.168.1.100")
        print("  Multiple IPs: python ios_deb_ip_changer_final.py 192.168.1.100 192.168.50.232")
        print("  Tweaked:      python ios_deb_ip_changer_final.py --tweak 192.168.1.100")
        print("  Custom base:  python ios_deb_ip_changer_final.py --base custom.deb 192.168.1.100")
        return 1

    changer = DebIPChanger()
    changer.apply_tweak = args.tweak

    # Override base if provided
    if args.base:
        if not os.path.exists(args.base):
            print(f"[ERROR] --base not found: {args.base}")
            return 1
        changer.original_deb = args.base

    # Parse IPs from command line
    ip_list = []
    for ip in args.ips:
        if changer.validate_ip(ip):
            ip_list.append(ip)
        else:
            print(f"⚠ Skipping invalid IP: {ip}")

    if not ip_list:
        print("✗ No valid IPs provided!")
        return 1

    return changer.run_quick(ip_list)

if __name__ == "__main__":
    sys.exit(main())
