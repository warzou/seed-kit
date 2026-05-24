#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
action_wrapper="$script_dir/wifi-kit-action-wrapper.sh"
iface="${WIFI_KIT_BOOT_GUARD_IFACE:-wlan0}"
internet_probe="${WIFI_KIT_BOOT_GUARD_PROBE:-1.1.1.1}"
connect_wait_seconds="${WIFI_KIT_BOOT_GUARD_CONNECT_WAIT:-25}"
ping_wait_seconds="${WIFI_KIT_BOOT_GUARD_PING_WAIT:-3}"
log_file="${WIFI_KIT_BOOT_GUARD_LOG:-/tmp/wifi-kit-actions/boot-guard-$(id -u).log}"
runtime_config="${WIFI_KIT_RUNTIME_CONFIG:-}"

usage() {
  cat <<'EOF'
wifi-kit minimal boot guard prototype

Usage:
  sh modules/wifi-kit/prototype/wifi-kit-boot-guard.sh audit
  sh modules/wifi-kit/prototype/wifi-kit-boot-guard.sh plan
  sh modules/wifi-kit/prototype/wifi-kit-boot-guard.sh run

Modes:
  audit  Read tools, runtime config, active Wi-Fi, and candidate profiles only.
  plan   Print the bounded startup decision tree. No network writes.
  run    Try last_good_connection with Internet validation, then return_connection
         for LAN reachability, then start AP mode through the existing wrapper.
EOF
}

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

kv() {
  printf '%s=%s\n' "$1" "$2"
}

section() {
  printf '\n[%s]\n' "$1"
}

find_tool() {
  command -v "$1" 2>/dev/null || true
}

default_runtime_config_path() {
  if [ -n "$runtime_config" ]; then
    printf '%s\n' "$runtime_config"
    return 0
  fi
  if [ -r "/etc/seed-kit/wifi-kit/runtime.conf" ]; then
    printf '%s\n' "/etc/seed-kit/wifi-kit/runtime.conf"
    return 0
  fi
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    sudo_home=$(getent passwd "$SUDO_USER" 2>/dev/null | awk -F: '{ print $6 }' | sed -n '1p')
    if [ -n "$sudo_home" ]; then
      printf '%s\n' "$sudo_home/.config/wifi-kit/runtime.conf"
      return 0
    fi
  fi
  printf '%s\n' "${HOME:-/tmp}/.config/wifi-kit/runtime.conf"
}

runtime_config=$(default_runtime_config_path)
export WIFI_KIT_RUNTIME_CONFIG="$runtime_config"

runtime_value() {
  key=$1
  fallback=${2:-}
  if [ -r "$runtime_config" ]; then
    value=$(sed -n "s/^$key=//p" "$runtime_config" 2>/dev/null | sed -n '1p' || true)
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return 0
    fi
  fi
  printf '%s\n' "$fallback"
}

safe_line_value() {
  key=$1
  value=$2
  cr=$(printf '\r')
  case "$value" in
    *"
"*|*"$cr"*) kv "$key" "refused-newline"; exit 2 ;;
  esac
}

ensure_log_parent() {
  log_dir=$(dirname -- "$log_file")
  mkdir -p "$log_dir" 2>/dev/null || true
  chmod 1777 "$log_dir" 2>/dev/null || true
}

log_event() {
  ensure_log_parent
  {
    printf 'timestamp=%s action=boot-guard status=%s' "$(timestamp)" "$1"
    if [ "${2:-}" ]; then
      printf ' detail=%s' "$2"
    fi
    printf '\n'
  } >> "$log_file" 2>/dev/null || true
}

active_connection() {
  nmcli_bin=$(find_tool nmcli)
  [ -n "$nmcli_bin" ] || return 0
  "$nmcli_bin" -t -f DEVICE,CONNECTION device status 2>/dev/null |
    awk -F: -v iface="$iface" '$1 == iface { print $2; exit }'
}

connection_ssid() {
  connection=$1
  nmcli_bin=$(find_tool nmcli)
  [ -n "$nmcli_bin" ] || return 0
  [ -n "$connection" ] || return 0
  "$nmcli_bin" -g 802-11-wireless.ssid connection show "$connection" 2>/dev/null | sed -n '1p' || true
}

connection_exists() {
  connection=$1
  nmcli_bin=$(find_tool nmcli)
  [ -n "$nmcli_bin" ] || return 1
  [ -n "$connection" ] || return 1
  "$nmcli_bin" connection show "$connection" >/dev/null 2>&1
}

has_default_route() {
  ip_bin=$(find_tool ip)
  [ -n "$ip_bin" ] || return 1
  "$ip_bin" route show default 2>/dev/null | grep -q .
}

internet_ok() {
  ping_bin=$(find_tool ping)
  [ -n "$ping_bin" ] || return 1
  has_default_route || return 1
  "$ping_bin" -c 1 -W "$ping_wait_seconds" "$internet_probe" >/dev/null 2>&1
}

write_runtime_value() {
  key=$1
  value=$2
  safe_line_value "$key" "$value"
  config_dir=$(dirname -- "$runtime_config")
  mkdir -p "$config_dir"
  chmod 700 "$config_dir" 2>/dev/null || true
  if [ ! -f "$runtime_config" ]; then
    {
      printf '# Wifi-Kit prototype runtime config\n'
      printf '# Stores AP recovery password only; never stores client Wi-Fi passwords.\n'
    } > "$runtime_config"
  fi
  tmp="${runtime_config}.$$"
  awk -v key="$key" -v value="$value" '
    BEGIN { done = 0 }
    $0 ~ "^" key "=" { print key "=" value; done = 1; next }
    { print }
    END { if (!done) print key "=" value }
  ' "$runtime_config" > "$tmp"
  install -m 600 "$tmp" "$runtime_config"
  rm -f "$tmp"
}

save_last_good() {
  connection=$1
  ssid=$2
  [ -n "$connection" ] || return 0
  write_runtime_value last_good_connection "$connection"
  if [ -n "$ssid" ]; then
    write_runtime_value last_good_ssid "$ssid"
  fi
}

try_connection() {
  label=$1
  connection=$2
  require_internet=$3
  nmcli_bin=$(find_tool nmcli)
  [ -n "$nmcli_bin" ] || { kv "${label}_status" "nmcli-missing"; return 1; }
  [ -n "$connection" ] || { kv "${label}_status" "missing"; return 1; }
  connection_exists "$connection" || { kv "${label}_status" "profile-missing"; return 1; }

  kv "${label}_connection" "$connection"
  log_event "try-$label" "connection=$connection"
  if "$nmcli_bin" --wait "$connect_wait_seconds" connection up "$connection" ifname "$iface" >/dev/null 2>&1; then
    kv "${label}_nmcli" "connected"
  else
    kv "${label}_nmcli" "failed"
    log_event "failed-$label" "nmcli-up-failed"
    return 1
  fi

  if [ "$require_internet" = "yes" ]; then
    if internet_ok; then
      kv "${label}_internet" "ok"
      save_last_good "$connection" "$(connection_ssid "$connection")"
      log_event "success-$label" "internet-ok"
      return 0
    fi
    kv "${label}_internet" "failed"
    log_event "failed-$label" "internet-failed"
    return 1
  fi

  if internet_ok; then
    kv "${label}_internet" "ok"
    last_good_ssid=$(connection_ssid "$connection")
    if [ -z "$last_good_ssid" ] && [ "$label" = "return" ]; then
      last_good_ssid=$(runtime_value return_ssid "$(runtime_value default_ssid "")")
    fi
    save_last_good "$connection" "$last_good_ssid"
    if [ "$label" = "return" ]; then
      kv "return_last_good_persisted" "yes"
    else
      kv "${label}_last_good_persisted" "yes"
    fi
    log_event "success-$label" "internet-ok-last-good-saved"
  else
    kv "${label}_internet" "failed"
    if [ "$label" = "return" ]; then
      kv "return_last_good_persisted" "no"
    else
      kv "${label}_last_good_persisted" "no"
    fi
    log_event "success-$label" "lan-profile-connected-internet-failed"
  fi
  return 0
}

cmd_audit() {
  section "boot-guard-audit"
  kv "mode" "audit"
  kv "network_writes" "false"
  kv "runtime_config" "$runtime_config"
  kv "runtime_config_readable" "$([ -r "$runtime_config" ] && printf yes || printf no)"
  kv "iface" "$iface"
  kv "active_connection" "$(active_connection)"
  kv "last_good_connection" "$(runtime_value last_good_connection "")"
  kv "last_good_ssid" "$(runtime_value last_good_ssid "")"
  kv "return_connection" "$(runtime_value return_connection "$(runtime_value default_connection "")")"
  kv "return_ssid" "$(runtime_value return_ssid "$(runtime_value default_ssid "")")"
  kv "internet_probe" "$internet_probe"
  kv "connect_wait_seconds" "$connect_wait_seconds"
  kv "ping_wait_seconds" "$ping_wait_seconds"
  kv "nmcli" "$(find_tool nmcli)"
  kv "ip" "$(find_tool ip)"
  kv "ping" "$(find_tool ping)"
  kv "action_wrapper" "$action_wrapper"
  kv "action_wrapper_present" "$([ -f "$action_wrapper" ] && printf yes || printf no)"
  kv "log_file" "$log_file"
}

cmd_plan() {
  cmd_audit
  section "boot-guard-plan"
  kv "01.try_last_good" "nmcli --wait $connect_wait_seconds connection up <last_good_connection> if present; validate default route plus ping $internet_probe"
  kv "02.persist_last_good" "after Internet success only: write last_good_connection and last_good_ssid"
  kv "03.try_return_connection" "if last_good missing/failed, nmcli --wait $connect_wait_seconds connection up <return_connection>; LAN-only success is accepted, and saved as last_good only when route plus ping $internet_probe succeed"
  kv "04.start_ap_mode" "if both Wi-Fi attempts fail, run existing wrapper start-ap-mode"
  kv "05.ap_policy" "AP remains active until explicit return-default-network"
  kv "criteria_not_checked" "DNS resolution, sshd health"
  kv "forbidden" "delete profiles, store client Wi-Fi passwords, reboot, loop forever"
}

cmd_run() {
  section "boot-guard-run"
  kv "mode" "run"
  kv "runtime_config" "$runtime_config"
  kv "iface" "$iface"
  kv "log_file" "$log_file"

  last_good_connection=$(runtime_value last_good_connection "")
  return_connection=$(runtime_value return_connection "$(runtime_value default_connection "")")

  if try_connection "last_good" "$last_good_connection" "yes"; then
    kv "decision" "normal-last-good"
    exit 0
  fi

  if try_connection "return" "$return_connection" "no"; then
    kv "decision" "normal-return-connection"
    exit 0
  fi

  kv "decision" "start-ap-mode"
  log_event "start-ap-mode" "wifi-attempts-failed"
  if [ ! -f "$action_wrapper" ]; then
    kv "ap_status" "wrapper-missing"
    exit 1
  fi
  exec sh "$action_wrapper" start-ap-mode
}

if [ "$#" -ne 1 ]; then
  usage
  exit 2
fi

case "$1" in
  audit) cmd_audit ;;
  plan) cmd_plan ;;
  run) cmd_run ;;
  -h|--help|help) usage ;;
  *) usage; exit 2 ;;
esac
