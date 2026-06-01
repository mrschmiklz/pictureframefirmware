#!/usr/bin/env python3
"""Sync Google Tasks to tasks.json for the picture frame.

Setup (one time):
  1. https://console.cloud.google.com/ → create project → enable "Google Tasks API"
  2. APIs & Services → Credentials → Create OAuth client ID → Desktop app
  3. Download JSON as tasks/credentials.json
  4. python google_tasks.py auth
  5. python google_tasks.py sync

Commands:
  auth   Open browser to authorize this PC/NAS
  sync   Pull today's tasks into tasks.json and render PNG
  lists  Show your Google Task lists (pick tasklist_id for config)
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import date, datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent
CONFIG_FILE = ROOT / "google_config.json"
TOKEN_FILE = ROOT / "google_token.json"
TASKS_FILE = ROOT / "tasks.json"
SCOPES = ["https://www.googleapis.com/auth/tasks"]


def load_config() -> dict:
    if not CONFIG_FILE.exists():
        example = ROOT / "google_config.json.example"
        raise SystemExit(
            f"Missing {CONFIG_FILE}. Copy {example.name} to google_config.json and edit it."
        )
    with CONFIG_FILE.open(encoding="utf-8") as handle:
        return json.load(handle)


def credentials_path(config: dict) -> Path:
    return ROOT / config.get("credentials_file", "credentials.json")


def load_credentials(config: dict):
    from google.auth.transport.requests import Request
    from google.oauth2.credentials import Credentials
    from google_auth_oauthlib.flow import InstalledAppFlow

    creds = None
    if TOKEN_FILE.exists():
        creds = Credentials.from_authorized_user_file(str(TOKEN_FILE), SCOPES)

    if creds and creds.valid:
        return creds

    if creds and creds.expired and creds.refresh_token:
        creds.refresh(Request())
        TOKEN_FILE.write_text(creds.to_json(), encoding="utf-8")
        return creds

    secret = credentials_path(config)
    if not secret.exists():
        raise SystemExit(
            f"Missing {secret}. Download OAuth Desktop credentials from Google Cloud Console."
        )

    flow = InstalledAppFlow.from_client_secrets_file(str(secret), SCOPES)
    creds = flow.run_local_server(port=0)
    TOKEN_FILE.write_text(creds.to_json(), encoding="utf-8")
    return creds


def get_service(config: dict | None = None):
    from googleapiclient.discovery import build

    config = config or load_config()
    creds = load_credentials(config)
    return build("tasks", "v1", credentials=creds, cache_discovery=False)


def parse_due(value: str | None) -> date | None:
    if not value:
        return None
    cleaned = value.replace("Z", "+00:00")
    return datetime.fromisoformat(cleaned).date()


def fetch_frame_tasks(config: dict | None = None) -> dict:
    config = config or load_config()
    service = get_service(config)
    tasklist_id = config.get("tasklist_id", "@default")
    max_tasks = int(config.get("max_tasks", 8))
    include_no_due = bool(config.get("include_no_due_date", True))
    include_overdue = bool(config.get("include_overdue", True))
    today = datetime.now().date()

    items = []
    page_token = None
    while True:
        response = (
            service.tasks()
            .list(
                tasklist=tasklist_id,
                showCompleted=True,
                showHidden=False,
                maxResults=100,
                pageToken=page_token,
            )
            .execute()
        )
        items.extend(response.get("items", []))
        page_token = response.get("nextPageToken")
        if not page_token:
            break

    selected = []
    for item in items:
        title = (item.get("title") or "").strip()
        if not title:
            continue
        status = item.get("status", "needsAction")
        done = status == "completed"
        due = parse_due(item.get("due"))

        if done:
            continue

        if due is None:
            if not include_no_due:
                continue
        elif due > today and not include_overdue:
            continue
        elif due > today:
            continue

        selected.append(
            {
                "id": item["id"],
                "text": title,
                "done": done,
                "due": item.get("due"),
                "google_id": item["id"],
            }
        )

    selected.sort(key=lambda task: (task.get("due") is None, task.get("due") or ""))
    selected = selected[:max_tasks]

    return {
        "title": "Today",
        "source": "google",
        "tasklist_id": tasklist_id,
        "synced_at": datetime.now(timezone.utc).isoformat(),
        "tasks": selected,
    }


def set_task_done(task_id: str, done: bool, config: dict | None = None) -> None:
    config = config or load_config()
    service = get_service(config)
    tasklist_id = config.get("tasklist_id", "@default")
    body = {"status": "completed" if done else "needsAction"}
    service.tasks().patch(tasklist=tasklist_id, task=task_id, body=body).execute()


def save_tasks(data: dict) -> None:
    with TASKS_FILE.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")


def render_png() -> None:
    subprocess.run([sys.executable, str(ROOT / "render_tasks.py")], check=True)


def sync(render: bool = True) -> Path | None:
    data = fetch_frame_tasks()
    save_tasks(data)
    print(f"Synced {len(data['tasks'])} tasks from Google Tasks")
    if render:
        render_png()
        return ROOT / "tasks_today.png"
    return None


def cmd_lists() -> None:
    config = load_config()
    service = get_service(config)
    response = service.tasklists().list(maxResults=100).execute()
    for item in response.get("items", []):
        print(f"{item['id']}\t{item.get('title', '')}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Google Tasks → picture frame")
    parser.add_argument("command", choices=["auth", "sync", "lists"])
    parser.add_argument("--no-render", action="store_true")
    args = parser.parse_args()

    config = load_config()
    if args.command == "auth":
        load_credentials(config)
        print(f"Authorized. Token saved to {TOKEN_FILE}")
        return
    if args.command == "lists":
        cmd_lists()
        return
    if args.command == "sync":
        path = sync(render=not args.no_render)
        if path:
            print(f"Wrote {path}")


if __name__ == "__main__":
    main()
