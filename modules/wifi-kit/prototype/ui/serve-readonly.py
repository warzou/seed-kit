#!/usr/bin/env python3
"""Read-only local HTTP prototype for wifi-kit."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import socket
import subprocess
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
SUDOERS_PATH = Path(os.environ.get("WIFI_KIT_SUDOERS_PATH", "/etc/sudoers.d/wifi-kit"))
UI_SERVICE_NAME = os.environ.get("WIFI_KIT_UI_SERVICE", "wifi-kit-ui.service")
BOOT_GUARD_SERVICE_NAME = os.environ.get("WIFI_KIT_BOOT_GUARD_SERVICE", "wifi-kit-boot-guard.service")
INDEX_HTML = SCRIPT_DIR / "index.html"
NORMAL_UI_PORT = 18089  # Prototype/dev local UI default; production/service target is 54321 in contract.
RECOVERY_UI_PORT = 80
RECOVERY_AP_TEST_PASSWORD = "12345678"
AP_ONLY_NM_STATE = Path("/tmp/wifi-kit-ap-only-nm-state")
RUNTIME_CONFIG_PATH = Path(
    os.environ.get("WIFI_KIT_RUNTIME_CONFIG", str(Path.home() / ".config" / "wifi-kit" / "runtime.conf"))
)
ACTION_LOG_DIR = Path(os.environ.get("WIFI_KIT_ACTION_LOG_DIR", "/tmp/wifi-kit-actions"))


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


RECONNECT_PREVIOUS_LOG = action_log_path("reconnect-previous")
CONNECT_TRANSACTION_TIMEOUT_SECONDS = 180
CONNECT_WRAPPER_ACTION = "connect-wifi"
START_AP_MODE_LOG = action_log_path("start-ap-mode")
RETURN_DEFAULT_NETWORK_LOG = action_log_path("return-default-network")
AP_RETURN_CHECK_ONCE_LOG = action_log_path("ap-return-check")
DEFAULT_NETWORK_CONNECTION = "netplan-wlan0-GL-MT6000-d53"
AP_MODE_MAX_SECONDS = 300
PRIVILEGED_ACTIONS_ENV = "WIFI_KIT_ENABLE_PRIVILEGED_ACTIONS"
AP_RECOVERY_CONFIRM = "WIFI-KIT AP RECOVERY MANUAL TEST"
CONNECT_TRANSACTION_CONFIRM = "WIFI-KIT CONNECT SAFE TRANSACTION"
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
}

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
    "/start-ap-mode": "start-ap-mode",
    "/return-default-network": "return-default-network",
    "/ap-return-check-once": "ap-return-check-once",
    "/api/ap-return-check-once": "ap-return-check-once",
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
        "path": str(RUNTIME_CONFIG_PATH),
        "password_policy": "min-8-chars",
        "secret_policy": "stores AP recovery password only; never stores client Wi-Fi passwords",
    }


def redact_public_payload(value):
    if isinstance(value, dict):
        redacted = {}
        for key, item in value.items():
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
        },
        "runtime": {
            "config_exists": RUNTIME_CONFIG_PATH.exists(),
            "config_readable": os.access(RUNTIME_CONFIG_PATH, os.R_OK),
            "ap_ssid_configured": bool(config.get("ap_ssid")),
            "last_good_configured": bool(runtime_config_value("last_good_connection") or runtime_config_value("last_good_ssid")),
        },
        "install": {
            "app_dir_exists": app_dir_exists,
            "wrapper_exists": wrapper_exists,
            "sudoers_exists": sudoers_exists,
            "ui_service_enabled": systemd_is_enabled(UI_SERVICE_NAME),
            "ui_service_active": systemd_is_active(UI_SERVICE_NAME),
            "boot_guard_enabled": systemd_is_enabled(BOOT_GUARD_SERVICE_NAME),
            "boot_guard_active": systemd_is_active(BOOT_GUARD_SERVICE_NAME),
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
    ap_confirmed = bool_payload(payload.get("ap_confirmed")) or bool_payload(payload.get("confirm"))
    action = "start-ap-mode"
    config = read_runtime_config()
    if dry_run or not privileged_actions_enabled() or not dangerous_real_apply or not ap_confirmed:
        append_action_log(
            START_AP_MODE_LOG,
            action=action,
            status="planned",
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
            "dry_run": dry_run,
            "privileged_actions_enabled": privileged_actions_enabled(),
            "dangerous_real_apply": dangerous_real_apply,
            "confirm_required": "ap_confirmed=true",
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

    append_action_log(START_AP_MODE_LOG, action=action, status="started", max_seconds=AP_MODE_MAX_SECONDS, ap_ssid=config["ap_ssid"])
    return {
        "status": "started",
        "action": action,
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
            "no",
        ],
        check=False,
        capture_output=True,
        text=True,
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


def networkmanager_scan(refresh: bool = True) -> dict:
    nmcli_bin = find_tool("nmcli") or "nmcli"
    refresh_backend = "networkmanager"
    refresh_note = ""
    if refresh:
        subprocess.run(
            [nmcli_bin, "-t", "device", "wifi", "rescan"],
            check=False,
            capture_output=True,
            text=True,
        )
        time.sleep(2.0)

    networks, error = nmcli_wifi_list(nmcli_bin)
    if refresh and len(networks) <= 1:
        ok, refresh_note = wpa_cli_refresh_scan("wlan0")
        if ok:
            refresh_backend = "networkmanager+wpa_cli"
            time.sleep(5.0)
            wpa_networks, wpa_error = nmcli_wifi_list(nmcli_bin)
            if wpa_networks:
                networks = wpa_networks
                error = ""
            elif wpa_error:
                error = wpa_error

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


def wifi_scan(refresh: bool = True) -> dict:
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
                "confirm_required": "user_confirmed=true",
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
        "normal_ui_port": NORMAL_UI_PORT,
        "recovery_ui_port": RECOVERY_UI_PORT,
        "recovery_ap_password_policy": "min-8-chars",
        "recovery_ap_password_configurable": True,
        "recovery_ap_password_set": bool(config["ap_password"]),
        "original_ssid": config["original_ssid"],
        "original_connection": config["original_connection"],
        "return_ssid": config["return_ssid"],
        "return_connection": config["return_connection"],
        "runtime_config_path": str(RUNTIME_CONFIG_PATH),
        "ui_access_password": "future-not-configured",
        "last_recovery_event": "recovery-captive-ui-validated" if recovery_active else "normal-client-mode",
    }


def ui_data(recovery: dict | None = None) -> dict:
    diagnose = safe_diagnose()
    snapshot = snapshot_preview()
    hostname = socket.gethostname() or "node"
    config = read_runtime_config()
    scan = wifi_scan(refresh=False)
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
        recovery_payload["runtime_config_path"] = str(RUNTIME_CONFIG_PATH)
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
            "ap_services_started": bool(recovery and recovery.get("active")),
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

    @property
    def recovery(self) -> dict:
        return getattr(self.server, "wifi_kit_recovery", {})

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        raw_path = parsed.path
        path = normalize_request_path(raw_path)
        log_route("post", raw_path, path)
        if path == "/wifi/connect":
            payload, status = start_recovery_wifi_connect(parse_post_payload(self), bool(self.recovery.get("active")))
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
            self.send_redirect("/recovery")
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
            runtime_actions = {"reconnect-previous", "start-ap-mode", "return-default-network", "ap-return-check-once"}
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
    return parser.parse_args()


def main() -> None:
    args = parse_args()
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
