#!/usr/bin/env python3
import sys
import tarfile
import io
AR_MAGIC = b"!<arch>\n"

def read_members(f):
    if f.read(8) != AR_MAGIC:
        raise ValueError("Missing ar global header")
    members = []
    while True:
        hdr = f.read(60)
        if not hdr: break
        if len(hdr) < 60:
            raise ValueError("Truncated member header")
        name = hdr[0:16].decode('ascii').strip()
        size = int(hdr[48:58].decode('ascii').strip() or "0")
        data = f.read(size)
        if size % 2 == 1:
            f.read(1)
        members.append((name, data))
    return members

def main(path):
    with open(path,'rb') as f:
        members = read_members(f)
    order = [n for n,_ in members]
    print("Order:", order)
    if order[:1] != ['debian-binary']:
        print("FAIL: debian-binary not first"); return 1
    if 'control.tar.gz' not in order:
        print("FAIL: missing control.tar.gz"); return 1
    data_name = next((n for n,_ in members if n.startswith('data.tar')), None)
    if not data_name:
        print("FAIL: missing data.tar.*"); return 1
    debbin = next(d for n,d in members if n=='debian-binary')
    if debbin != b'2.0\n':
        print("FAIL: wrong debian-binary contents"); return 1
    data_bytes = next(d for n,d in members if n==data_name)
    sig = data_bytes[:6]
    if sig.startswith(b'\x5d\x00\x00'):
        print("OK: LZMA-alone")
    elif sig.startswith(b'\xFD7zXZ') or sig[:2]==b'\xFD7':
        print("FAIL: XZ container used"); return 1
    else:
        print("WARN: Unknown data signature:", sig)

    # Additional check: verify control file exists inside control.tar.gz
    ctrl = next(d for n,d in members if n=='control.tar.gz')
    try:
        with tarfile.open(fileobj=io.BytesIO(ctrl), mode='r:gz') as t:
            names = t.getnames()
        if 'control' not in names:
            print("FAIL: control file missing inside control.tar.gz")
            return 1
    except Exception as e:
        print("FAIL: cannot read control.tar.gz:", e)
        return 1

    print("PASS")
    return 0

if __name__ == "__main__":
    if len(sys.argv)!=2:
        print("Usage: python validate_deb.py path/to/file.deb"); sys.exit(2)
    sys.exit(main(sys.argv[1]))