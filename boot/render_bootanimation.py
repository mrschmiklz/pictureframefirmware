#!/usr/bin/env python3
"""Build bootanimation.zip from a source PNG for the 1280x800 picture frame."""

from __future__ import annotations

import argparse
import zipfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent
OUTPUT = ROOT / "bootanimation.zip"
PART_DIR = ROOT / "part0"
DEFAULT_SOURCE = Path(r"\\192.168.1.23\nas\boot.png")
CACHED_SOURCE = ROOT / "source.png"

WIDTH = 1280
HEIGHT = 800
FPS = 30
FADE_FRAMES = 12


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


def load_source(path: Path) -> Image.Image:
    if not path.exists():
        raise FileNotFoundError(f"Source image not found: {path}")
    return Image.open(path)


def render_frames(base: Image.Image) -> list[Image.Image]:
    frames: list[Image.Image] = []
    black = Image.new("RGB", (WIDTH, HEIGHT), (0, 0, 0))
    for i in range(FADE_FRAMES):
        alpha = (i + 1) / FADE_FRAMES
        frames.append(Image.blend(black, base, alpha))
    frames.append(base.copy())
    return frames


def build(source: Path, output: Path = OUTPUT) -> Path:
    image = fit_cover(load_source(source), WIDTH, HEIGHT)
    source.parent.mkdir(parents=True, exist_ok=True)
    image.save(CACHED_SOURCE)

    if PART_DIR.exists():
        for old in PART_DIR.glob("*.png"):
            old.unlink()
    else:
        PART_DIR.mkdir(parents=True)

    frames = render_frames(image)
    for i, frame in enumerate(frames):
        frame.save(PART_DIR / f"{i:05d}.png")

    # Loop part0 until Android finishes booting.
    desc = f"{WIDTH} {HEIGHT} {FPS}\nc 1 0 part0\n"
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_STORED) as zf:
        zf.writestr("desc.txt", desc)
        for png in sorted(PART_DIR.glob("*.png")):
            zf.write(png, f"part0/{png.name}")

    print(f"Built {output} from {source} ({len(frames)} frames @ {FPS} fps)")
    return output


def main() -> None:
    parser = argparse.ArgumentParser(description="Build bootanimation.zip")
    parser.add_argument(
        "--source",
        type=Path,
        default=DEFAULT_SOURCE if DEFAULT_SOURCE.exists() else CACHED_SOURCE,
        help="PNG source image (default: NAS boot.png or cached source.png)",
    )
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    build(args.source, args.output)


if __name__ == "__main__":
    main()
