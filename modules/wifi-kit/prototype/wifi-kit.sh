#!/bin/sh
set -eu

WIFI_KIT_STATE_ROOT="${WIFI_KIT_STATE_ROOT:-/tmp/wifi-kit-sim-state}"
WIFI_KIT_STATE_FILE="${WIFI_KIT_STATE_ROOT}/state.conf"
WIFI_KIT_KNOWN_FILE="${WIFI_KIT_STATE_ROOT}/known_networks.txt"

ui() { printf '%s\n' "$*"; }
ui_header() { printf '\n[wifi-kit] %s\n' "$*"; }

init_state_root() {
  mkdir -p "$WIFI_KIT_STATE_ROOT"
  # shell-safe simulation: local writable path by default
  chmod 700 "$WIFI_KIT_STATE_ROOT" 2>/dev/null || true
}

init_state_file() {
  if [ ! -f "$WIFI_KIT_STATE_FILE" ]; then
    cat > "$WIFI_KIT_STATE_FILE" <<'EOF'
mode=ap
last_successful_ssid=
known_networks=
last_error=
retry_count=0
EOF
  fi
}

init_known_file() {
  if [ ! -f "$WIFI_KIT_KNOWN_FILE" ]; then
    : > "$WIFI_KIT_KNOWN_FILE" 2>/dev/null || true
    chmod 600 "$WIFI_KIT_KNOWN_FILE" 2>/dev/null || true
  fi
}

load_state() {
  mode="ap"
  last_successful_ssid=""
  known_networks=""
  last_error=""
  retry_count="0"

  while IFS='=' read -r key value; do
    case "$key" in
      mode) mode="$value" ;;
      last_successful_ssid) last_successful_ssid="$value" ;;
      known_networks) known_networks="$value" ;;
      last_error) last_error="$value" ;;
      retry_count) retry_count="$value" ;;
      *) ;;
    esac
  done < "$WIFI_KIT_STATE_FILE"
}

save_state() {
  cat > "$WIFI_KIT_STATE_FILE" <<EOF
mode=$mode
last_successful_ssid=$last_successful_ssid
known_networks=$known_networks
last_error=$last_error
retry_count=$retry_count
EOF
}

is_known_ssid() {
  ssid="$1"
  if [ ! -f "$WIFI_KIT_KNOWN_FILE" ]; then
    return 1
  fi
  grep -Fq "$ssid|" "$WIFI_KIT_KNOWN_FILE"
}

timestamp_utc() {
  date -u +'%Y-%m-%dT%H:%M:%SZ'
}

list_known_networks() {
  if [ ! -f "$WIFI_KIT_KNOWN_FILE" ] || [ ! -s "$WIFI_KIT_KNOWN_FILE" ]; then
    ui "  - none (simulated)"
    return 0
  fi

  ui "  - known networks (safe metadata only)"
  while IFS='|' read -r ssid added last seen result; do
    [ -z "${ssid-}" ] && continue
    ui "    * $ssid | added=$added | last=$last | result=$result"
  done < "$WIFI_KIT_KNOWN_FILE"
}

ensure_runtime() {
  init_state_root
  init_state_file
  init_known_file
  load_state
}

cmd_status() {
  ensure_runtime
  ui_header "status"
  ui "mode=$mode"
  ui "last_successful_ssid=${last_successful_ssid:-<none>}"
  ui "last_error=${last_error:-<none>}"
  ui "retry_count=$retry_count"
  list_known_networks
}

cmd_scan() {
  ensure_runtime
  ui_header "scan (simulated)"
  ui "source: local fake scan table (no radio access, no wifi hardware calls)"
  ui "candidate networks:"
  ui "  - CafeLab (strength: good, open: no)"
  ui "  - HomeHub (strength: medium, open: no)"
  ui "  - GuestNet (strength: weak, open: yes)"
}

cmd_connect() {
  ensure_runtime
  ssid="$1"
  psk="$2"
  if [ -z "$ssid" ]; then
    ui "connect requires an SSID: connect <SSID>"
    exit 1
  fi
  mode=client
  if [ -n "$psk" ]; then
    ui "connect: credentials received for '$ssid' -> psk [REDACTED]"
  else
    ui "connect: no psk argument; continuing simulation only"
  fi

  if is_known_ssid "$ssid"; then
    last_error=""
    last_successful_ssid="$ssid"
    retry_count=0
    ui "connect result: success (simulated from known-network cache)"
  elif [ "$ssid" = "GuestNet" ]; then
    last_error="simulated association failed (simulated captive/unstable AP)"
    retry_count=$((retry_count + 1))
    mode=ap
    ui "connect result: failed (simulated)"
  else
    # deterministic but realistic V0 behavior: first attempt may still succeed
    if [ "$((retry_count % 2))" -eq 0 ]; then
      last_error=""
      last_successful_ssid="$ssid"
      retry_count=0
      ui "connect result: success (simulated new profile created)"
    else
      last_error="simulated auth timeout (no RF events observed)"
      retry_count=$((retry_count + 1))
      mode=ap
      ui "connect result: failed (simulated)"
    fi
  fi

  save_state
}

cmd_save_known_network() {
  ensure_runtime
  ssid="$1"
  if [ -z "$ssid" ]; then
    ui "save-known-network requires an SSID"
    exit 1
  fi

  if is_known_ssid "$ssid"; then
    ui "known network already present (no secret stored)"
    return 0
  fi

  now="$(timestamp_utc)"
  printf '%s|%s|%s|new\n' "$ssid" "$now" "$now" >> "$WIFI_KIT_KNOWN_FILE"
  chmod 600 "$WIFI_KIT_KNOWN_FILE" 2>/dev/null || true
  known_networks="$(printf '%s;known' "$ssid")"
  save_state
  ui "saved known network metadata only for '$ssid' (no psk)"
}

cmd_reconnect_plan() {
  ensure_runtime
  ui_header "reconnect-plan (simulated)"
  ui "input: mode=$mode, retry_count=$retry_count, last_error=${last_error:-<none>}"

  if [ "$mode" != "client" ] && [ "$mode" != "recovery" ]; then
    ui "plan: device currently in AP mode, prefer onboarding or manual trigger"
    return 0
  fi

  if [ "$retry_count" -ge 3 ]; then
    ui "plan: threshold reached -> recovery window"
    ui "  - schedule recovery mode"
    ui "  - keep AP/bootstrap for rescue"
    ui "  - rotate candidates from known networks"
    return 0
  fi

  if [ ! -f "$WIFI_KIT_KNOWN_FILE" ] || [ ! -s "$WIFI_KIT_KNOWN_FILE" ]; then
    ui "plan: no known networks => cannot auto-retry"
    return 0
  fi

  ui "plan: try known networks in this order (simulated)"
  while IFS='|' read -r ssid added last result; do
    [ -z "$ssid" ] && continue
    ui "  - $ssid (last=$last, result=$result)"
  done < "$WIFI_KIT_KNOWN_FILE"
  ui "plan: incrementally retry with backoff (simulation)"
}

cmd_recovery_plan() {
  ensure_runtime
  ui_header "recovery-plan (simulated)"
  ui "current mode: $mode"
  ui "action:"
  ui "  1) keep known networks metadata unchanged"
  ui "  2) switch to AP/bootstrap mode for manual rescue"
  ui "  3) avoid destructive operations on network config"
  ui "  4) wait for explicit re-onboarding input"
  ui "  5) record recovery attempt in state via reconnect-plan"
}

usage() {
  cat <<'EOF'
Usage:
  sh prototype/wifi-kit.sh status
  sh prototype/wifi-kit.sh scan
  sh prototype/wifi-kit.sh connect <SSID> [--psk <PSK>]
  sh prototype/wifi-kit.sh save-known-network <SSID>
  sh prototype/wifi-kit.sh reconnect-plan
  sh prototype/wifi-kit.sh recovery-plan

This is a SAFE prototype. No hostapd/dnsmasq/NetworkManager actions are executed.
EOF
}

main() {
  command="$1"
  case "$command" in
    status) cmd_status ;;
    scan) cmd_scan ;;
    connect)
      shift
      ssid="${1:-}"
      shift || true
      psk=""
      if [ "${1-}" = "--psk" ]; then
        psk="${2-}"
      fi
      cmd_connect "$ssid" "$psk"
      ;;
    save-known-network) shift; cmd_save_known_network "${1-}" ;;
    reconnect-plan) cmd_reconnect_plan ;;
    recovery-plan) cmd_recovery_plan ;;
    *) usage ;;
  esac
}

if [ "${1-}" = "--help" ] || [ -z "${1-}" ]; then
  usage
  exit 0
fi

main "$@"
