#!/bin/sh
set -eu

iface="wlan0"
target_ssid=""
target_security=""
timeout_seconds="180"
temporary_connection="wifi-kit-recovery-target"
connect_log="/tmp/wifi-kit-connect-recovery.log"
ap_only_nm_state="/tmp/wifi-kit-ap-only-nm-state"
ap_setup_script="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/ap-setup-test.sh"

usage() {
  cat <<'EOF'
wifi-kit recovery Wi-Fi connect helper

This helper is intended to run from the recovery captive UI only. It receives
the target Wi-Fi password on stdin, never logs it, and never calls save_config.

Usage:
  printf '%s\n' "$RUNTIME_PASSWORD" | \
    sh modules/wifi-kit/prototype/wifi-kit-connect-recovery.sh \
      --ssid <ssid> \
      --security <security> \
      --timeout-seconds 180
EOF
}

fail() {
  log "status=failure error=$(quote "$*")"
  printf 'error: %s\n' "$*" >&2
  exit 1
}

quote() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/^/"/; s/$/"/'
}

timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

log() {
  printf 'timestamp=%s action=connect-recovery ssid=%s timeout_seconds=%s %s\n' \
    "$(quote "$(timestamp)")" \
    "$(quote "$target_ssid")" \
    "$(quote "$timeout_seconds")" \
    "$*" >>"$connect_log" 2>/dev/null || true
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

require_number() {
  name=$1
  value=$2
  case "$value" in
    ''|*[!0-9]*) fail "$name must be a non-negative integer" ;;
  esac
}

read_state_value() {
  key=$1
  [ -r "$ap_only_nm_state" ] || return 0
  sed -n "s/^$key=//p" "$ap_only_nm_state" | sed -n '1p'
}

security_requires_password() {
  case "$(printf '%s' "$target_security" | tr '[:upper:]' '[:lower:]')" in
    ''|open|none|--|inconnu|unknown) return 1 ;;
    *) return 0 ;;
  esac
}

active_ssid() {
  "$nmcli_bin" -t --escape no -f ACTIVE,SSID device wifi list --rescan no 2>/dev/null |
    awk -F: '$1 == "yes" { print $2; exit }'
}

ip_address() {
  "$nmcli_bin" -g IP4.ADDRESS device show "$iface" 2>/dev/null | sed -n '1p'
}

gateway() {
  "$nmcli_bin" -g IP4.GATEWAY device show "$iface" 2>/dev/null | sed -n '1p'
}

cleanup_failed_attempt() {
  "$nmcli_bin" connection delete "$temporary_connection" >/dev/null 2>&1 || true
}

restart_recovery_best_effort() {
  log "step=$(quote "restart-recovery") status=$(quote "starting")"
  WIFI_KIT_AP_PSK="${WIFI_KIT_AP_PSK:-12345678}" \
    sh "$ap_setup_script" apply-ap-recovery-manual-test \
      --dangerous-real-apply \
      --confirm "WIFI-KIT AP RECOVERY MANUAL TEST" \
      --max-seconds 300 >>"$connect_log" 2>&1 &
  log "step=$(quote "restart-recovery") status=$(quote "started")"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --iface)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      iface=$2
      shift 2
      ;;
    --ssid)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      target_ssid=$2
      shift 2
      ;;
    --security)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      target_security=$2
      shift 2
      ;;
    --timeout-seconds)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      timeout_seconds=$2
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

[ -n "$target_ssid" ] || fail "missing-ssid"
require_number "--timeout-seconds" "$timeout_seconds"
[ "$timeout_seconds" -gt 0 ] || fail "--timeout-seconds must be greater than 0"

IFS= read -r target_password || target_password=""
if security_requires_password && [ -z "$target_password" ]; then
  fail "missing-password"
fi

umask 077
: >"$connect_log" 2>/dev/null || true
chmod 600 "$connect_log" 2>/dev/null || true

[ "$(id -u 2>/dev/null || printf 1)" = "0" ] || fail "root-required"
nmcli_bin="$(find_tool nmcli 2>/dev/null || true)"
[ -n "$nmcli_bin" ] || fail "nmcli-required"
[ -x "$ap_setup_script" ] || [ -r "$ap_setup_script" ] || fail "ap-setup-test-missing"

previous_connection="$(read_state_value active_connection || true)"
previous_iface="$(read_state_value iface || true)"
[ -n "$previous_iface" ] || previous_iface="$iface"

log "status=$(quote "started") previous_connection=$(quote "${previous_connection:-unknown}") secret_policy=$(quote "stdin-runtime-only-not-logged")"
log "step=$(quote "stop-recovery-for-sta-attempt") status=$(quote "starting")"
sh "$ap_setup_script" stop >>"$connect_log" 2>&1 || true
log "step=$(quote "stop-recovery-for-sta-attempt") status=$(quote "done")"

"$nmcli_bin" device set "$iface" managed yes >/dev/null 2>&1 || true
cleanup_failed_attempt

log "step=$(quote "create-temporary-profile") status=$(quote "starting") persistence=$(quote "save-no")"
"$nmcli_bin" connection add type wifi ifname "$iface" con-name "$temporary_connection" ssid "$target_ssid" save no >>"$connect_log" 2>&1 ||
  fail "temporary-profile-create-failed"
"$nmcli_bin" connection modify "$temporary_connection" connection.autoconnect no >>"$connect_log" 2>&1 || true
if [ -n "$target_password" ]; then
  "$nmcli_bin" connection modify "$temporary_connection" 802-11-wireless-security.key-mgmt wpa-psk >>"$connect_log" 2>&1 ||
    fail "temporary-profile-security-failed"
  "$nmcli_bin" connection modify "$temporary_connection" 802-11-wireless-security.psk "$target_password" >/dev/null 2>&1 ||
    fail "temporary-profile-secret-attach-failed"
fi
unset target_password

log "step=$(quote "connect-temporary-profile") status=$(quote "starting")"
if ! "$nmcli_bin" --wait 45 connection up "$temporary_connection" ifname "$iface" >>"$connect_log" 2>&1; then
  log "step=$(quote "connect-temporary-profile") status=$(quote "failed")"
  cleanup_failed_attempt
  restart_recovery_best_effort
  exit 1
fi

elapsed=0
validated="no"
while [ "$elapsed" -lt "$timeout_seconds" ]; do
  ssid_now="$(active_ssid || true)"
  ip_now="$(ip_address || true)"
  gateway_now="$(gateway || true)"
  if [ "$ssid_now" = "$target_ssid" ] && [ -n "$ip_now" ] && [ -n "$gateway_now" ]; then
    if ping -c 1 -W 2 "$gateway_now" >/dev/null 2>&1; then
      validated="yes"
      break
    fi
  fi
  sleep 3
  elapsed=$((elapsed + 3))
done

if [ "$validated" = "yes" ]; then
  log "status=$(quote "success") connected_ssid=$(quote "$target_ssid") ip=$(quote "$ip_now") gateway=$(quote "$gateway_now") elapsed_seconds=$(quote "$elapsed") recovery=$(quote "stopped")"
  exit 0
fi

log "status=$(quote "failure") reason=$(quote "validation-timeout") elapsed_seconds=$(quote "$elapsed") recovery=$(quote "restart-attempted")"
cleanup_failed_attempt
restart_recovery_best_effort
exit 1
