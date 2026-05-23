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


RECONNECT_PREVIOUS_LOG = action_log_path("reconnect-previous")
CONNECT_TRANSACTION_LOG = action_log_path("connect-transaction-ui")
CONNECT_TRANSACTION_TIMEOUT_SECONDS = 180
CONNECT_WRAPPER_ACTION = "connect-wifi"
START_AP_MODE_LOG = action_log_path("start-ap-mode")
RETURN_DEFAULT_NETWORK_LOG = action_log_path("return-default-network")
DEFAULT_NETWORK_CONNECTION = "netplan-wlan0-GL-MT6000-d53"
AP_MODE_MAX_SECONDS = 300
PRIVILEGED_ACTIONS_ENV = "WIFI_KIT_ENABLE_PRIVILEGED_ACTIONS"
AP_RECOVERY_CONFIRM = "WIFI-KIT AP RECOVERY MANUAL TEST"
CONNECT_TRANSACTION_CONFIRM = "WIFI-KIT CONNECT SAFE TRANSACTION"
SAVED_NM_SECRET_SENTINEL = "__WIFI_KIT_USE_SAVED_NM_SECRET__"
RUNTIME_CONFIG_KEYS = {
    "original_ssid",
    "original_connection",
    "return_ssid",
    "return_connection",
    "default_ssid",
    "default_connection",
    "ap_ssid",
    "ap_password",
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
    "/exit-recovery": "exit-recovery",
    "/reboot-recovery": "reboot-recovery",
    "/set-recovery-password": "set-recovery-password",
}


def run_json_command(args: list[str]) -> dict:
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
        "ap_ssid": f"Wifi-Kit-{hostname}",
        "ap_password": os.environ.get("WIFI_KIT_AP_PSK", RECOVERY_AP_TEST_PASSWORD),
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


def public_runtime_config() -> dict[str, object]:
    config = read_runtime_config()
    return {
        "original_ssid": config["original_ssid"],
        "original_connection": config["original_connection"],
        "return_ssid": config["return_ssid"],
        "return_connection": config["return_connection"],
        "ap_ssid": config["ap_ssid"],
        "ap_password": config["ap_password"],
        "path": str(RUNTIME_CONFIG_PATH),
        "password_policy": "min-8-chars",
        "secret_policy": "stores AP recovery password only; never stores client Wi-Fi passwords",
    }


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
        f"ap_ssid={config['ap_ssid']}",
        f"ap_password={config['ap_password']}",
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
    return path.open("a", encoding="utf-8")


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


def action_wrapper_path() -> Path:
    return INSTALLED_ACTION_WRAPPER_SH if INSTALLED_ACTION_WRAPPER_SH.exists() else ACTION_WRAPPER_SH


def privileged_action_command(action: str) -> tuple[list[str], str]:
    wrapper_path = action_wrapper_path()
    if not wrapper_path.exists():
        return [], "wrapper-missing"
    wrapper_command = [str(wrapper_path), action]
    if os.geteuid() == 0:
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
    if os.geteuid() == 0:
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


def safe_diagnose() -> dict:
    return run_json_command(["safe-diagnose", "--json"])


def scan(refresh: bool = False) -> dict:
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


def start_recovery_wifi_connect(payload: dict, recovery_active: bool) -> tuple[dict, int]:
    if payload.get("_error"):
        return {"status": "failure", "error": payload["_error"], "connect_started": False}, 400

    ssid = str(payload.get("ssid", "")).strip()
    password = str(payload.get("password", ""))
    known_profile = str(payload.get("known_profile", "")).strip()
    security = str(payload.get("security", "")).strip()
    dangerous_real_apply = bool_payload(payload.get("dangerous_real_apply"))
    confirm = str(payload.get("confirm", ""))
    use_saved_nm_secret = password == SAVED_NM_SECRET_SENTINEL
    known_connection = known_connection_for_ssid(ssid, known_profile) if use_saved_nm_secret else None
    existing_connection = str(known_connection.get("profile", "")) if known_connection else ""
    if not ssid:
        return {"status": "failure", "error": "missing-ssid", "connect_started": False}, 400
    if len(ssid.encode("utf-8")) > 32:
        return {"status": "failure", "error": "ssid-too-long", "connect_started": False}, 400
    if use_saved_nm_secret and not existing_connection:
        return {"status": "failure", "error": "known-profile-not-found", "connect_started": False}, 400
    if security_requires_password(security) and not password and not existing_connection:
        return {"status": "failure", "error": "missing-password", "connect_started": False}, 400
    if password and not use_saved_nm_secret and len(password) < 8:
        return {"status": "failure", "error": "password-too-short", "connect_started": False}, 400

    backend = "raspberrypi-networkmanager" if networkmanager_owns_wlan0() else "unknown"
    secret_policy = (
        "saved NetworkManager profile requested by sentinel; no secret was read, returned, or logged"
        if existing_connection
        else "runtime-only; password was not logged or persisted"
    )
    connect_plan = [
        "require AP recovery context",
        "require WIFI_KIT_ENABLE_PRIVILEGED_ACTIONS=1",
        "require exact confirmation phrase",
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
        not recovery_active
        or not privileged_actions_enabled()
        or not dangerous_real_apply
        or confirm != CONNECT_TRANSACTION_CONFIRM
    ):
        return (
            {
                "status": "planned",
                "mutation": "not-started",
                "error": "safe-gates-not-satisfied",
                "requested_ssid": ssid,
                "backend": backend,
                "connect_started": False,
                "recovery_active": recovery_active,
                "privileged_actions_enabled": privileged_actions_enabled(),
                "dangerous_real_apply": dangerous_real_apply,
                "confirm_required": CONNECT_TRANSACTION_CONFIRM,
                "confirm_ok": confirm == CONNECT_TRANSACTION_CONFIRM,
                "secret_policy": secret_policy,
                "existing_connection": existing_connection,
                "warning_if_recovery_active": "Real Wi-Fi connect requires AP recovery context, privileged actions, and exact confirmation.",
                "connect_plan": connect_plan,
            },
            409,
        )

    command, error = privileged_connect_transaction_command()
    if error:
        payload = privileged_error_response("wifi-connect-transaction", error)
        payload.update(
            {
                "requested_ssid": ssid,
                "backend": backend,
                "connect_started": False,
            }
        )
        return payload, 403 if error == "wifi-kit-network-rights-not-installed" else 500

    try:
        process = subprocess.Popen(
            command,
            cwd=str(SCRIPT_DIR.parent),
            stdin=subprocess.PIPE,
            stdout=open_action_log(CONNECT_TRANSACTION_LOG),
            stderr=subprocess.STDOUT,
            start_new_session=True,
            text=True,
        )
        assert process.stdin is not None
        process.stdin.write(f"ssid={ssid}\n")
        process.stdin.write(f"confirm={CONNECT_TRANSACTION_CONFIRM}\n")
        process.stdin.write("dangerous_real_apply=true\n")
        process.stdin.write(f"timeout_seconds={CONNECT_TRANSACTION_TIMEOUT_SECONDS}\n")
        if existing_connection:
            process.stdin.write(f"existing_connection={existing_connection}\n")
        else:
            process.stdin.write(f"password={password}\n")
        process.stdin.close()
    except (OSError, BrokenPipeError) as exc:
        return {
            "status": "failure",
            "error": f"start-failed: {exc}",
            "requested_ssid": ssid,
            "backend": backend,
            "connect_started": False,
        }, 500

    return (
        {
            "status": "started",
            "action": "wifi-connect-transaction",
            "requested_ssid": ssid,
            "backend": backend,
            "connect_started": True,
            "existing_connection": existing_connection,
            "timeout_seconds": CONNECT_TRANSACTION_TIMEOUT_SECONDS,
            "expected_behavior": "success-keeps-target-failure-rolls-back-rollback-failure-starts-ap-recovery",
            "secret_policy": (
                "existing NetworkManager profile selected by sentinel; no secret was read, returned, or logged"
                if existing_connection
                else "runtime-only; password is passed on stdin and never returned or logged"
            ),
            "log": str(CONNECT_TRANSACTION_LOG),
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
        "recovery_ap_password_current": config["ap_password"],
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
        "actions": "plan-only",
        "normal_ui_port": NORMAL_UI_PORT,
        "recovery_ui_port": RECOVERY_UI_PORT,
        "ap_password_policy": "min-8-chars",
        "ap_password_configurable": True,
        "ap_password_current": config["ap_password"],
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
        recovery_payload["ap_password_current"] = config["ap_password"]
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
            "source": "state-snapshot --simulate --json",
            "data": snapshot,
        },
        "connect_options": {
            "apply_endpoint": "not-implemented",
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
            payload, status = start_recovery_wifi_connect(parse_post_payload(self), bool(self.recovery.get("active")))
            self.send_json(payload, status=status)
            return

        if parsed.path == "/start-ap-mode":
            payload, status = start_ap_mode(parse_post_payload(self))
            self.send_json(payload, status=status)
            return

        if parsed.path == "/return-default-network":
            payload, status = return_default_network(parse_post_payload(self))
            self.send_json(payload, status=status)
            return

        if parsed.path == "/api/runtime-config":
            payload, status = update_runtime_config(parse_post_payload(self))
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

        if path == "/api/runtime-config":
            self.send_json(public_runtime_config())
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
        "actions": "plan-only",
        "normal_ui_port": NORMAL_UI_PORT,
        "recovery_ui_port": RECOVERY_UI_PORT,
        "ap_password_policy": "min-8-chars",
        "ap_password_configurable": True,
        "ap_password_current": config["ap_password"],
        "original_ssid": config["original_ssid"],
        "original_connection": config["original_connection"],
        "return_ssid": config["return_ssid"],
        "return_connection": config["return_connection"],
        "runtime_config_path": str(RUNTIME_CONFIG_PATH),
        "ui_access_password": "future-not-configured",
        "action_endpoints": sorted(ACTION_PATHS.keys()),
    }
    print(f"wifi-kit read-only HTTP on http://{args.host}:{args.port}")
    print("GET read-only; POST actions: /reconnect-previous, /start-ap-mode, /return-default-network")
    server.serve_forever()


if __name__ == "__main__":
    main()
