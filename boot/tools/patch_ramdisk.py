#!/usr/bin/env python3
"""Extract ramdisk.gz, patch init.sun8i.rc for frame-sync boot hook, repack ramdisk.gz."""

from __future__ import annotations

import argparse
import gzip
import io
import os
import shutil
import struct
import sys
import tempfile

SERVICE_BLOCK = """
# Picture frame custom firmware (frame-sync)
service frame-sync-boot /system/bin/sh /data/local/frame-sync/boot.sh
    class late_start
    user root
    group root
    oneshot
    disabled
"""

BOOT_COMPLETED_HOOK = "start frame-sync-boot"


def read_cpio_entries(data: bytes) -> list[tuple[str, bytes, int]]:
    """Parse newc cpio archive into (name, content, mode) entries."""
    entries: list[tuple[str, bytes, int]] = []
    offset = 0
    while offset + 110 <= len(data):
        magic = data[offset : offset + 6]
        if magic != b"070701":
            break
        namesize = int(data[offset + 94 : offset + 102], 16)
        filesize = int(data[offset + 54 : offset + 62], 16)
        mode = int(data[offset + 14 : offset + 22], 16)
        name = data[offset + 110 : offset + 110 + namesize - 1].decode("utf-8", errors="replace")
        content_offset = offset + 110 + ((namesize + 3) // 4) * 4
        content = data[content_offset : content_offset + filesize]
        entries.append((name, content, mode))
        offset = content_offset + ((filesize + 3) // 4) * 4
        if name == "TRAILER!!!":
            break
    return entries


def write_cpio_entries(entries: list[tuple[str, bytes, int]]) -> bytes:
    out = bytearray()
    for name, content, mode in entries:
        namesize = len(name) + 1
        header = (
            f"070701"
            f"{mode:08x}"
            f"00000000"
            f"00000000"
            f"00000001"
            f"00000000"
            f"{len(content):08x}"
            f"{namesize:08x}"
            f"00000000"
            f"00000000"
            f"00000000"
            f"00000000"
            f"00000000"
        ).encode("ascii")
        out.extend(header)
        out.extend(name.encode("ascii") + b"\x00")
        pad = (4 - (len(out) % 4)) % 4
        out.extend(b"\x00" * pad)
        out.extend(content)
        pad = (4 - (len(out) % 4)) % 4
        out.extend(b"\x00" * pad)
    return bytes(out)


def patch_init_content(text: str) -> str:
    if "frame-sync-boot" in text:
        return text

    if SERVICE_BLOCK.strip() not in text:
        text = text.rstrip() + "\n" + SERVICE_BLOCK

    marker = "on property:sys.boot_completed=1"
    if marker in text and BOOT_COMPLETED_HOOK not in text:
        lines = text.splitlines()
        out = []
        i = 0
        while i < len(lines):
            out.append(lines[i])
            if lines[i].strip() == marker:
                j = i + 1
                while j < len(lines) and lines[j].startswith("start "):
                    out.append(lines[j])
                    j += 1
                out.append(BOOT_COMPLETED_HOOK)
                i = j
                continue
            i += 1
        text = "\n".join(out)
        if not text.endswith("\n"):
            text += "\n"
    return text


def patch_ramdisk(ramdisk_gz: str, output_gz: str) -> None:
    with gzip.open(ramdisk_gz, "rb") as handle:
        raw = handle.read()

    entries = read_cpio_entries(raw)
    if not entries:
        raise ValueError("Could not parse ramdisk cpio archive")

    target_names = ("init.sun8i.rc", "init.rc")
    patched = False
    new_entries: list[tuple[str, bytes, int]] = []
    for name, content, mode in entries:
        base = os.path.basename(name)
        if base in target_names:
            text = content.decode("utf-8", errors="replace")
            updated = patch_init_content(text)
            if updated != text:
                content = updated.encode("utf-8")
                patched = True
                print(f"Patched {name}")
        new_entries.append((name, content, mode))

    if not patched:
        raise ValueError("No init.sun8i.rc/init.rc patch applied (already patched?)")

    repacked = write_cpio_entries(new_entries)
    with gzip.open(output_gz, "wb", compresslevel=9) as handle:
        handle.write(repacked)

    print(f"Wrote patched ramdisk -> {output_gz}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Patch frame-sync hook into boot ramdisk")
    parser.add_argument("ramdisk_gz")
    parser.add_argument("output_gz")
    args = parser.parse_args()
    try:
        patch_ramdisk(args.ramdisk_gz, args.output_gz)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
