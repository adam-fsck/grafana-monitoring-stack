#!/usr/bin/env python3
"""Polls Microsoft Graph for Entra ID sign-in and directory audit logs and
pushes each record as a JSON log line to Loki."""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

TENANT_ID = os.environ["ENTRA_TENANT_ID"]
CLIENT_ID = os.environ["ENTRA_CLIENT_ID"]
CLIENT_SECRET = os.environ["ENTRA_CLIENT_SECRET"]
POLL_INTERVAL = int(os.environ.get("ENTRA_POLL_INTERVAL_SECONDS", "300"))
LOKI_URL = os.environ.get("LOKI_URL", "http://loki:3100/loki/api/v1/push")
STATE_DIR = os.environ.get("STATE_DIR", "/state")

TOKEN_URL = f"https://login.microsoftonline.com/{TENANT_ID}/oauth2/v2.0/token"
GRAPH_BASE = "https://graph.microsoft.com/v1.0"

# Requires Application permissions AuditLog.Read.All + Directory.Read.All,
# admin-consented, on the Azure App Registration used here.
SOURCES = {
    "entra-signin": "/auditLogs/signIns",
    "entra-directory-audit": "/auditLogs/directoryAudits",
}


def get_token() -> str:
    data = urllib.parse.urlencode(
        {
            "grant_type": "client_credentials",
            "client_id": CLIENT_ID,
            "client_secret": CLIENT_SECRET,
            "scope": "https://graph.microsoft.com/.default",
        }
    ).encode()
    req = urllib.request.Request(TOKEN_URL, data=data, method="POST")
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)["access_token"]


def state_path(name: str) -> str:
    return os.path.join(STATE_DIR, f"{name}.cursor")


def load_cursor(name: str) -> str:
    path = state_path(name)
    if os.path.exists(path):
        with open(path) as f:
            cursor = f.read().strip()
            if cursor:
                return cursor
    # First run: start 5 minutes back, not from epoch, to avoid pulling a
    # tenant's full audit history on first start.
    return (datetime.now(timezone.utc) - timedelta(minutes=5)).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )


def save_cursor(name: str, value: str) -> None:
    with open(state_path(name), "w") as f:
        f.write(value)


def fetch_records(token: str, path: str, since: str) -> list:
    query = urllib.parse.urlencode(
        {"$filter": f"createdDateTime ge {since}", "$orderby": "createdDateTime asc"}
    )
    url = f"{GRAPH_BASE}{path}?{query}"
    headers = {"Authorization": f"Bearer {token}"}
    records = []
    while url:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = json.load(resp)
        records.extend(body.get("value", []))
        url = body.get("@odata.nextLink")
    return records


def push_to_loki(job: str, records: list) -> None:
    if not records:
        return
    values = []
    for rec in records:
        dt = datetime.strptime(rec["createdDateTime"], "%Y-%m-%dT%H:%M:%SZ").replace(
            tzinfo=timezone.utc
        )
        ts_ns = str(int(dt.timestamp() * 1_000_000_000))
        values.append([ts_ns, json.dumps(rec, separators=(",", ":"))])

    payload = {
        "streams": [
            {
                "stream": {"job": job, "platform": "m365", "source": "entra-id"},
                "values": values,
            }
        ]
    }
    req = urllib.request.Request(
        LOKI_URL,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        resp.read()


def run_once() -> None:
    token = get_token()
    for job, path in SOURCES.items():
        since = load_cursor(job)
        records = fetch_records(token, path, since)
        if records:
            push_to_loki(job, records)
            save_cursor(job, records[-1]["createdDateTime"])
            print(f"{job}: pushed {len(records)} records", flush=True)
        else:
            print(f"{job}: no new records", flush=True)


def main() -> None:
    os.makedirs(STATE_DIR, exist_ok=True)
    while True:
        try:
            run_once()
        except (urllib.error.URLError, urllib.error.HTTPError, KeyError) as exc:
            print(f"poll failed: {exc}", file=sys.stderr, flush=True)
        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    main()
