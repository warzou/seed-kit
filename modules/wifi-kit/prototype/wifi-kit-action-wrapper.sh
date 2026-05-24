#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ap_setup_script="$script_dir/ap-setup-test.sh"
connect_transaction_script="$script_dir/wifi-kit-connect-transaction.sh"
ap_return_check_script="$script_dir/wifi-kit-ap-return-check.sh"
log_file="/tmp/wifi-kit-action-wrapper.log"
ui_connect_log="${WIFI_KIT_CONNECT_UI_LOG:-}"
runtime_config="${WIFI_KIT_RUNTIME_CONFIG:-}"
return_connection="netplan-wlan0-GL-MT6000-d53"
ap_test_psk="12345678"
ap_ssid=""
ap_timeout_seconds="300"
connect_timeout_seconds="180"

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
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

append_ui_connect_log() {
  line=$1
  [ -n "$ui_connect_log" ] || return 0
  prepare_ui_log "$ui_connect_log" || return 0
  ( printf '%s\n' "$line" >> "$ui_connect_log" ) 2>/dev/null || true
}

log_ui_connect_marker() {
  marker=$1
  detail=${2:-}
  [ -n "$ui_connect_log" ] || return 0
  log_event "connect-wifi" "$marker" "$detail"
}

log_event() {
  action=$1
  status=$2
  detail=${3:-}
  line=$(
    printf 'timestamp="%s" action=%s status="%s"' "$(timestamp)" "$action" "$status"
    if [ -n "$detail" ]; then
      printf ' detail="%s"' "$(json_escape "$detail")"
    fi
    printf '\n'
  )
  printf '%s\n' "$line" >> "$log_file" 2>/dev/null || true
  if [ "$action" = "connect-wifi" ] && [ -n "$ui_connect_log" ]; then
    append_ui_connect_log "$line"
  fi
  if [ "$action" = "connect-wifi" ]; then
    printf '%s\n' "$line"
  fi
}

runtime_config_value() {
  key=$1
  fallback=$2
  if [ -r "$runtime_config" ]; then
    value=$(sed -n "s/^$key=//p" "$runtime_config" 2>/dev/null | sed -n '1p' || true)
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return 0
    fi
  fi
  printf '%s\n' "$fallback"
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
  if [ -r "/home/warzy/.config/wifi-kit/runtime.conf" ]; then
    printf '%s\n' "/home/warzy/.config/wifi-kit/runtime.conf"
    return 0
  fi
  printf '%s\n' "${HOME:-/tmp}/.config/wifi-kit/runtime.conf"
}

runtime_config=$(default_runtime_config_path)
export WIFI_KIT_RUNTIME_CONFIG="$runtime_config"

reply() {
  status=$1
  action=$2
  detail=${3:-}
  printf 'status=%s\n' "$status"
  printf 'action=%s\n' "$action"
  if [ -n "$detail" ]; then
    printf 'detail=%s\n' "$detail"
  fi
}

safe_line_value() {
  key=$1
  value=$2
  cr=$(printf '\r')
  case "$value" in
    *"$cr"*) reply "refused" "$key" "newline-not-allowed"; exit 2 ;;
  esac
}

require_number() {
  key=$1
  value=$2
  max=$3
  case "$value" in
    ''|*[!0-9]*) reply "refused" "$key" "number-required"; exit 2 ;;
  esac
  [ "$value" -le "$max" ] || { reply "refused" "$key" "number-too-large"; exit 2; }
}

read_connect_request() {
  connect_ssid=""
  connect_password=""
  connect_existing_connection=""
  connect_confirm=""
  connect_dangerous_real_apply="false"
  connect_timeout_seconds="180"
  while IFS= read -r line; do
    key=${line%%=*}
    value=${line#*=}
    [ "$key" != "$line" ] || continue
    safe_line_value "$key" "$value"
    case "$key" in
      ssid) connect_ssid=$value ;;
      password) connect_password=$value ;;
      existing_connection) connect_existing_connection=$value ;;
      confirm) connect_confirm=$value ;;
      dangerous_real_apply) connect_dangerous_real_apply=$value ;;
      timeout_seconds) connect_timeout_seconds=$value ;;
      ui_log) ui_connect_log=$value ;;
      *) ;;
    esac
  done
}

require_root() {
  if [ "$(id -u)" != "0" ]; then
    log_event "$1" "refused" "root-required"
    reply "refused" "$1" "root-required"
    exit 1
  fi
}

if [ "$#" -ne 1 ]; then
  log_event "unknown" "refused" "usage"
  reply "refused" "unknown" "usage: wifi-kit-action-wrapper.sh start-ap-mode|return-default-network|connect-wifi|ap-return-check-once"
  exit 2
fi

action=$1
return_connection="${WIFI_KIT_RETURN_CONNECTION:-$(runtime_config_value return_connection "$(runtime_config_value default_connection "$return_connection")")}"
ap_test_psk="${WIFI_KIT_AP_PSK:-$(runtime_config_value ap_password "$ap_test_psk")}"
ap_ssid="${WIFI_KIT_AP_SSID:-$(runtime_config_value ap_ssid "")}"

case "$action" in
  start-ap-mode)
    require_root "$action"
    if [ ! -f "$ap_setup_script" ]; then
      log_event "$action" "failure" "ap-setup-test-missing"
      reply "failure" "$action" "ap-setup-test-missing"
      exit 1
    fi
    log_event "$action" "started" "timeout=$ap_timeout_seconds"
    export WIFI_KIT_AP_PSK="$ap_test_psk"
    if [ -n "$ap_ssid" ]; then
      exec sh "$ap_setup_script" apply-ap-recovery-manual-test \
        --dangerous-real-apply \
        --confirm "WIFI-KIT AP RECOVERY MANUAL TEST" \
        --ssid "$ap_ssid" \
        --stay-up-until-stop \
        --max-seconds "$ap_timeout_seconds"
    fi
    exec sh "$ap_setup_script" apply-ap-recovery-manual-test \
      --dangerous-real-apply \
      --confirm "WIFI-KIT AP RECOVERY MANUAL TEST" \
      --stay-up-until-stop \
      --max-seconds "$ap_timeout_seconds"
    ;;
  return-default-network)
    require_root "$action"
    if [ -f "$ap_return_check_script" ]; then
      WIFI_KIT_RUNTIME_CONFIG="$runtime_config" sh "$ap_return_check_script" stop-loop >/dev/null 2>&1 || true
    fi
    log_event "$action" "started" "connection=$return_connection"
    if [ -f "$ap_setup_script" ]; then
      sh "$ap_setup_script" stop >> "$log_file" 2>&1 || true
    fi
    exec nmcli connection up "$return_connection"
    ;;
  connect-wifi)
    read_connect_request
    log_ui_connect_marker "wrapper-received-ui-log" "path-accepted"
    require_root "$action"
    if [ -f "$ap_return_check_script" ]; then
      WIFI_KIT_RUNTIME_CONFIG="$runtime_config" sh "$ap_return_check_script" stop-loop >/dev/null 2>&1 || true
    fi
    [ -n "$connect_ssid" ] || { reply "refused" "$action" "missing-ssid"; exit 2; }
    ssid_bytes=$(printf '%s' "$connect_ssid" | wc -c | tr -d ' ')
    [ "$ssid_bytes" -le 32 ] || { reply "refused" "$action" "ssid-too-long"; exit 2; }
    [ "$connect_confirm" = "WIFI-KIT CONNECT SAFE TRANSACTION" ] || { reply "refused" "$action" "confirm-phrase-mismatch"; exit 2; }
    [ "$connect_dangerous_real_apply" = "true" ] || [ "$connect_dangerous_real_apply" = "1" ] ||
      { reply "refused" "$action" "dangerous-real-apply-required"; exit 2; }
    require_number "timeout_seconds" "$connect_timeout_seconds" "600"
    [ -f "$connect_transaction_script" ] || { reply "failure" "$action" "connect-transaction-missing"; exit 1; }
    log_event "$action" "started" "ssid=$connect_ssid existing_connection=${connect_existing_connection:-none}"
    export WIFI_KIT_AP_PSK="$ap_test_psk"
    if [ -n "$ap_ssid" ]; then
      export WIFI_KIT_AP_SSID="$ap_ssid"
    fi
    if [ -n "$ui_connect_log" ]; then
      export WIFI_KIT_CONNECT_UI_LOG="$ui_connect_log"
    fi
    export WIFI_KIT_CONNECT_STDOUT_LOG=1
    log_ui_connect_marker "wrapper-launching-transaction" "existing_connection=${connect_existing_connection:-none}"
    if [ -n "$connect_existing_connection" ]; then
      exec sh "$connect_transaction_script" apply \
        --ssid "$connect_ssid" \
        --existing-connection "$connect_existing_connection" \
        --dangerous-real-apply \
        --confirm "WIFI-KIT CONNECT SAFE TRANSACTION" \
        --timeout-seconds "$connect_timeout_seconds"
    fi
    [ -n "$connect_password" ] || { reply "refused" "$action" "missing-password"; exit 2; }
    [ "${#connect_password}" -ge 8 ] || { reply "refused" "$action" "password-too-short"; exit 2; }
    printf '%s\n' "$connect_password" | sh "$connect_transaction_script" apply \
      --ssid "$connect_ssid" \
      --dangerous-real-apply \
      --confirm "WIFI-KIT CONNECT SAFE TRANSACTION" \
      --timeout-seconds "$connect_timeout_seconds"
    ;;
  ap-return-check-once)
    require_root "$action"
    [ -f "$ap_return_check_script" ] || { reply "failure" "$action" "ap-return-check-missing"; exit 1; }
    WIFI_KIT_RUNTIME_CONFIG="$runtime_config" sh "$ap_return_check_script" stop-loop >/dev/null 2>&1 || true
    log_event "$action" "started" "mode=run-once"
    WIFI_KIT_RUNTIME_CONFIG="$runtime_config" exec sh "$ap_return_check_script" run-once
    ;;
  *)
    log_event "$action" "refused" "action-not-allowed"
    reply "refused" "$action" "action-not-allowed"
    exit 2
    ;;
esac
