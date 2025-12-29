#!/usr/bin/env python3
"""
End-to-end debranding + optional IP variant builder.

Modes:
  1) If debranded base (iosvcam_base.deb) absent or --force, rebuild from branded source.
  2) If --ip passed, generate one or more IP-specific variants from debranded base.
"""

import argparse, os, sys, tarfile, lzma, shutil, re, tempfile, ipaddress, subprocess
from pathlib import Path
import deb_packer

BRANDED_DEFAULT = "tools/iosvcam_supp.deb"   # fallback if user doesn't specify
DEBRANDED_BASE  = "iosvcam_base.deb"
MODIFIED_DIR    = "modified_debs"
EXACT_IP_LENGTH = 12

BRAND_PATTERNS = {
    b'www.bkatm.com':          b'localhost    ',      # length preserved
    b'https://www.bkatm.com':  b'http://localhost     ',
    b'Login (www.bkatm.com)':  b'Login                 '
}

BINARY_REL_PATH = Path("var/jb/Library/MobileSubstrate/DynamicLibraries/vcamera.dylib")

def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--base-branded", help="Path to original branded .deb", default=BRANDED_DEFAULT)
    p.add_argument("--force-rebrand", action="store_true", help="Rebuild debranded base even if exists")
    p.add_argument("--verify-only", action="store_true", help="Only verify debranded base & exit")
    p.add_argument("--ip", nargs="*", help="One or more IPs to generate variants")
    p.add_argument("--output-dir", default=MODIFIED_DIR)
    p.add_argument("--keep-work", action="store_true", help="Do not delete temp workspace")
    return p.parse_args()

def validate_ip(ip):
    try:
        ipaddress.IPv4Address(ip)
    except ValueError:
        return False, "Invalid IPv4 address."
    if len(ip) != EXACT_IP_LENGTH:
        return False, f"IP must be exactly {EXACT_IP_LENGTH} characters (current length {len(ip)})."
    return True, ""

def ensure_dir(p: Path):
    p.mkdir(parents=True, exist_ok=True)

def extract_deb(deb_path: Path, work_dir: Path):
    # Minimal extractor for deb: ar + control.tar.gz + data.tar.lzma
    with deb_path.open('rb') as f:
        if f.read(8) != b'!<arch>\n':
            raise RuntimeError("Not a valid ar/deb")
        def read_member():
            hdr = f.read(60)
            if not hdr: return None
            if len(hdr) < 60: raise RuntimeError("Truncated member header")
            name = hdr[:16].decode('ascii').strip()
            size = int(hdr[48:58].decode('ascii').strip() or "0")
            data = f.read(size)
            if size % 2 == 1: f.read(1)
            return name, data
        members=[]
        while True:
            m=read_member()
            if not m: break
            members.append(m)

    control_bytes = None
    data_bytes = None
    for name,data in members:
        # Handle member names with or without trailing slashes
        clean_name = name.rstrip('/')
        if clean_name == 'control.tar.gz':
            control_bytes = data
        elif clean_name.startswith('data.tar'):
            data_bytes = data
    if not control_bytes or not data_bytes:
        raise RuntimeError("Missing control or data archive in deb.")
    # Extract control
    control_dir = work_dir / "control"
    control_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(delete=False) as tf:
        tf.write(control_bytes)
        tmp_control = Path(tf.name)
    with tarfile.open(tmp_control, 'r:gz') as t:
        t.extractall(control_dir)
    tmp_control.unlink()
    # Extract data (LZMA alone or maybe original XZ)
    # Try LZMA-alone first
    try:
        data_tar = lzma.LZMADecompressor(format=lzma.FORMAT_ALONE).decompress(data_bytes)
    except lzma.LZMAError:
        # fallback attempt XZ -> convert
        data_tar = lzma.decompress(data_bytes)  # auto for XZ
    data_dir = work_dir / "data"
    data_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(delete=False) as tf:
        tf.write(data_tar)
        tmp_data = Path(tf.name)
    with tarfile.open(tmp_data, 'r:') as t:
        t.extractall(data_dir)
    tmp_data.unlink()
    return work_dir

def patch_branding(binary_path: Path):
    data = binary_path.read_bytes()
    replaced = 0
    for old,new in BRAND_PATTERNS.items():
        if old in data:
            occurrences = data.count(old)
            if len(old) != len(new):
                raise RuntimeError(f"Replacement length mismatch for {old}")
            data = data.replace(old, new)
            replaced += occurrences
    if replaced:
        binary_path.write_bytes(data)
    return replaced

def verify_no_branding(binary_path: Path):
    data = binary_path.read_bytes()
    lower = data.lower()
    return not (b"bkatm" in lower)

def build_debranded_base(branded_source: Path, force: bool):
    base = Path(DEBRANDED_BASE)
    if base.exists() and not force:
        print("[INFO] Debranded base already exists; skipping rebuild.")
        return
    work = Path("_debrand_work")
    if work.exists():
        shutil.rmtree(work)
    work.mkdir()
    print(f"[STEP] Extracting branded source: {branded_source}")
    extract_deb(branded_source, work)
    binary_path = work / "data" / BINARY_REL_PATH
    if not binary_path.exists():
        raise RuntimeError(f"Binary not found at expected path: {binary_path}")
    print("[STEP] Patching branding...")
    count = patch_branding(binary_path)
    print(f"[INFO] Replaced {count} branding occurrences.")
    if not verify_no_branding(binary_path):
        raise RuntimeError("Branding still detected after patch.")
    print("[STEP] Rebuilding debranded .deb ...")
    deb_packer.build_deb(work, base)
    print("[STEP] Validating...")
    rc = subprocess.call([sys.executable, "validate_deb.py", str(base)])
    if rc != 0:
        raise RuntimeError("Validation failed for debranded base.")
    shutil.rmtree(work)
    print(f"[OK] Created {base}")

def generate_ip_variant(base_deb: Path, ip: str, output_dir: Path):
    ok, reason = validate_ip(ip)
    if not ok:
        raise RuntimeError(f"Invalid IP '{ip}': {reason}")
    # Reuse the ip changer script with --base override if patched, else emulate minimal patch.
    # We assume patched ios_deb_ip_changer_final.py supports --base.
    script_candidates = [
        Path("ios_deb_ip_changer_final.py"),
        Path("tools/ios_deb_ip_changer_final.py"),
    ]
    script_path = next((p for p in script_candidates if p.exists()), None)
    if not script_path:
        raise RuntimeError("Could not locate ios_deb_ip_changer_final.py")
    ensure_dir(output_dir)
    cmd = [
        sys.executable,
        str(script_path),
        "--base", str(base_deb),
        ip
    ]
    print(f"[RUN] {' '.join(cmd)}")
    rc = subprocess.call(cmd)
    if rc != 0:
        raise RuntimeError(f"IP changer failed for {ip}")
    # Find newest matching output
    ip_tag = ip.replace('.', '_')
    produced = sorted(output_dir.glob(f"*{ip_tag}*.deb"), key=lambda p: p.stat().st_mtime, reverse=True)
    if produced:
        print(f"[OK] Generated: {produced[0]}")
    else:
        print("[WARN] Could not locate generated .deb (pattern mismatch).")

def main():
    args = parse_args()
    branded = Path(args.base_branded)
    if not branded.exists():
        raise SystemExit(f"Branded source .deb not found: {branded}")
    if args.verify_only and not Path(DEBRANDED_BASE).exists():
        print("No debranded base present to verify.")
        return 1
    # Build or confirm base
    build_debranded_base(branded, args.force_rebrand)
    if args.verify_only:
        print("[OK] Verification complete.")
        return 0
    if not args.ip:
        print("[INFO] No IPs provided; debranded base ready.")
        return 0
    out_dir = Path(args.output_dir)
    valid_ips = []
    for ip in args.ip:
        ok, reason = validate_ip(ip)
        if ok:
            valid_ips.append(ip)
        else:
            print(f"[WARN] Skipping IP '{ip}': {reason}")
    if not valid_ips:
        print("[WARN] No valid IPs supplied; nothing to generate.")
        return 0
    for ip in valid_ips:
        generate_ip_variant(Path(DEBRANDED_BASE), ip, out_dir)
    return 0

if __name__ == "__main__":
    sys.exit(main())
