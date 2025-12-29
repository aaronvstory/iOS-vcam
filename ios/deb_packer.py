#!/usr/bin/env python3
import tarfile, lzma, os
from pathlib import Path

AR_MAGIC = b"!<arch>\n"

def _strip_pax(tarinfo: tarfile.TarInfo) -> tarfile.TarInfo:
    tarinfo.pax_headers = {}
    return tarinfo

def build_control_tar(control_dir: Path, out_path: Path):
    with tarfile.open(out_path, "w:gz", format=tarfile.GNU_FORMAT) as tar:
        # Add directories first so package extraction creates paths
        for p in control_dir.rglob("*"):
            if p.is_dir():
                tar.add(p, arcname=p.relative_to(control_dir), recursive=False, filter=_strip_pax)
        for p in control_dir.rglob("*"):
            if p.is_file():
                tar.add(p, arcname=p.relative_to(control_dir), filter=_strip_pax)

def build_data_tar(data_dir: Path, raw_tar: Path):
    with tarfile.open(raw_tar, "w", format=tarfile.GNU_FORMAT) as tar:
        # Add directories first so package extraction creates paths
        for p in data_dir.rglob("*"):
            if p.is_dir():
                tar.add(p, arcname=p.relative_to(data_dir), recursive=False, filter=_strip_pax)
        for p in data_dir.rglob("*"):
            if p.is_file():
                tar.add(p, arcname=p.relative_to(data_dir), filter=_strip_pax)

def compress_lzma_alone(raw_tar: Path, lzma_path: Path, preset=6):
    data = raw_tar.read_bytes()
    comp = lzma.compress(data, format=lzma.FORMAT_ALONE, preset=preset)
    lzma_path.write_bytes(comp)
    raw_tar.unlink()

def _add_ar_member(ar_file, name: str, content: bytes):
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
    with output_deb.open("wb") as ar:
        ar.write(AR_MAGIC)
        _add_ar_member(ar, "debian-binary", b"2.0\n")
        _add_ar_member(ar, "control.tar.gz", control_tgz.read_bytes())
        _add_ar_member(ar, "data.tar.lzma", data_lzma.read_bytes())

def build_deb(extracted_root: Path, output_deb: Path):
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
    print(f"[deb_packer] Built {output_deb}")
