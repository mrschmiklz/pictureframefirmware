#!/usr/bin/env python3
"""Patch Aimor launcher APK splash PNGs with a custom boot image."""

from __future__ import annotations

import argparse
import io
import shutil
import struct
import zipfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_APK = ROOT.parent / "dump" / "launcher_aimor.apk"
DEFAULT_SOURCE = Path(r"\\192.168.1.23\nas\boot.png")
DEFAULT_OUTPUT = ROOT / "launcher_aimor.patched.apk"

# Splash / logo drawables identified from APK analysis.
EXACT_TARGETS = {
    "res/UW.png",
    "res/WL.png",
    "res/zs1.png",
    "res/ix.png",
    "res/n8.png",
    "res/Vb.png",
    "res/Yg.png",
    "res/31.png",
    "res/cy.png",
    "res/xz.png",
}

MIN_REPLACE_BYTES = 12000


def fit_cover(img: Image.Image, width: int, height: int) -> Image.Image:
    img = img.convert("RGB")
    src_w, src_h = img.size
    scale = max(width / src_w, height / src_h)
    new_w = max(width, int(src_w * scale))
    new_h = max(height, int(src_h * scale))
    resized = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
    left = (new_w - width) // 2
    top = (new_h - height) // 2
    return resized.crop((left, top, left + width, top + height))


def fit_square(img: Image.Image, size: int) -> Image.Image:
    return fit_cover(img, size, size)


def png_size(data: bytes) -> tuple[int, int] | None:
    if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    width, height = struct.unpack(">II", data[16:24])
    return width, height


def render_png(img: Image.Image) -> bytes:
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def should_replace(name: str, data: bytes) -> bool:
    if not name.startswith("res/") or not name.endswith(".png"):
        return False
    if name in EXACT_TARGETS:
        return True
    size = png_size(data)
    if not size:
        return False
    w, h = size
    if abs(w - h) <= 64 and max(w, h) < 1024:
        return False
    if w >= 1024 and h >= 600:
        return True
    if h >= 1024 and w >= 600:
        return True
    return False


def patch_apk(source_png: Path, input_apk: Path, output_apk: Path) -> list[str]:
    base = Image.open(source_png)
    replaced: list[str] = []

    with zipfile.ZipFile(input_apk, "r") as src, zipfile.ZipFile(output_apk, "w") as dst:
        for info in src.infolist():
            data = src.read(info.filename)
            if should_replace(info.filename, data):
                size = png_size(data)
                if size:
                    w, h = size
                    if w == h:
                        out = fit_square(base, w)
                    else:
                        out = fit_cover(base, w, h)
                    data = render_png(out)
                    replaced.append(f"{info.filename} ({w}x{h})")
            dst.writestr(info, data, compress_type=info.compress_type)

    return replaced


def main() -> None:
    parser = argparse.ArgumentParser(description="Patch Aimor splash PNGs in launcher APK")
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--input-apk", type=Path, default=DEFAULT_APK)
    parser.add_argument("--output-apk", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    if not args.source.exists():
        raise SystemExit(f"Missing source image: {args.source}")
    if not args.input_apk.exists():
        raise SystemExit(f"Missing input APK: {args.input_apk}")

    args.output_apk.parent.mkdir(parents=True, exist_ok=True)
    if args.output_apk.exists():
        args.output_apk.unlink()

    replaced = patch_apk(args.source, args.input_apk, args.output_apk)
    print(f"Patched {len(replaced)} PNGs -> {args.output_apk}")
    for item in replaced:
        print(f"  {item}")


if __name__ == "__main__":
    main()
