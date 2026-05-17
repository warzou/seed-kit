#!/bin/sh
set -eu

mode=""
iface="wlan0"
ap_ssid=""
ap_channel=""
ap_duration_seconds="30"
temporary_hostapd_conf="/tmp/wifi-kit-hostapd-test.conf"
confirm_phrase=""
dangerous_real_apply="0"

usage() {
  cat <<'EOF'
wifi-kit AP setup test prototype

Plan-first helper for the first minimal AP radio test. By default it never
starts hostapd, never starts dnsmasq, never changes NetworkManager, never
changes persistent Wi-Fi state, never logs secrets, and never calls save_config.

Usage:
  sh modules/wifi-kit/prototype/ap-setup-test.sh preflight
  sh modules/wifi-kit/prototype/ap-setup-test.sh plan
  sh modules/wifi-kit/prototype/ap-setup-test.sh apply
  sh modules/wifi-kit/prototype/ap-setup-test.sh apply-short-test \
    --confirm "WIFI-KIT AP SHORT TEST"

Options:
  --iface <name>           Wi-Fi interface. Default: wlan0
  --ssid <name>            Future AP SSID. Default: Wifi-Kit-<hostname>
  --channel <number>       Future AP channel. Default: current wlan0 channel if detected
  --duration-seconds <n>   Future short AP test duration. Default: 30
  --confirm <phrase>       Required for apply-short-test: WIFI-KIT AP SHORT TEST
  --dangerous-real-apply   Future execution gate. Do not use without a separate validation prompt.
EOF
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_number() {
  name=$1
  value=$2
  case "$value" in
    ''|*[!0-9]*) fail "$name must be a non-negative integer" ;;
  esac
}

kv() {
  printf '%s=%s\n' "$1" "$2"
}

section() {
  printf '\n[%s]\n' "$1"
}

shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
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

host_label() {
  hostname 2>/dev/null | sed 's/[^A-Za-z0-9_.-]/-/g; s/^-*//; s/-*$//' | sed -n '1p'
}

default_ap_ssid() {
  label="$(host_label)"
  if [ -n "$label" ]; then
    printf 'Wifi-Kit-%s\n' "$label"
  else
    printf 'Wifi-Kit-node\n'
  fi
}

effective_ap_ssid() {
  if [ -n "$ap_ssid" ]; then
    printf '%s\n' "$ap_ssid"
  else
    default_ap_ssid
  fi
}

tool_state() {
  tool=$1
  path="$(find_tool "$tool" 2>/dev/null || true)"
  if [ -n "$path" ]; then
    kv "${tool}_present" "yes"
    kv "${tool}_path" "$path"
  else
    kv "${tool}_present" "no"
    kv "${tool}_path" "missing"
  fi
}

current_channel() {
  iw_bin="$(find_tool iw 2>/dev/null || true)"
  [ -n "$iw_bin" ] || return 0
  "$iw_bin" dev "$iface" info 2>/dev/null |
    awk '$1 == "channel" { print $2; exit }'
}

networkmanager_active() {
  nmcli_bin="$(find_tool nmcli 2>/dev/null || true)"
  [ -n "$nmcli_bin" ] || return 1
  nm_state="$("$nmcli_bin" -t -f RUNNING general 2>/dev/null | sed -n '1p' || true)"
  [ "$nm_state" = "running" ]
}

active_connection() {
  nmcli_bin="$(find_tool nmcli 2>/dev/null || true)"
  [ -n "$nmcli_bin" ] || return 0
  "$nmcli_bin" -t -f DEVICE,CONNECTION device status 2>/dev/null |
    awk -F: -v iface="$iface" '$1 == iface { print $2; exit }'
}

device_state() {
  nmcli_bin="$(find_tool nmcli 2>/dev/null || true)"
  [ -n "$nmcli_bin" ] || return 0
  "$nmcli_bin" -t -f DEVICE,STATE device status 2>/dev/null |
    awk -F: -v iface="$iface" '$1 == iface { print $2; exit }'
}

supports_ap_sta_same_channel() {
  iw_bin="$(find_tool iw 2>/dev/null || true)"
  [ -n "$iw_bin" ] || return 1
  "$iw_bin" list 2>/dev/null |
    awk '
      /valid interface combinations:/ { in_combo = 1 }
      in_combo && /^[[:space:]]+\*/ {
        managed_ap = index($0, "#{ managed } <= 1") && index($0, "#{ AP } <= 1")
      }
      in_combo && managed_ap && index($0, "#channels <= 1") { found = 1 }
      END { exit found ? 0 : 1 }
    '
}

cmd_preflight() {
  channel="$(current_channel || true)"
  active="$(active_connection || true)"
  state="$(device_state || true)"
  ssid="$(effective_ap_ssid)"
  if [ -z "$ap_channel" ]; then
    ap_channel="${channel:-unknown}"
  fi

  printf '[wifi-kit] AP setup test preflight\n'
  kv "mode" "preflight-readonly"
  kv "network_writes" "false"
  kv "ap_started" "false"
  kv "hostapd_started" "false"
  kv "dnsmasq_started" "false"
  kv "networkmanager_modified" "false"
  kv "save_config" "not-called"
  kv "interface" "$iface"
  kv "hostname" "$(host_label || true)"
  kv "future_ap_ssid" "$ssid"
  tool_state hostapd
  tool_state dnsmasq
  tool_state iw
  tool_state nmcli
  kv "backend_networkmanager_active" "$(networkmanager_active && printf yes || printf no)"
  kv "nm_device_state" "${state:-unknown}"
  kv "nm_active_connection" "${active:-unknown}"
  kv "current_channel" "${channel:-unknown}"
  kv "future_ap_channel" "$ap_channel"
  kv "ap_sta_same_channel_constraint" "yes"
  kv "ap_sta_same_channel_supported" "$(supports_ap_sta_same_channel && printf yes || printf no)"
  kv "recommended_first_test" "ap-only-short-duration"
  kv "preflight_status" "OK"
}

cmd_plan() {
  channel="$(current_channel || true)"
  ssid="$(effective_ap_ssid)"
  if [ -z "$ap_channel" ]; then
    ap_channel="${channel:-6}"
  fi

  printf '[wifi-kit] AP setup test plan\n'
  kv "mode" "plan-only"
  kv "network_writes" "false"
  kv "real_apply_allowed" "false"
  kv "interface" "$iface"
  kv "future_ap_ssid" "$ssid"
  kv "future_ap_channel" "$ap_channel"
  kv "duration_seconds" "$ap_duration_seconds"
  kv "ap_sta_same_channel_constraint" "yes"
  kv "recommended_first_test" "ap-only-short-duration"

  section "future-ap-only-short-test"
  kv "01.preflight" "sh modules/wifi-kit/prototype/ap-setup-test.sh preflight"
  kv "02.write_temp_hostapd_config" "create $temporary_hostapd_conf with ssid=$ssid channel=$ap_channel wpa=2"
  kv "03.runtime_secret" "WPA2 passphrase supplied at runtime only; never repo/log/diff"
  kv "04.start_hostapd_foreground" "hostapd $temporary_hostapd_conf"
  kv "05.observe_phone_visibility" "confirm SSID appears from phone"
  kv "06.stop_hostapd" "terminate foreground hostapd after ${ap_duration_seconds}s or manual stop"
  kv "07.cleanup" "remove $temporary_hostapd_conf"
  kv "08.verify" "iw dev; nmcli device status; SSH route still expected via wlan0"

  section "future-ap-sta-test"
  kv "01.require_same_channel" "AP channel must match STA channel on Raspberry Pi Zero 2 W"
  kv "02.current_sta_channel" "${channel:-unknown}"
  kv "03.ap_channel_candidate" "$ap_channel"
  kv "04.networkmanager_coordination" "not implemented; do not modify NM in this prototype"

  section "forbidden-now"
  kv "hostapd_start" "no"
  kv "dnsmasq_start" "no"
  kv "networkmanager_changes" "no"
  kv "wlan0_changes" "no"
  kv "reboot" "no"
  kv "save_config" "no"
  kv "captive_portal" "no"
}

write_hostapd_config_plan() {
  ssid=$1
  channel=$2

  cat <<EOF
interface=$iface
driver=nl80211
ssid=$ssid
hw_mode=g
channel=$channel
ieee80211n=1
wmm_enabled=1
auth_algs=1
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_passphrase=<runtime-only-secret>
EOF
}

write_hostapd_config_real() {
  ssid=$1
  channel=$2
  passphrase=$3

  cat >"$temporary_hostapd_conf" <<EOF
interface=$iface
driver=nl80211
ssid=$ssid
hw_mode=g
channel=$channel
ieee80211n=1
wmm_enabled=1
auth_algs=1
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_passphrase=$passphrase
EOF
  chmod 600 "$temporary_hostapd_conf"
}

runtime_ap_passphrase() {
  if [ -n "${WIFI_KIT_AP_PSK:-}" ]; then
    printf '%s\n' "$WIFI_KIT_AP_PSK"
    return 0
  fi
  if [ -r /proc/sys/kernel/random/uuid ]; then
    uuid="$(sed 's/-//g; s/^\(.\{16\}\).*/\1/' /proc/sys/kernel/random/uuid)"
    printf 'WifiKit%s\n' "$uuid"
  else
    printf 'WifiKit%sTest\n' "$(date +%s)"
  fi
}

cmd_apply_short_test() {
  [ "$confirm_phrase" = "WIFI-KIT AP SHORT TEST" ] ||
    fail "apply-short-test requires --confirm \"WIFI-KIT AP SHORT TEST\""

  channel="$(current_channel || true)"
  ssid="$(effective_ap_ssid)"
  if [ -z "$ap_channel" ]; then
    ap_channel="${channel:-6}"
  fi
  require_number "--duration-seconds" "$ap_duration_seconds"
  if [ "$ap_duration_seconds" -gt 30 ]; then
    fail "--duration-seconds must be <= 30 for the first AP test"
  fi

  hostapd_bin="$(find_tool hostapd 2>/dev/null || true)"
  if [ -z "$hostapd_bin" ]; then
    hostapd_bin="hostapd"
  fi

  quoted_conf=$(shell_quote "$temporary_hostapd_conf")
  quoted_hostapd=$(shell_quote "$hostapd_bin")

  printf '[wifi-kit] AP setup short test gated plan\n'
  kv "mode" "apply-short-test-plan"
  kv "real_apply_requested" "$dangerous_real_apply"
  kv "network_writes" "false"
  kv "hostapd_started" "false"
  kv "dnsmasq_started" "false"
  kv "networkmanager_modified" "false"
  kv "save_config" "not-called"
  kv "interface" "$iface"
  kv "ap_ssid" "$ssid"
  kv "ap_channel" "$ap_channel"
  kv "duration_seconds" "$ap_duration_seconds"
  kv "temporary_hostapd_conf" "$temporary_hostapd_conf"
  kv "hostapd_present" "$(find_tool hostapd >/dev/null 2>&1 && printf yes || printf no)"
  kv "hostapd_command" "$hostapd_bin $temporary_hostapd_conf"

  section "temporary-hostapd-config"
  write_hostapd_config_plan "$ssid" "$ap_channel"

  section "exact-command"
  kv "01.write_config" "create $quoted_conf mode 600 with runtime-only passphrase"
  kv "02.run_foreground" "timeout ${ap_duration_seconds}s $quoted_hostapd $quoted_conf"
  kv "03.cleanup" "rm -f $quoted_conf"
  kv "04.verify" "systemctl is-active hostapd || true; iw dev; nmcli device status"
  kv "05.next_root_command" "sudo sh modules/wifi-kit/prototype/ap-setup-test.sh apply-short-test --dangerous-real-apply --confirm \"WIFI-KIT AP SHORT TEST\""

  section "guards"
  kv "apply_without_extra_gate" "plan-only"
  kv "real_execution_requires" "--dangerous-real-apply plus separate explicit validation"
  kv "root_required" "yes"
  kv "ap_mode" "ap-only-short-duration"
  kv "dnsmasq" "not-used"
  kv "captive_portal" "not-used"
  kv "networkmanager_changes" "none"
  kv "persistent_system_files" "none"
  kv "save_config" "not-called"

  if [ "$dangerous_real_apply" != "1" ]; then
    section "apply"
    kv "apply_status" "refused-plan-only"
    return 0
  fi

  if [ "$(id -u 2>/dev/null || printf 1)" != "0" ]; then
    fail "real AP short test requires root; run: sudo sh modules/wifi-kit/prototype/ap-setup-test.sh apply-short-test --dangerous-real-apply --confirm \"WIFI-KIT AP SHORT TEST\""
  fi
  find_tool hostapd >/dev/null 2>&1 || fail "hostapd is required"

  passphrase="$(runtime_ap_passphrase)"
  case "$passphrase" in
    ????????*) ;;
    *) fail "runtime AP passphrase must be at least 8 characters" ;;
  esac

  cleanup() {
    rm -f "$temporary_hostapd_conf"
  }
  trap cleanup EXIT INT TERM HUP
  cleanup

  umask 077
  write_hostapd_config_real "$ssid" "$ap_channel" "$passphrase"

  section "real-apply"
  kv "apply_status" "starting"
  kv "ap_ssid" "$ssid"
  kv "duration_seconds" "$ap_duration_seconds"
  kv "temporary_hostapd_conf" "$temporary_hostapd_conf"
  kv "hostapd_command" "$hostapd_bin $temporary_hostapd_conf"
  kv "runtime_secret" "not-logged"
  kv "phone_check" "look for SSID $ssid now"

  set +e
  timeout "${ap_duration_seconds}s" "$hostapd_bin" "$temporary_hostapd_conf"
  hostapd_rc=$?
  set -e

  cleanup
  trap - EXIT INT TERM HUP

  section "post-check"
  kv "hostapd_exit_code" "$hostapd_rc"
  kv "config_cleanup" "done"
  if [ "$hostapd_rc" -eq 124 ]; then
    kv "apply_status" "completed-timeout"
    return 0
  fi
  if [ "$hostapd_rc" -eq 0 ]; then
    kv "apply_status" "completed"
    return 0
  fi
  kv "apply_status" "hostapd-failed"
  return "$hostapd_rc"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    preflight|plan|apply|apply-short-test)
      [ -z "$mode" ] || fail "choose only one mode"
      mode="$1"
      ;;
    --iface)
      [ "$#" -gt 1 ] || fail "--iface requires a value"
      iface="$2"
      shift
      ;;
    --ssid)
      [ "$#" -gt 1 ] || fail "--ssid requires a value"
      ap_ssid="$2"
      shift
      ;;
    --channel)
      [ "$#" -gt 1 ] || fail "--channel requires a value"
      ap_channel="$2"
      shift
      ;;
    --duration-seconds)
      [ "$#" -gt 1 ] || fail "--duration-seconds requires a value"
      ap_duration_seconds="$2"
      shift
      ;;
    --confirm)
      [ "$#" -gt 1 ] || fail "--confirm requires a value"
      confirm_phrase="$2"
      shift
      ;;
    --dangerous-real-apply)
      dangerous_real_apply="1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
  shift
done

case "${mode:-}" in
  preflight) cmd_preflight ;;
  plan) cmd_plan ;;
  apply) fail "AP setup apply is intentionally refused; run a reviewed real AP test separately" ;;
  apply-short-test) cmd_apply_short_test ;;
  *)
    usage
    exit 2
    ;;
esac
