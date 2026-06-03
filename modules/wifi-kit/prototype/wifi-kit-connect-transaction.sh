#!/bin/sh
set -eu

# EXPERIMENTAL PROTOTYPE ONLY.
# This script is not a stable Wifi-Kit feature. The apply mode can disconnect
# the current SSH session and must only be used during a controlled test window.

mode=""
iface="wlan0"
target_ssid=""
existing_connection=""
confirm_phrase=""
dangerous_real_apply="0"
tx_timeout_seconds="180"
rollback_timeout_seconds="90"
internet_probe="1.1.1.1"
dns_probe="example.com"
log_file=""
state_file=""
ui_log_file="${WIFI_KIT_CONNECT_UI_LOG:-}"
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
action_wrapper="$script_dir/wifi-kit-action-wrapper.sh"
runtime_config="${WIFI_KIT_RUNTIME_CONFIG:-}"

usage() {
  cat <<'EOF'
wifi-kit connect transaction prototype
EXPERIMENTAL: apply can disconnect SSH and is only for controlled test windows.

One guarded transaction for changing Wi-Fi with rollback and AP recovery
fallback. Passwords are read from stdin only and are never logged.

Usage:
  sh modules/wifi-kit/prototype/wifi-kit-connect-transaction.sh audit
  sh modules/wifi-kit/prototype/wifi-kit-connect-transaction.sh plan --ssid "<SSID>"
  printf '%s\n' "$RUNTIME_PASSWORD" | \
    sudo sh modules/wifi-kit/prototype/wifi-kit-connect-transaction.sh apply \
      --ssid "<SSID>" \
      --dangerous-real-apply \
      --confirm "WIFI-KIT CONNECT SAFE TRANSACTION"
  sudo sh modules/wifi-kit/prototype/wifi-kit-connect-transaction.sh apply \
      --ssid "<SSID>" \
      --existing-connection "<NetworkManager profile>" \
      --dangerous-real-apply \
      --confirm "WIFI-KIT CONNECT SAFE TRANSACTION"
EOF
}

fail() {
  log_event "failure" "error=$1"
  state_set "status" "failure"
  state_set "error" "$1"
  printf 'error: %s\n' "$1" >&2
  exit 1
}

quote() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/^/"/; s/$/"/'
}

timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

safe_ui_log_path() {
  path=$1
  case "$path" in
    /tmp/wifi-kit-actions/*.log)
      base=${path##*/}
      [ "$path" = "/tmp/wifi-kit-actions/$base" ] || return 1
      [ -n "$base" ] || return 1
      ;;
    *)
      return 1
      ;;
  esac
}

prepare_ui_log() {
  path=$1
  safe_ui_log_path "$path" || return 1
  mkdir -p /tmp/wifi-kit-actions 2>/dev/null || return 1
  chmod 1777 /tmp/wifi-kit-actions 2>/dev/null || true
  ( : >> "$path" ) 2>/dev/null || return 1
  chmod 0666 "$path" 2>/dev/null || true
}

append_ui_log() {
  line=$1
  [ -n "$ui_log_file" ] || return 0
  prepare_ui_log "$ui_log_file" || return 0
  ( printf '%s\n' "$line" >> "$ui_log_file" ) 2>/dev/null || true
}

tx_id() {
  date -u '+%Y%m%dT%H%M%SZ'
}

log_event() {
  status=$1
  detail=${2:-}
  line=$(
    printf 'timestamp=%s action=connect-transaction status=%s ssid=%s' \
      "$(quote "$(timestamp)")" \
      "$(quote "$status")" \
      "$(quote "${target_ssid:-unknown}")"
    if [ -n "$detail" ]; then
      printf ' %s' "$detail"
    fi
    printf '\n'
  )
  if [ -n "$log_file" ]; then
    printf '%s\n' "$line" >>"$log_file" 2>/dev/null || true
  fi
  if [ -n "$ui_log_file" ]; then
    append_ui_log "$line"
  fi
  if [ "${WIFI_KIT_CONNECT_STDOUT_LOG:-}" = "1" ]; then
    printf '%s\n' "$line"
  fi
}

state_init() {
  umask 077
  : >"$state_file" 2>/dev/null || true
  chmod 600 "$state_file" 2>/dev/null || true
}

state_set() {
  [ -n "$state_file" ] || return 0
  key=$1
  value=$2
  printf '%s=%s\n' "$key" "$value" >>"$state_file" 2>/dev/null || true
}

kv() {
  printf '%s=%s\n' "$1" "$2"
}

section() {
  printf '\n[%s]\n' "$1"
}

find_tool() {
  tool=$1
  if command -v "$tool" >/dev/null 2>&1; then
    command -v "$tool"
    return 0
  fi
  for dir in /usr/sbin /sbin /usr/bin /bin; do
    if [ -x "$dir/$tool" ]; then
      printf '%s\n' "$dir/$tool"
      return 0
    fi
  done
  return 1
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

set_runtime_config_value() {
  key=$1
  value=$2
  path=$runtime_config
  dir=${path%/*}
  tmp="$dir/.runtime.conf.$$.$key.tmp"
  owner_uid=""
  owner_gid=""
  mkdir -p "$dir" 2>/dev/null || return 1
  chmod 700 "$dir" 2>/dev/null || true
  if [ -r "$path" ]; then
    owner_uid=$(stat -c '%u' "$path" 2>/dev/null || true)
    owner_gid=$(stat -c '%g' "$path" 2>/dev/null || true)
    awk -v key="$key" -v value="$value" '
      BEGIN { done = 0 }
      index($0, key "=") == 1 { print key "=" value; done = 1; next }
      { print }
      END { if (!done) print key "=" value }
    ' "$path" >"$tmp" || return 1
  else
    {
      printf '# Wifi-Kit prototype runtime config\n'
      printf '# Stores AP recovery password only; never stores client Wi-Fi passwords.\n'
      printf '%s=%s\n' "$key" "$value"
    } >"$tmp" || return 1
  fi
  if [ -z "$owner_uid" ] && [ -n "${SUDO_UID:-}" ] && [ "${SUDO_UID:-0}" != "0" ]; then
    owner_uid=$SUDO_UID
    owner_gid=${SUDO_GID:-}
  fi
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ] &&
    [ -n "${SUDO_UID:-}" ] && [ "${SUDO_UID:-0}" != "0" ]; then
    sudo_home=$(getent passwd "$SUDO_USER" 2>/dev/null | awk -F: '{ print $6 }' | sed -n '1p')
    if [ -n "$sudo_home" ] && [ "$path" = "$sudo_home/.config/wifi-kit/runtime.conf" ]; then
      owner_uid=$SUDO_UID
      owner_gid=${SUDO_GID:-}
    fi
  fi
  chmod 600 "$tmp" 2>/dev/null || true
  mv "$tmp" "$path" || return 1
  chmod 600 "$path" 2>/dev/null || true
  if [ -n "$owner_uid" ] && [ -n "$owner_gid" ]; then
    chown "$owner_uid:$owner_gid" "$path" 2>/dev/null || true
  fi
}

persist_last_good() {
  ssid=$1
  connection=$2
  [ -n "$ssid" ] || return 0
  [ -n "$connection" ] || return 0
  if set_runtime_config_value last_good_ssid "$ssid" &&
    set_runtime_config_value last_good_connection "$connection"; then
    log_event "last-good-persisted" "last_good_ssid=$(quote "$ssid") last_good_connection=$(quote "$connection")"
    state_set "last_good_ssid" "$ssid"
    state_set "last_good_connection" "$connection"
    return 0
  fi
  log_event "last-good-persist-failed" "runtime_config=$(quote "$runtime_config")"
  return 1
}

runtime_config_value() {
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

apply_runtime_autoconnect_policy() {
  last_good_connection=$1
  return_connection=$(runtime_config_value return_connection "$(runtime_config_value default_connection "")")
  [ -n "$last_good_connection" ] || return 0
  "$nmcli" connection modify "$last_good_connection" connection.autoconnect yes >>"$log_file" 2>&1 || true
  log_event "autoconnect-policy" "last_good_connection=$(quote "$last_good_connection") autoconnect=yes"
  if [ -n "$return_connection" ] && [ "$return_connection" != "$last_good_connection" ]; then
    if "$nmcli" connection show "$return_connection" >/dev/null 2>&1; then
      "$nmcli" connection modify "$return_connection" connection.autoconnect no >>"$log_file" 2>&1 || true
      log_event "autoconnect-policy" "return_connection=$(quote "$return_connection") autoconnect=no scope=boot-only"
    fi
  fi
}

require_number() {
  name=$1
  value=$2
  case "$value" in
    ''|*[!0-9]*) fail "$name must be a non-negative integer" ;;
  esac
}

need_ssid() {
  [ -n "$target_ssid" ] || fail "missing-ssid"
  bytes=$(printf '%s' "$target_ssid" | wc -c | tr -d ' ')
  [ "$bytes" -le 32 ] || fail "ssid-too-long"
}

nmcli_bin() {
  find_tool nmcli 2>/dev/null || true
}

active_connection() {
  "$nmcli" -t --escape no -f DEVICE,CONNECTION device status 2>/dev/null |
    awk -F: -v iface="$iface" '$1 == iface { print $2; exit }'
}

active_ssid() {
  "$nmcli" -t --escape no -f ACTIVE,SSID device wifi list --rescan no 2>/dev/null |
    awk -F: '$1 == "yes" { print $2; exit }'
}

device_state() {
  "$nmcli" -t --escape no -f DEVICE,STATE device status 2>/dev/null |
    awk -F: -v iface="$iface" '$1 == iface { print $2; exit }'
}

device_general_state() {
  "$nmcli" -g GENERAL.STATE device show "$iface" 2>/dev/null | sed -n '1p'
}

ip_address() {
  "$nmcli" -g IP4.ADDRESS device show "$iface" 2>/dev/null | sed -n '1p'
}

gateway() {
  "$nmcli" -g IP4.GATEWAY device show "$iface" 2>/dev/null | sed -n '1p'
}

stable_connected() {
  state=$1
  general=$2
  case "$(printf '%s %s' "$state" "$general" | tr '[:upper:]' '[:lower:]')" in
    *connecting*|*configuring*|*prepare*|*auth*|*unavailable*|*disconnect*) return 1 ;;
  esac
  [ "$state" = "connected" ] && return 0
  case "$general" in
    100\ *|connected) return 0 ;;
  esac
  return 1
}

sshd_active() {
  if command -v pgrep >/dev/null 2>&1 && pgrep -x sshd >/dev/null 2>&1; then
    return 0
  fi
  if command -v ss >/dev/null 2>&1 && ss -lnt 2>/dev/null | awk '$4 ~ /:22$/ { found=1 } END { exit found ? 0 : 1 }'; then
    return 0
  fi
  return 1
}

dns_ok() {
  getent hosts "$dns_probe" >/dev/null 2>&1
}

validate_network() {
  expected_ssid=$1
  require_internet=$2

  ssid_now=$(active_ssid || true)
  ip_now=$(ip_address || true)
  gateway_now=$(gateway || true)
  state_now=$(device_state || true)
  general_now=$(device_general_state || true)

  if ! stable_connected "$state_now" "$general_now"; then
    printf 'networkmanager-not-stable'
    return 1
  fi
  if [ -n "$expected_ssid" ] && [ "$ssid_now" != "$expected_ssid" ]; then
    printf 'ssid-not-active'
    return 1
  fi
  if [ -z "$ip_now" ]; then
    printf 'ipv4-missing'
    return 1
  fi
  if [ -z "$gateway_now" ]; then
    printf 'gateway-missing'
    return 1
  fi
  if ! ping -c 1 -W 2 "$gateway_now" >/dev/null 2>&1; then
    printf 'gateway-ping-failed'
    return 1
  fi
  if [ "$require_internet" = "yes" ] && ! ping -c 1 -W 3 "$internet_probe" >/dev/null 2>&1; then
    printf 'internet-ping-failed'
    return 1
  fi
  if [ "$require_internet" = "yes" ] && ! dns_ok; then
    printf 'dns-failed'
    return 1
  fi
  if ! sshd_active; then
    printf 'sshd-not-active'
    return 1
  fi
  printf 'validated'
  return 0
}

wait_validate() {
  expected_ssid=$1
  require_internet=$2
  timeout=$3
  elapsed=0
  last_reason="not-started"
  while [ "$elapsed" -lt "$timeout" ]; do
    set +e
    reason=$(validate_network "$expected_ssid" "$require_internet")
    validate_rc=$?
    set -e
    if [ "$validate_rc" -eq 0 ]; then
      printf 'validated'
      return 0
    fi
    last_reason=$reason
    case "$elapsed" in
      0|15|30|60|90|120|150)
        log_event "waiting" "step=validate reason=$(quote "$last_reason") elapsed_seconds=$(quote "$elapsed")" >/dev/null
        ;;
    esac
    sleep 3
    elapsed=$((elapsed + 3))
  done
  printf '%s' "$last_reason"
  return 1
}

delete_temp_profile() {
  [ -n "${temp_connection:-}" ] || return 0
  "$nmcli" connection delete "$temp_connection" >/dev/null 2>&1 || true
}

stable_profile_suffix() {
  printf '%s' "$1" |
    sed 's/[^A-Za-z0-9._-]/_/g; s/^_*//; s/_*$//' |
    cut -c 1-48
}

stable_profile_name() {
  suffix=$(stable_profile_suffix "$1")
  [ -n "$suffix" ] || suffix="ssid"
  printf 'wifi-kit-known-%s\n' "$suffix"
}

connection_exists() {
  "$nmcli" connection show "$1" >/dev/null 2>&1
}

is_wifi_kit_transient_profile() {
  case "$1" in
    wifi-kit-tx-*|wifi-kit-recovery-target) return 0 ;;
    *) return 1 ;;
  esac
}

stabilize_success_profile() {
  ssid=$1
  connection=$2
  stable_connection=$(stable_profile_name "$ssid")

  if [ "$connection" = "$stable_connection" ]; then
    printf '%s\n' "$connection"
    return 0
  fi

  if connection_exists "$stable_connection"; then
    log_event "stable-profile-existing" "stable_connection=$(quote "$stable_connection")" >/dev/null
    printf '%s\n' "$stable_connection"
    return 0
  fi

  if [ "$connection" = "$temp_connection" ] || is_wifi_kit_transient_profile "$connection"; then
    if "$nmcli" connection modify "$connection" connection.id "$stable_connection" connection.autoconnect yes >>"$log_file" 2>&1; then
      log_event "stable-profile-created" "stable_connection=$(quote "$stable_connection") source_connection=$(quote "$connection")" >/dev/null
      if [ "$connection" = "$temp_connection" ]; then
        temp_connection=""
      fi
      printf '%s\n' "$stable_connection"
      return 0
    fi
    log_event "stable-profile-failed" "source_connection=$(quote "$connection") stable_connection=$(quote "$stable_connection")" >/dev/null
  fi

  printf '%s\n' "$connection"
}

rollback_previous() {
  [ -n "$previous_connection" ] && [ "$previous_connection" != "--" ] ||
    return 1
  log_event "rollback-started" "previous_connection=$(quote "$previous_connection")"
  "$nmcli" device set "$iface" managed yes >/dev/null 2>&1 || true
  "$nmcli" --wait 45 connection up "$previous_connection" ifname "$iface" >>"$log_file" 2>&1 || return 1
  reason=$(wait_validate "$previous_ssid" "no" "$rollback_timeout_seconds" || true)
  [ "$reason" = "validated" ]
}

start_ap_recovery() {
  [ -r "$action_wrapper" ] || {
    log_event "recovery-failure" "error=action-wrapper-missing"
    return 1
  }
  log_event "recovery-starting" "backend=nm-hotspot via=action-wrapper"
  WIFI_KIT_RUNTIME_CONFIG="$runtime_config" sh "$action_wrapper" start-ap-mode >/dev/null 2>&1 &
  log_event "recovery-started" "status=background backend=nm-hotspot hostapd=legacy-explicit-only"
}

cmd_audit() {
  nmcli=$(nmcli_bin)
  printf '[wifi-kit] connect transaction audit\n'
  kv "mode" "audit-readonly"
  kv "network_writes" "false"
  kv "secret_policy" "stdin-only-for-apply"
  kv "iface" "$iface"
  kv "nmcli" "${nmcli:-missing}"
  if [ -n "$nmcli" ]; then
    kv "networkmanager_running" "$("$nmcli" -t -f RUNNING general 2>/dev/null | sed -n '1p' || true)"
    kv "device_state" "$(device_state || true)"
    kv "active_connection" "$(active_connection || true)"
    kv "active_ssid" "$(active_ssid || true)"
    kv "ip" "$(ip_address || true)"
    kv "gateway" "$(gateway || true)"
  fi
  kv "sshd_active" "$(sshd_active && printf yes || printf no)"
  kv "action_wrapper" "$action_wrapper"
  kv "action_wrapper_present" "$([ -r "$action_wrapper" ] && printf yes || printf no)"
}

cmd_plan() {
  need_ssid
  printf '[wifi-kit] connect transaction plan\n'
  kv "mode" "plan-readonly"
  kv "network_writes" "false"
  kv "target_ssid" "$target_ssid"
  kv "password_source" "$([ -n "$existing_connection" ] && printf 'existing-networkmanager-profile' || printf 'stdin-only-during-apply')"
  kv "log_file" "/tmp/wifi-kit-connect-transaction-<txid>.log"
  kv "state_file" "/tmp/wifi-kit-connect-transaction-<txid>.state"
  kv "existing_connection" "${existing_connection:-none}"
  kv "temporary_profile" "$([ -n "$existing_connection" ] && printf 'none' || printf 'wifi-kit-tx-<txid>')"
  kv "stable_profile" "wifi-kit-known-<SSID_safe>"
  section "transaction"
  kv "01.snapshot" "current wlan0 NetworkManager connection, SSID, IP, gateway"
  kv "02.prepare_target" "$([ -n "$existing_connection" ] && printf 'use existing NetworkManager profile without reading secrets' || printf 'create wifi-kit-tx-<txid>, autoconnect=no, delete on failure')"
  kv "03.connect_target" "$([ -n "$existing_connection" ] && printf 'nmcli connection up existing profile' || printf 'nmcli connection up temporary profile')"
  kv "04.validate_target" "IPv4, default gateway, gateway ping, ping $internet_probe, DNS $dns_probe, sshd active"
  kv "05.success" "keep stable profile wifi-kit-known-<SSID_safe> for Wifi-Kit-created/transient profiles"
  kv "06.failure" "rollback previous active NetworkManager profile"
  kv "07.rollback_failure" "start temporary AP recovery"
  kv "08.cleanup" "delete only failed Wifi-Kit temporary profile"
  section "forbidden"
  kv "delete_user_profiles" "false"
  kv "secret_logging" "false"
  kv "sudoers_systemd" "false"
  kv "ui_integration" "gated-by-recovery-privileged-actions-and-confirmation"
}

require_apply_gates() {
  [ "$dangerous_real_apply" = "1" ] || fail "dangerous-real-apply-required"
  [ "$confirm_phrase" = "WIFI-KIT CONNECT SAFE TRANSACTION" ] ||
    fail "confirm-phrase-mismatch"
  [ "$(id -u 2>/dev/null || printf 1)" = "0" ] || fail "root-required"
}

cmd_apply() {
  need_ssid
  require_apply_gates
  require_number "--timeout-seconds" "$tx_timeout_seconds"
  require_number "--rollback-timeout-seconds" "$rollback_timeout_seconds"

  IFS= read -r runtime_password || runtime_password=""
  if [ -z "$existing_connection" ]; then
    [ -n "$runtime_password" ] || fail "missing-password"
  fi

  nmcli=$(nmcli_bin)
  [ -n "$nmcli" ] || fail "nmcli-required"
  [ "$("$nmcli" -t -f RUNNING general 2>/dev/null | sed -n '1p' || true)" = "running" ] ||
    fail "networkmanager-not-running"

  tx=$(tx_id)-$$
  temp_connection="wifi-kit-tx-$tx"
  log_file="/tmp/wifi-kit-connect-transaction-$tx.log"
  state_file="/tmp/wifi-kit-connect-transaction-$tx.state"
  state_init
  state_set "tx_id" "$tx"
  state_set "target_ssid" "$target_ssid"
  state_set "existing_connection" "${existing_connection:-}"
  state_set "temporary_connection" "$([ -n "$existing_connection" ] && printf '' || printf '%s' "$temp_connection")"
  state_set "status" "started"
  log_event "started" "tx_id=$(quote "$tx") temporary_connection=$(quote "$temp_connection") existing_connection=$(quote "${existing_connection:-}") secret_policy=$(quote "stdin-or-existing-profile-not-logged")"

  previous_connection=$(active_connection || true)
  previous_ssid=$(active_ssid || true)
  previous_ip=$(ip_address || true)
  previous_gateway=$(gateway || true)
  [ -n "$previous_connection" ] && [ "$previous_connection" != "--" ] ||
    fail "previous-active-connection-missing"

  state_set "previous_connection" "$previous_connection"
  state_set "previous_ssid" "$previous_ssid"
  state_set "previous_ip" "$previous_ip"
  state_set "previous_gateway" "$previous_gateway"
  log_event "snapshot" "previous_connection=$(quote "$previous_connection") previous_ssid=$(quote "$previous_ssid") previous_ip=$(quote "$previous_ip") previous_gateway=$(quote "$previous_gateway")"

  cleanup() {
    delete_temp_profile
  }
  trap cleanup EXIT INT TERM HUP

  if [ -n "$existing_connection" ]; then
    temp_connection=""
    unset runtime_password
    log_event "connect-starting" "existing_connection=$(quote "$existing_connection")"
    connect_target=$existing_connection
  else
    "$nmcli" connection add type wifi ifname "$iface" con-name "$temp_connection" ssid "$target_ssid" save yes >>"$log_file" 2>&1 ||
      fail "temporary-profile-create-failed"
    "$nmcli" connection modify "$temp_connection" connection.autoconnect no >>"$log_file" 2>&1 || true
    "$nmcli" connection modify "$temp_connection" 802-11-wireless-security.key-mgmt wpa-psk >>"$log_file" 2>&1 ||
      fail "temporary-profile-security-failed"
    "$nmcli" connection modify "$temp_connection" 802-11-wireless-security.psk "$runtime_password" >/dev/null 2>&1 ||
      fail "temporary-profile-secret-attach-failed"
    stable_candidate=$(stable_profile_name "$target_ssid")
    if connection_exists "$stable_candidate"; then
      "$nmcli" connection modify "$stable_candidate" 802-11-wireless.ssid "$target_ssid" >>"$log_file" 2>&1 || true
      "$nmcli" connection modify "$stable_candidate" 802-11-wireless-security.key-mgmt wpa-psk >>"$log_file" 2>&1 || true
      "$nmcli" connection modify "$stable_candidate" 802-11-wireless-security.psk "$runtime_password" >/dev/null 2>&1 ||
        fail "stable-profile-secret-attach-failed"
      delete_temp_profile
      temp_connection=""
      connect_target=$stable_candidate
      log_event "connect-starting" "stable_connection=$(quote "$stable_candidate")"
    else
      connect_target=$temp_connection
      log_event "connect-starting" "temporary_connection=$(quote "$temp_connection")"
    fi
    unset runtime_password
  fi

  if "$nmcli" --wait 45 connection up "$connect_target" ifname "$iface" >>"$log_file" 2>&1; then
    reason=$(wait_validate "$target_ssid" "yes" "$tx_timeout_seconds" || true)
    if [ "$reason" = "validated" ]; then
      connected_ssid=$(active_ssid || true)
      [ -n "$connected_ssid" ] || connected_ssid=$target_ssid
      connected_connection=$(active_connection || true)
      [ -n "$connected_connection" ] && [ "$connected_connection" != "--" ] || connected_connection=$connect_target
      connected_connection=$(stabilize_success_profile "$connected_ssid" "$connected_connection")
      persist_last_good "$connected_ssid" "$connected_connection" || true
      apply_runtime_autoconnect_policy "$connected_connection"
      state_set "status" "success"
      state_set "connected_ssid" "$connected_ssid"
      state_set "connected_connection" "$connected_connection"
      log_event "success" "connected_ssid=$(quote "$connected_ssid") connected_connection=$(quote "$connected_connection")"
      trap - EXIT INT TERM HUP
      exit 0
    fi
    log_event "validation-failed" "reason=$(quote "$reason")"
  else
    log_event "connect-failed" "reason=nmcli-connection-up-failed"
  fi

  if rollback_previous; then
    delete_temp_profile
    state_set "status" "rolled-back"
    log_event "rolled-back" "previous_connection=$(quote "$previous_connection")"
    trap - EXIT INT TERM HUP
    exit 1
  fi

  delete_temp_profile
  state_set "status" "recovery-required"
  log_event "rollback-failed" "fallback=ap-recovery"
  start_ap_recovery || true
  trap - EXIT INT TERM HUP
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    audit|plan|apply)
      [ -z "$mode" ] || fail "mode-already-set"
      mode=$1
      shift
      ;;
    --iface)
      [ "$#" -ge 2 ] || fail "--iface requires a value"
      iface=$2
      shift 2
      ;;
    --ssid)
      [ "$#" -ge 2 ] || fail "--ssid requires a value"
      target_ssid=$2
      shift 2
      ;;
    --existing-connection)
      [ "$#" -ge 2 ] || fail "--existing-connection requires a value"
      existing_connection=$2
      shift 2
      ;;
    --confirm)
      [ "$#" -ge 2 ] || fail "--confirm requires a value"
      confirm_phrase=$2
      shift 2
      ;;
    --dangerous-real-apply)
      dangerous_real_apply="1"
      shift
      ;;
    --timeout-seconds)
      [ "$#" -ge 2 ] || fail "--timeout-seconds requires a value"
      tx_timeout_seconds=$2
      shift 2
      ;;
    --rollback-timeout-seconds)
      [ "$#" -ge 2 ] || fail "--rollback-timeout-seconds requires a value"
      rollback_timeout_seconds=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

[ -n "$mode" ] || mode="audit"

case "$mode" in
  audit) cmd_audit ;;
  plan) cmd_plan ;;
  apply) cmd_apply ;;
  *) usage >&2; exit 2 ;;
esac
