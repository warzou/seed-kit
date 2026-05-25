#!/usr/bin/env python3
"""Read-only local HTTP prototype for wifi-kit."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


SCRIPT_DIR = Path(__file__).resolve().parent
WIFI_KIT_SH = SCRIPT_DIR.parent / "wifi-kit.sh"
AP_SETUP_TEST_SH = SCRIPT_DIR.parent / "ap-setup-test.sh"
CONNECT_TRANSACTION_SH = SCRIPT_DIR.parent / "wifi-kit-connect-transaction.sh"
ACTION_WRAPPER_SH = SCRIPT_DIR.parent / "wifi-kit-action-wrapper.sh"
INSTALLED_ACTION_WRAPPER_SH = Path(os.environ.get("WIFI_KIT_ACTION_WRAPPER", "/opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh"))
INSTALLED_APP_DIR = INSTALLED_ACTION_WRAPPER_SH.parent
INSTALLED_NM_AP_LAB_SH = INSTALLED_APP_DIR / "wifi-kit-nm-ap-lab.sh"
SUDOERS_PATH = Path(os.environ.get("WIFI_KIT_SUDOERS_PATH", "/etc/sudoers.d/wifi-kit"))
UI_SERVICE_NAME = os.environ.get("WIFI_KIT_UI_SERVICE", "wifi-kit-ui.service")
BOOT_GUARD_SERVICE_NAME = os.environ.get("WIFI_KIT_BOOT_GUARD_SERVICE", "wifi-kit-boot-guard.service")
RUNTIME_WATCHDOG_SERVICE_NAME = os.environ.get("WIFI_KIT_RUNTIME_WATCHDOG_SERVICE", "wifi-kit-runtime-watchdog.service")
INDEX_HTML = SCRIPT_DIR / "index.html"
NORMAL_UI_PORT = 18089  # Prototype/dev local UI default; production/service target is 54321 in contract.
RECOVERY_UI_PORT = 80
RECOVERY_AP_TEST_PASSWORD = "12345678"
AP_ONLY_NM_STATE = Path("/tmp/wifi-kit-ap-only-nm-state")
RECOVERY_UI_PID = Path("/tmp/wifi-kit-ui-recovery.pid")
RECOVERY_HOSTAPD_PID = Path("/tmp/wifi-kit-hostapd-test.pid")
NM_AP_LAB_UI_PID = Path("/tmp/wifi-kit-nm-ap-lab-ui.pid")
RUNTIME_CONFIG_PATH = Path(
    os.environ.get("WIFI_KIT_RUNTIME_CONFIG", str(Path.home() / ".config" / "wifi-kit" / "runtime.conf"))
)
ACTION_LOG_DIR = Path(os.environ.get("WIFI_KIT_ACTION_LOG_DIR", "/tmp/wifi-kit-actions"))
RUNTIME_WATCHDOG_STATE = Path(os.environ.get("WIFI_KIT_RUNTIME_WATCHDOG_STATE", "/tmp/wifi-kit-actions/runtime-watchdog-state"))
RUNTIME_WATCHDOG_INSTABILITY = Path(
    os.environ.get("WIFI_KIT_RUNTIME_WATCHDOG_INSTABILITY", "/tmp/wifi-kit-actions/runtime-watchdog-instability")
)


def action_log_identity() -> str:
    try:
        return str(os.getuid())
    except AttributeError:
        return os.environ.get("USERNAME", "unknown")


def action_log_path(action: str) -> Path:
    return ACTION_LOG_DIR / f"{action}-{action_log_identity()}.log"


def unique_action_log_path(action: str) -> Path:
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    return ACTION_LOG_DIR / f"{action}-{action_log_identity()}-{timestamp}.log"


def is_action_log_path(path: Path) -> bool:
    try:
        return path.resolve().parent == ACTION_LOG_DIR.resolve()
    except OSError:
        return False


def pid_is_alive(pid_path: Path, expected_markers: tuple[str, ...]) -> bool:
    try:
        pid_text = pid_path.read_text(encoding="utf-8").strip().splitlines()[0]
        pid = int(pid_text)
    except (OSError, IndexError, ValueError):
        return False
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    cmdline_path = Path("/proc") / str(pid) / "cmdline"
    try:
        cmdline = cmdline_path.read_text(encoding="utf-8", errors="replace").replace("\x00", " ")
    except OSError:
        return True
    return any(marker in cmdline for marker in expected_markers)


def recovery_runtime_active() -> bool:
    return pid_is_alive(RECOVERY_UI_PID, ("serve-readonly.py", "--recovery-mode")) or pid_is_alive(
        RECOVERY_HOSTAPD_PID,
        ("hostapd", "wifi-kit-hostapd-test.conf"),
    )


RECONNECT_PREVIOUS_LOG = action_log_path("reconnect-previous")
CONNECT_TRANSACTION_TIMEOUT_SECONDS = 180
CONNECT_WRAPPER_ACTION = "connect-wifi"
START_AP_MODE_LOG = action_log_path("start-ap-mode")
RETURN_DEFAULT_NETWORK_LOG = action_log_path("return-default-network")
AP_RETURN_CHECK_ONCE_LOG = action_log_path("ap-return-check")
SYSTEM_REBOOT_LOG = action_log_path("system-reboot")
SYSTEM_SHUTDOWN_LOG = action_log_path("system-shutdown")
SCAN_FROM_AP_LOG = action_log_path("scan-from-ap-recovery")
SCAN_FROM_AP_CACHE = ACTION_LOG_DIR / "scan-from-ap-recovery-cache.json"
SCAN_FROM_AP_RESTART_ATTEMPTS = 3
SCAN_FROM_AP_RESTART_DELAY_SECONDS = 3
NM_AP_LAB_PROFILE = "wifi-kit-recovery-ap"
AP_MODE_BACKEND = os.environ.get("WIFI_KIT_AP_BACKEND", "nm-hotspot")
DEFAULT_NETWORK_CONNECTION = "netplan-wlan0-GL-MT6000-d53"
AP_MODE_MAX_SECONDS = 300
PRIVILEGED_ACTIONS_ENV = "WIFI_KIT_ENABLE_PRIVILEGED_ACTIONS"
AP_RECOVERY_CONFIRM = "WIFI-KIT AP RECOVERY MANUAL TEST"
CONNECT_TRANSACTION_CONFIRM = "WIFI-KIT CONNECT SAFE TRANSACTION"
SYSTEM_REBOOT_CONFIRM = "REBOOT WIFI-KIT NODE"
SYSTEM_SHUTDOWN_CONFIRM = "SHUTDOWN WIFI-KIT NODE"
SAVED_NM_SECRET_SENTINEL = "__WIFI_KIT_USE_SAVED_NM_SECRET__"
SAVED_NM_SECRET_PLACEHOLDER = "********"
RUNTIME_CONFIG_KEYS = {
    "original_ssid",
    "original_connection",
    "return_ssid",
    "return_connection",
    "last_good_ssid",
    "last_good_connection",
    "default_ssid",
    "default_connection",
    "ap_ssid",
    "ap_password",
    "return_check_enabled",
    "return_check_interval_minutes",
    "return_check_target",
    "return_check_mode",
    "runtime_recovery_enabled",
    "runtime_recovery_debug_passive",
    "runtime_recovery_grace_seconds",
    "runtime_recovery_instability_window_minutes",
    "runtime_recovery_instability_threshold",
}

CAPTIVE_PATHS = {
    "/generate_204",
    "/gen_204",
    "/redirect",
    "/hotspot-detect.html",
    "/library/test/success.html",
    "/connecttest.txt",
    "/ncsi.txt",
}

ACTION_PATHS = {
    "/reconnect-previous": "reconnect-previous",
    "/start-recovery": "start-recovery",
    "/start-ap-mode": "start-ap-mode",
    "/return-default-network": "return-default-network",
    "/ap-return-check-once": "ap-return-check-once",
    "/api/ap-return-check-once": "ap-return-check-once",
    "/system-reboot": "reboot-system",
    "/system-shutdown": "shutdown-system",
    "/exit-recovery": "exit-recovery",
    "/reboot-recovery": "reboot-recovery",
    "/set-recovery-password": "set-recovery-password",
}


def public_recovery_status(recovery: dict | None) -> dict:
    if not recovery:
        return {}
    allowed_keys = {
        "active",
        "ssid",
        "ip",
        "ui_port",
        "dhcp",
        "dns",
        "ui",
        "captive_portal",
        "actions",
        "normal_ui_port",
        "recovery_ui_port",
        "ap_password_policy",
        "ap_password_configurable",
        "ap_password_set",
        "original_ssid",
        "original_connection",
        "return_ssid",
        "return_connection",
        "runtime_recovery_enabled",
        "runtime_recovery_debug_passive",
        "runtime_recovery_grace_seconds",
        "runtime_recovery_instability_window_minutes",
        "runtime_recovery_instability_threshold",
        "runtime_watchdog",
        "runtime_config_path",
        "ui_access_password",
        "action_endpoints",
    }
    return {key: value for key, value in recovery.items() if key in allowed_keys}


def normalize_request_path(path: str) -> str:
    if path == "/":
        return path
    return path.rstrip("/") or "/"


def log_route(event: str, raw_path: str, path: str) -> None:
    print(
        f"wifi-kit-route event={event} raw_path={json.dumps(raw_path)} path={json.dumps(path)}",
        flush=True,
    )


def run_json_command(args: list[str]) -> dict:
    if not WIFI_KIT_SH.exists():
        return {
            "status": "unavailable",
            "command": " ".join(args),
            "error": "legacy-wifi-kit-sh-not-installed",
        }
    shell_bin = find_tool("sh")
    if not shell_bin:
        return {
            "status": "error",
            "command": " ".join(args),
            "error": "sh-not-found",
        }
    try:
        result = subprocess.run(
            [shell_bin, str(WIFI_KIT_SH), *args],
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError as exc:
        return {
            "status": "error",
            "command": " ".join(args),
            "error": f"start-failed: {exc}",
        }

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


def safe_label(value: str, *, fallback: str = "") -> str:
    cleaned = " ".join(str(value or "").strip().split())
    return cleaned or fallback


def has_line_break(value: str) -> bool:
    return "\n" in value or "\r" in value


def ssid_for_connection(profile: str) -> str:
    profile = safe_label(profile)
    if not profile:
        return ""
    details = run_text_command(
        ["nmcli", "-t", "--escape", "yes", "-f", "802-11-wireless.ssid", "connection", "show", profile],
        timeout=2.0,
    )
    for detail in details.splitlines():
        key, sep, value = detail.partition(":")
        if sep and key == "802-11-wireless.ssid":
            return nmcli_unescape(value)
    return ""


def human_ssid_for_connection(profile: str, candidate_ssid: str) -> str:
    candidate_ssid = safe_label(candidate_ssid)
    if candidate_ssid and candidate_ssid != profile:
        return candidate_ssid
    return ssid_for_connection(profile) or candidate_ssid or profile


def default_runtime_config() -> dict[str, str]:
    hostname = socket.gethostname() or "node"
    return {
        "original_ssid": DEFAULT_NETWORK_CONNECTION,
        "original_connection": DEFAULT_NETWORK_CONNECTION,
        "return_ssid": DEFAULT_NETWORK_CONNECTION,
        "return_connection": DEFAULT_NETWORK_CONNECTION,
        "last_good_ssid": "",
        "last_good_connection": "",
        "ap_ssid": f"Wifi-Kit-{hostname}",
        "ap_password": os.environ.get("WIFI_KIT_AP_PSK", RECOVERY_AP_TEST_PASSWORD),
        "return_check_enabled": "false",
        "return_check_interval_minutes": "1",
        "return_check_target": "last_good_ssid",
        "return_check_mode": "periodic-from-ap",
        "runtime_recovery_enabled": "true",
        "runtime_recovery_debug_passive": "false",
        "runtime_recovery_grace_seconds": "30",
        "runtime_recovery_instability_window_minutes": "10",
        "runtime_recovery_instability_threshold": "3",
    }


def read_runtime_config() -> dict[str, str]:
    config = default_runtime_config()
    try:
        for line in RUNTIME_CONFIG_PATH.read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            key, sep, value = stripped.partition("=")
            if sep and key in RUNTIME_CONFIG_KEYS:
                config[key] = value
    except OSError:
        pass
    raw_legacy_ssid = safe_label(config.get("default_ssid", ""), fallback=DEFAULT_NETWORK_CONNECTION)
    legacy_connection = safe_label(config.get("default_connection", ""), fallback=raw_legacy_ssid)
    legacy_ssid = human_ssid_for_connection(legacy_connection, config.get("default_ssid", "") or legacy_connection)
    config["original_connection"] = safe_label(config.get("original_connection", ""), fallback=legacy_connection)
    config["original_ssid"] = human_ssid_for_connection(
        config["original_connection"],
        config.get("original_ssid", "") or legacy_ssid,
    )
    config["return_connection"] = safe_label(config.get("return_connection", ""), fallback=legacy_connection)
    config["return_ssid"] = human_ssid_for_connection(
        config["return_connection"],
        config.get("return_ssid", "") or legacy_ssid,
    )
    config["ap_ssid"] = safe_label(config.get("ap_ssid", ""), fallback=default_runtime_config()["ap_ssid"])
    config["ap_password"] = str(config.get("ap_password") or RECOVERY_AP_TEST_PASSWORD)
    return config


def runtime_config_value(key: str) -> str:
    try:
        for line in RUNTIME_CONFIG_PATH.read_text(encoding="utf-8").splitlines():
            name, sep, value = line.partition("=")
            if sep and name == key:
                return value
    except OSError:
        return ""
    return ""


def redact_runtime_config(config: dict[str, str]) -> dict[str, object]:
    return {
        "original_ssid": config["original_ssid"],
        "original_connection": config["original_connection"],
        "return_ssid": config["return_ssid"],
        "return_connection": config["return_connection"],
        "last_good_ssid": config.get("last_good_ssid", ""),
        "last_good_connection": config.get("last_good_connection", ""),
        "ap_ssid": config["ap_ssid"],
        "ap_password_set": bool(config["ap_password"]),
        "return_check_enabled": config.get("return_check_enabled", "false"),
        "return_check_interval_minutes": config.get("return_check_interval_minutes", "1"),
        "return_check_target": config.get("return_check_target", "last_good_ssid"),
        "return_check_mode": config.get("return_check_mode", "periodic-from-ap"),
        "runtime_recovery_enabled": config.get("runtime_recovery_enabled", "true"),
        "runtime_recovery_debug_passive": config.get("runtime_recovery_debug_passive", "false"),
        "runtime_recovery_grace_seconds": config.get("runtime_recovery_grace_seconds", "30"),
        "runtime_recovery_instability_window_minutes": config.get("runtime_recovery_instability_window_minutes", "10"),
        "runtime_recovery_instability_threshold": config.get("runtime_recovery_instability_threshold", "3"),
        "path": str(RUNTIME_CONFIG_PATH),
        "password_policy": "min-8-chars",
        "secret_policy": "stores AP recovery password only; never stores client Wi-Fi passwords",
    }


def redact_public_payload(value):
    if isinstance(value, dict):
        redacted = {}
        for key, item in value.items():
            if key == "confirm_required":
                redacted["requires_user_confirmation"] = True
                redacted["confirmation_kind"] = "simple"
                continue
            if key == "ap_password":
                redacted["ap_password_set"] = bool(item)
                continue
            if key == "ap_password_current":
                redacted["ap_password_set"] = bool(item)
                continue
            if key == "recovery_ap_password_current":
                redacted["recovery_ap_password_set"] = bool(item)
                continue
            redacted[key] = redact_public_payload(item)
        return redacted
    if isinstance(value, list):
        return [redact_public_payload(item) for item in value]
    if isinstance(value, str) and CONNECT_TRANSACTION_CONFIRM in value:
        return value.replace(CONNECT_TRANSACTION_CONFIRM, "internal-confirmation")
    return value


def normalize_action_status(payload: dict, http_status: int) -> str:
    status = str(payload.get("status", "")).strip().lower()
    if status == "started":
        return "started"
    if status in {"saved", "success", "done"}:
        return "done"
    if status in {"planned", "refused"}:
        return "refused"
    if status in {"failure", "failed"}:
        return "refused" if http_status < 500 else "failed"
    return "failed" if http_status >= 400 else "done"


def action_message(action: str, status: str, payload: dict) -> str:
    for key in ("message", "warning", "note"):
        value = str(payload.get(key, "")).strip()
        if value:
            return value
    error = str(payload.get("error", "")).strip()
    if error:
        return error
    defaults = {
        "started": f"{action} started.",
        "done": f"{action} completed.",
        "refused": f"{action} refused by safety gates.",
        "failed": f"{action} failed.",
    }
    return defaults.get(status, f"{action} returned {status}.")


def action_response(action: str, payload: dict, http_status: int) -> dict:
    normalized_status = normalize_action_status(payload, http_status)
    response = dict(payload)
    if "status" in payload and str(payload.get("status")) != normalized_status:
        response["raw_status"] = payload.get("status")
    response.update(
        {
            "ok": normalized_status in {"started", "done"},
            "action": str(payload.get("action") or action),
            "status": normalized_status,
            "message": action_message(action, normalized_status, payload),
            "log": str(payload.get("log", "")),
            "error": payload.get("error") or None,
        }
    )
    return response


def public_runtime_config() -> dict[str, object]:
    return redact_runtime_config(read_runtime_config())


def write_runtime_config(config: dict[str, str]) -> None:
    RUNTIME_CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(RUNTIME_CONFIG_PATH.parent, 0o700)
    except OSError:
        pass
    tmp_path = RUNTIME_CONFIG_PATH.with_name(f".{RUNTIME_CONFIG_PATH.name}.{os.getpid()}.tmp")
    lines = [
        "# Wifi-Kit prototype runtime config",
        "# Stores AP recovery password only; never stores client Wi-Fi passwords.",
        "# original_* is initialized once and must not be changed automatically.",
        f"original_ssid={config['original_ssid']}",
        f"original_connection={config['original_connection']}",
        f"return_ssid={config['return_ssid']}",
        f"return_connection={config['return_connection']}",
        f"last_good_ssid={config.get('last_good_ssid', '')}",
        f"last_good_connection={config.get('last_good_connection', '')}",
        f"ap_ssid={config['ap_ssid']}",
        f"ap_password={config['ap_password']}",
        f"return_check_enabled={config.get('return_check_enabled', 'false')}",
        f"return_check_interval_minutes={config.get('return_check_interval_minutes', '1')}",
        f"return_check_target={config.get('return_check_target', 'last_good_ssid')}",
        f"return_check_mode={config.get('return_check_mode', 'periodic-from-ap')}",
        f"runtime_recovery_enabled={config.get('runtime_recovery_enabled', 'true')}",
        f"runtime_recovery_debug_passive={config.get('runtime_recovery_debug_passive', 'false')}",
        f"runtime_recovery_grace_seconds={config.get('runtime_recovery_grace_seconds', '30')}",
        f"runtime_recovery_instability_window_minutes={config.get('runtime_recovery_instability_window_minutes', '10')}",
        f"runtime_recovery_instability_threshold={config.get('runtime_recovery_instability_threshold', '3')}",
    ]
    fd = os.open(tmp_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write("\n".join(lines) + "\n")
        os.replace(tmp_path, RUNTIME_CONFIG_PATH)
        os.chmod(RUNTIME_CONFIG_PATH, 0o600)
    finally:
        try:
            tmp_path.unlink()
        except OSError:
            pass


def update_runtime_config(payload: dict) -> tuple[dict, int]:
    if payload.get("_error"):
        return {"status": "failure", "error": payload["_error"]}, 400

    config = read_runtime_config()
    original_missing = not config.get("original_ssid") or not config.get("original_connection")
    for key in ("original_ssid", "original_connection"):
        if key not in payload:
            continue
        raw_original = str(payload.get(key, ""))
        if has_line_break(raw_original):
            return {"status": "failure", "error": f"{key.replace('_', '-')}-invalid"}, 400
        original_value = safe_label(raw_original)
        if not original_value:
            return {"status": "failure", "error": f"{key.replace('_', '-')}-required"}, 400
        if not original_missing and original_value != config[key]:
            return {"status": "failure", "error": "original-network-immutable"}, 409
        config[key] = original_value
    if "return_ssid" in payload or "default_ssid" in payload:
        raw_return_ssid = str(payload.get("return_ssid", payload.get("default_ssid", "")))
        if has_line_break(raw_return_ssid):
            return {"status": "failure", "error": "return-ssid-invalid"}, 400
        return_ssid = safe_label(raw_return_ssid)
        if not return_ssid:
            return {"status": "failure", "error": "return-ssid-required"}, 400
        config["return_ssid"] = return_ssid
    if "return_connection" in payload or "default_connection" in payload:
        raw_return_connection = str(payload.get("return_connection", payload.get("default_connection", "")))
        if has_line_break(raw_return_connection):
            return {"status": "failure", "error": "return-connection-invalid"}, 400
        return_connection = safe_label(raw_return_connection)
        if not return_connection:
            return {"status": "failure", "error": "return-connection-required"}, 400
        config["return_connection"] = return_connection
    if "ap_ssid" in payload:
        raw_ap_ssid = str(payload.get("ap_ssid", ""))
        if has_line_break(raw_ap_ssid):
            return {"status": "failure", "error": "ap-ssid-invalid"}, 400
        ap_ssid = safe_label(raw_ap_ssid)
        if not ap_ssid:
            return {"status": "failure", "error": "ap-ssid-required"}, 400
        if len(ap_ssid.encode("utf-8")) > 32:
            return {"status": "failure", "error": "ap-ssid-too-long"}, 400
        config["ap_ssid"] = ap_ssid
    if "ap_password" in payload:
        ap_password = str(payload.get("ap_password", ""))
        if has_line_break(ap_password):
            return {"status": "failure", "error": "ap-password-invalid"}, 400
        if len(ap_password) < 8:
            return {"status": "failure", "error": "ap-password-too-short"}, 400
        if looks_like_test_ap_password(ap_password) and not bool_payload(payload.get("allow_test_ap_password")):
            return {
                "status": "failure",
                "error": "ap-password-looks-like-test-value",
                "message": "Mot de passe AP refuse: valeur de test/factice sans validation explicite.",
            }, 400
        config["ap_password"] = ap_password
    if "return_check_enabled" in payload:
        enabled = str(payload.get("return_check_enabled", "")).strip().lower()
        if enabled in {"true", "1", "yes", "on"}:
            config["return_check_enabled"] = "true"
        elif enabled in {"false", "0", "no", "off", ""}:
            config["return_check_enabled"] = "false"
        else:
            return {"status": "failure", "error": "return-check-enabled-invalid"}, 400
    if "return_check_interval_minutes" in payload:
        interval = str(payload.get("return_check_interval_minutes", "")).strip()
        if not interval.isdigit() or int(interval) < 1:
            return {"status": "failure", "error": "return-check-interval-invalid"}, 400
        config["return_check_interval_minutes"] = str(int(interval))
    if "return_check_target" in payload:
        target = str(payload.get("return_check_target", "")).strip()
        if target != "last_good_ssid":
            return {"status": "failure", "error": "return-check-target-unsupported"}, 400
        config["return_check_target"] = target
    if "return_check_mode" in payload:
        mode = str(payload.get("return_check_mode", "")).strip()
        if mode != "periodic-from-ap":
            return {"status": "failure", "error": "return-check-mode-unsupported"}, 400
        config["return_check_mode"] = mode
    if "runtime_recovery_enabled" in payload:
        enabled = str(payload.get("runtime_recovery_enabled", "")).strip().lower()
        if enabled in {"true", "1", "yes", "on"}:
            config["runtime_recovery_enabled"] = "true"
        elif enabled in {"false", "0", "no", "off", ""}:
            config["runtime_recovery_enabled"] = "false"
        else:
            return {"status": "failure", "error": "runtime-recovery-enabled-invalid"}, 400
    if "runtime_recovery_debug_passive" in payload:
        debug_passive = str(payload.get("runtime_recovery_debug_passive", "")).strip().lower()
        if debug_passive in {"true", "1", "yes", "on"}:
            config["runtime_recovery_debug_passive"] = "true"
        elif debug_passive in {"false", "0", "no", "off", ""}:
            config["runtime_recovery_debug_passive"] = "false"
        else:
            return {"status": "failure", "error": "runtime-recovery-debug-passive-invalid"}, 400
    if "runtime_recovery_grace_seconds" in payload:
        grace = str(payload.get("runtime_recovery_grace_seconds", "")).strip()
        if not grace.isdigit() or int(grace) < 1:
            return {"status": "failure", "error": "runtime-recovery-grace-invalid"}, 400
        config["runtime_recovery_grace_seconds"] = str(int(grace))
    if "runtime_recovery_instability_window_minutes" in payload:
        window = str(payload.get("runtime_recovery_instability_window_minutes", "")).strip()
        if not window.isdigit() or int(window) < 1:
            return {"status": "failure", "error": "runtime-recovery-window-invalid"}, 400
        config["runtime_recovery_instability_window_minutes"] = str(int(window))
    if "runtime_recovery_instability_threshold" in payload:
        threshold = str(payload.get("runtime_recovery_instability_threshold", "")).strip()
        if not threshold.isdigit() or int(threshold) < 1:
            return {"status": "failure", "error": "runtime-recovery-threshold-invalid"}, 400
        config["runtime_recovery_instability_threshold"] = str(int(threshold))

    write_runtime_config(config)
    return {
        "status": "saved",
        "config": public_runtime_config(),
        "secret_policy": "AP password stored in runtime config with 0600 permissions; client Wi-Fi passwords are not stored",
    }, 200


def find_tool(name: str) -> str:
    found = shutil.which(name)
    if found:
        return found
    for prefix in ("/usr/sbin", "/sbin", "/usr/bin", "/bin"):
        candidate = Path(prefix) / name
        if candidate.exists() and os.access(candidate, os.X_OK):
            return str(candidate)
    return ""


def command_is_success(args: list[str], timeout: float = 2.0) -> bool:
    try:
        result = subprocess.run(
            args,
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    return result.returncode == 0


def systemd_is_enabled(service: str) -> bool:
    systemctl = find_tool("systemctl")
    return bool(systemctl) and command_is_success([systemctl, "is-enabled", service], timeout=2.0)


def systemd_is_active(service: str) -> bool:
    systemctl = find_tool("systemctl")
    return bool(systemctl) and command_is_success([systemctl, "is-active", service], timeout=2.0)


def read_ap_only_state_value(key: str) -> str:
    try:
        for line in AP_ONLY_NM_STATE.read_text(encoding="utf-8").splitlines():
            name, sep, value = line.partition("=")
            if sep and name == key:
                return value
    except OSError:
        return ""
    return ""


def read_key_value_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    try:
        for line in path.read_text(encoding="utf-8").splitlines():
            key, sep, value = line.partition("=")
            if sep and key:
                values[key] = value
    except OSError:
        pass
    return values


def runtime_watchdog_status() -> dict[str, object]:
    state = read_key_value_file(RUNTIME_WATCHDOG_STATE)
    instability = read_key_value_file(RUNTIME_WATCHDOG_INSTABILITY)
    return {
        "state_file": str(RUNTIME_WATCHDOG_STATE),
        "state_exists": RUNTIME_WATCHDOG_STATE.exists(),
        "status": state.get("status", "unknown"),
        "reason": state.get("reason", ""),
        "runtime_match": state.get("runtime_match", ""),
        "runtime_reason": state.get("runtime_reason", state.get("reason", "")),
        "runtime_recovery_debug_passive": state.get("runtime_recovery_debug_passive", ""),
        "current_connection": state.get("current_connection", ""),
        "current_ssid": state.get("current_ssid", ""),
        "last_good_connection": state.get("last_good_connection", ""),
        "last_good_ssid": state.get("last_good_ssid", ""),
        "ssid": state.get("ssid", ""),
        "unstable_ssid": instability.get("unstable_ssid", state.get("unstable_ssid", "")),
        "unstable_count": instability.get("unstable_count", state.get("unstable_count", "")),
        "unstable_window_minutes": instability.get("unstable_window_minutes", state.get("unstable_window_minutes", "")),
        "log_file": state.get("log_file", ""),
        "timestamp": state.get("timestamp", ""),
    }


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
        ensure_action_log_parent(RECONNECT_PREVIOUS_LOG)
        with RECONNECT_PREVIOUS_LOG.open("a", encoding="utf-8") as handle:
            handle.write(" ".join(fields) + "\n")
    except OSError:
        pass


def ensure_action_log_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.parent == ACTION_LOG_DIR:
        try:
            path.parent.chmod(0o1777)
        except OSError:
            pass


def open_action_log(path: Path):
    ensure_action_log_parent(path)
    handle = path.open("a", encoding="utf-8")
    if is_action_log_path(path):
        try:
            path.chmod(0o666)
        except OSError:
            pass
    return handle


def append_action_log(path: Path, *, action: str, status: str, **fields: object) -> None:
    timestamp = datetime.now(timezone.utc).isoformat(timespec="seconds")
    parts = [
        f"timestamp={json.dumps(timestamp)}",
        f"action={action}",
        f"status={json.dumps(status)}",
    ]
    for key, value in fields.items():
        parts.append(f"{key}={json.dumps(str(value))}")
    try:
        with open_action_log(path) as handle:
            handle.write(" ".join(parts) + "\n")
    except OSError:
        pass


def parse_log_value(raw: str) -> str:
    raw = raw.strip()
    if not raw:
        return ""
    if raw[0] == '"':
        try:
            return str(json.loads(raw))
        except json.JSONDecodeError:
            return raw.strip('"')
    return raw.strip("'\"")


def parse_action_log_line(line: str) -> dict[str, str]:
    parsed: dict[str, str] = {}
    for match in re.finditer(r"([A-Za-z0-9_]+)=('(?:[^']*)'|\"(?:\\.|[^\"])*\"|[^ ]+)", line):
        parsed[match.group(1)] = parse_log_value(match.group(2))
    return parsed


def wifi_connect_attempts_by_ssid() -> dict[str, dict[str, str]]:
    attempts: dict[str, dict[str, str]] = {}
    failure_statuses = {
        "failure",
        "failed",
        "refused",
        "validation-failed",
        "connect-failed",
        "nm-hotspot-connect-failed",
    }
    success_statuses = {"success", "done", "nm-hotspot-connect-success"}
    try:
        log_paths = list(ACTION_LOG_DIR.glob("*connect*.log"))
    except OSError:
        return attempts

    def log_mtime(path: Path) -> float:
        try:
            return path.stat().st_mtime
        except OSError:
            return 0.0

    for path in sorted(log_paths, key=log_mtime):
        try:
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        for line in lines:
            fields = parse_action_log_line(line)
            action = fields.get("action", "")
            if action not in {"wifi-connect-transaction", "connect-transaction", "nm-hotspot-connect"}:
                continue
            ssid = fields.get("ssid") or fields.get("requested_ssid") or fields.get("target_ssid")
            if not ssid or ssid == "unknown":
                continue
            status = fields.get("status", "")
            if status not in failure_statuses and status not in success_statuses:
                continue
            attempts[ssid] = {
                "last_connect_status": status,
                "last_connect_failed": "true" if status in failure_statuses else "false",
                "last_connect_error": fields.get("error") or fields.get("reason") or fields.get("detail") or "",
                "last_connect_timestamp": fields.get("timestamp", ""),
                "last_connect_log": str(path),
            }
    return attempts


def write_json_file(path: Path, payload: dict) -> None:
    ensure_action_log_parent(path)
    tmp_path = path.with_suffix(path.suffix + ".tmp")
    tmp_path.write_text(json.dumps(redact_public_payload(payload), indent=2) + "\n", encoding="utf-8")
    tmp_path.replace(path)
    if is_action_log_path(path):
        try:
            path.chmod(0o666)
        except OSError:
            pass


def read_scan_from_ap_cache() -> dict:
    try:
        payload = json.loads(SCAN_FROM_AP_CACHE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {
            "status": "unavailable",
            "backend": "ap-recovery-cache",
            "reason": "scan-cache-missing",
            "refresh_attempted": False,
            "refresh_status": "not-requested",
            "networks": [],
        }
    if not isinstance(payload, dict):
        return {
            "status": "unavailable",
            "backend": "ap-recovery-cache",
            "reason": "scan-cache-invalid",
            "refresh_attempted": False,
            "refresh_status": "not-requested",
            "networks": [],
        }
    payload.setdefault("backend", "ap-recovery-cache")
    payload.setdefault("networks", [])
    payload["cache_path"] = str(SCAN_FROM_AP_CACHE)
    return payload


def bool_payload(value: object) -> bool:
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in {"1", "true", "yes", "on"}


def looks_like_test_ap_password(value: str) -> bool:
    normalized = value.strip().lower()
    if normalized == RECOVERY_AP_TEST_PASSWORD:
        return False
    markers = ("test", "demo", "fixture", "fake", "example", "password")
    return any(marker in normalized for marker in markers)


def privileged_actions_enabled() -> bool:
    return os.environ.get(PRIVILEGED_ACTIONS_ENV) == "1"


def is_root_process() -> bool:
    return hasattr(os, "geteuid") and os.geteuid() == 0


def action_wrapper_path() -> Path:
    return INSTALLED_ACTION_WRAPPER_SH if INSTALLED_ACTION_WRAPPER_SH.exists() else ACTION_WRAPPER_SH


def backend_status(recovery: dict | None = None) -> dict[str, object]:
    config = read_runtime_config()
    diagnose = safe_diagnose()
    recovery = recovery or {}
    wrapper_path = action_wrapper_path()
    app_dir_exists = INSTALLED_APP_DIR.exists()
    wrapper_exists = wrapper_path.exists()
    sudoers_exists = SUDOERS_PATH.exists()
    privileged_ready = privileged_actions_enabled() and wrapper_exists and (is_root_process() or sudoers_exists)
    notes: list[str] = []

    if not privileged_actions_enabled():
        notes.append(f"{PRIVILEGED_ACTIONS_ENV} is not enabled; real network actions return planned or refused responses.")
    if not wrapper_exists:
        notes.append("Wifi-Kit action wrapper is missing.")
    if not sudoers_exists and not is_root_process():
        notes.append("Wifi-Kit sudoers drop-in is missing or not readable from this process.")

    return {
        "ok": True,
        "mode": "runtime" if app_dir_exists or privileged_actions_enabled() else "local",
        "actions": {
            "scan": bool(find_tool("nmcli") or find_tool("iw") or find_tool("wpa_cli")),
            "connect_wifi": privileged_ready,
            "start_ap_mode": privileged_ready,
            "return_default_network": privileged_ready,
            "ap_return_check_once": privileged_ready,
            "reboot_system": privileged_ready and os.environ.get("WIFI_KIT_ENABLE_SYSTEM_POWER_ACTIONS") == "1",
            "shutdown_system": privileged_ready and os.environ.get("WIFI_KIT_ENABLE_SYSTEM_POWER_ACTIONS") == "1",
        },
        "runtime": {
            "config_exists": RUNTIME_CONFIG_PATH.exists(),
            "config_readable": os.access(RUNTIME_CONFIG_PATH, os.R_OK),
            "ap_ssid_configured": bool(config.get("ap_ssid")),
            "last_good_configured": bool(runtime_config_value("last_good_connection") or runtime_config_value("last_good_ssid")),
            "runtime_recovery_enabled": config.get("runtime_recovery_enabled", "true"),
            "runtime_recovery_debug_passive": config.get("runtime_recovery_debug_passive", "false"),
            "runtime_recovery_grace_seconds": config.get("runtime_recovery_grace_seconds", "30"),
            "runtime_recovery_instability_window_minutes": config.get("runtime_recovery_instability_window_minutes", "10"),
            "runtime_recovery_instability_threshold": config.get("runtime_recovery_instability_threshold", "3"),
            "runtime_watchdog": runtime_watchdog_status(),
        },
        "install": {
            "app_dir_exists": app_dir_exists,
            "wrapper_exists": wrapper_exists,
            "sudoers_exists": sudoers_exists,
            "ui_service_enabled": systemd_is_enabled(UI_SERVICE_NAME),
            "ui_service_active": systemd_is_active(UI_SERVICE_NAME),
            "boot_guard_enabled": systemd_is_enabled(BOOT_GUARD_SERVICE_NAME),
            "boot_guard_active": systemd_is_active(BOOT_GUARD_SERVICE_NAME),
            "runtime_watchdog_enabled": systemd_is_enabled(RUNTIME_WATCHDOG_SERVICE_NAME),
            "runtime_watchdog_active": systemd_is_active(RUNTIME_WATCHDOG_SERVICE_NAME),
        },
        "network": {
            "current_ssid": system_info(diagnose, recovery).get("wifi", "unknown"),
            "primary_ssid": config.get("return_ssid") or config.get("original_ssid") or "",
            "ap_ssid": config.get("ap_ssid") or "",
            "iface": diagnose.get("interface") or "wlan0",
        },
        "notes": notes,
    }


def privileged_action_command(action: str) -> tuple[list[str], str]:
    wrapper_path = action_wrapper_path()
    if not wrapper_path.exists():
        return [], "wrapper-missing"
    wrapper_command = [str(wrapper_path), action]
    if is_root_process():
        return wrapper_command, ""
    sudo_bin = find_tool("sudo")
    if not sudo_bin:
        return [], "sudo-missing"
    probe = subprocess.run(
        [sudo_bin, "-n", "-l", *wrapper_command],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if probe.returncode != 0:
        return [], "wifi-kit-network-rights-not-installed"
    return [sudo_bin, "-n", *wrapper_command], ""


def privileged_connect_transaction_command() -> tuple[list[str], str]:
    wrapper_path = action_wrapper_path()
    if not wrapper_path.exists():
        return [], "wrapper-missing"
    command = [str(wrapper_path), CONNECT_WRAPPER_ACTION]
    if is_root_process():
        return command, ""
    sudo_bin = find_tool("sudo")
    if not sudo_bin:
        return [], "sudo-missing"
    probe = subprocess.run(
        [sudo_bin, "-n", "-l", *command],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if probe.returncode != 0:
        return [], "wifi-kit-network-rights-not-installed"
    return [sudo_bin, "-n", *command], ""


def privileged_error_response(action: str, error: str) -> dict[str, object]:
    message = (
        "Wifi-Kit n'est pas encore installe avec les droits reseau. "
        "Installe le wrapper root-owned et la regle sudoers whitelist avant les actions reelles."
    )
    return {
        "status": "failure",
        "action": action,
        "error": error,
        "message": message if error == "wifi-kit-network-rights-not-installed" else error,
        "operator_action": (
            "installer modules/wifi-kit/prototype/sudoers/wifi-kit.sudoers avec visudo apres validation"
            if error == "wifi-kit-network-rights-not-installed"
            else "verifier les dependances Wifi-Kit"
        ),
    }


def start_ap_mode(payload: dict) -> tuple[dict, int]:
    dry_run = bool_payload(payload.get("dry_run"))
    dangerous_real_apply = bool_payload(payload.get("dangerous_real_apply"))
    ap_confirmed = (
        bool_payload(payload.get("ap_confirmed"))
        or bool_payload(payload.get("user_confirmed"))
        or bool_payload(payload.get("confirmed"))
        or bool_payload(payload.get("confirm"))
    )
    action = "start-ap-mode"
    config = read_runtime_config()
    backend = str(payload.get("backend") or AP_MODE_BACKEND or "nm-hotspot").strip()
    nm_helper_path = INSTALLED_NM_AP_LAB_SH if INSTALLED_NM_AP_LAB_SH.exists() else SCRIPT_DIR.parent / "wifi-kit-nm-ap-lab.sh"
    if dry_run or not privileged_actions_enabled() or not dangerous_real_apply or not ap_confirmed:
        append_action_log(
            START_AP_MODE_LOG,
            action=action,
            status="planned",
            backend=backend,
            nm_helper_path=str(nm_helper_path),
            max_seconds=AP_MODE_MAX_SECONDS,
            privileged_actions_enabled=privileged_actions_enabled(),
            dangerous_real_apply=dangerous_real_apply,
            confirm_ok=ap_confirmed,
            ap_ssid=config["ap_ssid"],
        )
        return {
            "status": "planned",
            "action": action,
            "ap_started": False,
            "backend": backend,
            "nm_helper_path": str(nm_helper_path),
            "dry_run": dry_run,
            "privileged_actions_enabled": privileged_actions_enabled(),
            "dangerous_real_apply": dangerous_real_apply,
            "requires_user_confirmation": True,
            "confirmation_kind": "simple",
            "confirm_ok": ap_confirmed,
            "ssid": config["ap_ssid"],
            "timeout_seconds": AP_MODE_MAX_SECONDS,
            "log": str(START_AP_MODE_LOG),
            "config": public_runtime_config(),
            "warning": "Real start can interrupt normal Wi-Fi access while AP mode starts.",
        }, 200

    command, error = privileged_action_command(action)
    if error:
        append_action_log(START_AP_MODE_LOG, action=action, status="failure", error=error)
        payload = privileged_error_response(action, error)
        payload.update({"ap_started": False, "log": str(START_AP_MODE_LOG)})
        return payload, 403 if error == "wifi-kit-network-rights-not-installed" else 500

    if backend == "nm-hotspot":
        env = os.environ.copy()
        env["WIFI_KIT_AP_BACKEND"] = "nm-hotspot"
        env["WIFI_KIT_NM_AP_LAB_APPLY"] = "1"
        env["WIFI_KIT_RUNTIME_CONFIG"] = str(RUNTIME_CONFIG_PATH)
        env["WIFI_KIT_AP_PSK"] = config["ap_password"]
        env["WIFI_KIT_AP_SSID"] = config["ap_ssid"]
        append_action_log(
            START_AP_MODE_LOG,
            action=action,
            status="starting",
            backend=backend,
            nm_helper_path=str(nm_helper_path),
            ap_ssid=config["ap_ssid"],
        )
        try:
            with open_action_log(START_AP_MODE_LOG) as handle:
                result = subprocess.run(
                    command,
                    cwd=str(SCRIPT_DIR.parent),
                    check=False,
                    stdout=handle,
                    stderr=subprocess.STDOUT,
                    text=True,
                    timeout=70,
                    env=env,
                )
        except (OSError, subprocess.TimeoutExpired) as exc:
            append_action_log(
                START_AP_MODE_LOG,
                action=action,
                status="failure",
                backend=backend,
                nm_helper_path=str(nm_helper_path),
                error=f"start-failed: {exc}",
            )
            return {
                "status": "failure",
                "action": action,
                "backend": backend,
                "nm_helper_path": str(nm_helper_path),
                "error": f"start-failed: {exc}",
                "ap_started": False,
                "log": str(START_AP_MODE_LOG),
            }, 500

        status = nm_hotspot_recovery_status()
        success = result.returncode == 0 and bool(status["hotspot_active"]) and bool(status["ui_recovery_active"]) and bool(status["port_80_listening"])
        append_action_log(
            START_AP_MODE_LOG,
            action=action,
            status="done" if success else "failure",
            backend=backend,
            nm_helper_path=str(nm_helper_path),
            returncode=result.returncode,
            hotspot_active=status["hotspot_active"],
            ui_recovery_active=status["ui_recovery_active"],
            port_80_listening=status["port_80_listening"],
        )
        if success:
            return {
                "status": "done",
                "action": action,
                "backend": backend,
                "nm_helper_path": str(nm_helper_path),
                "ap_started": True,
                "ssid": config["ap_ssid"],
                "hotspot_active": True,
                "ui_recovery_active": True,
                "port_80_listening": True,
                "recovery_url": "http://192.168.50.1:80",
                "expected_behavior": "nm-hotspot-recovery-ui-active",
                "secret_policy": "AP password is supplied from runtime config and not logged by this endpoint",
                "log": str(START_AP_MODE_LOG),
            }, 200
        return {
            "status": "failure",
            "action": action,
            "backend": backend,
            "nm_helper_path": str(nm_helper_path),
            "error": "ap-recovery-not-active-after-start",
            "ap_started": False,
            "hotspot_active": status["hotspot_active"],
            "ui_recovery_active": status["ui_recovery_active"],
            "port_80_listening": status["port_80_listening"],
            "returncode": result.returncode,
            "message": "Mode AP non confirme par l'etat runtime reel.",
            "log": str(START_AP_MODE_LOG),
        }, 502

    try:
        env = os.environ.copy()
        env["WIFI_KIT_AP_PSK"] = config["ap_password"]
        env["WIFI_KIT_AP_SSID"] = config["ap_ssid"]
        subprocess.Popen(
            command,
            cwd=str(SCRIPT_DIR.parent),
            start_new_session=True,
            stdin=subprocess.DEVNULL,
            stdout=open_action_log(START_AP_MODE_LOG),
            stderr=subprocess.STDOUT,
            env=env,
        )
    except OSError as exc:
        append_action_log(START_AP_MODE_LOG, action=action, status="failure", error=f"start-failed: {exc}")
        return {
            "status": "failure",
            "action": action,
            "error": f"start-failed: {exc}",
            "ap_started": False,
            "log": str(START_AP_MODE_LOG),
        }, 500

    append_action_log(START_AP_MODE_LOG, action=action, status="started", backend=backend, max_seconds=AP_MODE_MAX_SECONDS, ap_ssid=config["ap_ssid"])
    return {
        "status": "started",
        "action": action,
        "backend": backend,
        "ap_started": True,
        "ssid": config["ap_ssid"],
        "timeout_seconds": AP_MODE_MAX_SECONDS,
        "expected_behavior": "normal-network-may-drop-ap-captive-ui-starts-on-port-80",
        "secret_policy": "AP password is supplied from runtime config and not logged by this endpoint",
        "log": str(START_AP_MODE_LOG),
    }, 202


def return_default_network(payload: dict) -> tuple[dict, int]:
    dry_run = bool_payload(payload.get("dry_run"))
    action = "return-default-network"
    config = read_runtime_config()
    connection = config["return_connection"] or config["return_ssid"]
    if not connection:
        return {
            "status": "failure",
            "action": action,
            "error": "return-connection-not-configured",
            "return_started": False,
        }, 400
    if dry_run or not privileged_actions_enabled():
        append_action_log(
            RETURN_DEFAULT_NETWORK_LOG,
            action=action,
            status="planned",
            connection=connection,
            privileged_actions_enabled=privileged_actions_enabled(),
        )
        return {
            "status": "planned",
            "action": action,
            "return_connection": connection,
            "default_connection": connection,
            "return_started": False,
            "dry_run": dry_run,
            "privileged_actions_enabled": privileged_actions_enabled(),
            "config": public_runtime_config(),
            "log": str(RETURN_DEFAULT_NETWORK_LOG),
            "warning": "Real return can interrupt network access for a few seconds.",
        }, 200

    command, error = privileged_action_command(action)
    if error:
        append_action_log(RETURN_DEFAULT_NETWORK_LOG, action=action, status="failure", connection=connection, error=error)
        payload = privileged_error_response(action, error)
        payload.update(
            {
                "return_started": False,
                "return_connection": connection,
                "default_connection": connection,
            }
        )
        return payload, 403 if error == "wifi-kit-network-rights-not-installed" else 500

    try:
        env = os.environ.copy()
        env["WIFI_KIT_RETURN_CONNECTION"] = connection
        subprocess.Popen(
            command,
            cwd=str(SCRIPT_DIR.parent),
            start_new_session=True,
            stdin=subprocess.DEVNULL,
            stdout=open_action_log(RETURN_DEFAULT_NETWORK_LOG),
            stderr=subprocess.STDOUT,
            env=env,
        )
    except OSError as exc:
        append_action_log(RETURN_DEFAULT_NETWORK_LOG, action=action, status="failure", connection=connection, error=f"start-failed: {exc}")
        return {"status": "failure", "action": action, "error": f"start-failed: {exc}", "return_started": False}, 500

    append_action_log(RETURN_DEFAULT_NETWORK_LOG, action=action, status="started", connection=connection)
    return {
        "status": "started",
        "action": action,
        "return_connection": connection,
        "default_connection": connection,
        "return_started": True,
        "expected_behavior": "NetworkManager reconnects the configured return connection.",
        "log": str(RETURN_DEFAULT_NETWORK_LOG),
    }, 202


def ap_return_check_once(payload: dict) -> tuple[dict, int]:
    dry_run = bool_payload(payload.get("dry_run"))
    action = "ap-return-check-once"
    config = read_runtime_config()
    if dry_run or not privileged_actions_enabled():
        append_action_log(
            AP_RETURN_CHECK_ONCE_LOG,
            action=action,
            status="planned",
            privileged_actions_enabled=privileged_actions_enabled(),
            return_check_enabled=config.get("return_check_enabled", "false"),
            target_connection=config.get("last_good_connection") or config.get("return_connection") or "",
        )
        return {
            "status": "planned",
            "action": action,
            "return_check_started": False,
            "dry_run": dry_run,
            "privileged_actions_enabled": privileged_actions_enabled(),
            "return_check_enabled": config.get("return_check_enabled", "false"),
            "target_ssid": config.get("last_good_ssid") or config.get("return_ssid") or "",
            "target_connection": config.get("last_good_connection") or config.get("return_connection") or "",
            "log": str(AP_RETURN_CHECK_ONCE_LOG),
            "warning": "Real AP return check stops AP recovery briefly, tries the known Wi-Fi, and restarts AP recovery if the return fails.",
        }, 200

    command, error = privileged_action_command(action)
    if error:
        append_action_log(AP_RETURN_CHECK_ONCE_LOG, action=action, status="failure", error=error)
        payload = privileged_error_response(action, error)
        payload.update({"return_check_started": False, "log": str(AP_RETURN_CHECK_ONCE_LOG)})
        return payload, 403 if error == "wifi-kit-network-rights-not-installed" else 500

    try:
        env = os.environ.copy()
        env["WIFI_KIT_RUNTIME_CONFIG"] = str(RUNTIME_CONFIG_PATH)
        subprocess.Popen(
            command,
            cwd=str(SCRIPT_DIR.parent),
            start_new_session=True,
            stdin=subprocess.DEVNULL,
            stdout=open_action_log(AP_RETURN_CHECK_ONCE_LOG),
            stderr=subprocess.STDOUT,
            env=env,
        )
    except OSError as exc:
        append_action_log(AP_RETURN_CHECK_ONCE_LOG, action=action, status="failure", error=f"start-failed: {exc}")
        return {
            "status": "failure",
            "action": action,
            "error": f"start-failed: {exc}",
            "return_check_started": False,
            "log": str(AP_RETURN_CHECK_ONCE_LOG),
        }, 500

    append_action_log(AP_RETURN_CHECK_ONCE_LOG, action=action, status="started")
    return {
        "status": "started",
        "action": action,
        "return_check_started": True,
        "target_ssid": config.get("last_good_ssid") or config.get("return_ssid") or "",
        "target_connection": config.get("last_good_connection") or config.get("return_connection") or "",
        "expected_behavior": "AP recovery stops briefly; known Wi-Fi is tried once; success stays normal; failure restarts AP recovery.",
        "log": str(AP_RETURN_CHECK_ONCE_LOG),
    }, 202


def system_power_action(payload: dict, action: str) -> tuple[dict, int]:
    spec = {
        "reboot-system": {
            "endpoint_action": "system-reboot",
            "requested": "reboot_requested",
            "confirm": SYSTEM_REBOOT_CONFIRM,
            "log": SYSTEM_REBOOT_LOG,
            "message": "Redemarrage systeme demande.",
        },
        "shutdown-system": {
            "endpoint_action": "system-shutdown",
            "requested": "shutdown_requested",
            "confirm": SYSTEM_SHUTDOWN_CONFIRM,
            "log": SYSTEM_SHUTDOWN_LOG,
            "message": "Extinction systeme demandee.",
        },
    }[action]
    dry_run = bool_payload(payload.get("dry_run"))
    dangerous_real_apply = bool_payload(payload.get("dangerous_real_apply"))
    user_confirmed = bool_payload(payload.get("user_confirmed")) or bool_payload(payload.get("confirmed"))
    confirm_phrase = str(payload.get("confirm") or payload.get("confirm_phrase") or "").strip()
    confirm_ok = user_confirmed and confirm_phrase == spec["confirm"]
    real_power_enabled = os.environ.get("WIFI_KIT_ENABLE_SYSTEM_POWER_ACTIONS") == "1"
    log_path = spec["log"]

    if not confirm_ok:
        append_action_log(
            log_path,
            action=action,
            status="refused",
            reason="confirmation-required",
            dangerous_real_apply=dangerous_real_apply,
            confirm_ok=confirm_ok,
        )
        return {
            "status": "refused",
            "action": action,
            spec["requested"]: False,
            "requires_user_confirmation": True,
            "confirmation_kind": "strong",
            "confirm_ok": False,
            "expected_confirmation": spec["confirm"],
            "log": str(log_path),
            "error": "confirmation-required",
            "message": "Confirmation forte requise avant action systeme.",
        }, 403

    if dry_run or not privileged_actions_enabled() or not dangerous_real_apply or not real_power_enabled:
        append_action_log(
            log_path,
            action=action,
            status="planned",
            dangerous_real_apply=dangerous_real_apply,
            privileged_actions_enabled=privileged_actions_enabled(),
            real_power_enabled=real_power_enabled,
            confirm_ok=confirm_ok,
        )
        return {
            "status": "planned",
            "action": action,
            spec["requested"]: False,
            "dry_run": dry_run,
            "privileged_actions_enabled": privileged_actions_enabled(),
            "dangerous_real_apply": dangerous_real_apply,
            "real_power_enabled": real_power_enabled,
            "requires_user_confirmation": True,
            "confirmation_kind": "strong",
            "confirm_ok": True,
            "log": str(log_path),
            "warning": "Architecture SAFE uniquement: aucune action systeme reelle sans gate explicite futur.",
        }, 200

    command, error = privileged_action_command(action)
    if error:
        append_action_log(log_path, action=action, status="failure", error=error)
        response = privileged_error_response(action, error)
        response.update({spec["requested"]: False, "log": str(log_path)})
        return response, 403 if error == "wifi-kit-network-rights-not-installed" else 500

    try:
        with open_action_log(log_path) as handle:
            result = subprocess.run(
                command,
                cwd=str(SCRIPT_DIR.parent),
                check=False,
                stdin=subprocess.DEVNULL,
                stdout=handle,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=5,
            )
    except (OSError, subprocess.TimeoutExpired) as exc:
        append_action_log(log_path, action=action, status="failure", error=f"start-failed: {exc}")
        return {"status": "failure", "action": action, "error": f"start-failed: {exc}", spec["requested"]: False, "log": str(log_path)}, 500

    append_action_log(log_path, action=action, status="requested", returncode=result.returncode)
    return {
        "status": "started" if result.returncode == 0 else "failure",
        "action": action,
        spec["requested"]: result.returncode == 0,
        "message": spec["message"] if result.returncode == 0 else "Action systeme refusee par le wrapper.",
        "returncode": result.returncode,
        "log": str(log_path),
    }, 202 if result.returncode == 0 else 500


def start_reconnect_previous() -> dict:
    previous_connection = read_ap_only_state_value("active_connection") or "unknown"
    if not is_root_process():
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
        ensure_action_log_parent(RECONNECT_PREVIOUS_LOG)
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


def current_ip_for_iface(iface: str) -> str:
    output = run_text_command(["ip", "-o", "-4", "addr", "show", "dev", iface])
    for line in output.splitlines():
        parts = line.split()
        if "inet" in parts:
            index = parts.index("inet")
            if index + 1 < len(parts):
                return parts[index + 1]
    return ""


def safe_diagnose() -> dict:
    iface = "wlan0"
    current_ip = current_ip_for_iface(iface)
    current_ssid = wlan_ssid()
    backend = "raspberrypi-networkmanager" if networkmanager_owns_wlan0() else "runtime-readonly"
    scan_status = "available" if (find_tool("nmcli") or find_tool("iw") or find_tool("wpa_cli")) else "unavailable"
    return {
        "mode": "safe-diagnose",
        "timestamp": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "backend": backend,
        "interface": iface,
        "current_ssid_state": current_ssid if current_ssid != "unknown" else "unknown",
        "current_ip": current_ip or "unknown",
        "ssh_route_interface": "unknown",
        "network_writes": False,
        "scan_status": scan_status,
        "source": "serve-readonly.py",
    }


def scan(refresh: bool = False) -> dict:
    if not WIFI_KIT_SH.exists() or not find_tool("sh"):
        reason = "legacy-wifi-kit-sh-not-installed" if not WIFI_KIT_SH.exists() else "shell-not-available"
        return {
            "status": "unavailable",
            "backend": "runtime-readonly",
            "reason": reason,
            "refresh_attempted": refresh,
            "refresh_status": "unavailable",
            "networks": [],
        }
    args = ["scan-real", "--json"]
    if refresh:
        args.insert(1, "--refresh")
    return run_json_command(args)


def nmcli_wifi_list(nmcli_bin: str) -> tuple[list[dict], str]:
    return nmcli_wifi_list_with_rescan(nmcli_bin, rescan="no")


def nmcli_wifi_list_with_rescan(nmcli_bin: str, *, rescan: str) -> tuple[list[dict], str]:
    result = subprocess.run(
        [
            nmcli_bin,
            "-t",
            "--escape",
            "no",
            "-f",
            "IN-USE,SSID,SIGNAL,SECURITY,CHAN",
            "device",
            "wifi",
            "list",
            "--rescan",
            rescan,
        ],
        check=False,
        capture_output=True,
        text=True,
        timeout=8,
    )
    if result.returncode != 0:
        return [], result.stderr.strip()

    networks = []
    seen = set()
    for line in result.stdout.splitlines():
        parts = line.split(":", 4)
        in_use = parts[0] if len(parts) > 0 else ""
        ssid = parts[1] if len(parts) > 1 else ""
        signal = parts[2] if len(parts) > 2 else ""
        security = parts[3] if len(parts) > 3 else ""
        channel = parts[4] if len(parts) > 4 else ""
        if not ssid:
            continue
        key = (ssid, security, channel)
        if key in seen:
            continue
        seen.add(key)
        current = in_use.strip() == "*"
        networks.append(
            {
                "ssid": ssid,
                "signal": f"{signal}%",
                "security": security or "open",
                "channel": channel or "inconnu",
                "chan": channel or "inconnu",
                "current": "yes" if current else "no",
                "ssid_hidden": False,
            }
        )
    return networks, ""


def wpa_cli_refresh_scan(iface: str = "wlan0") -> tuple[bool, str]:
    wpa_cli_bin = find_tool("wpa_cli")
    if not wpa_cli_bin:
        return False, "wpa_cli-not-found"
    try:
        result = subprocess.run(
            [wpa_cli_bin, "-i", iface, "scan"],
            check=False,
            capture_output=True,
            text=True,
            timeout=3,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return False, f"wpa_cli-scan-failed: {exc}"
    if result.returncode != 0:
        return False, (result.stderr or result.stdout).strip() or "wpa_cli-scan-failed"
    return True, "ok"


def short_command_error(result: subprocess.CompletedProcess[str]) -> str:
    return (result.stderr or result.stdout or "").strip()[:300]


def networkmanager_scan(refresh: bool = True) -> dict:
    nmcli_bin = find_tool("nmcli") or "nmcli"
    refresh_backend = "networkmanager"
    refresh_note = ""
    try:
        if refresh:
            subprocess.run(
                [nmcli_bin, "-t", "device", "wifi", "rescan"],
                check=False,
                capture_output=True,
                text=True,
                timeout=8,
            )
        time.sleep(2.0)
        networks, error = nmcli_wifi_list(nmcli_bin)
        if refresh and len(networks) <= 1:
            ok, refresh_note = wpa_cli_refresh_scan("wlan0")
            if ok:
                refresh_backend = "networkmanager+wpa_cli"
                time.sleep(3.0)
                wpa_networks, wpa_error = nmcli_wifi_list(nmcli_bin)
                if wpa_networks:
                    networks = wpa_networks
                    error = ""
                elif wpa_error:
                    error = wpa_error
    except subprocess.TimeoutExpired as exc:
        return {
            "status": "unavailable",
            "backend": "networkmanager",
            "reason": "nmcli-scan-timeout",
            "stderr": str(exc),
            "networks": [],
        }

    if error:
        return {
            "status": "unavailable",
            "backend": "networkmanager",
            "reason": "nmcli-scan-failed",
            "stderr": error,
            "networks": [],
        }

    return {
        "status": "ok",
        "backend": "networkmanager",
        "refresh_backend": refresh_backend,
        "refresh_note": refresh_note,
        "interface": "wlan0",
        "timestamp": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "refresh_attempted": refresh,
        "refresh_status": "ok" if refresh else "not-requested",
        "networks": networks,
    }


def nm_hotspot_recovery_active() -> bool:
    if os.environ.get("WIFI_KIT_RECOVERY_BACKEND") == "nm-hotspot" or os.environ.get("WIFI_KIT_NM_AP_LAB") == "1":
        return True
    output = run_text_command(
        ["nmcli", "-t", "--escape", "no", "-f", "NAME,TYPE,DEVICE", "connection", "show", "--active"],
        timeout=3.0,
    )
    for line in output.splitlines():
        name, typ, device = (line.split(":") + ["", "", ""])[:3]
        if name == NM_AP_LAB_PROFILE and typ in {"wifi", "802-11-wireless"} and device == "wlan0":
            return True
    return False


def tcp_port_open(host: str, port: int, timeout: float = 1.0) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def nm_hotspot_recovery_status() -> dict[str, bool]:
    port_80_listening = tcp_port_open("192.168.50.1", 80)
    ui_recovery_active = pid_is_alive(NM_AP_LAB_UI_PID, ("serve-readonly.py", "--recovery-mode")) or port_80_listening
    return {
        "hotspot_active": nm_hotspot_recovery_active(),
        "ui_recovery_active": ui_recovery_active,
        "port_80_listening": port_80_listening,
    }


def nm_hotspot_scan(refresh: bool = True) -> dict:
    action = "scan-from-ap-recovery"
    nmcli_bin = find_tool("nmcli") or "nmcli"
    append_action_log(
        SCAN_FROM_AP_LOG,
        action=action,
        status="nmcli-scan-start",
        scan_mode="nm-hotspot-nondisruptive",
        no_ap_stop=True,
        refresh=refresh,
    )
    try:
        networks, error = nmcli_wifi_list_with_rescan(nmcli_bin, rescan="yes" if refresh else "no")
    except subprocess.TimeoutExpired as exc:
        append_action_log(
            SCAN_FROM_AP_LOG,
            action=action,
            status="nmcli-scan-failed",
            scan_mode="nm-hotspot-nondisruptive",
            no_ap_stop=True,
            error=exc,
        )
        return {
            "status": "unavailable",
            "backend": "networkmanager-hotspot",
            "scan_mode": "nm-hotspot-nondisruptive",
            "reason": "nmcli-scan-timeout",
            "stderr": str(exc),
            "refresh_attempted": refresh,
            "refresh_status": "failed",
            "ap_recovery_scan": True,
            "ap_recovery_interrupted": False,
            "ap_recovery_disconnects_clients": False,
            "no_ap_stop": True,
            "networks": [],
        }
    if error:
        append_action_log(
            SCAN_FROM_AP_LOG,
            action=action,
            status="nmcli-scan-failed",
            scan_mode="nm-hotspot-nondisruptive",
            no_ap_stop=True,
            error=error,
        )
        return {
            "status": "unavailable",
            "backend": "networkmanager-hotspot",
            "scan_mode": "nm-hotspot-nondisruptive",
            "reason": "nmcli-scan-failed",
            "stderr": error,
            "refresh_attempted": refresh,
            "refresh_status": "failed",
            "ap_recovery_scan": True,
            "ap_recovery_interrupted": False,
            "ap_recovery_disconnects_clients": False,
            "no_ap_stop": True,
            "networks": [],
        }
    payload = {
        "status": "ok",
        "backend": "networkmanager-hotspot",
        "scan_mode": "nm-hotspot-nondisruptive",
        "reason": "nm-hotspot-scan-ok",
        "interface": "wlan0",
        "timestamp": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "refresh_attempted": refresh,
        "refresh_status": "ok" if refresh else "not-requested",
        "ap_recovery_scan": True,
        "ap_recovery_interrupted": False,
        "ap_recovery_disconnects_clients": False,
        "no_ap_stop": True,
        "message": "Scan experimental sans coupure AP. Si l'AP disparait, c'est probablement une limite driver/NM, pas un stop volontaire du backend.",
        "log": str(SCAN_FROM_AP_LOG),
        "networks": networks,
    }
    write_json_file(SCAN_FROM_AP_CACHE, payload)
    append_action_log(
        SCAN_FROM_AP_LOG,
        action=action,
        status="nmcli-scan-result",
        scan_mode="nm-hotspot-nondisruptive",
        no_ap_stop=True,
        network_count=len(networks),
    )
    return payload


def ap_scan_worker_env() -> dict[str, str]:
    env = os.environ.copy()
    env["WIFI_KIT_AP_SKIP_NM_RESTORE"] = "1"
    env["WIFI_KIT_AP_SKIP_UI_RESTORE"] = "1"
    env["WIFI_KIT_RUNTIME_CONFIG"] = str(RUNTIME_CONFIG_PATH)
    return env


def wait_until_inactive(pid_path: Path, timeout_seconds: float = 5.0) -> bool:
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() <= deadline:
        if not pid_is_alive(pid_path, ("serve-readonly.py", "hostapd", "dnsmasq")):
            return True
        time.sleep(0.25)
    return not pid_is_alive(pid_path, ("serve-readonly.py", "hostapd", "dnsmasq"))


def stop_ap_for_scan(env: dict[str, str]) -> None:
    append_action_log(SCAN_FROM_AP_LOG, action="scan-from-ap-recovery", status="scan-ap-pausing")
    result = subprocess.run(
        [find_tool("sh") or "sh", str(AP_SETUP_TEST_SH), "stop"],
        check=False,
        capture_output=True,
        text=True,
        timeout=30,
        env=env,
    )
    append_action_log(
        SCAN_FROM_AP_LOG,
        action="scan-from-ap-recovery",
        status="scan-ap-paused",
        returncode=result.returncode,
        detail=short_command_error(result),
    )
    ui_stopped = wait_until_inactive(RECOVERY_UI_PID)
    hostapd_stopped = wait_until_inactive(RECOVERY_HOSTAPD_PID)
    append_action_log(
        SCAN_FROM_AP_LOG,
        action="scan-from-ap-recovery",
        status="scan-ap-stop-observed",
        ui_stopped=ui_stopped,
        hostapd_stopped=hostapd_stopped,
    )


def restart_ap_after_scan(env: dict[str, str]) -> bool:
    wrapper = INSTALLED_ACTION_WRAPPER_SH if INSTALLED_ACTION_WRAPPER_SH.exists() else ACTION_WRAPPER_SH
    for attempt in range(1, SCAN_FROM_AP_RESTART_ATTEMPTS + 1):
        append_action_log(SCAN_FROM_AP_LOG, action="scan-from-ap-recovery", status="scan-ap-restarting", attempt=attempt)
        if attempt > 1:
            try:
                stop_ap_for_scan(env)
            except (OSError, subprocess.TimeoutExpired) as exc:
                append_action_log(SCAN_FROM_AP_LOG, action="scan-from-ap-recovery", status="scan-ap-pre-retry-stop-failed", error=exc)
        try:
            result = subprocess.run(
                [find_tool("sh") or "sh", str(wrapper), "start-ap-mode"],
                check=False,
                capture_output=True,
                text=True,
                timeout=60,
                env=env,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            append_action_log(SCAN_FROM_AP_LOG, action="scan-from-ap-recovery", status="scan-ap-restart-error", attempt=attempt, error=exc)
            result = None
        if result is not None and result.returncode == 0:
            append_action_log(SCAN_FROM_AP_LOG, action="scan-from-ap-recovery", status="scan-ap-active", attempt=attempt)
            return True
        append_action_log(
            SCAN_FROM_AP_LOG,
            action="scan-from-ap-recovery",
            status="scan-ap-restart-failed",
            attempt=attempt,
            returncode="timeout" if result is None else result.returncode,
            detail="" if result is None else short_command_error(result),
        )
        time.sleep(SCAN_FROM_AP_RESTART_DELAY_SECONDS)
    append_action_log(SCAN_FROM_AP_LOG, action="scan-from-ap-recovery", status="scan-failed-recovery-restarted")
    return False


def run_ap_recovery_scan_worker() -> int:
    action = "scan-from-ap-recovery"
    nmcli_bin = find_tool("nmcli") or "nmcli"
    env = ap_scan_worker_env()
    try:
        stop_ap_for_scan(env)
        subprocess.run([nmcli_bin, "device", "set", "wlan0", "managed", "yes"], check=False, capture_output=True, text=True, timeout=10)
        append_action_log(SCAN_FROM_AP_LOG, action=action, status="scan-starting")
        scan_payload = networkmanager_scan(refresh=True)
        scan_payload["ap_recovery_scan"] = True
        scan_payload["ap_recovery_interrupted"] = True
        scan_payload["ap_recovery_restart_expected"] = True
        scan_payload["ap_recovery_disconnects_clients"] = True
        scan_payload["message"] = "AP recovery was interrupted briefly for Wi-Fi scan; connected devices were disconnected and must reconnect to the AP."
        write_json_file(SCAN_FROM_AP_CACHE, scan_payload)
        append_action_log(
            SCAN_FROM_AP_LOG,
            action=action,
            status="scan-finished",
            scan_status=scan_payload.get("status", "unknown"),
            network_count=len(scan_payload.get("networks", [])),
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        scan_payload = {
            "status": "unavailable",
            "backend": "ap-recovery-orchestrated",
            "reason": "scan-from-ap-recovery-failed",
            "error": str(exc),
            "ap_recovery_scan": True,
            "ap_recovery_restart_expected": True,
            "ap_recovery_disconnects_clients": True,
            "networks": [],
        }
        write_json_file(SCAN_FROM_AP_CACHE, scan_payload)
        append_action_log(SCAN_FROM_AP_LOG, action=action, status="scan-failed", error=exc)
    finally:
        try:
            subprocess.run([nmcli_bin, "device", "disconnect", "wlan0"], check=False, capture_output=True, text=True, timeout=10)
            subprocess.run([nmcli_bin, "device", "set", "wlan0", "managed", "no"], check=False, capture_output=True, text=True, timeout=10)
        except (OSError, subprocess.TimeoutExpired):
            pass
        restart_ap_after_scan(env)
    return 0


def start_ap_recovery_scan() -> dict:
    action = "scan-from-ap-recovery"
    append_action_log(SCAN_FROM_AP_LOG, action=action, status="scan-ap-pausing", request="accepted")
    try:
        subprocess.Popen(
            [sys.executable, str(Path(__file__).resolve()), "--scan-ap-recovery-worker"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            close_fds=True,
            start_new_session=True,
            env=os.environ.copy() | {"WIFI_KIT_RUNTIME_CONFIG": str(RUNTIME_CONFIG_PATH)},
        )
    except OSError as exc:
        append_action_log(SCAN_FROM_AP_LOG, action=action, status="failed", error=exc)
        cached = read_scan_from_ap_cache()
        cached.update(
            {
                "status": "unavailable",
                "backend": "ap-recovery-orchestrated",
                "reason": "scan-worker-start-failed",
                "error": str(exc),
                "refresh_attempted": True,
                "refresh_status": "failed",
                "log": str(SCAN_FROM_AP_LOG),
            }
        )
        return cached
    cached = read_scan_from_ap_cache()
    cached.update(
        {
            "status": "started",
            "backend": "ap-recovery-orchestrated",
            "reason": "ap-recovery-scan-started",
            "refresh_attempted": True,
            "refresh_status": "started",
            "ap_recovery_scan": True,
            "ap_recovery_interrupted": True,
            "ap_recovery_restart_expected": True,
            "ap_recovery_disconnects_clients": True,
            "log": str(SCAN_FROM_AP_LOG),
            "message": "AP recovery will be interrupted briefly for scan. Connected devices will be disconnected, then the AP should restart.",
        }
    )
    return cached


def wifi_scan(refresh: bool = True, recovery_active: bool = False) -> dict:
    if recovery_active:
        if nm_hotspot_recovery_active():
            return nm_hotspot_scan(refresh=refresh)
        if refresh:
            return start_ap_recovery_scan()
        cached = read_scan_from_ap_cache()
        cached["ap_recovery_scan"] = True
        cached.setdefault("message", "Use Scanner to pause AP recovery briefly and refresh the Wi-Fi list.")
        return cached
    if networkmanager_owns_wlan0() or shutil.which("nmcli"):
        nm_scan = networkmanager_scan(refresh=refresh)
        if nm_scan.get("status") == "ok":
            return nm_scan
    fallback = scan(refresh=refresh)
    current_ssid = wlan_ssid()
    for network in fallback.get("networks", []):
        channel = str(network.get("channel") or "").strip()
        if not channel:
            channel = str(network.get("chan") or "inconnu").strip() or "inconnu"
            network["channel"] = channel
            if "chan" not in network:
                network["chan"] = channel
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


def security_requires_password(security: str) -> bool:
    normalized = security.strip().lower()
    return normalized not in {"", "open", "none", "--", "unknown", "inconnu"}


def known_connection_for_ssid(ssid: str, requested_profile: str = "") -> dict[str, object] | None:
    for connection in known_wifi_connections(None):
        if str(connection.get("ssid", "")) != ssid:
            continue
        if requested_profile and str(connection.get("profile", "")) != requested_profile:
            continue
        return connection
    return None


def connect_wrapper_stdin_lines(
    *,
    ui_log: Path,
    ssid: str,
    existing_connection: str,
    password: str,
) -> list[str]:
    lines = [
        f"ui_log={ui_log}\n",
        f"ssid={ssid}\n",
        f"confirm={CONNECT_TRANSACTION_CONFIRM}\n",
        "dangerous_real_apply=true\n",
        f"timeout_seconds={CONNECT_TRANSACTION_TIMEOUT_SECONDS}\n",
    ]
    if existing_connection:
        lines.append(f"existing_connection={existing_connection}\n")
    else:
        lines.append(f"password={password}\n")
    return lines


def safe_nm_profile_name(ssid: str) -> str:
    safe = re.sub(r"[^A-Za-z0-9_.-]+", "-", ssid).strip("-._")
    return f"wifi-kit-known-{safe[:48] or 'wifi'}"


def classify_nmcli_connect_error(text: str) -> str:
    lowered = text.lower()
    if "secrets were required" in lowered or "no secrets" in lowered or "password" in lowered:
        return "wrong-password"
    if "not found" in lowered or "no network with ssid" in lowered or "ssid" in lowered:
        return "network-not-found"
    if "timeout" in lowered or "timed out" in lowered:
        return "timeout"
    return "nmcli-error"


def restore_nm_hotspot_after_connect_failure(log_path: Path) -> bool:
    nmcli_bin = find_tool("nmcli") or "nmcli"
    append_action_log(
        log_path,
        action="nm-hotspot-connect",
        status="nm-hotspot-restore-start",
        hotspot_profile=NM_AP_LAB_PROFILE,
    )
    try:
        result = subprocess.run(
            [nmcli_bin, "connection", "up", NM_AP_LAB_PROFILE, "ifname", "wlan0"],
            check=False,
            capture_output=True,
            text=True,
            timeout=25,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        append_action_log(
            log_path,
            action="nm-hotspot-connect",
            status="nm-hotspot-restore-failed",
            error=exc,
        )
        return False
    restored = result.returncode == 0
    append_action_log(
        log_path,
        action="nm-hotspot-connect",
        status="nm-hotspot-restored-after-failure" if restored else "nm-hotspot-restore-failed",
        returncode=result.returncode,
        detail=short_command_error(result),
    )
    return restored


def nm_hotspot_wifi_connect(payload: dict) -> tuple[dict, int]:
    connect_log = unique_action_log_path("nm-hotspot-connect")

    def refused(error: str, http_status: int = 400, **extra: object) -> tuple[dict, int]:
        append_action_log(connect_log, action="nm-hotspot-connect", status="refused", error=error)
        response = {
            "status": "failure",
            "action": "nm-hotspot-connect",
            "error": error,
            "connect_started": False,
            "log": str(connect_log),
        }
        response.update(extra)
        return response, http_status

    if payload.get("_error"):
        return refused(str(payload["_error"]))
    ssid = str(payload.get("ssid", "")).strip()
    password = str(payload.get("password", ""))
    known_profile = str(payload.get("known_profile", "")).strip()
    security = str(payload.get("security", "")).strip()
    user_confirmed = bool_payload(payload.get("user_confirmed")) or bool_payload(payload.get("confirmed"))
    if not ssid:
        return refused("missing-ssid")
    if len(ssid.encode("utf-8")) > 32:
        return refused("ssid-too-long", requested_ssid=ssid)
    if not user_confirmed:
        return refused("user-confirmation-required", requested_ssid=ssid, recovery_mode="nm-hotspot")
    known_connection = known_connection_for_ssid(ssid, known_profile) if known_profile else None
    existing_connection = str(known_connection.get("profile", "")) if known_connection else ""
    if security_requires_password(security) and not password and not existing_connection:
        return refused("missing-password", requested_ssid=ssid)
    if password == SAVED_NM_SECRET_PLACEHOLDER:
        return refused("saved-secret-placeholder-requires-known-profile", requested_ssid=ssid)
    if password and len(password) < 8:
        return refused("password-too-short", requested_ssid=ssid)

    nmcli_bin = find_tool("nmcli") or "nmcli"
    target_connection = existing_connection or safe_nm_profile_name(ssid)
    command = (
        [nmcli_bin, "connection", "up", existing_connection, "ifname", "wlan0"]
        if existing_connection
        else [nmcli_bin, "--wait", "30", "device", "wifi", "connect", ssid, "ifname", "wlan0", "name", target_connection]
    )
    if not existing_connection and security_requires_password(security):
        command.extend(["password", password])

    append_action_log(
        connect_log,
        action="nm-hotspot-connect",
        status="nm-hotspot-connect-start",
        ssid=ssid,
        connection=target_connection,
        existing_connection=existing_connection or "none",
        secret_policy="runtime-only-or-existing-profile; secret not logged",
    )
    try:
        result = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=45,
        )
    except subprocess.TimeoutExpired as exc:
        append_action_log(connect_log, action="nm-hotspot-connect", status="nm-hotspot-connect-failed", error="timeout")
        restored = restore_nm_hotspot_after_connect_failure(connect_log)
        return {
            "status": "failure",
            "action": "nm-hotspot-connect",
            "error": "timeout",
            "requested_ssid": ssid,
            "connection": target_connection,
            "connect_started": True,
            "hotspot_restored": restored,
            "log": str(connect_log),
            "message": "Connexion timeout; le hotspot NM recovery a ete relance.",
            "connect_plan": [
                "NM hotspot recovery actif",
                "test de connexion NetworkManager vers le SSID demande",
                "timeout: relance du profil hotspot recovery",
            ],
        }, 504
    if result.returncode == 0:
        append_action_log(
            connect_log,
            action="nm-hotspot-connect",
            status="nm-hotspot-connect-success",
            ssid=ssid,
            connection=target_connection,
        )
        return {
            "status": "done",
            "action": "nm-hotspot-connect",
            "requested_ssid": ssid,
            "connection": target_connection,
            "connect_started": True,
            "hotspot_expected_to_disappear": True,
            "log": str(connect_log),
            "message": f"Connexion reussie vers {ssid}. Le hotspot recovery peut disparaitre, c'est attendu.",
            "connect_plan": [
                "NM hotspot recovery actif",
                "test de connexion NetworkManager vers le SSID demande",
                "succes: bascule en mode client normal",
            ],
        }, 200

    detail = short_command_error(result)
    error = classify_nmcli_connect_error(detail)
    append_action_log(
        connect_log,
        action="nm-hotspot-connect",
        status="nm-hotspot-connect-failed",
        ssid=ssid,
        connection=target_connection,
        error=error,
        returncode=result.returncode,
        detail=detail,
    )
    restored = restore_nm_hotspot_after_connect_failure(connect_log)
    return {
        "status": "failure",
        "action": "nm-hotspot-connect",
        "error": error,
        "requested_ssid": ssid,
        "connection": target_connection,
        "connect_started": True,
        "hotspot_restored": restored,
        "stderr": detail,
        "log": str(connect_log),
        "message": f"Connexion impossible ({error}); le hotspot NM recovery reste disponible.",
        "connect_plan": [
            "NM hotspot recovery actif",
            "test de connexion NetworkManager vers le SSID demande",
            "echec: relance du profil hotspot recovery",
        ],
    }, 502


def start_recovery_wifi_connect(payload: dict, recovery_active: bool) -> tuple[dict, int]:
    connect_transaction_log = unique_action_log_path("connect-transaction-ui")

    def refused(error: str, http_status: int = 400, **extra: object) -> tuple[dict, int]:
        append_action_log(
            connect_transaction_log,
            action="wifi-connect-transaction",
            status="refused",
            error=error,
            ssid=str(extra.get("requested_ssid", "")) or "unknown",
            existing_connection=str(extra.get("existing_connection", "")) or "none",
        )
        response = {
            "status": "failure",
            "error": error,
            "connect_started": False,
            "log": str(connect_transaction_log),
        }
        response.update(extra)
        return response, http_status

    if payload.get("_error"):
        return refused(str(payload["_error"]))

    ssid = str(payload.get("ssid", "")).strip()
    password = str(payload.get("password", ""))
    known_profile = str(payload.get("known_profile", "")).strip()
    security = str(payload.get("security", "")).strip()
    dangerous_real_apply = bool_payload(payload.get("dangerous_real_apply"))
    user_confirmed = bool_payload(payload.get("user_confirmed")) or bool_payload(payload.get("confirmed"))
    if password == SAVED_NM_SECRET_PLACEHOLDER and known_profile:
        password = SAVED_NM_SECRET_SENTINEL
    use_saved_nm_secret = password == SAVED_NM_SECRET_SENTINEL
    known_connection = known_connection_for_ssid(ssid, known_profile) if use_saved_nm_secret else None
    existing_connection = str(known_connection.get("profile", "")) if known_connection else ""
    known_profile_reconnect = bool(existing_connection and use_saved_nm_secret)
    recovery_gate_ok = recovery_active or known_profile_reconnect
    if not ssid:
        return refused("missing-ssid")
    if len(ssid.encode("utf-8")) > 32:
        return refused("ssid-too-long", requested_ssid=ssid)
    if use_saved_nm_secret and not existing_connection:
        return refused("known-profile-not-found", requested_ssid=ssid)
    if security_requires_password(security) and not password and not existing_connection:
        return refused("missing-password", requested_ssid=ssid)
    if password and not use_saved_nm_secret and len(password) < 8:
        return refused("password-too-short", requested_ssid=ssid)

    backend = "raspberrypi-networkmanager" if networkmanager_owns_wlan0() else "unknown"
    secret_policy = (
        "saved NetworkManager profile requested by sentinel; no secret was read, returned, or logged"
        if existing_connection
        else "runtime-only; password was not logged or persisted"
    )
    connect_plan = [
        (
            "allow normal mode because a known NetworkManager profile was selected"
            if known_profile_reconnect
            else "require AP recovery context"
        ),
        "require WIFI_KIT_ENABLE_PRIVILEGED_ACTIONS=1",
        "require browser confirmation from the operator",
        (
            f"use existing NetworkManager profile {existing_connection} without reading its secret"
            if existing_connection
            else "read password only from this runtime request"
        ),
        "run guarded NetworkManager transaction",
        "rollback previous profile on failure",
        "start AP recovery only if rollback fails",
    ]
    if (
        not recovery_gate_ok
        or not privileged_actions_enabled()
        or not dangerous_real_apply
        or not user_confirmed
    ):
        append_action_log(
            connect_transaction_log,
            action="wifi-connect-transaction",
            status="refused",
            error="safe-gates-not-satisfied",
            ssid=ssid,
            existing_connection=existing_connection or "none",
            recovery_active=recovery_active,
            normal_mode_known_profile_allowed=known_profile_reconnect,
            privileged_actions_enabled=privileged_actions_enabled(),
            dangerous_real_apply=dangerous_real_apply,
            user_confirmed=user_confirmed,
        )
        return (
            {
                "status": "planned",
                "mutation": "not-started",
                "error": "safe-gates-not-satisfied",
                "requested_ssid": ssid,
                "backend": backend,
                "connect_started": False,
                "recovery_active": recovery_active,
                "normal_mode_known_profile_allowed": known_profile_reconnect,
                "privileged_actions_enabled": privileged_actions_enabled(),
                "dangerous_real_apply": dangerous_real_apply,
                "confirm_ok": user_confirmed,
                "secret_policy": secret_policy,
                "existing_connection": existing_connection,
                "log": str(connect_transaction_log),
                "warning_if_recovery_active": (
                    "Known NetworkManager profile reconnect can run from normal mode with rollback, privileged actions, and browser confirmation."
                    if known_profile_reconnect
                    else "Real Wi-Fi connect requires AP recovery context, privileged actions, and browser confirmation."
                ),
                "connect_plan": connect_plan,
            },
            409,
        )

    command, error = privileged_connect_transaction_command()
    if error:
        append_action_log(
            connect_transaction_log,
            action="wifi-connect-transaction",
            status="refused",
            error=error,
            ssid=ssid,
            existing_connection=existing_connection or "none",
        )
        payload = privileged_error_response("wifi-connect-transaction", error)
        payload.update(
            {
                "requested_ssid": ssid,
                "backend": backend,
                "connect_started": False,
                "existing_connection": existing_connection,
                "normal_mode_known_profile_allowed": known_profile_reconnect,
                "secret_policy": secret_policy,
                "log": str(connect_transaction_log),
            }
        )
        return payload, 403 if error == "wifi-kit-network-rights-not-installed" else 500

    try:
        append_action_log(
            connect_transaction_log,
            action="wifi-connect-transaction",
            status="starting",
            ssid=ssid,
            existing_connection=existing_connection or "none",
            secret_policy=secret_policy,
        )
        stdin_lines = connect_wrapper_stdin_lines(
            ui_log=connect_transaction_log,
            ssid=ssid,
            existing_connection=existing_connection,
            password=password,
        )
        append_action_log(
            connect_transaction_log,
            action="wifi-connect-transaction",
            status="backend-handoff",
            stdin_keys=(
                "ui_log,ssid,confirm,dangerous_real_apply,timeout_seconds,"
                + ("existing_connection" if existing_connection else "password")
            ),
            ui_log=str(connect_transaction_log),
        )
        env = os.environ.copy()
        env["WIFI_KIT_CONNECT_UI_LOG"] = str(connect_transaction_log)
        process = subprocess.Popen(
            command,
            cwd=str(SCRIPT_DIR.parent),
            stdin=subprocess.PIPE,
            stdout=open_action_log(connect_transaction_log),
            stderr=subprocess.STDOUT,
            start_new_session=True,
            text=True,
            env=env,
        )
        assert process.stdin is not None
        process.stdin.writelines(stdin_lines)
        process.stdin.close()
    except (OSError, BrokenPipeError) as exc:
        append_action_log(
            connect_transaction_log,
            action="wifi-connect-transaction",
            status="failed",
            error=f"start-failed: {exc}",
            ssid=ssid,
            existing_connection=existing_connection or "none",
        )
        return {
            "status": "failure",
            "error": f"start-failed: {exc}",
            "requested_ssid": ssid,
            "backend": backend,
            "connect_started": False,
            "log": str(connect_transaction_log),
        }, 500

    return (
        {
            "status": "started",
            "action": "wifi-connect-transaction",
            "requested_ssid": ssid,
            "backend": backend,
            "connect_started": True,
            "existing_connection": existing_connection,
            "normal_mode_known_profile_allowed": known_profile_reconnect,
            "timeout_seconds": CONNECT_TRANSACTION_TIMEOUT_SECONDS,
            "expected_behavior": "success-keeps-target-failure-rolls-back-rollback-failure-starts-ap-recovery",
            "secret_policy": (
                "existing NetworkManager profile selected by sentinel; no secret was read, returned, or logged"
                if existing_connection
                else "runtime-only; password is passed on stdin and never returned or logged"
            ),
            "log": str(connect_transaction_log),
            "connect_plan": [
                "snapshot active NetworkManager profile and SSID",
                (
                    f"connect wlan0 using existing NetworkManager profile {existing_connection}"
                    if existing_connection
                    else "create temporary Wifi-Kit NetworkManager profile"
                ),
                (
                    "reuse saved NetworkManager secret without exposing it"
                    if existing_connection
                    else "connect wlan0 to the requested SSID with runtime-only password"
                ),
                "validate stable connected state, target SSID, IPv4, gateway, internet ping, DNS, and sshd",
                "on success: keep the new Wi-Fi",
                "on failure: reconnect the previous NetworkManager profile",
                "if rollback fails: start temporary AP recovery",
                "cleanup only the temporary Wifi-Kit profile",
            ],
        },
        202,
    )

def snapshot_preview() -> dict:
    diagnose = safe_diagnose()
    return {
        "mode": "state-snapshot",
        "simulated": True,
        "source": "serve-readonly.py",
        "backend": diagnose.get("backend", "runtime-readonly"),
        "interface": diagnose.get("interface", "wlan0"),
        "current_ssid_state": diagnose.get("current_ssid_state", "unknown"),
        "current_ip": diagnose.get("current_ip", "unknown"),
        "ssh_route_interface": diagnose.get("ssh_route_interface", "unknown"),
        "network_writes": False,
        "timestamp": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }


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


def nmcli_unescape(value: str) -> str:
    return value.replace("\\:", ":").replace("\\\\", "\\")


def scan_visible_ssids(scan: dict | None = None) -> set[str]:
    if not isinstance(scan, dict):
        return set()
    networks = scan.get("networks")
    if not isinstance(networks, list):
        return set()
    visible: set[str] = set()
    for network in networks:
        if isinstance(network, dict) and network.get("ssid"):
            visible.add(str(network["ssid"]))
    return visible


def known_wifi_connections(scan: dict | None = None) -> list[dict[str, object]]:
    output = run_text_command(
        ["nmcli", "-t", "--escape", "yes", "-f", "NAME,UUID,TYPE,DEVICE,AUTOCONNECT,ACTIVE", "connection", "show"],
        timeout=4.0,
    )
    visible_ssids = scan_visible_ssids(scan)
    connect_attempts = wifi_connect_attempts_by_ssid()
    connections: list[dict[str, object]] = []
    for line in output.splitlines():
        parts = line.split(":", 5)
        if len(parts) < 3:
            continue
        name = nmcli_unescape(parts[0])
        uuid = nmcli_unescape(parts[1])
        typ = parts[2]
        device = nmcli_unescape(parts[3]) if len(parts) > 3 else ""
        autoconnect = nmcli_unescape(parts[4]) if len(parts) > 4 else ""
        active = nmcli_unescape(parts[5]) if len(parts) > 5 else ""
        if typ != "802-11-wireless":
            continue
        ssid = ""
        details = run_text_command(
            ["nmcli", "-t", "--escape", "yes", "-f", "802-11-wireless.ssid", "connection", "show", name],
            timeout=2.0,
        )
        for detail in details.splitlines():
            key, sep, value = detail.partition(":")
            if sep and key == "802-11-wireless.ssid":
                ssid = nmcli_unescape(value)
                break
        display_ssid = ssid or name
        connect_attempt = connect_attempts.get(display_ssid, {})
        connections.append(
            {
                "profile": name,
                "ssid": display_ssid,
                "label": f"{display_ssid} - {name}",
                "uuid": uuid,
                "type": typ,
                "device": device,
                "autoconnect": autoconnect,
                "active": active,
                "active_bool": active.lower() == "yes",
                "visible": display_ssid in visible_ssids if visible_ssids else False,
                "visible_known": bool(visible_ssids),
                "last_connect_failed": connect_attempt.get("last_connect_failed") == "true",
                "last_connect_status": connect_attempt.get("last_connect_status", ""),
                "last_connect_error": connect_attempt.get("last_connect_error", ""),
                "last_connect_timestamp": connect_attempt.get("last_connect_timestamp", ""),
            }
        )
    return sorted(connections, key=lambda item: (str(item["ssid"]).lower(), str(item["profile"]).lower()))


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


def ap_client_count() -> int | None:
    clients: set[str] = set()
    observed_source = False
    lease_paths = [
        Path("/var/lib/NetworkManager/dnsmasq-wlan0.leases"),
        Path("/var/lib/NetworkManager/dnsmasq-wifi-kit-recovery-ap.leases"),
        Path("/tmp/wifi-kit-dnsmasq-test.leases"),
    ]
    for path in lease_paths:
        try:
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
            observed_source = True
            for line in lines:
                parts = line.split()
                if len(parts) >= 3:
                    clients.add(parts[1].lower())
        except OSError:
            continue
    try:
        lines = Path("/proc/net/arp").read_text(encoding="utf-8", errors="replace").splitlines()[1:]
        observed_source = True
        for line in lines:
            parts = line.split()
            if len(parts) >= 4 and parts[0].startswith("192.168.50.") and parts[3] != "00:00:00:00:00:00":
                clients.add(parts[3].lower())
    except OSError:
        pass
    return len(clients) if observed_source else None


def system_info(diagnose: dict, recovery: dict | None = None) -> dict:
    recovery = recovery or {}
    config = read_runtime_config()
    recovery_active = bool(recovery.get("active"))
    hostname = socket.gethostname() or "unknown"
    recovery_ssid = config["ap_ssid"] or recovery.get("ssid") or f"Wifi-Kit-{hostname}"
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
        "ap_client_count": recovery.get("ap_client_count"),
        "normal_ui_port": NORMAL_UI_PORT,
        "recovery_ui_port": RECOVERY_UI_PORT,
        "recovery_ap_password_policy": "min-8-chars",
        "recovery_ap_password_configurable": True,
        "recovery_ap_password_set": bool(config["ap_password"]),
        "original_ssid": config["original_ssid"],
        "original_connection": config["original_connection"],
        "return_ssid": config["return_ssid"],
        "return_connection": config["return_connection"],
        "runtime_recovery_enabled": config.get("runtime_recovery_enabled", "true"),
        "runtime_recovery_debug_passive": config.get("runtime_recovery_debug_passive", "false"),
        "runtime_recovery_grace_seconds": config.get("runtime_recovery_grace_seconds", "30"),
        "runtime_recovery_instability_window_minutes": config.get("runtime_recovery_instability_window_minutes", "10"),
        "runtime_recovery_instability_threshold": config.get("runtime_recovery_instability_threshold", "3"),
        "runtime_watchdog": runtime_watchdog_status(),
        "runtime_config_path": str(RUNTIME_CONFIG_PATH),
        "ui_access_password": "future-not-configured",
        "last_recovery_event": "recovery-captive-ui-validated" if recovery_active else "normal-client-mode",
    }


def ui_data(recovery: dict | None = None) -> dict:
    diagnose = safe_diagnose()
    snapshot = snapshot_preview()
    hostname = socket.gethostname() or "node"
    config = read_runtime_config()
    recovery_active = bool(recovery and recovery.get("active"))
    scan = wifi_scan(refresh=False, recovery_active=recovery_active)
    wifi_connections = known_wifi_connections(scan)
    recovery_payload = {
        "active": False,
        "ssid": config["ap_ssid"] or f"Wifi-Kit-{hostname}",
        "ip": "192.168.50.1",
        "ui_port": 80,
        "dhcp": "planned",
        "dns": "planned",
        "ui": "read-only",
        "captive_portal": "planned",
        "actions": "runtime-gated",
        "normal_ui_port": NORMAL_UI_PORT,
        "recovery_ui_port": RECOVERY_UI_PORT,
        "ap_password_policy": "min-8-chars",
        "ap_password_configurable": True,
        "ap_password_set": bool(config["ap_password"]),
        "original_ssid": config["original_ssid"],
        "original_connection": config["original_connection"],
        "return_ssid": config["return_ssid"],
        "return_connection": config["return_connection"],
        "runtime_recovery_enabled": config.get("runtime_recovery_enabled", "true"),
        "runtime_recovery_debug_passive": config.get("runtime_recovery_debug_passive", "false"),
        "runtime_recovery_grace_seconds": config.get("runtime_recovery_grace_seconds", "30"),
        "runtime_recovery_instability_window_minutes": config.get("runtime_recovery_instability_window_minutes", "10"),
        "runtime_recovery_instability_threshold": config.get("runtime_recovery_instability_threshold", "3"),
        "runtime_watchdog": runtime_watchdog_status(),
        "runtime_config_path": str(RUNTIME_CONFIG_PATH),
        "ui_access_password": "future-not-configured",
    }
    if recovery:
        recovery_payload.update(recovery)
        recovery_payload["ssid"] = config["ap_ssid"] or recovery_payload.get("ssid") or f"Wifi-Kit-{hostname}"
        recovery_payload.pop("ap_password_current", None)
        recovery_payload["ap_password_set"] = bool(config["ap_password"])
        recovery_payload["original_ssid"] = config["original_ssid"]
        recovery_payload["original_connection"] = config["original_connection"]
        recovery_payload["return_ssid"] = config["return_ssid"]
        recovery_payload["return_connection"] = config["return_connection"]
        recovery_payload["runtime_recovery_enabled"] = config.get("runtime_recovery_enabled", "true")
        recovery_payload["runtime_recovery_debug_passive"] = config.get("runtime_recovery_debug_passive", "false")
        recovery_payload["runtime_recovery_grace_seconds"] = config.get("runtime_recovery_grace_seconds", "30")
        recovery_payload["runtime_recovery_instability_window_minutes"] = config.get("runtime_recovery_instability_window_minutes", "10")
        recovery_payload["runtime_recovery_instability_threshold"] = config.get("runtime_recovery_instability_threshold", "3")
        recovery_payload["runtime_watchdog"] = runtime_watchdog_status()
        recovery_payload["runtime_config_path"] = str(RUNTIME_CONFIG_PATH)
    recovery_payload["ap_client_count"] = ap_client_count() if recovery_active else None
    return {
        "diagnose": diagnose,
        "snapshot": snapshot,
        "runtime_config": public_runtime_config(),
        "known_wifi_connections": wifi_connections,
        "runtime_state": {
            "source": "serve-readonly.py state snapshot",
            "data": snapshot,
        },
        "connect_options": {
            "apply_endpoint": "/wifi/connect",
            "actions": "runtime-gated",
            "ap_services_started": recovery_active,
        },
        "recovery": recovery_payload,
        "system": system_info(diagnose, recovery_payload),
        "scan": scan,
    }


def render_index(recovery: dict | None = None) -> str:
    html = INDEX_HTML.read_text(encoding="utf-8")
    data = json.dumps(ui_data(recovery), indent=2).replace("<", "\\u003c")
    start = '<script id="wifi-kit-data" type="application/json">'
    end = "</script>"
    before, rest = html.split(start, 1)
    _old_json, after = rest.split(end, 1)
    return f"{before}{start}\n{data}\n  {end}{after}"


def render_portal(recovery: dict | None = None) -> str:
    recovery = recovery or {}
    recovery_ip = recovery.get("ip") or "192.168.50.1"
    recovery_url = f"http://{recovery_ip}/recovery"
    return f"""<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Wifi-Kit</title>
  <style>
    :root {{
      color-scheme: light;
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: #f4f7fb;
      color: #142033;
    }}
    body {{
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      padding: 24px;
      box-sizing: border-box;
    }}
    main {{
      width: min(100%, 420px);
      display: grid;
      gap: 16px;
      text-align: center;
    }}
    h1 {{
      margin: 0;
      font-size: 2rem;
      line-height: 1.05;
    }}
    p {{
      margin: 0;
      color: #4d5b70;
      font-size: 1rem;
      line-height: 1.45;
    }}
    a.button {{
      display: inline-flex;
      align-items: center;
      justify-content: center;
      min-height: 48px;
      border-radius: 8px;
      background: #1769e0;
      color: white;
      padding: 0 18px;
      font-weight: 800;
      text-decoration: none;
    }}
    a.link {{
      color: #1769e0;
      overflow-wrap: anywhere;
    }}
  </style>
</head>
<body>
  <main>
    <h1>Wifi-Kit</h1>
    <p>Configure le Wi-Fi de ce node.</p>
    <a class="button" href="{recovery_url}">Ouvrir la configuration Wi-Fi</a>
    <p><a class="link" href="{recovery_url}">{recovery_url}</a></p>
  </main>
</body>
</html>
"""


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
        payload = redact_public_payload(payload)
        body = json.dumps(payload, indent=2).encode("utf-8") + b"\n"
        self.send_bytes(status, "application/json; charset=utf-8", body)

    def send_action_json(self, action: str, payload: dict, status: int = 200) -> None:
        self.send_json(action_response(action, payload, status), status=status)

    def send_redirect(self, location: str = "/recovery") -> None:
        body = b"Wifi-Kit recovery\n"
        self.send_response(302)
        self.send_header("Location", location)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_captive_redirect(self, raw_path: str, path: str) -> None:
        target = "/portal"
        log_route("captive-route-hit", raw_path, f"{path}->{target}")
        self.send_redirect(target)

    @property
    def recovery(self) -> dict:
        return getattr(self.server, "wifi_kit_recovery", {})

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        raw_path = parsed.path
        path = normalize_request_path(raw_path)
        log_route("post", raw_path, path)
        if path == "/wifi/connect":
            post_payload = parse_post_payload(self)
            if bool(self.recovery.get("active")) and nm_hotspot_recovery_active():
                payload, status = nm_hotspot_wifi_connect(post_payload)
                self.send_action_json("nm-hotspot-connect", payload, status=status)
                return
            payload, status = start_recovery_wifi_connect(post_payload, bool(self.recovery.get("active")))
            self.send_action_json("wifi-connect-transaction", payload, status=status)
            return

        if path == "/start-ap-mode":
            payload, status = start_ap_mode(parse_post_payload(self))
            self.send_action_json("start-ap-mode", payload, status=status)
            return

        if path == "/return-default-network":
            payload, status = return_default_network(parse_post_payload(self))
            self.send_action_json("return-default-network", payload, status=status)
            return

        if path in ("/ap-return-check-once", "/api/ap-return-check-once"):
            payload, status = ap_return_check_once(parse_post_payload(self))
            self.send_action_json("ap-return-check-once", payload, status=status)
            return

        if path == "/system-reboot":
            payload, status = system_power_action(parse_post_payload(self), "reboot-system")
            self.send_action_json("reboot-system", payload, status=status)
            return

        if path == "/system-shutdown":
            payload, status = system_power_action(parse_post_payload(self), "shutdown-system")
            self.send_action_json("shutdown-system", payload, status=status)
            return

        if path == "/api/runtime-config":
            payload, status = update_runtime_config(parse_post_payload(self))
            self.send_action_json("runtime-config", payload, status=status)
            return

        if path == "/reconnect-previous":
            if not self.recovery.get("active"):
                previous_connection = read_ap_only_state_value("active_connection") or "unknown"
                append_reconnect_previous_log(
                    previous_connection=previous_connection,
                    recovery_mode_active=False,
                    reconnect_started=False,
                    status="failure",
                    error="recovery-not-active",
                )
                self.send_action_json(
                    "reconnect-previous",
                    {
                        "status": "failure",
                        "action": "reconnect-previous",
                        "error": "recovery-not-active",
                        "previous_connection": previous_connection,
                        "reconnect_started": False,
                        "safety": "No recovery cleanup was started from normal mode.",
                    },
                    status=409,
                )
                return

            payload = start_reconnect_previous()
            self.send_action_json("reconnect-previous", payload, status=200 if payload.get("status") == "success" else 500)
            return

        self.send_action_json(
            "unknown-post",
            {
                "error": "method-not-allowed",
                "status": "failure",
                "action": "unknown-post",
                "safety": "Only known Wifi-Kit POST actions can mutate recovery state.",
            },
            status=405,
        )

    def do_PUT(self) -> None:
        self.do_POST()

    def do_DELETE(self) -> None:
        self.do_POST()

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        raw_path = parsed.path
        path = normalize_request_path(raw_path)
        query = parse_qs(parsed.query)
        log_route("get", raw_path, path)

        if path in CAPTIVE_PATHS:
            self.send_captive_redirect(raw_path, path)
            return

        if path == "/portal":
            self.send_bytes(200, "text/html; charset=utf-8", render_portal(self.recovery).encode("utf-8"))
            return

        if path in ("/", "/index.html", "/recovery"):
            self.send_bytes(200, "text/html; charset=utf-8", render_index(self.recovery).encode("utf-8"))
            return

        if path == "/status":
            status_backend = backend_status(self.recovery)
            status_system = status_backend["network"] | {
                "hostname": socket.gethostname() or "unknown",
                "mode": "recovery" if self.recovery.get("active") else "runtime",
            }
            self.send_json(
                {
                    "status": "ok",
                    "mode": "recovery" if self.recovery.get("active") else "runtime",
                    "recovery": public_recovery_status(self.recovery),
                    "system": status_system,
                    "backend": status_backend,
                    "normal_ui_port": NORMAL_UI_PORT,
                    "recovery_ui_port": RECOVERY_UI_PORT,
                    "recovery_ap_password_policy": "min-8-chars",
                    "recovery_ap_password_configurable": True,
                    "actions": status_backend["actions"],
                }
            )
            return

        if path in ACTION_PATHS:
            action = ACTION_PATHS[path]
            runtime_actions = {"reconnect-previous", "start-ap-mode", "return-default-network", "ap-return-check-once", "reboot-system", "shutdown-system"}
            self.send_json(
                {
                    "status": "runtime-gated" if action in runtime_actions else "unavailable",
                    "action": action,
                    "mutation": "post-required" if action in runtime_actions else "not-wired",
                    "safety": "GET is read-only; use the matching POST endpoint for gated runtime actions.",
                    "recovery": public_recovery_status(self.recovery),
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
            self.send_json(wifi_scan(refresh=query.get("refresh") != ["0"], recovery_active=bool(self.recovery.get("active"))))
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

        if path == "/api/backend-status":
            log_route("match-backend-status", raw_path, path)
            self.send_json(backend_status(self.recovery))
            return

        if path == "/api/runtime-config":
            self.send_json(public_runtime_config())
            return

        log_route("not-found", raw_path, path)
        self.send_json({"error": "not-found"}, status=404)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="wifi-kit read-only local HTTP prototype")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=NORMAL_UI_PORT)
    parser.add_argument("--recovery-mode", action="store_true")
    parser.add_argument("--recovery-ssid", default="")
    parser.add_argument("--recovery-ip", default="192.168.50.1")
    parser.add_argument("--scan-ap-recovery-worker", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.scan_ap_recovery_worker:
        raise SystemExit(run_ap_recovery_scan_worker())
    if not args.recovery_mode and recovery_runtime_active():
        print("wifi-kit normal UI suppressed while AP recovery is active")
        raise SystemExit(0)
    hostname = socket.gethostname() or "node"
    config = read_runtime_config()
    server = ThreadingHTTPServer((args.host, args.port), WifiKitReadOnlyHandler)
    server.wifi_kit_recovery = {
        "active": bool(args.recovery_mode),
        "ssid": args.recovery_ssid or config["ap_ssid"] or f"Wifi-Kit-{hostname}",
        "ip": args.recovery_ip,
        "ui_port": args.port,
        "dhcp": "active" if args.recovery_mode else "planned",
        "dns": "active" if args.recovery_mode else "planned",
        "ui": "active" if args.recovery_mode else "read-only",
        "captive_portal": "basic" if args.recovery_mode else "planned",
        "actions": "runtime-gated",
        "normal_ui_port": NORMAL_UI_PORT,
        "recovery_ui_port": RECOVERY_UI_PORT,
        "ap_password_policy": "min-8-chars",
        "ap_password_configurable": True,
        "ap_password_set": bool(config["ap_password"]),
        "original_ssid": config["original_ssid"],
        "original_connection": config["original_connection"],
        "return_ssid": config["return_ssid"],
        "return_connection": config["return_connection"],
        "runtime_config_path": str(RUNTIME_CONFIG_PATH),
        "ui_access_password": "future-not-configured",
        "action_endpoints": sorted(ACTION_PATHS.keys()),
    }
    print(f"wifi-kit read-only HTTP on http://{args.host}:{args.port}")
    print("GET read-only; POST actions: /reconnect-previous, /start-ap-mode, /return-default-network, /ap-return-check-once")
    server.serve_forever()


if __name__ == "__main__":
    main()
