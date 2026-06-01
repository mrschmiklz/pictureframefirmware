#!/usr/bin/env python3
"""Unpack Android boot.img (header v0/v1/v2). Based on AOSP mkbootimg tooling."""

from __future__ import annotations

import argparse
import os
import struct
import sys

BOOT_MAGIC = b"ANDROID!"
BOOT_MAGIC_SIZE = 8
HEADER_V1_SIZE = 1648
HEADER_V2_SIZE = 1660


def read_header(data: bytes) -> dict:
    if data[:BOOT_MAGIC_SIZE] != BOOT_MAGIC:
        raise ValueError("Not an Android boot image (missing ANDROID! magic)")

    fields = struct.unpack("8s10I", data[:44])
    header = {
        "kernel_size": fields[1],
        "kernel_addr": fields[2],
        "ramdisk_size": fields[3],
        "ramdisk_addr": fields[4],
        "second_size": fields[5],
        "second_addr": fields[6],
        "tags_addr": fields[7],
        "page_size": fields[8],
        "header_version": 0,
        "os_version": 0,
        "name": "",
        "cmdline": "",
        "extra_cmdline": "",
        "id": b"",
        "recovery_dtbo_size": 0,
        "recovery_dtbo_offset": 0,
        "boot_header_size": 0,
    }

    header["name"] = data[48:64].split(b"\x00", 1)[0].decode("ascii", errors="replace")
    header["cmdline"] = data[64:576].split(b"\x00", 1)[0].decode("ascii", errors="replace")

    if header["kernel_size"] == 0:
        raise ValueError("Invalid boot image: kernel_size is 0")

    header_size = header["page_size"]
    if len(data) >= HEADER_V2_SIZE:
        version = struct.unpack("I", data[1420:1424])[0]
        if version in (1, 2):
            header["header_version"] = version
            header["os_version"] = struct.unpack("I", data[1424:1428])[0]
            header["extra_cmdline"] = data[1428:1908].split(b"\x00", 1)[0].decode("ascii", errors="replace")
            header["recovery_dtbo_size"] = struct.unpack("I", data[1632:1636])[0]
            header["recovery_dtbo_offset"] = struct.unpack("Q", data[1636:1644])[0]
            header["boot_header_size"] = struct.unpack("I", data[1644:1648])[0]
            header_size = header["boot_header_size"] or (HEADER_V2_SIZE if version == 2 else HEADER_V1_SIZE)

    header["header_size"] = header_size
    return header


def write_cfg(header: dict, output_dir: str) -> None:
    path = os.path.join(output_dir, "bootimg.cfg")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(f"bootsize={header['page_size']}\n")
        handle.write(f"pagesize={header['page_size']}\n")
        handle.write(f"kerneladdr={hex(header['kernel_addr'])}\n")
        handle.write(f"ramdiskaddr={hex(header['ramdisk_addr'])}\n")
        handle.write(f"secondaddr={hex(header['second_addr'])}\n")
        handle.write(f"tagsaddr={hex(header['tags_addr'])}\n")
        handle.write(f"name={header['name']}\n")
        handle.write(f"cmdline={header['cmdline']}\n")
        handle.write(f"extra_cmdline={header['extra_cmdline']}\n")
        handle.write(f"header_version={header['header_version']}\n")
        handle.write(f"os_version={header['os_version']}\n")
        handle.write(f"recovery_dtbo_size={header['recovery_dtbo_size']}\n")
        handle.write(f"recovery_dtbo_offset={header['recovery_dtbo_offset']}\n")
        handle.write(f"boot_header_size={header['boot_header_size']}\n")


def unpack(input_file: str, output_dir: str) -> None:
    os.makedirs(output_dir, exist_ok=True)
    with open(input_file, "rb") as handle:
        data = handle.read()

    header = read_header(data)
    write_cfg(header, output_dir)

    page_size = header["page_size"]
    header_size = header["header_size"]
    offset = page_size  # kernel starts after first page

    kernel = data[offset : offset + header["kernel_size"]]
    with open(os.path.join(output_dir, "kernel"), "wb") as handle:
        handle.write(kernel)

    offset += ((header["kernel_size"] + page_size - 1) // page_size) * page_size
    ramdisk = data[offset : offset + header["ramdisk_size"]]
    with open(os.path.join(output_dir, "ramdisk.gz"), "wb") as handle:
        handle.write(ramdisk)

    offset += ((header["ramdisk_size"] + page_size - 1) // page_size) * page_size
    if header["second_size"]:
        second = data[offset : offset + header["second_size"]]
        with open(os.path.join(output_dir, "second"), "wb") as handle:
            handle.write(second)

    print(f"Unpacked {input_file} -> {output_dir}")
    print(f"  page_size={page_size} kernel={header['kernel_size']} ramdisk={header['ramdisk_size']}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Unpack Android boot.img")
    parser.add_argument("bootimg")
    parser.add_argument("output_dir")
    args = parser.parse_args()
    try:
        unpack(args.bootimg, args.output_dir)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
