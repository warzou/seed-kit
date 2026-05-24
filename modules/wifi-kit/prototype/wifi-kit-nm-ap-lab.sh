#!/bin/sh
set -eu

runtime_config="${WIFI_KIT_RUNTIME_CONFIG:-${HOME:-/tmp}/.config/wifi-kit/runtime.conf}"
iface="${WIFI_KIT_NM_AP_IFACE:-wlan0}"
ap_profile="${WIFI_KIT_NM_AP_PROFILE:-wifi-kit-recovery-ap}"
ap_ssid_default="Wifi-Kit-pocket-node"
ap_ssid="${WIFI_KIT_NM_AP_SSID:-}"
ap_ip="${WIFI_KIT_NM_AP_IP:-192.168.50.1/24}"
ui_host="${WIFI_KIT_NM_AP_UI_HOST:-192.168.50.1}"
ui_port="${WIFI_KIT_NM_AP_UI_PORT:-80}"
test_ssid="${WIFI_KIT_NM_AP_TEST_SSID:-}"
test_profile="${WIFI_KIT_NM_AP_TEST_PROFILE:-}"
test_timeout="${WIFI_KIT_NM_AP_TEST_TIMEOUT:-30}"

usage() {
  cat <<'EOF'
wifi-kit NetworkManager AP lab prototype

Usage:
  sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh audit
  sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh plan
  sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh simulate-test-connection
  sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh dry-run-ap-start
  sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh dry-run-ap-stop

This helper is experimental and read-only. It never starts AP mode, never
changes NetworkManager, never stores Wi-Fi client passwords, and never reboots.
It prints the exact NetworkManager commands to test later on disposable
hardware.
EOF
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

shell_quote() {
  # Display-only quoting for the dry-run commands below. These commands are not
  # executed by this helper; avoid depending on sed on minimal target systems.
  printf "'%s'" "$1"
}

nmcli_path() {
  find_tool nmcli 2>/dev/null || true
}

iw_path() {
  find_tool iw 2>/dev/null || true
}

effective_ap_ssid() {
  if [ -n "$ap_ssid" ]; then
    printf '%s\n' "$ap_ssid"
    return 0
  fi
  runtime_value ap_ssid "$ap_ssid_default"
}

nm_read() {
  nmcli_bin=$(nmcli_path)
  [ -n "$nmcli_bin" ] || return 0
  "$nmcli_bin" "$@" 2>/dev/null || true
}

iw_valid_combinations() {
  iw_bin=$(iw_path)
  [ -n "$iw_bin" ] || return 0
  "$iw_bin" list 2>/dev/null |
    awk '
      /valid interface combinations:/ { in_combo = 1 }
      in_combo { print }
      in_combo && /Supported commands:/ { exit }
    '
}

cmd_audit() {
  ssid=$(effective_ap_ssid)
  nmcli_bin=$(nmcli_path)
  iw_bin=$(iw_path)

  section "nm-ap-lab-audit"
  kv "status" "ok"
  kv "mode" "audit"
  kv "network_writes" "false"
  kv "runtime_config" "$runtime_config"
  kv "iface" "$iface"
  kv "ap_profile" "$ap_profile"
  kv "ap_ssid" "$ssid"
  kv "ap_ip" "$ap_ip"
  kv "ui_bind" "$ui_host:$ui_port"
  kv "nmcli" "${nmcli_bin:-missing}"
  kv "iw" "${iw_bin:-missing}"
  kv "secret_policy" "no client Wi-Fi password is read, logged, or stored"

  section "networkmanager-device-status"
  if [ -n "$nmcli_bin" ]; then
    nm_read -t -f DEVICE,TYPE,STATE,CONNECTION device status
  else
    kv "nmcli_status" "missing"
  fi

  section "networkmanager-wifi-profiles"
  if [ -n "$nmcli_bin" ]; then
    nm_read -t --escape no -f NAME,TYPE,AUTOCONNECT,AUTOCONNECT-PRIORITY connection show |
      awk -F: '$2 == "wifi" { print }'
  else
    kv "nmcli_profiles" "unavailable"
  fi

  section "iw-valid-interface-combinations"
  if [ -n "$iw_bin" ]; then
    iw_valid_combinations
  else
    kv "iw_valid_combinations" "unavailable-iw-missing"
    kv "interpretation" "install iw for a read-only hardware capability audit before real AP+STA tests"
  fi

  section "feasibility-notes"
  kv "ap_sta_product_status" "experimental-lab-only"
  kv "known_constraint" "single-radio AP+STA requires same channel when driver reports #channels <= 1"
  kv "zero2w_risk" "brcmfmac may advertise combinations that are unstable in real AP+STA or scan activity"
  kv "v1_recommendation" "keep hostapd AP-only recovery as stable product path until NM-only lab succeeds"
}

cmd_plan() {
  ssid=$(effective_ap_ssid)
  section "nm-ap-lab-plan"
  kv "status" "planned"
  kv "network_writes" "false"
  kv "scope" "prototype-isolated-no-change-to-current-recovery-flow"
  kv "goal" "test whether NetworkManager can own AP recovery and perform scan/test-connect without disrupting clients"
  kv "ap_profile" "$ap_profile"
  kv "ap_ssid" "$ssid"
  kv "ap_ip" "$ap_ip"
  kv "ui_bind" "$ui_host:$ui_port"

  section "candidate-nm-commands"
  kv "01_create_ap" "nmcli connection add type wifi ifname $iface con-name $ap_profile autoconnect no ssid $(shell_quote "$ssid")"
  kv "02_mode_ap" "nmcli connection modify $ap_profile 802-11-wireless.mode ap 802-11-wireless.band bg"
  kv "03_security" "nmcli connection modify $ap_profile wifi-sec.key-mgmt wpa-psk wifi-sec.psk <runtime-ap-password>"
  kv "04_ipv4_shared" "nmcli connection modify $ap_profile ipv4.method shared ipv4.addresses $ap_ip"
  kv "05_ipv6" "nmcli connection modify $ap_profile ipv6.method ignore"
  kv "06_start_ap" "nmcli connection up $ap_profile ifname $iface"
  kv "07_start_ui" "python3 /opt/seed-kit/wifi-kit/ui/serve-readonly.py --host $ui_host --port $ui_port --recovery-mode --recovery-ssid $(shell_quote "$ssid") --recovery-ip ${ui_host}"
  kv "08_scan_while_ap" "nmcli -t --escape no -f IN-USE,SSID,SIGNAL,SECURITY,CHAN device wifi list --rescan yes"
  kv "09_test_connect" "only if AP remains visible: try a target profile under bounded timeout"
  kv "10_stop_ap" "nmcli connection down $ap_profile"
  kv "11_delete_lab_profile" "nmcli connection delete $ap_profile"

  section "success-criteria"
  kv "ap_visible_during_scan" "required"
  kv "client_stays_connected_during_scan" "required"
  kv "test_connect_success_path" "new Wi-Fi active, AP disappears only after explicit final switch"
  kv "test_connect_failure_path" "AP remains available and UI reports reason"
  kv "forbidden" "no reboot, no profile deletion outside $ap_profile, no fallback return_connection during runtime"
}

cmd_simulate_test_connection() {
  section "nm-ap-lab-simulate-test-connection"
  kv "status" "planned"
  kv "network_writes" "false"
  kv "test_ssid" "${test_ssid:-missing-set-WIFI_KIT_NM_AP_TEST_SSID}"
  kv "test_profile" "${test_profile:-missing-set-WIFI_KIT_NM_AP_TEST_PROFILE}"
  kv "timeout_seconds" "$test_timeout"
  kv "step_01" "keep NM AP profile active"
  kv "step_02" "scan using NetworkManager and confirm AP stays visible from client"
  kv "step_03" "if driver supports AP+STA, create or reuse target managed profile"
  kv "step_04" "try nmcli --wait $test_timeout connection up <target> ifname $iface"
  kv "step_05_success" "stop AP profile only after target Wi-Fi is validated"
  kv "step_05_failure" "keep or restore AP profile and report reason"
  kv "risk" "on single-radio #channels<=1, target network on another channel may force AP down"
}

cmd_dry_run_ap_start() {
  ssid=$(effective_ap_ssid)
  section "nm-ap-lab-dry-run-ap-start"
  kv "status" "planned"
  kv "network_writes" "false"
  kv "command_01" "nmcli connection add type wifi ifname $iface con-name $ap_profile autoconnect no ssid $(shell_quote "$ssid")"
  kv "command_02" "nmcli connection modify $ap_profile 802-11-wireless.mode ap wifi-sec.key-mgmt wpa-psk wifi-sec.psk <runtime-ap-password>"
  kv "command_03" "nmcli connection modify $ap_profile ipv4.method shared ipv4.addresses $ap_ip ipv6.method ignore"
  kv "command_04" "nmcli connection up $ap_profile ifname $iface"
  kv "command_05" "python3 /opt/seed-kit/wifi-kit/ui/serve-readonly.py --host $ui_host --port $ui_port --recovery-mode --recovery-ssid $(shell_quote "$ssid") --recovery-ip $ui_host"
}

cmd_dry_run_ap_stop() {
  section "nm-ap-lab-dry-run-ap-stop"
  kv "status" "planned"
  kv "network_writes" "false"
  kv "command_01" "nmcli connection down $ap_profile"
  kv "command_02" "nmcli connection delete $ap_profile"
  kv "command_03_optional_return" "nmcli connection up <known-good-profile> ifname $iface"
}

if [ "$#" -ne 1 ]; then
  usage
  exit 2
fi

case "$1" in
  audit) cmd_audit ;;
  plan) cmd_plan ;;
  simulate-test-connection) cmd_simulate_test_connection ;;
  dry-run-ap-start) cmd_dry_run_ap_start ;;
  dry-run-ap-stop) cmd_dry_run_ap_stop ;;
  -h|--help|help) usage ;;
  *)
    usage
    exit 2
    ;;
esac
