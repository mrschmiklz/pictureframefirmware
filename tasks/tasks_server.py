#!/usr/bin/env python3
"""Small LAN web UI to view and complete daily tasks, re-rendering the frame PNG."""

from __future__ import annotations

import html
import json
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parent
TASKS_FILE = ROOT / "tasks.json"
OUTPUT_FILE = ROOT / "tasks_today.png"
CONFIG_FILE = ROOT / "google_config.json"
HOST = "0.0.0.0"
PORT = 8765


def google_enabled() -> bool:
    return CONFIG_FILE.exists()


def load_port() -> int:
    if CONFIG_FILE.exists():
        try:
            with CONFIG_FILE.open(encoding="utf-8") as handle:
                return int(json.load(handle).get("ui_port", PORT))
        except (json.JSONDecodeError, ValueError, TypeError):
            pass
    return PORT


def load_tasks() -> dict:
    with TASKS_FILE.open(encoding="utf-8") as handle:
        return json.load(handle)


def save_tasks(data: dict) -> None:
    with TASKS_FILE.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")


def render_png() -> None:
    subprocess.run([sys.executable, str(ROOT / "render_tasks.py")], check=True)


def sync_google() -> None:
    subprocess.run([sys.executable, str(ROOT / "google_tasks.py"), "sync"], check=True)


def toggle_task(task_id: str) -> bool:
    data = load_tasks()
    new_done = None
    for task in data.get("tasks", []):
        if str(task.get("id")) == task_id:
            new_done = not bool(task.get("done"))
            task["done"] = new_done
            break
    if new_done is None:
        return False

    if google_enabled() and data.get("source") == "google":
        import google_tasks

        google_tasks.set_task_done(task_id, new_done)
        data = google_tasks.fetch_frame_tasks()
        save_tasks(data)
    else:
        save_tasks(data)

    render_png()
    return True


def page(data: dict) -> str:
    rows = []
    for task in data.get("tasks", []):
        checked = "checked" if task.get("done") else ""
        label = html.escape(str(task.get("text", "")))
        task_id = html.escape(str(task.get("id", "")))
        rows.append(
            f"""
            <label class="task">
              <input type="checkbox" data-id="{task_id}" {checked}>
              <span>{label}</span>
            </label>
            """
        )
    body = "\n".join(rows) or "<p>No tasks yet.</p>"
    title = html.escape(str(data.get("title", "Today")))
    return f"""<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Frame tasks</title>
  <style>
    body {{ font-family: Segoe UI, sans-serif; background:#121722; color:#eef2ff; margin:0; padding:24px; }}
    h1 {{ margin:0 0 8px; }}
    .meta {{ color:#9aa4bd; margin-bottom:24px; }}
    .task {{ display:flex; gap:12px; align-items:flex-start; padding:14px 0; border-bottom:1px solid #243049; font-size:20px; }}
    .task span {{ flex:1; }}
    .task input {{ width:22px; height:22px; margin-top:4px; }}
    .done span {{ color:#8ec8a0; text-decoration:line-through; }}
    #status {{ color:#8ec8a0; min-height:24px; margin-top:16px; }}
  </style>
</head>
<body>
  <h1>{title}</h1>
  <div class="meta">Tap to update the picture frame slide.{' Synced from Google Tasks.' if google_enabled() else ''}</div>
  {body}
  <div id="status"></div>
  <script>
    const status = document.getElementById('status');
    document.querySelectorAll('.task input').forEach((box) => {{
      box.addEventListener('change', async () => {{
        const id = box.dataset.id;
        status.textContent = 'Saving...';
        const res = await fetch('/api/toggle?id=' + encodeURIComponent(id), {{ method: 'POST' }});
        if (!res.ok) {{
          status.textContent = 'Save failed';
          box.checked = !box.checked;
          return;
        }}
        box.closest('.task').classList.toggle('done', box.checked);
        status.textContent = 'Updated on frame slide';
      }});
      box.closest('.task').classList.toggle('done', box.checked);
    }});
  </script>
</body>
</html>"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format: str, *args) -> None:
        return

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/api/tasks":
            payload = json.dumps(load_tasks()).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(payload)
            return
        if parsed.path not in ("/", "/index.html"):
            self.send_error(404)
            return
        body = page(load_tasks()).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path != "/api/toggle":
            self.send_error(404)
            return
        task_id = parse_qs(parsed.query).get("id", [""])[0]
        if not toggle_task(task_id):
            self.send_error(404, "Task not found")
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"ok": True}).encode("utf-8"))


def main() -> None:
    port = load_port()
    if google_enabled():
        try:
            sync_google()
        except SystemExit as exc:
            print(f"Google sync skipped: {exc}")
        except Exception as exc:
            print(f"Google sync failed: {exc}")
    else:
        render_png()
    server = ThreadingHTTPServer((HOST, port), Handler)
    print(f"Tasks UI: http://127.0.0.1:{port}")
    print(f"PNG output: {OUTPUT_FILE}")
    server.serve_forever()


if __name__ == "__main__":
    main()
