#!/usr/bin/env python3
"""Repack Android boot.img from bootimg.cfg + kernel + ramdisk.gz."""

from __future__ import annotations

import argparse
import os
import struct
import sys

BOOT_MAGIC = b"ANDROID!"


def read_cfg(path: str) -> dict:
    cfg: dict[str, str] = {}
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line or "=" not in line:
                continue
            key, value = line.split("=", 1)
            cfg[key] = value
    return cfg


def parse_int(value: str) -> int:
    return int(value, 0)


def pad(data: bytes, page_size: int) -> bytes:
    if not data:
        return b""
    rem = len(data) % page_size
    if rem:
        data += b"\x00" * (page_size - rem)
    return data


def repack(work_dir: str, output_file: str) -> None:
    cfg = read_cfg(os.path.join(work_dir, "bootimg.cfg"))
    page_size = parse_int(cfg["pagesize"])
    kernel = open(os.path.join(work_dir, "kernel"), "rb").read()
    ramdisk = open(os.path.join(work_dir, "ramdisk.gz"), "rb").read()
    second_path = os.path.join(work_dir, "second")
    second = open(second_path, "rb").read() if os.path.exists(second_path) else b""

    header_version = parse_int(cfg.get("header_version", "0"))
    os_version = parse_int(cfg.get("os_version", "0"))
    recovery_dtbo_size = parse_int(cfg.get("recovery_dtbo_size", "0"))
    recovery_dtbo_offset = parse_int(cfg.get("recovery_dtbo_offset", "0"))
    boot_header_size = parse_int(cfg.get("boot_header_size", "0"))

    name = cfg.get("name", "").encode("ascii", errors="replace")[:16]
    name = name + b"\x00" * (16 - len(name))
    cmdline = cfg.get("cmdline", "").encode("ascii", errors="replace")[:512]
    cmdline = cmdline + b"\x00" * (512 - len(cmdline))
    extra_cmdline = cfg.get("extra_cmdline", "").encode("ascii", errors="replace")[:1024]
    extra_cmdline = extra_cmdline + b"\x00" * (1024 - len(extra_cmdline))

    header = struct.pack(
        "8s10I",
        BOOT_MAGIC,
        len(kernel),
        parse_int(cfg["kerneladdr"]),
        len(ramdisk),
        parse_int(cfg["ramdiskaddr"]),
        len(second),
        parse_int(cfg["secondaddr"]),
        parse_int(cfg["tagsaddr"]),
        page_size,
        header_version,
        os_version,
    )
    header += name
    header += cmdline

    if header_version >= 1:
        header += extra_cmdline
        header += b"\x00" * 420  # id field placeholder
        header += struct.pack("I", recovery_dtbo_size)
        header += struct.pack("Q", recovery_dtbo_offset)
        header += struct.pack("I", boot_header_size or 1648)
        if header_version >= 2:
            header += struct.pack("I", 0)  # unused

    header = pad(header, page_size)

    image = header + pad(kernel, page_size) + pad(ramdisk, page_size)
    if second:
        image += pad(second, page_size)

    with open(output_file, "wb") as handle:
        handle.write(image)

    print(f"Repacked {output_file} ({len(image)} bytes)")


def main() -> int:
    parser = argparse.ArgumentParser(description="Repack Android boot.img")
    parser.add_argument("work_dir")
    parser.add_argument("output_file")
    args = parser.parse_args()
    try:
        repack(args.work_dir, args.output_file)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
