#!/usr/bin/env python3
"""Read-only local HTTP prototype for wifi-kit."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import socket
import subprocess
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


SCRIPT_DIR = Path(__file__).resolve().parent
WIFI_KIT_SH = SCRIPT_DIR.parent / "wifi-kit.sh"
AP_SETUP_TEST_SH = SCRIPT_DIR.parent / "ap-setup-test.sh"
INDEX_HTML = SCRIPT_DIR / "index.html"
NORMAL_UI_PORT = 18089
RECOVERY_UI_PORT = 80
RECOVERY_AP_TEST_PASSWORD = "12345678"
AP_ONLY_NM_STATE = Path("/tmp/wifi-kit-ap-only-nm-state")
RECONNECT_PREVIOUS_LOG = Path("/tmp/wifi-kit-reconnect-previous.log")

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


def read_ap_only_state_value(key: str) -> str:
    try:
        for line in AP_ONLY_NM_STATE.read_text(encoding="utf-8").splitlines():
            name, sep, value = line.partition("=")
            if sep and name == key:
                return value
    except OSError:
        return ""
    return ""


def append_reconnect_previous_log(
    *,
    previous_connection: str,
    recovery_mode_active: bool,
    reconnect_started: bool,
    status: str,
    error: str = "",
) -> None:
    timestamp = datetime.now(timezone.utc).isoformat(timespec="seconds")
    fields = [
        f"timestamp={json.dumps(timestamp)}",
        "action=reconnect-previous",
        f"previous_connection={json.dumps(previous_connection or 'unknown')}",
        f"recovery_mode_active={'yes' if recovery_mode_active else 'no'}",
        f"reconnect_started={'yes' if reconnect_started else 'no'}",
        f"status={json.dumps(status)}",
    ]
    if error:
        fields.append(f"error={json.dumps(error)}")
    try:
        with RECONNECT_PREVIOUS_LOG.open("a", encoding="utf-8") as handle:
            handle.write(" ".join(fields) + "\n")
    except OSError:
        pass


def start_reconnect_previous() -> dict:
    previous_connection = read_ap_only_state_value("active_connection") or "unknown"
    if os.geteuid() != 0:
        append_reconnect_previous_log(
            previous_connection=previous_connection,
            recovery_mode_active=True,
            reconnect_started=False,
            status="failure",
            error="root-required",
        )
        return {
            "status": "failure",
            "error": "root-required",
            "previous_connection": previous_connection,
            "reconnect_started": False,
        }

    try:
        subprocess.Popen(
            [
                "sh",
                "-c",
                'sleep 1; exec sh "$1" stop >> "$2" 2>&1',
                "wifi-kit-reconnect-previous",
                str(AP_SETUP_TEST_SH),
                str(RECONNECT_PREVIOUS_LOG),
            ],
            cwd=str(SCRIPT_DIR.parent),
            start_new_session=True,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except OSError as exc:
        append_reconnect_previous_log(
            previous_connection=previous_connection,
            recovery_mode_active=True,
            reconnect_started=False,
            status="failure",
            error=f"start-failed: {exc}",
        )
        return {
            "status": "failure",
            "error": f"start-failed: {exc}",
            "previous_connection": previous_connection,
            "reconnect_started": False,
        }

    append_reconnect_previous_log(
        previous_connection=previous_connection,
        recovery_mode_active=True,
        reconnect_started=True,
        status="success",
    )

    return {
        "status": "success",
        "action": "reconnect-previous",
        "previous_connection": previous_connection,
        "reconnect_started": True,
        "log": str(RECONNECT_PREVIOUS_LOG),
        "note": "Recovery UI may disappear while wlan0 returns to NetworkManager.",
    }


def safe_diagnose() -> dict:
    return run_json_command(["safe-diagnose", "--json"])


def scan(refresh: bool = False) -> dict:
    args = ["scan-real", "--json"]
    if refresh:
        args.insert(1, "--refresh")
    return run_json_command(args)


def networkmanager_scan(refresh: bool = True) -> dict:
    rescan = "yes" if refresh else "no"
    result = subprocess.run(
        [
            "nmcli",
            "-t",
            "--escape",
            "no",
            "-f",
            "IN-USE,SSID,SIGNAL,SECURITY",
            "device",
            "wifi",
            "list",
            "--rescan",
            rescan,
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return {
            "status": "unavailable",
            "backend": "networkmanager",
            "reason": "nmcli-scan-failed",
            "stderr": result.stderr.strip(),
            "networks": [],
        }

    networks = []
    seen = set()
    for line in result.stdout.splitlines():
        in_use, ssid, signal, security = (line.split(":", 3) + ["", "", "", ""])[:4]
        if not ssid:
            continue
        key = (ssid, security)
        if key in seen:
            continue
        seen.add(key)
        current = in_use.strip() == "*"
        networks.append(
            {
                "ssid": ssid,
                "signal": f"{signal}%",
                "security": security or "open",
                "current": "yes" if current else "no",
                "ssid_hidden": False,
            }
        )

    return {
        "status": "ok",
        "backend": "networkmanager",
        "interface": "wlan0",
        "timestamp": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "refresh_attempted": refresh,
        "refresh_status": "ok" if refresh else "not-requested",
        "networks": networks,
    }


def wifi_scan(refresh: bool = True) -> dict:
    if networkmanager_owns_wlan0() or shutil.which("nmcli"):
        nm_scan = networkmanager_scan(refresh=refresh)
        if nm_scan.get("status") == "ok":
            return nm_scan
    fallback = scan(refresh=refresh)
    current_ssid = wlan_ssid()
    for network in fallback.get("networks", []):
        network["current"] = "yes" if network.get("ssid") == current_ssid else "no"
    return fallback


def parse_post_payload(handler: BaseHTTPRequestHandler) -> dict:
    try:
        length = int(handler.headers.get("Content-Length", "0"))
    except ValueError:
        length = 0
    if length <= 0:
        return {}
    if length > 8192:
        return {"_error": "payload-too-large"}
    raw = handler.rfile.read(length).decode("utf-8", errors="replace")
    content_type = handler.headers.get("Content-Type", "")
    if "application/json" in content_type:
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            return {"_error": "invalid-json"}
        return payload if isinstance(payload, dict) else {"_error": "invalid-json"}
    values = parse_qs(raw, keep_blank_values=True)
    return {key: value[-1] if value else "" for key, value in values.items()}


def wifi_connect_plan(payload: dict, recovery_active: bool) -> tuple[dict, int]:
    if payload.get("_error"):
        return {"status": "failure", "error": payload["_error"], "connect_started": False}, 400

    ssid = str(payload.get("ssid", "")).strip()
    password = str(payload.get("password", ""))
    if not ssid:
        return {"status": "failure", "error": "missing-ssid", "connect_started": False}, 400
    if len(ssid.encode("utf-8")) > 32:
        return {"status": "failure", "error": "ssid-too-long", "connect_started": False}, 400
    if password and len(password) < 8:
        return {"status": "failure", "error": "password-too-short", "connect_started": False}, 400

    backend = "raspberrypi-networkmanager" if networkmanager_owns_wlan0() else "unknown"
    return (
        {
            "status": "planned",
            "mutation": "not-implemented",
            "requested_ssid": ssid,
            "backend": backend,
            "password_received": "yes" if password else "no",
            "secret_policy": "runtime-only; password is not logged or persisted",
            "connect_started": False,
            "warning_if_recovery_active": (
                "Future apply will keep recovery active until NetworkManager validates IP, gateway, and internet."
                if recovery_active
                else "Normal mode plan only; no recovery cleanup required in this stub."
            ),
            "connect_plan": [
                "create temporary NetworkManager connection for requested SSID",
                "attempt connection without modifying the previous profile",
                "validate IP address, gateway, and internet reachability",
                "on success: stop recovery services and return to normal UI",
                "on failure: keep AP recovery active and report the error",
            ],
        },
        200,
    )


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


def networkmanager_owns_wlan0() -> bool:
    output = run_text_command(["nmcli", "-t", "-f", "DEVICE,TYPE,STATE", "device", "status"])
    for line in output.splitlines():
        device, typ, state = (line.split(":") + ["", "", ""])[:3]
        if device == "wlan0" and typ == "wifi" and state in {"connected", "connecting", "disconnected"}:
            return True
    return False


def wlan_ssid() -> str:
    output = run_text_command(["nmcli", "-t", "-f", "ACTIVE,SSID", "device", "wifi", "list", "--rescan", "no"])
    for line in output.splitlines():
        active, _, ssid = line.partition(":")
        if active == "yes" and ssid:
            return ssid
    output = run_text_command(["iw", "dev", "wlan0", "link"])
    for line in output.splitlines():
        stripped = line.strip()
        if stripped.startswith("SSID:"):
            return stripped.partition(":")[2].strip() or "unknown"
    return "unknown"


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
    nm_owns_wlan0 = networkmanager_owns_wlan0()
    scan_backend = diagnose.get("backend") or "unknown"
    diagnose_wifi = diagnose.get("current_ssid_state") or ""
    wifi = wlan_ssid()
    if wifi == "unknown" and diagnose_wifi not in {"", "unknown", "present"}:
        wifi = diagnose_wifi
    if wifi == "unknown":
        wifi = wlan_connection()
    return {
        "hostname": hostname,
        "mode": "recovery" if recovery_active else "normal",
        "ip": diagnose.get("current_ip") or "unknown",
        "wifi": recovery_ssid if recovery_active else wifi,
        "interface": diagnose.get("interface") or "unknown",
        "networkmanager": networkmanager_state(),
        "backend": f"NM + {scan_backend}" if nm_owns_wlan0 and scan_backend != "unknown" else ("NM" if nm_owns_wlan0 else scan_backend),
        "scan_backend": scan_backend,
        "uptime": uptime_label(),
        "temperature": temperature_label(),
        "recovery_active": recovery_active,
        "ap_state": "active" if recovery_active else "inactive",
        "dhcp_state": recovery.get("dhcp") or "inactive",
        "dns_state": recovery.get("dns") or "inactive",
        "ui_state": recovery.get("ui") or "read-only",
        "recovery_ssid": recovery_ssid,
        "recovery_ip": recovery.get("ip") or "192.168.50.1",
        "normal_ui_port": NORMAL_UI_PORT,
        "recovery_ui_port": RECOVERY_UI_PORT,
        "recovery_ap_password_policy": "min-8-chars",
        "recovery_ap_password_configurable": True,
        "recovery_ap_password_current": RECOVERY_AP_TEST_PASSWORD,
        "ui_access_password": "future-not-configured",
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
            "normal_ui_port": NORMAL_UI_PORT,
            "recovery_ui_port": RECOVERY_UI_PORT,
            "ap_password_policy": "min-8-chars",
            "ap_password_configurable": True,
            "ap_password_current": RECOVERY_AP_TEST_PASSWORD,
            "ui_access_password": "future-not-configured",
        },
        "system": system_info(diagnose, recovery),
        "scan": wifi_scan(refresh=False),
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
        parsed = urlparse(self.path)
        if parsed.path == "/wifi/connect":
            payload, status = wifi_connect_plan(parse_post_payload(self), bool(self.recovery.get("active")))
            self.send_json(payload, status=status)
            return

        if parsed.path == "/reconnect-previous":
            if not self.recovery.get("active"):
                previous_connection = read_ap_only_state_value("active_connection") or "unknown"
                append_reconnect_previous_log(
                    previous_connection=previous_connection,
                    recovery_mode_active=False,
                    reconnect_started=False,
                    status="failure",
                    error="recovery-not-active",
                )
                self.send_json(
                    {
                        "status": "failure",
                        "error": "recovery-not-active",
                        "previous_connection": previous_connection,
                        "reconnect_started": False,
                        "safety": "No recovery cleanup was started from normal mode.",
                    },
                    status=409,
                )
                return

            payload = start_reconnect_previous()
            self.send_json(payload, status=200 if payload.get("status") == "success" else 500)
            return

        self.send_json(
            {
                "error": "method-not-allowed",
                "safety": "Only POST /reconnect-previous can mutate recovery state.",
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
                    "normal_ui_port": NORMAL_UI_PORT,
                    "recovery_ui_port": RECOVERY_UI_PORT,
                    "recovery_ap_password_policy": "min-8-chars",
                    "recovery_ap_password_configurable": True,
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

        if path == "/wifi/scan":
            self.send_json(wifi_scan(refresh=query.get("refresh") != ["0"]))
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
    parser.add_argument("--port", type=int, default=NORMAL_UI_PORT)
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
        "normal_ui_port": NORMAL_UI_PORT,
        "recovery_ui_port": RECOVERY_UI_PORT,
        "ap_password_policy": "min-8-chars",
        "ap_password_configurable": True,
        "ap_password_current": RECOVERY_AP_TEST_PASSWORD,
        "ui_access_password": "future-not-configured",
        "action_endpoints": sorted(ACTION_PATHS.keys()),
    }
    print(f"wifi-kit read-only HTTP on http://{args.host}:{args.port}")
    print("GET read-only; POST /reconnect-previous only when recovery is active")
    server.serve_forever()


if __name__ == "__main__":
    main()
