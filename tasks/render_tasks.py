#!/usr/bin/env python3
"""Render today's task list as a 1280x800 PNG for the picture frame slideshow."""

from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
TASKS_FILE = ROOT / "tasks.json"
OUTPUT_FILE = ROOT / "tasks_today.png"
CONFIG_FILE = ROOT / "google_config.json"

WIDTH = 1280
HEIGHT = 800
BG = (18, 22, 32)
TEXT = (240, 244, 255)
MUTED = (160, 170, 190)
DONE = (120, 200, 140)
ACCENT = (90, 160, 255)


def load_tasks() -> dict:
    with TASKS_FILE.open(encoding="utf-8") as handle:
        return json.load(handle)


def save_tasks(data: dict) -> None:
    with TASKS_FILE.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")


def pick_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        "C:/Windows/Fonts/segoeui.ttf",
        "C:/Windows/Fonts/arial.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    ]
    for path in candidates:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def render(data: dict | None = None, output: Path = OUTPUT_FILE) -> Path:
    data = data or load_tasks()
    tasks = data.get("tasks", [])
    title = data.get("title") or "Today"
    now = datetime.now()

    image = Image.new("RGB", (WIDTH, HEIGHT), BG)
    draw = ImageDraw.Draw(image)

    title_font = pick_font(54)
    time_font = pick_font(34)
    task_font = pick_font(36)
    small_font = pick_font(24)

    draw.text((64, 48), title, font=title_font, fill=TEXT)
    draw.text((64, 118), now.strftime("%A, %B %d  ·  %I:%M %p").lstrip("0"), font=time_font, fill=MUTED)

    open_count = sum(1 for task in tasks if not task.get("done"))
    done_count = len(tasks) - open_count
    draw.text((64, 168), f"{open_count} open  ·  {done_count} done", font=small_font, fill=MUTED)

    y = 240
    line_height = 58
    max_lines = 8

    for index, task in enumerate(tasks[:max_lines]):
        done = bool(task.get("done"))
        box_color = DONE if done else MUTED
        text = str(task.get("text", "")).strip()
        prefix = "✓" if done else "○"
        draw.rounded_rectangle((64, y + 8, 96, y + 40), radius=6, outline=box_color, width=2)
        draw.text((72, y + 4), prefix, font=small_font, fill=box_color)
        draw.text((120, y), text, font=task_font, fill=(MUTED if done else TEXT))
        if done:
            bbox = draw.textbbox((120, y), text, font=task_font)
            mid = (bbox[1] + bbox[3]) // 2
            draw.line((120, mid, bbox[2], mid), fill=MUTED, width=2)
        y += line_height

    if len(tasks) > max_lines:
        draw.text((64, y), f"+ {len(tasks) - max_lines} more on phone", font=small_font, fill=MUTED)

    footer = "Google Tasks"
    if CONFIG_FILE.exists():
        try:
            with CONFIG_FILE.open(encoding="utf-8") as handle:
                port = json.load(handle).get("ui_port", 8765)
            footer = f"Google Tasks  ·  check off at http://192.168.1.23:{port}"
        except (json.JSONDecodeError, OSError):
            footer = "Google Tasks"
    elif data.get("source") == "google":
        footer = "Google Tasks"
    draw.text((64, HEIGHT - 56), footer, font=small_font, fill=(100, 110, 130))

    image.save(output, format="PNG", optimize=True)
    return output


if __name__ == "__main__":
    path = render()
    print(f"Wrote {path}")
