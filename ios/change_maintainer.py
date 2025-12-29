#!/usr/bin/env python3
"""
Change maintainer field in .deb package from "Michael" to "kox"
"""
import tarfile
import lzma
import os
import sys
from pathlib import Path

AR_MAGIC = b"!<arch>\n"

def extract_ar_member(deb_path: Path, member_name: str) -> bytes:
    """Extract a specific member from an AR archive."""
    with deb_path.open('rb') as f:
        # Read AR magic
        magic = f.read(8)
        if magic != AR_MAGIC:
            raise ValueError(f"Not a valid AR archive: {deb_path}")

        # Read members until we find the one we want
        while True:
            header = f.read(60)
            if not header:
                raise ValueError(f"Member '{member_name}' not found in AR archive")

            if len(header) != 60:
                raise ValueError("Invalid AR header")

            name = header[0:16].decode('ascii').strip()
            size = int(header[48:58].decode('ascii').strip())

            # Read content
            content = f.read(size)

            # Skip padding byte if size is odd
            if size % 2 == 1:
                f.read(1)

            if name == member_name:
                return content

def extract_deb(deb_path: Path, extract_dir: Path):
    """Extract .deb package to directory structure."""
    extract_dir.mkdir(parents=True, exist_ok=True)

    # Extract control.tar.gz
    control_bytes = extract_ar_member(deb_path, "control.tar.gz")
    control_dir = extract_dir / "control"
    control_dir.mkdir(exist_ok=True)

    import io
    with tarfile.open(fileobj=io.BytesIO(control_bytes), mode='r:gz') as tar:
        tar.extractall(control_dir)

    # Extract data.tar.lzma
    data_bytes = extract_ar_member(deb_path, "data.tar.lzma")
    data_dir = extract_dir / "data"
    data_dir.mkdir(exist_ok=True)

    # Decompress LZMA
    decompressed = lzma.decompress(data_bytes, format=lzma.FORMAT_ALONE)
    with tarfile.open(fileobj=io.BytesIO(decompressed), mode='r') as tar:
        tar.extractall(data_dir)

    print(f"[extract_deb] Extracted to {extract_dir}")

def modify_maintainer(control_file: Path, new_maintainer: str, new_author: str = None, remove_repo: bool = False):
    """Modify the Maintainer, Author fields and optionally remove repository references in the control file."""
    lines = control_file.read_text().splitlines()
    modified = []
    maintainer_found = False
    author_found = False

    for line in lines:
        if line.startswith("Maintainer:"):
            old_value = line
            modified.append(f"Maintainer: {new_maintainer}")
            maintainer_found = True
            print(f"[modify_control] Changed: {old_value}")
            print(f"[modify_control] To: Maintainer: {new_maintainer}")
        elif line.startswith("Author:") and new_author:
            old_value = line
            modified.append(f"Author: {new_author}")
            author_found = True
            print(f"[modify_control] Changed: {old_value}")
            print(f"[modify_control] To: Author: {new_author}")
        elif line.startswith("Homepage:") and remove_repo:
            print(f"[modify_control] Removed: {line}")
            continue  # Skip this line
        elif line.startswith("Depiction:") and remove_repo:
            print(f"[modify_control] Removed: {line}")
            continue  # Skip this line
        elif "bkatm" in line.lower() and remove_repo:
            print(f"[modify_control] Removed bkatm reference: {line}")
            continue  # Skip this line
        else:
            modified.append(line)

    if not maintainer_found:
        print("[modify_control] Warning: Maintainer field not found, adding it")
        modified.insert(0, f"Maintainer: {new_maintainer}")

    if new_author and not author_found:
        print("[modify_control] Warning: Author field not found, adding it")
        modified.insert(1 if maintainer_found else 0, f"Author: {new_author}")

    control_file.write_text('\n'.join(modified) + '\n')

def build_control_tar(control_dir: Path, out_path: Path):
    """Build control.tar.gz from control directory."""
    with tarfile.open(out_path, "w:gz") as tar:
        for p in control_dir.rglob("*"):
            if p.is_file():
                tar.add(p, arcname=p.relative_to(control_dir))

def build_data_tar(data_dir: Path, raw_tar: Path):
    """Build data.tar from data directory."""
    with tarfile.open(raw_tar, "w") as tar:
        for p in data_dir.rglob("*"):
            if p.is_file():
                tar.add(p, arcname=p.relative_to(data_dir))

def compress_lzma_alone(raw_tar: Path, lzma_path: Path, preset=6):
    """Compress tar with LZMA-alone format."""
    data = raw_tar.read_bytes()
    comp = lzma.compress(data, format=lzma.FORMAT_ALONE, preset=preset)
    lzma_path.write_bytes(comp)
    raw_tar.unlink()

def _add_ar_member(ar_file, name: str, content: bytes):
    """Add a member to AR archive."""
    if len(name) > 16:
        raise ValueError(f"Name '{name}' too long for simple ar (16 char max).")
    header = (
        name.ljust(16) +
        "0".ljust(12) +
        "0".ljust(6) +
        "0".ljust(6) +
        "100644".ljust(8) +
        str(len(content)).ljust(10) +
        "`\n"
    ).encode("ascii")
    if len(header) != 60:
        raise RuntimeError("Ar header not 60 bytes.")
    ar_file.write(header)
    ar_file.write(content)
    if len(content) % 2 == 1:
        ar_file.write(b"\n")

def write_deb(output_deb: Path, control_tgz: Path, data_lzma: Path):
    """Write .deb AR archive."""
    with output_deb.open("wb") as ar:
        ar.write(AR_MAGIC)
        _add_ar_member(ar, "debian-binary", b"2.0\n")
        _add_ar_member(ar, "control.tar.gz", control_tgz.read_bytes())
        _add_ar_member(ar, "data.tar.lzma", data_lzma.read_bytes())

def repack_deb(extracted_root: Path, output_deb: Path):
    """Repack .deb from extracted directory."""
    control_dir = extracted_root / "control"
    data_dir = extracted_root / "data"
    if not control_dir.exists() or not data_dir.exists():
        raise RuntimeError("Expected 'control' and 'data' directories inside extracted root.")

    tmp = extracted_root / "_repack_tmp"
    tmp.mkdir(exist_ok=True)

    control_tgz = tmp / "control.tar.gz"
    raw_data_tar = tmp / "data.tar"
    data_lzma = tmp / "data.tar.lzma"

    build_control_tar(control_dir, control_tgz)
    build_data_tar(data_dir, raw_data_tar)
    compress_lzma_alone(raw_data_tar, data_lzma)
    write_deb(output_deb, control_tgz, data_lzma)

    print(f"[repack_deb] Built {output_deb}")

def main():
    if len(sys.argv) < 2:
        print("Usage: python change_maintainer.py <input.deb> [new_maintainer] [new_author] [--remove-repo]")
        print("Example: python change_maintainer.py iosvcam_base.deb kox kox --remove-repo")
        sys.exit(1)

    input_deb = Path(sys.argv[1])
    new_maintainer = sys.argv[2] if len(sys.argv) > 2 else "kox"
    new_author = sys.argv[3] if len(sys.argv) > 3 and not sys.argv[3].startswith('--') else None
    remove_repo = '--remove-repo' in sys.argv

    if not input_deb.exists():
        print(f"Error: {input_deb} not found")
        sys.exit(1)

    # Create backup
    backup_path = input_deb.with_suffix('.deb.backup')
    if not backup_path.exists():
        import shutil
        shutil.copy2(input_deb, backup_path)
        print(f"[backup] Created backup: {backup_path}")

    # Extract
    extract_dir = input_deb.parent / "temp_maintainer_change"
    if extract_dir.exists():
        import shutil
        shutil.rmtree(extract_dir)

    extract_deb(input_deb, extract_dir)

    # Modify control file
    control_file = extract_dir / "control" / "control"
    if not control_file.exists():
        print(f"Error: control file not found at {control_file}")
        sys.exit(1)

    modify_maintainer(control_file, new_maintainer, new_author, remove_repo)

    # Repack
    output_deb = input_deb.with_suffix('.modified.deb')
    repack_deb(extract_dir, output_deb)

    print(f"\n✓ Success!")
    print(f"  Original (backup): {backup_path}")
    print(f"  Modified output: {output_deb}")
    print(f"\nTo replace the original:")
    print(f"  mv {output_deb} {input_deb}")

    # Cleanup
    import shutil
    shutil.rmtree(extract_dir)

if __name__ == "__main__":
    main()
