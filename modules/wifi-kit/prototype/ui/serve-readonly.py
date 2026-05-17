#!/usr/bin/env python3
"""Read-only local HTTP prototype for wifi-kit."""

from __future__ import annotations

import argparse
import json
import socket
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


SCRIPT_DIR = Path(__file__).resolve().parent
WIFI_KIT_SH = SCRIPT_DIR.parent / "wifi-kit.sh"
INDEX_HTML = SCRIPT_DIR / "index.html"

CAPTIVE_PATHS = {
    "/generate_204",
    "/gen_204",
    "/hotspot-detect.html",
    "/library/test/success.html",
    "/connecttest.txt",
    "/ncsi.txt",
}

ACTION_PATHS = {
    "/reconnect-previous": "reconnect-previous",
    "/choose-other-wifi": "choose-other-wifi",
    "/start-recovery": "start-recovery",
    "/exit-recovery": "exit-recovery",
    "/reboot-recovery": "reboot-recovery",
    "/set-recovery-password": "set-recovery-password",
}


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


def run_text_command(args: list[str], timeout: float = 2.0) -> str:
    try:
        result = subprocess.run(
            args,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    if result.returncode != 0:
        return ""
    return result.stdout.strip()


def safe_diagnose() -> dict:
    return run_json_command(["safe-diagnose", "--json"])


def scan(refresh: bool = False) -> dict:
    args = ["scan-real", "--json"]
    if refresh:
        args.insert(1, "--refresh")
    return run_json_command(args)


def snapshot_preview() -> dict:
    return run_json_command(["state-snapshot", "--simulate", "--json"])


def uptime_label() -> str:
    try:
        seconds = int(float(Path("/proc/uptime").read_text(encoding="utf-8").split()[0]))
    except (OSError, ValueError, IndexError):
        return "unknown"
    days, rem = divmod(seconds, 86400)
    hours, rem = divmod(rem, 3600)
    minutes = rem // 60
    if days:
        return f"{days}d {hours}h"
    if hours:
        return f"{hours}h {minutes}m"
    return f"{minutes}m"


def temperature_label() -> str:
    try:
        raw = Path("/sys/class/thermal/thermal_zone0/temp").read_text(encoding="utf-8").strip()
        value = int(raw) / 1000
    except (OSError, ValueError):
        return "unknown"
    return f"{value:.1f} C"


def networkmanager_state() -> str:
    state = run_text_command(["nmcli", "-t", "-f", "RUNNING", "general"])
    return state or "unknown"


def wlan_connection() -> str:
    output = run_text_command(["nmcli", "-t", "-f", "DEVICE,CONNECTION", "device", "status"])
    for line in output.splitlines():
        device, _, connection = line.partition(":")
        if device == "wlan0":
            return connection or "unknown"
    return "unknown"


def system_info(diagnose: dict, recovery: dict | None = None) -> dict:
    recovery = recovery or {}
    recovery_active = bool(recovery.get("active"))
    hostname = socket.gethostname() or "unknown"
    recovery_ssid = recovery.get("ssid") or f"Wifi-Kit-{hostname}"
    return {
        "hostname": hostname,
        "mode": "recovery" if recovery_active else "normal",
        "ip": diagnose.get("current_ip") or "unknown",
        "wifi": diagnose.get("current_ssid_state") or wlan_connection(),
        "interface": diagnose.get("interface") or "unknown",
        "networkmanager": networkmanager_state(),
        "uptime": uptime_label(),
        "temperature": temperature_label(),
        "recovery_active": recovery_active,
        "ap_state": "active" if recovery_active else "inactive",
        "dhcp_state": recovery.get("dhcp") or "inactive",
        "dns_state": recovery.get("dns") or "inactive",
        "ui_state": recovery.get("ui") or "read-only",
        "recovery_ssid": recovery_ssid,
        "recovery_ip": recovery.get("ip") or "192.168.50.1",
        "last_recovery_event": "recovery-captive-ui-validated" if recovery_active else "normal-client-mode",
    }


def ui_data(recovery: dict | None = None) -> dict:
    diagnose = safe_diagnose()
    snapshot = snapshot_preview()
    hostname = socket.gethostname() or "node"
    return {
        "diagnose": diagnose,
        "snapshot": snapshot,
        "runtime_state": {
            "source": "state-snapshot --simulate --json",
            "data": snapshot,
        },
        "connect_options": {
            "keep_ap_active_default": True,
            "apply_endpoint": "not-implemented",
            "ap_services_started": bool(recovery and recovery.get("active")),
        },
        "recovery": recovery or {
            "active": False,
            "ssid": f"Wifi-Kit-{hostname}",
            "ip": "192.168.50.1",
            "ui_port": 80,
            "dhcp": "planned",
            "dns": "planned",
            "ui": "read-only",
            "captive_portal": "planned",
            "actions": "plan-only",
        },
        "system": system_info(diagnose, recovery),
        "scan": scan(),
    }


def render_index(recovery: dict | None = None) -> str:
    html = INDEX_HTML.read_text(encoding="utf-8")
    data = json.dumps(ui_data(recovery), indent=2).replace("<", "\\u003c")
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

    def send_redirect(self, location: str = "/recovery") -> None:
        body = b"Wifi-Kit recovery\n"
        self.send_response(302)
        self.send_header("Location", location)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    @property
    def recovery(self) -> dict:
        return getattr(self.server, "wifi_kit_recovery", {})

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

        if path in CAPTIVE_PATHS:
            self.send_redirect("/recovery")
            return

        if path in ("/", "/index.html", "/recovery"):
            self.send_bytes(200, "text/html; charset=utf-8", render_index(self.recovery).encode("utf-8"))
            return

        if path == "/status":
            self.send_json(
                {
                    "status": "ok",
                    "mode": "recovery" if self.recovery.get("active") else "readonly",
                    "recovery": self.recovery,
                    "system": ui_data(self.recovery)["system"],
                    "actions": "plan-only",
                }
            )
            return

        if path in ACTION_PATHS:
            self.send_json(
                {
                    "status": "planned",
                    "action": ACTION_PATHS[path],
                    "mutation": "not-implemented",
                    "safety": "visible in UI only; no network mutation from HTTP V1",
                    "recovery": self.recovery,
                }
            )
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
            self.send_json(ui_data(self.recovery)["runtime_state"])
            return

        if path == "/api/ui-data":
            self.send_json(ui_data(self.recovery))
            return

        self.send_json({"error": "not-found"}, status=404)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="wifi-kit read-only local HTTP prototype")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8088)
    parser.add_argument("--recovery-mode", action="store_true")
    parser.add_argument("--recovery-ssid", default="")
    parser.add_argument("--recovery-ip", default="192.168.50.1")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    hostname = socket.gethostname() or "node"
    server = ThreadingHTTPServer((args.host, args.port), WifiKitReadOnlyHandler)
    server.wifi_kit_recovery = {
        "active": bool(args.recovery_mode),
        "ssid": args.recovery_ssid or f"Wifi-Kit-{hostname}",
        "ip": args.recovery_ip,
        "ui_port": args.port,
        "dhcp": "active" if args.recovery_mode else "planned",
        "dns": "active" if args.recovery_mode else "planned",
        "ui": "active" if args.recovery_mode else "read-only",
        "captive_portal": "basic" if args.recovery_mode else "planned",
        "actions": "plan-only",
        "action_endpoints": sorted(ACTION_PATHS.keys()),
    }
    print(f"wifi-kit read-only HTTP on http://{args.host}:{args.port}")
    print("GET only; no network mutation endpoints")
    server.serve_forever()


if __name__ == "__main__":
    main()
