#!/usr/bin/env python3
"""PC web UI for Wi-Fi frame boot console (direct HTTP + NAS queue fallback)."""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.parse
import urllib.request
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "scripts" / "frame.conf"
NAS_CONSOLE = Path(r"\\192.168.1.23\nas\frame-console")
FRAME_IP = "192.168.1.85"
FRAME_PORT = 8080
TOKEN = "frame-local"
HOST = "127.0.0.1"
PORT = 8766


def load_config() -> None:
    global FRAME_IP, TOKEN, NAS_CONSOLE
    if not CONFIG.exists():
        return
    for line in CONFIG.read_text(encoding="utf-8").splitlines():
        if "=" not in line or line.strip().startswith("#"):
            continue
        key, value = line.split("=", 1)
        key, value = key.strip(), value.strip()
        if key == "FRAME_IP":
            FRAME_IP = value
        elif key == "AGENT_TOKEN":
            TOKEN = value
        elif key == "NAS_HOST":
            NAS_CONSOLE = Path(rf"\\{value}\nas\frame-console")


def frame_url(path: str, query: dict | None = None) -> str:
    q = {"token": TOKEN}
    if query:
        q.update(query)
    return f"http://{FRAME_IP}:{FRAME_PORT}{path}?{urllib.parse.urlencode(q)}"


def try_frame_get(path: str, query: dict | None = None) -> tuple[bool, str]:
    url = frame_url(path, query)
    try:
        with urllib.request.urlopen(url, timeout=5) as resp:
            return True, resp.read().decode("utf-8", "replace")
    except Exception as exc:  # noqa: BLE001
        return False, str(exc)


def queue_command(cmd: str) -> str:
    pending = NAS_CONSOLE / "queue" / "pending"
    pending.mkdir(parents=True, exist_ok=True)
    stamp = __import__("datetime").datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    path = pending / f"{stamp}.cmd"
    path.write_text(cmd, encoding="utf-8")
    return str(path)


def read_heartbeat() -> dict:
    hb = NAS_CONSOLE / "heartbeat.json"
    if hb.exists():
        try:
            return json.loads(hb.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            pass
    return {}


HTML = """<!doctype html>
<html><head><meta charset=utf-8><title>Frame Wi-Fi Console</title>
<style>
body{font-family:system-ui;background:#0f1419;color:#e8eef5;margin:1rem}
button,input,select{padding:.4rem .6rem;margin:.2rem;border-radius:6px;border:1px solid #345;background:#1a2330;color:inherit}
button{background:#2563eb;border-color:#2563eb;cursor:pointer}
pre{background:#111820;padding:1rem;border-radius:8px;white-space:pre-wrap}
.row{display:flex;gap:.5rem;flex-wrap:wrap;align-items:center}
</style></head><body>
<h1>Frame Wi-Fi Boot Console</h1>
<p>Direct: <code>http://FRAME_IP:8080</code> &nbsp;|&nbsp; NAS fallback queue when direct is down</p>
<div class=row>
<button onclick="act('status')">Status</button>
<button onclick="act('list','/system/media')">List /system/media</button>
<button onclick="act('install_splash')">Install splash</button>
<button onclick="act('pull_deploy')">Pull NAS deploy</button>
<button onclick="act('start_agent')">Start agent</button>
<button onclick="act('reboot')">Reboot</button>
</div>
<div class=row>
<input id=path value="/system/media/bootanimation.zip" style="flex:1">
<button onclick="act('read', document.getElementById('path').value)">Read file</button>
</div>
<pre id=out>Loading...</pre>
<script>
async function act(action, arg='') {
  const out = document.getElementById('out');
  out.textContent = 'Working...';
  const res = await fetch('/api/' + action + (arg ? '?path=' + encodeURIComponent(arg) : ''));
  out.textContent = await res.text();
}
act('status');
</script></body></html>"""


class Handler(BaseHTTPRequestHandler):
    def _json(self, obj: dict, code: int = HTTPStatus.OK) -> None:
        data = json.dumps(obj, indent=2).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _text(self, text: str, code: int = HTTPStatus.OK) -> None:
        data = text.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:  # noqa: N802
        load_config()
        if self.path == "/" or self.path.startswith("/?"):
            self._text(HTML.replace("FRAME_IP", FRAME_IP), HTTPStatus.OK)
            return

        if not self.path.startswith("/api/"):
            self.send_error(HTTPStatus.NOT_FOUND)
            return

        action = self.path.split("/api/", 1)[1].split("?", 1)[0]
        query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        path = query.get("path", [""])[0]

        if action == "status":
            ok, body = try_frame_get("/cgi-bin/status.cgi")
            if ok:
                self._text(f"DIRECT OK\n{body}")
                return
            hb = read_heartbeat()
            queued = queue_command("start_agent")
            self._text(
                "DIRECT FAILED\n"
                f"{body}\n\n"
                f"NAS heartbeat: {json.dumps(hb, indent=2)}\n\n"
                f"Queued start_agent via NAS:\n{queued}"
            )
            return

        if action == "list" and path:
            ok, body = try_frame_get("/cgi-bin/list.cgi", {"path": path})
            if ok:
                self._text(body)
                return
            queued = queue_command(f"copy_nas:frame-deploy/bootanimation.zip>{path}")
            self._text(f"Direct failed; queued NAS list fallback not available.\nQueued probe: {queued}")
            return

        if action == "read" and path:
            ok, body = try_frame_get("/cgi-bin/read.cgi", {"path": path})
            self._text(body if ok else f"Direct failed: {body}")
            return

        if action == "install_splash":
            ok, body = try_frame_get("/cgi-bin/install_splash.cgi")
            if ok:
                self._text(body)
                return
            queued = queue_command("install_splash")
            self._text(f"Queued install_splash:\n{queued}")
            return

        if action == "pull_deploy":
            queued = queue_command("pull_deploy")
            self._text(f"Queued pull_deploy:\n{queued}")
            return

        if action == "start_agent":
            queued = queue_command("start_agent")
            self._text(f"Queued start_agent:\n{queued}")
            return

        if action == "reboot":
            ok, body = try_frame_get("/cgi-bin/reboot.cgi")
            if ok:
                self._text(body)
                return
            queued = queue_command("reboot")
            self._text(f"Queued reboot:\n{queued}")
            return

        self.send_error(HTTPStatus.BAD_REQUEST)


def main() -> None:
    load_config()
    NAS_CONSOLE.mkdir(parents=True, exist_ok=True)
    (NAS_CONSOLE / "queue" / "pending").mkdir(parents=True, exist_ok=True)
    (NAS_CONSOLE / "queue" / "done").mkdir(parents=True, exist_ok=True)
    print(f"Frame Wi-Fi Console: http://{HOST}:{PORT}")
    print(f"Target frame: http://{FRAME_IP}:{FRAME_PORT}  NAS: {NAS_CONSOLE}")
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
