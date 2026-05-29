#!/bin/sh
set -eu

runtime_config="${WIFI_KIT_RUNTIME_CONFIG:-${HOME:-/tmp}/.config/wifi-kit/runtime.conf}"
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
action_wrapper="$script_dir/wifi-kit-action-wrapper.sh"
iface="${WIFI_KIT_NODE_IP_IFACE:-wlan0}"
state_file="${WIFI_KIT_NODE_IP_STATE:-/tmp/wifi-kit-node-ip-test.state}"
log_file="${WIFI_KIT_NODE_IP_LOG:-/tmp/wifi-kit-actions/node-ip-transaction-$(id -u).log}"
validation_seconds="${WIFI_KIT_NODE_IP_VALIDATION_SECONDS:-120}"
transaction_id="${WIFI_KIT_NODE_IP_TRANSACTION_ID:-}"

timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

kv() {
  printf '%s=%s\n' "$1" "$2"
}

log_event() {
  event=$1
  shift || true
  mkdir -p /tmp/wifi-kit-actions 2>/dev/null || true
  line="timestamp=$(timestamp) event=$event"
  for item in "$@"; do
    line="$line $item"
  done
  printf '%s\n' "$line" >> "$log_file" 2>/dev/null || true
}

runtime_value() {
  key=$1
  fallback=${2:-}
  if [ -r "$runtime_config" ]; then
    value=$(sed -n "s/^$key=//p" "$runtime_config" 2>/dev/null | sed -n '1p' || true)
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
    else
      printf '%s\n' "$fallback"
    fi
  else
    printf '%s\n' "$fallback"
  fi
}

find_tool() {
  tool=$1
  if [ -n "${WIFI_KIT_STATIC_IP_NMCLI:-}" ] && [ "$tool" = "nmcli" ]; then
    printf '%s\n' "$WIFI_KIT_STATIC_IP_NMCLI"
    return 0
  fi
  command -v "$tool" 2>/dev/null || {
    for dir in /usr/sbin /sbin /usr/bin /bin; do
      [ -x "$dir/$tool" ] && { printf '%s\n' "$dir/$tool"; return 0; }
    done
    return 1
  }
}

active_connection() {
  nmcli=$1
  "$nmcli" -t --escape no -f DEVICE,CONNECTION device status 2>/dev/null |
    awk -F: -v iface="$iface" '$1 == iface { print $2; exit }'
}

current_ipv4() {
  ip_bin=$(find_tool ip 2>/dev/null || true)
  [ -n "$ip_bin" ] || return 0
  "$ip_bin" -o -4 addr show dev "$iface" 2>/dev/null | awk '{ print $4; exit }'
}

profile_value() {
  nmcli=$1
  connection=$2
  field=$3
  "$nmcli" -g "$field" connection show "$connection" 2>/dev/null | paste -sd, - || true
}

safe_value() {
  value=$1
  cr=$(printf '\r')
  case "$value" in
    *"$cr"*|*'
'*) return 1 ;;
  esac
  return 0
}

validate_config() {
  node_ip_mode=$(runtime_value node_ip_mode dhcp)
  static_ip=$(runtime_value node_static_ip "")
  static_gateway=$(runtime_value node_static_gateway "")
  static_dns=$(runtime_value node_static_dns "")
  [ "$node_ip_mode" = "static" ] || { kv status refused; kv reason static-mode-required; exit 2; }
  [ -n "$static_ip" ] || { kv status refused; kv reason static-ip-required; exit 2; }
  case "$static_ip" in */*) ;; *) kv status refused; kv reason static-ip-cidr-required; exit 2 ;; esac
  [ -n "$static_gateway" ] || { kv status refused; kv reason static-gateway-required; exit 2; }
  safe_value "$static_ip" && safe_value "$static_gateway" && safe_value "$static_dns" || {
    kv status refused
    kv reason newline-not-allowed
    exit 2
  }
}

write_state() {
  transaction_id="$(date -u '+%Y%m%d%H%M%S')-$$"
  mkdir -p "$(dirname -- "$state_file")" 2>/dev/null || true
  {
    kv timestamp "$(timestamp)"
    kv transaction_id "$transaction_id"
    kv state testing
    kv iface "$iface"
    kv connection "$connection"
    kv previous_method "$previous_method"
    kv previous_addresses "$previous_addresses"
    kv previous_gateway "$previous_gateway"
    kv previous_dns "$previous_dns"
    kv static_ip "$static_ip"
    kv static_gateway "$static_gateway"
    kv static_dns "$static_dns"
    kv validation_seconds "$validation_seconds"
    kv confirmed no
    kv log_file "$log_file"
  } > "$state_file"
  chmod 0600 "$state_file" 2>/dev/null || true
}

state_value() {
  key=$1
  [ -r "$state_file" ] || return 0
  sed -n "s/^$key=//p" "$state_file" 2>/dev/null | sed -n '1p'
}

cancel_rollback_guard() {
  guard_unit=$(state_value guard_unit)
  guard_pid=$(state_value guard_pid)
  if [ -n "$guard_unit" ]; then
    systemctl stop "$guard_unit.timer" "$guard_unit.service" >/dev/null 2>&1 || true
    log_event "static-ip-rollback-guard-cancelled" "type=systemd-run unit=$guard_unit"
  fi
  if [ -n "$guard_pid" ]; then
    kill "$guard_pid" >/dev/null 2>&1 || true
    log_event "static-ip-rollback-guard-cancelled" "type=background-sleep pid=$guard_pid"
  fi
}

restore_previous_profile() {
  nmcli=$1
  connection=$(state_value connection)
  previous_method=$(state_value previous_method)
  previous_addresses=$(state_value previous_addresses)
  previous_gateway=$(state_value previous_gateway)
  previous_dns=$(state_value previous_dns)
  [ -n "$connection" ] || return 1
  [ -n "$previous_method" ] || previous_method=auto
  if [ "$previous_method" = "auto" ] || [ "$previous_method" = "disabled" ]; then
    "$nmcli" connection modify "$connection" ipv4.method auto ipv4.addresses "" ipv4.gateway "" ipv4.dns ""
  else
    "$nmcli" connection modify "$connection" ipv4.method "$previous_method" ipv4.addresses "$previous_addresses" ipv4.gateway "$previous_gateway" ipv4.dns "$previous_dns"
  fi
  "$nmcli" --wait 30 connection up "$connection" ifname "$iface"
}

rollback_active_device() {
  nmcli=$1
  "$nmcli" device reapply "$iface" 2>/dev/null || restore_previous_profile "$nmcli"
}

apply_static_temporarily() {
  nmcli=$1
  "$nmcli" device modify "$iface" ipv4.method manual ipv4.addresses "$static_ip" ipv4.gateway "$static_gateway" ipv4.dns "$static_dns"
}

persist_static_profile() {
  nmcli=$1
  connection=$(state_value connection)
  static_ip=$(state_value static_ip)
  static_gateway=$(state_value static_gateway)
  static_dns=$(state_value static_dns)
  [ -n "$connection" ] || return 1
  [ -n "$static_ip" ] || return 1
  [ -n "$static_gateway" ] || return 1
  "$nmcli" connection modify "$connection" ipv4.method manual ipv4.addresses "$static_ip" ipv4.gateway "$static_gateway" ipv4.dns "$static_dns" connection.autoconnect yes
}

start_rollback_guard() {
  systemd_run=$(find_tool systemd-run 2>/dev/null || true)
  if [ -n "$systemd_run" ]; then
    unit="wifi-kit-node-ip-rollback-$(date -u '+%Y%m%d%H%M%S')-$$"
    if "$systemd_run" \
      --quiet \
      --unit="$unit" \
      --on-active="${validation_seconds}s" \
      --property=Type=oneshot \
      --setenv=WIFI_KIT_NODE_IP_STATE="$state_file" \
      --setenv=WIFI_KIT_RUNTIME_CONFIG="$runtime_config" \
      --setenv=WIFI_KIT_NODE_IP_LOG="$log_file" \
      --setenv=WIFI_KIT_NODE_IP_TRANSACTION_ID="$transaction_id" \
      /bin/sh "$script_dir/wifi-kit-node-ip-transaction.sh" rollback >/dev/null 2>&1; then
      printf 'guard_unit=%s\n' "$unit" >> "$state_file" 2>/dev/null || true
      log_event "static-ip-rollback-guard-started" "type=systemd-run unit=$unit validation_seconds=$validation_seconds"
      return 0
    fi
  fi
  (
    sleep "$validation_seconds"
    WIFI_KIT_NODE_IP_STATE="$state_file" WIFI_KIT_RUNTIME_CONFIG="$runtime_config" WIFI_KIT_NODE_IP_LOG="$log_file" WIFI_KIT_NODE_IP_TRANSACTION_ID="$transaction_id" sh "$script_dir/wifi-kit-node-ip-transaction.sh" rollback >> "$log_file" 2>&1
  ) >/dev/null 2>&1 &
  guard_pid=$!
  printf 'guard_pid=%s\n' "$guard_pid" >> "$state_file" 2>/dev/null || true
  log_event "static-ip-rollback-guard-started" "type=background-sleep pid=$guard_pid validation_seconds=$validation_seconds"
}

start_ap_fallback() {
  [ -x "$action_wrapper" ] || return 0
  log_event "static-ip-ap-fallback" "reason=rollback-failed"
  WIFI_KIT_RUNTIME_CONFIG="$runtime_config" sh "$action_wrapper" start-ap-mode >> "$log_file" 2>&1 || true
}

cmd_test() {
  validate_config
  nmcli=$(find_tool nmcli 2>/dev/null || true)
  [ -n "$nmcli" ] || { kv status failure; kv reason nmcli-missing; exit 1; }
  connection=$(active_connection "$nmcli")
  [ -n "$connection" ] || { kv status refused; kv reason active-connection-required; exit 2; }
  previous_method=$(profile_value "$nmcli" "$connection" ipv4.method)
  previous_addresses=$(profile_value "$nmcli" "$connection" ipv4.addresses)
  previous_gateway=$(profile_value "$nmcli" "$connection" ipv4.gateway)
  previous_dns=$(profile_value "$nmcli" "$connection" ipv4.dns)
  write_state
  log_event "static-ip-test-started" "connection=$connection static_ip=$static_ip static_gateway=$static_gateway validation_seconds=$validation_seconds mode=temporary-device"
  start_rollback_guard
  apply_static_temporarily "$nmcli"
  kv status testing
  kv action node-ip-test
  kv connection "$connection"
  kv static_ip "$static_ip"
  kv static_gateway "$static_gateway"
  kv validation_seconds "$validation_seconds"
  kv current_ip "$(current_ipv4)"
  kv log "$log_file"
}

cmd_confirm() {
  [ -r "$state_file" ] || { kv status refused; kv reason no-pending-test; exit 2; }
  nmcli=$(find_tool nmcli 2>/dev/null || true)
  [ -n "$nmcli" ] || { kv status failure; kv reason nmcli-missing; exit 1; }
  persist_static_profile "$nmcli" >> "$log_file" 2>&1 || { kv status failure; kv reason persist-static-failed; exit 1; }
  cancel_rollback_guard
  sed 's/^confirmed=.*/confirmed=yes/' "$state_file" > "$state_file.$$"
  mv "$state_file.$$" "$state_file"
  log_event "static-ip-confirmed" "connection=$(state_value connection) static_ip=$(state_value static_ip)"
  kv status success
  kv action node-ip-confirm
  kv static_ip "$(state_value static_ip)"
  kv log "$log_file"
}

cmd_rollback() {
  [ -r "$state_file" ] || { kv status skipped; kv reason no-pending-test; exit 0; }
  state_transaction_id=$(state_value transaction_id)
  if [ -n "$transaction_id" ] && [ -n "$state_transaction_id" ] && [ "$transaction_id" != "$state_transaction_id" ]; then
    log_event "static-ip-rollback-skipped" "reason=stale-guard transaction_id=$transaction_id state_transaction_id=$state_transaction_id"
    kv status skipped
    kv reason stale-guard
    exit 0
  fi
  if [ "$(state_value confirmed)" = "yes" ]; then
    log_event "static-ip-rollback-skipped" "reason=confirmed"
    kv status skipped
    kv reason confirmed
    exit 0
  fi
  nmcli=$(find_tool nmcli 2>/dev/null || true)
  [ -n "$nmcli" ] || { kv status failure; kv reason nmcli-missing; start_ap_fallback; exit 1; }
  cancel_rollback_guard
  log_event "static-ip-rollback-started" "connection=$(state_value connection)"
  if rollback_active_device "$nmcli" >> "$log_file" 2>&1; then
    log_event "static-ip-rollback-success" "connection=$(state_value connection)"
    kv status rolled-back
    kv action node-ip-rollback
    kv log "$log_file"
    exit 0
  fi
  log_event "static-ip-rollback-failed" "connection=$(state_value connection)"
  start_ap_fallback
  kv status failure
  kv action node-ip-rollback
  kv reason rollback-failed-ap-fallback-started
  kv log "$log_file"
  exit 1
}

cmd_status() {
  if [ -r "$state_file" ]; then
    cat "$state_file"
  else
    kv state none
  fi
}

case "${1:-}" in
  test) cmd_test ;;
  confirm) cmd_confirm ;;
  rollback) cmd_rollback ;;
  status) cmd_status ;;
  *) kv status refused; kv reason "usage: test|confirm|rollback|status"; exit 2 ;;
esac
