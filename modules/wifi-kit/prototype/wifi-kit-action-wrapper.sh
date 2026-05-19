#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ap_setup_script="$script_dir/ap-setup-test.sh"
log_file="/tmp/wifi-kit-action-wrapper.log"
default_connection="netplan-wlan0-GL-MT6000-d53"
ap_test_psk="12345678"
ap_timeout_seconds="300"

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

log_event() {
  action=$1
  status=$2
  detail=${3:-}
  {
    printf 'timestamp="%s" action=%s status="%s"' "$(timestamp)" "$action" "$status"
    if [ -n "$detail" ]; then
      printf ' detail="%s"' "$(json_escape "$detail")"
    fi
    printf '\n'
  } >> "$log_file" 2>/dev/null || true
}

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

require_root() {
  if [ "$(id -u)" != "0" ]; then
    log_event "$1" "refused" "root-required"
    reply "refused" "$1" "root-required"
    exit 1
  fi
}

if [ "$#" -ne 1 ]; then
  log_event "unknown" "refused" "usage"
  reply "refused" "unknown" "usage: wifi-kit-action-wrapper.sh start-ap-mode|return-default-network"
  exit 2
fi

action=$1

case "$action" in
  start-ap-mode)
    require_root "$action"
    if [ ! -f "$ap_setup_script" ]; then
      log_event "$action" "failure" "ap-setup-test-missing"
      reply "failure" "$action" "ap-setup-test-missing"
      exit 1
    fi
    log_event "$action" "started" "timeout=$ap_timeout_seconds"
    WIFI_KIT_AP_PSK=$ap_test_psk
    export WIFI_KIT_AP_PSK
    exec sh "$ap_setup_script" apply-ap-recovery-manual-test \
      --dangerous-real-apply \
      --confirm "WIFI-KIT AP RECOVERY MANUAL TEST" \
      --max-seconds "$ap_timeout_seconds"
    ;;
  return-default-network)
    require_root "$action"
    log_event "$action" "started" "connection=$default_connection"
    exec nmcli connection up "$default_connection"
    ;;
  *)
    log_event "$action" "refused" "action-not-allowed"
    reply "refused" "$action" "action-not-allowed"
    exit 2
    ;;
esac
