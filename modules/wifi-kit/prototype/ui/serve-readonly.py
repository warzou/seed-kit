#!/usr/bin/env python3
"""Read-only local HTTP prototype for wifi-kit."""

from __future__ import annotations

import argparse
import json
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


SCRIPT_DIR = Path(__file__).resolve().parent
WIFI_KIT_SH = SCRIPT_DIR.parent / "wifi-kit.sh"
INDEX_HTML = SCRIPT_DIR / "index.html"


def run_json_command(args: list[str]) -> dict:
    result = subprocess.run(
        ["sh", str(WIFI_KIT_SH), *args],
        check=False,
        capture_output=True,
        text=True,
    )

    if result.returncode != 0:
        return {
            "status": "error",
            "command": " ".join(args),
            "returncode": result.returncode,
            "stderr": result.stderr.strip(),
        }

    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        return {
            "status": "error",
            "command": " ".join(args),
            "error": f"invalid-json: {exc}",
        }


def safe_diagnose() -> dict:
    return run_json_command(["safe-diagnose", "--json"])


def scan(refresh: bool = False) -> dict:
    args = ["scan-real", "--json"]
    if refresh:
        args.insert(1, "--refresh")
    return run_json_command(args)


def snapshot_preview() -> dict:
    return run_json_command(["state-snapshot", "--simulate", "--json"])


def ui_data() -> dict:
    snapshot = snapshot_preview()
    return {
        "diagnose": safe_diagnose(),
        "snapshot": snapshot,
        "runtime_state": {
            "source": "state-snapshot --simulate --json",
            "data": snapshot,
        },
        "scan": scan(),
    }


def render_index() -> str:
    html = INDEX_HTML.read_text(encoding="utf-8")
    data = json.dumps(ui_data(), indent=2).replace("<", "\\u003c")
    start = '<script id="wifi-kit-data" type="application/json">'
    end = "</script>"
    before, rest = html.split(start, 1)
    _old_json, after = rest.split(end, 1)
    return f"{before}{start}\n{data}\n  {end}{after}"


class WifiKitReadOnlyHandler(BaseHTTPRequestHandler):
    server_version = "wifi-kit-readonly/0"

    def log_message(self, fmt: str, *args: object) -> None:
        return

    def send_bytes(self, status: int, content_type: str, body: bytes) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_json(self, payload: dict, status: int = 200) -> None:
        body = json.dumps(payload, indent=2).encode("utf-8") + b"\n"
        self.send_bytes(status, "application/json; charset=utf-8", body)

    def do_POST(self) -> None:
        self.send_json(
            {
                "error": "method-not-allowed",
                "safety": "read-only GET endpoints only",
            },
            status=405,
        )

    def do_PUT(self) -> None:
        self.do_POST()

    def do_DELETE(self) -> None:
        self.do_POST()

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)

        if path in ("/", "/index.html"):
            self.send_bytes(200, "text/html; charset=utf-8", render_index().encode("utf-8"))
            return

        if path == "/api/safe-diagnose":
            self.send_json(safe_diagnose())
            return

        if path == "/api/scan":
            self.send_json(scan(refresh=query.get("refresh") == ["1"]))
            return

        if path == "/api/scan-refresh":
            self.send_json(scan(refresh=True))
            return

        if path == "/api/snapshot-preview":
            self.send_json(snapshot_preview())
            return

        if path == "/api/runtime-state":
            self.send_json(ui_data()["runtime_state"])
            return

        if path == "/api/ui-data":
            self.send_json(ui_data())
            return

        self.send_json({"error": "not-found"}, status=404)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="wifi-kit read-only local HTTP prototype")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8088)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    server = ThreadingHTTPServer((args.host, args.port), WifiKitReadOnlyHandler)
    print(f"wifi-kit read-only HTTP on http://{args.host}:{args.port}")
    print("GET only; no network mutation endpoints")
    server.serve_forever()


if __name__ == "__main__":
    main()
