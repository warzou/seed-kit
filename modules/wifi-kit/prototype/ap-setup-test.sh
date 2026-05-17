#!/bin/sh
set -eu

mode=""
iface="wlan0"
ap_ssid="SeedKit-Setup"
ap_channel=""
ap_duration_seconds="30"
temporary_hostapd_conf="/tmp/wifi-kit-hostapd-test.conf"

usage() {
  cat <<'EOF'
wifi-kit AP setup test prototype

Plan-only helper for the first minimal AP radio test. It never starts hostapd,
never starts dnsmasq, never changes NetworkManager, never changes Wi-Fi state,
never reads secrets, and never calls save_config.

Usage:
  sh modules/wifi-kit/prototype/ap-setup-test.sh preflight
  sh modules/wifi-kit/prototype/ap-setup-test.sh plan
  sh modules/wifi-kit/prototype/ap-setup-test.sh apply

Options:
  --iface <name>           Wi-Fi interface. Default: wlan0
  --ssid <name>            Future AP SSID. Default: SeedKit-Setup
  --channel <number>       Future AP channel. Default: current wlan0 channel if detected
  --duration-seconds <n>   Future short AP test duration. Default: 30
EOF
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
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
  kv "future_ap_ssid" "$ap_ssid"
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
  if [ -z "$ap_channel" ]; then
    ap_channel="${channel:-6}"
  fi

  printf '[wifi-kit] AP setup test plan\n'
  kv "mode" "plan-only"
  kv "network_writes" "false"
  kv "real_apply_allowed" "false"
  kv "interface" "$iface"
  kv "future_ap_ssid" "$ap_ssid"
  kv "future_ap_channel" "$ap_channel"
  kv "duration_seconds" "$ap_duration_seconds"
  kv "ap_sta_same_channel_constraint" "yes"
  kv "recommended_first_test" "ap-only-short-duration"

  section "future-ap-only-short-test"
  kv "01.preflight" "sh modules/wifi-kit/prototype/ap-setup-test.sh preflight"
  kv "02.write_temp_hostapd_config" "create $temporary_hostapd_conf with ssid=$ap_ssid channel=$ap_channel wpa=2"
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

while [ "$#" -gt 0 ]; do
  case "$1" in
    preflight|plan|apply)
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
  *)
    usage
    exit 2
    ;;
esac
