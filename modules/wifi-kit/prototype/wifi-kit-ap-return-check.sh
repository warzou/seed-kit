#!/bin/sh
set -eu

runtime_config="${WIFI_KIT_RUNTIME_CONFIG:-${HOME:-/tmp}/.config/wifi-kit/runtime.conf}"

usage() {
  cat <<'EOF'
wifi-kit AP return check prototype

Usage:
  sh modules/wifi-kit/prototype/wifi-kit-ap-return-check.sh audit
  sh modules/wifi-kit/prototype/wifi-kit-ap-return-check.sh plan

Modes:
  audit  Read runtime config and resolve the future AP return-check target.
  plan   Print the future AP recovery return-check flow. No network writes.

This helper is read-only in this lot. It does not stop AP recovery, start Wi-Fi
connect, launch hostapd/dnsmasq, call sudo, or store secrets.
EOF
}

kv() {
  printf '%s=%s\n' "$1" "$2"
}

section() {
  printf '\n[%s]\n' "$1"
}

runtime_value() {
  key=$1
  fallback=${2:-}
  if [ -r "$runtime_config" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        "$key="*)
          printf '%s\n' "${line#*=}"
          return 0
          ;;
      esac
    done < "$runtime_config"
  fi
  printf '%s\n' "$fallback"
}

is_positive_integer() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    0) return 1 ;;
    *) return 0 ;;
  esac
}

return_check_enabled() {
  runtime_value return_check_enabled false
}

return_check_interval_minutes() {
  runtime_value return_check_interval_minutes 5
}

return_check_target() {
  runtime_value return_check_target last_good_ssid
}

return_check_mode() {
  runtime_value return_check_mode periodic-from-ap
}

target_ssid_for() {
  target=$1
  case "$target" in
    last_good_ssid|last_good_connection)
      runtime_value last_good_ssid ""
      ;;
    return_ssid|return_connection)
      runtime_value return_ssid ""
      ;;
    *)
      printf ''
      ;;
  esac
}

target_connection_for() {
  target=$1
  case "$target" in
    last_good_ssid|last_good_connection)
      runtime_value last_good_connection ""
      ;;
    return_ssid|return_connection)
      runtime_value return_connection ""
      ;;
    *)
      printf ''
      ;;
  esac
}

audit_values() {
  enabled=$(return_check_enabled)
  interval=$(return_check_interval_minutes)
  target=$(return_check_target)
  mode=$(return_check_mode)
  last_good_ssid=$(runtime_value last_good_ssid "")
  last_good_connection=$(runtime_value last_good_connection "")
  return_ssid=$(runtime_value return_ssid "")
  return_connection=$(runtime_value return_connection "")
  ap_ssid=$(runtime_value ap_ssid "")
  target_ssid=$(target_ssid_for "$target")
  target_connection=$(target_connection_for "$target")
  status="ok"
  reason=""

  case "$enabled" in
    true|false) ;;
    *) status="refused"; reason="return-check-enabled-invalid" ;;
  esac
  if ! is_positive_integer "$interval"; then
    status="refused"
    reason="${reason:-return-check-interval-invalid}"
  fi
  if [ "$mode" != "periodic-from-ap" ]; then
    status="refused"
    reason="${reason:-return-check-mode-unsupported}"
  fi
  case "$target" in
    last_good_ssid|last_good_connection|return_ssid|return_connection) ;;
    *) status="refused"; reason="${reason:-return-check-target-unsupported}" ;;
  esac
  if [ "$enabled" = "true" ] && [ -z "$target_ssid" ] && [ -z "$target_connection" ]; then
    status="refused"
    reason="${reason:-target-missing}"
  fi
  if [ "$enabled" = "false" ] && [ -z "$reason" ]; then
    reason="return-check-disabled"
  fi
}

cmd_audit() {
  audit_values
  kv "status" "$status"
  kv "mode" "audit"
  kv "mutations" "false"
  kv "runtime_config" "$runtime_config"
  kv "runtime_config_readable" "$([ -r "$runtime_config" ] && printf yes || printf no)"
  kv "return_check_enabled" "$enabled"
  kv "return_check_interval_minutes" "$interval"
  kv "return_check_target" "$target"
  kv "return_check_mode" "$mode"
  kv "target_ssid" "${target_ssid:-}"
  kv "target_connection" "${target_connection:-}"
  kv "last_good_ssid" "${last_good_ssid:-}"
  kv "last_good_connection" "${last_good_connection:-}"
  kv "return_ssid" "${return_ssid:-}"
  kv "return_connection" "${return_connection:-}"
  kv "ap_ssid" "${ap_ssid:-}"
  kv "secret_policy" "no client Wi-Fi password is read, logged, or stored"
  if [ -n "$reason" ]; then
    kv "reason" "$reason"
  fi
}

cmd_plan() {
  cmd_audit
  section "ap-return-check-plan"
  kv "network_writes" "false"
  kv "ap_stop_start" "false"
  kv "wifi_connect" "false"
  kv "hostapd" "not-started"
  kv "dnsmasq" "not-started"
  kv "sudo" "not-used"
  kv "reboot" "not-used"
  kv "future_01_scope" "only from AP recovery"
  kv "future_02_wait" "sleep return_check_interval_minutes between attempts"
  kv "future_03_leave_ap" "temporarily leave AP recovery; do not use permanent AP+STA"
  kv "future_04_try_target" "try last_good or return NetworkManager connection with bounded timeout"
  kv "future_05_success" "stay normal and leave AP recovery stopped"
  kv "future_06_failure" "relaunch or remain in AP recovery"
  kv "future_07_secrets" "no Wi-Fi client password read, logged, or returned"
}

if [ "$#" -ne 1 ]; then
  usage
  exit 2
fi

case "$1" in
  audit) cmd_audit ;;
  plan) cmd_plan ;;
  -h|--help|help) usage ;;
  *) usage; exit 2 ;;
esac
