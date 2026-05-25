#!/bin/sh
set -eu

runtime_config="${WIFI_KIT_RUNTIME_CONFIG:-${HOME:-/tmp}/.config/wifi-kit/runtime.conf}"
iface="${WIFI_KIT_NM_AP_IFACE:-wlan0}"
ap_profile="${WIFI_KIT_NM_AP_PROFILE:-wifi-kit-recovery-ap}"
ap_ssid_default="Wifi-Kit-pocket-node"
ap_ssid="${WIFI_KIT_NM_AP_SSID:-}"
ap_ip="${WIFI_KIT_NM_AP_IP:-192.168.50.1/24}"
ap_channel="${WIFI_KIT_NM_AP_CHANNEL:-6}"
ap_band="${WIFI_KIT_NM_AP_BAND:-bg}"
ui_host="${WIFI_KIT_NM_AP_UI_HOST:-192.168.50.1}"
ui_port="${WIFI_KIT_NM_AP_UI_PORT:-80}"
ui_script="${WIFI_KIT_NM_AP_UI_SCRIPT:-/opt/seed-kit/wifi-kit/ui/serve-readonly.py}"
ui_log="${WIFI_KIT_NM_AP_UI_LOG:-/tmp/wifi-kit-nm-ap-lab-ui.log}"
ui_pidfile="${WIFI_KIT_NM_AP_UI_PIDFILE:-/tmp/wifi-kit-nm-ap-lab-ui.pid}"
test_ssid="${WIFI_KIT_NM_AP_TEST_SSID:-}"
test_profile="${WIFI_KIT_NM_AP_TEST_PROFILE:-}"
test_timeout="${WIFI_KIT_NM_AP_TEST_TIMEOUT:-30}"
apply="${WIFI_KIT_NM_AP_LAB_APPLY:-0}"

usage() {
  cat <<'EOF'
wifi-kit NetworkManager AP lab prototype

Usage:
  sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh audit
  sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh plan
  sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh simulate-test-connection
  sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh dry-run-ap-start
  sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh dry-run-ap-stop

Concrete lab modes, dry-run by default:
  sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh create-profile
  sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh start-hotspot
  sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh stop-hotspot
  sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh start-ui
  sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh stop-ui
  sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh status
  sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh rollback
  sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh return-last-good
  sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh return-primary

By default this helper only prints commands. To run a concrete lab mode on a
disposable node, set WIFI_KIT_NM_AP_LAB_APPLY=1 explicitly. It never stores
client Wi-Fi passwords, never deletes user profiles, never starts hostapd or
dnsmasq, and never reboots.

rollback is technical cleanup only. Use return-last-good to reconnect the last
validated Wi-Fi, or return-primary to reconnect the configured primary Wi-Fi.
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
  # Display-only quoting for dry-run output. Lab defaults use ASCII/simple
  # values; use env overrides without quotes for early experiments.
  printf "'%s'" "$1"
}

nmcli_path() {
  find_tool nmcli 2>/dev/null || true
}

iw_path() {
  find_tool iw 2>/dev/null || true
}

python_path() {
  find_tool python3 2>/dev/null || find_tool python 2>/dev/null || true
}

ss_path() {
  find_tool ss 2>/dev/null || true
}

effective_ap_ssid() {
  if [ -n "$ap_ssid" ]; then
    printf '%s\n' "$ap_ssid"
    return 0
  fi
  runtime_value ap_ssid "$ap_ssid_default"
}

effective_ap_password_marker() {
  if [ -n "$(runtime_value ap_password "")" ]; then
    printf '<runtime-ap-password>'
  else
    printf '<set-ap-password-in-runtime.conf>'
  fi
}

return_connection() {
  runtime_value return_connection ""
}

return_ssid() {
  runtime_value return_ssid ""
}

last_good_connection() {
  runtime_value last_good_connection ""
}

last_good_ssid() {
  runtime_value last_good_ssid ""
}

nm_read() {
  nmcli_bin=$(nmcli_path)
  [ -n "$nmcli_bin" ] || return 0
  "$nmcli_bin" "$@" 2>/dev/null || true
}

pid_is_alive() {
  pid=$1
  case "$pid" in
    ''|*[!0-9]*) return 1 ;;
  esac
  kill -0 "$pid" 2>/dev/null
}

ui_pid() {
  if [ -r "$ui_pidfile" ]; then
    IFS= read -r pid < "$ui_pidfile" 2>/dev/null || true
    printf '%s\n' "${pid:-}"
  fi
}

ui_is_active() {
  pid=$(ui_pid)
  [ -n "$pid" ] && pid_is_alive "$pid"
}

hotspot_is_active() {
  nmcli_bin=$(nmcli_path)
  [ -n "$nmcli_bin" ] || return 1
  "$nmcli_bin" -t --escape no -f NAME,TYPE,DEVICE connection show --active 2>/dev/null |
    awk -F: -v profile="$ap_profile" -v iface="$iface" '$1 == profile && ($2 == "wifi" || $2 == "802-11-wireless") && $3 == iface { found = 1 } END { exit found ? 0 : 1 }'
}

port_is_listening() {
  ss_bin=$(ss_path)
  [ -n "$ss_bin" ] || return 1
  "$ss_bin" -ltn 2>/dev/null |
    awk -v host="$ui_host" -v port=":$ui_port" '$4 ~ port { if ($4 ~ host || $4 ~ "0.0.0.0" || $4 ~ "\\[::\\]") found = 1 } END { exit found ? 0 : 1 }'
}

connection_exists() {
  profile=$1
  nmcli_bin=$(nmcli_path)
  [ -n "$profile" ] || return 1
  [ -n "$nmcli_bin" ] || return 1
  "$nmcli_bin" connection show "$profile" >/dev/null 2>&1
}

ssid_for_connection() {
  profile=$1
  nmcli_bin=$(nmcli_path)
  [ -n "$profile" ] || return 0
  [ -n "$nmcli_bin" ] || return 0
  "$nmcli_bin" -t --escape no -f 802-11-wireless.ssid connection show "$profile" 2>/dev/null |
    awk -F: '$1 == "802-11-wireless.ssid" { print $2; exit }'
}

connection_for_ssid() {
  target_ssid=$1
  nmcli_bin=$(nmcli_path)
  [ -n "$target_ssid" ] || return 0
  [ -n "$nmcli_bin" ] || return 0
  "$nmcli_bin" -t --escape no -f NAME,TYPE connection show 2>/dev/null |
    while IFS=: read -r profile typ; do
      [ "$typ" = "802-11-wireless" ] || [ "$typ" = "wifi" ] || continue
      ssid=$(ssid_for_connection "$profile")
      if [ "$ssid" = "$target_ssid" ]; then
        printf '%s\n' "$profile"
        return 0
      fi
    done
}

resolve_return_target() {
  kind=$1
  case "$kind" in
    last-good)
      configured_connection=$(last_good_connection)
      configured_ssid=$(last_good_ssid)
      ;;
    primary)
      configured_connection=$(return_connection)
      configured_ssid=$(return_ssid)
      ;;
    *)
      configured_connection=""
      configured_ssid=""
      ;;
  esac
  resolved_connection=""
  if [ -n "$configured_connection" ] && connection_exists "$configured_connection"; then
    resolved_connection=$configured_connection
  elif [ -n "$configured_ssid" ]; then
    resolved_connection=$(connection_for_ssid "$configured_ssid")
  fi
  printf '%s|%s|%s\n' "$configured_connection" "$configured_ssid" "$resolved_connection"
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

run_or_print() {
  label=$1
  shift
  rendered=$*
  kv "$label" "$rendered"
  if [ "$apply" = "1" ]; then
    "$@"
  fi
}

require_apply_tool() {
  tool=$1
  path=$(find_tool "$tool" 2>/dev/null || true)
  if [ -z "$path" ]; then
    kv "status" "refused"
    kv "reason" "$tool-missing"
    exit 1
  fi
  printf '%s\n' "$path"
}

print_hotspot_recommendation() {
  section "windows-compatibility-recommendation"
  kv "ssid" "ASCII simple, no spaces or accents for first Windows lab pass"
  kv "band" "$ap_band"
  kv "channel" "$ap_channel"
  kv "channel_reason" "fixed 2.4 GHz channel 1/6/11 avoids client confusion and AP+STA channel drift"
  kv "security" "WPA2-PSK only"
  kv "wpa3" "disabled"
  kv "nm_ipv4" "ipv4.method shared, $ap_ip"
  kv "ui" "$ui_host:$ui_port"
  kv "caveat" "single-radio AP+STA can still fail if target STA network uses another channel"
}

create_profile_commands() {
  ssid=$1
  pass_marker=$(effective_ap_password_marker)
  kv "01_create_ap" "nmcli connection add type wifi ifname $iface con-name $ap_profile autoconnect no ssid $(shell_quote "$ssid")"
  kv "02_mode" "nmcli connection modify $ap_profile 802-11-wireless.mode ap 802-11-wireless.band $ap_band 802-11-wireless.channel $ap_channel"
  kv "03_security" "nmcli connection modify $ap_profile wifi-sec.key-mgmt wpa-psk wifi-sec.psk $pass_marker wifi-sec.proto rsn wifi-sec.pairwise ccmp wifi-sec.group ccmp"
  kv "04_ipv4" "nmcli connection modify $ap_profile ipv4.method shared ipv4.addresses $ap_ip"
  kv "05_ipv6" "nmcli connection modify $ap_profile ipv6.method ignore"
  kv "06_autoconnect" "nmcli connection modify $ap_profile connection.autoconnect no"
}

ui_start_command() {
  ssid=$1
  printf '%s\n' "nohup env WIFI_KIT_RECOVERY_BACKEND=nm-hotspot WIFI_KIT_NM_AP_LAB=1 WIFI_KIT_RUNTIME_CONFIG=$runtime_config python3 $ui_script --host $ui_host --port $ui_port --recovery-mode --recovery-ssid $(shell_quote "$ssid") --recovery-ip $ui_host >$ui_log 2>&1 &"
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
  kv "ap_band" "$ap_band"
  kv "ap_channel" "$ap_channel"
  kv "ui_bind" "$ui_host:$ui_port"
  kv "nmcli" "${nmcli_bin:-missing}"
  kv "iw" "${iw_bin:-missing}"
  kv "apply_gate" "$apply"
  kv "secret_policy" "no client Wi-Fi password is read, logged, or stored"

  print_hotspot_recommendation

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
  kv "windows_visibility_guess" "prefer WPA2-only RSN/CCMP, fixed 2.4 GHz channel, ASCII SSID"
  kv "v1_recommendation" "keep hostapd AP-only recovery as stable product path until NM-only lab succeeds"
}

cmd_plan() {
  ssid=$(effective_ap_ssid)
  section "nm-ap-lab-plan"
  kv "status" "planned"
  kv "network_writes" "false-by-default"
  kv "apply_gate" "set WIFI_KIT_NM_AP_LAB_APPLY=1 to execute concrete modes"
  kv "scope" "prototype-isolated-no-change-to-current-recovery-flow"
  kv "goal" "test whether NetworkManager can own AP recovery and perform scan/test-connect without disrupting clients"
  kv "ap_profile" "$ap_profile"
  kv "ap_ssid" "$ssid"
  kv "ap_ip" "$ap_ip"
  kv "ui_bind" "$ui_host:$ui_port"

  print_hotspot_recommendation

  section "candidate-nm-commands"
  create_profile_commands "$ssid"
  kv "07_start_ap" "nmcli connection up $ap_profile ifname $iface"
  kv "08_start_ui" "python3 $ui_script --host $ui_host --port $ui_port --recovery-mode --recovery-ssid $(shell_quote "$ssid") --recovery-ip $ui_host"
  kv "09_scan_while_ap" "nmcli -t --escape no -f IN-USE,SSID,SIGNAL,SECURITY,CHAN device wifi list --rescan yes"
  kv "10_test_connect" "only if AP remains visible: try a target profile under bounded timeout"
  kv "11_stop_ui" "kill pid from $ui_pidfile"
  kv "12_stop_ap" "nmcli connection down $ap_profile"
  kv "13_delete_lab_profile" "nmcli connection delete $ap_profile"

  section "success-criteria"
  kv "ap_visible_windows" "required"
  kv "ap_visible_ios_android" "required"
  kv "client_stays_connected_during_scan" "required for product direction"
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
  kv "step_02" "scan using NetworkManager and confirm AP stays visible from Windows/iPhone/Android"
  kv "step_03" "if driver supports AP+STA, create or reuse target managed profile"
  kv "step_04" "try nmcli --wait $test_timeout connection up <target> ifname $iface"
  kv "step_05_success" "stop AP profile only after target Wi-Fi is validated"
  kv "step_05_failure" "keep or restore AP profile and report reason"
  kv "risk" "on single-radio #channels<=1, target network on another channel may force AP down"
}

cmd_create_profile() {
  ssid=$(effective_ap_ssid)
  section "nm-ap-lab-create-profile"
  kv "status" "$([ "$apply" = "1" ] && printf applying || printf dry-run)"
  kv "network_writes" "$([ "$apply" = "1" ] && printf true || printf false)"
  create_profile_commands "$ssid"
  if [ "$apply" = "1" ]; then
    nmcli_bin=$(require_apply_tool nmcli)
    ap_password=$(runtime_value ap_password "")
    if [ -z "$ap_password" ]; then
      kv "status" "refused"
      kv "reason" "ap-password-missing-in-runtime-config"
      exit 1
    fi
    "$nmcli_bin" connection add type wifi ifname "$iface" con-name "$ap_profile" autoconnect no ssid "$ssid"
    "$nmcli_bin" connection modify "$ap_profile" 802-11-wireless.mode ap 802-11-wireless.band "$ap_band" 802-11-wireless.channel "$ap_channel"
    "$nmcli_bin" connection modify "$ap_profile" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$ap_password" wifi-sec.proto rsn wifi-sec.pairwise ccmp wifi-sec.group ccmp
    "$nmcli_bin" connection modify "$ap_profile" ipv4.method shared ipv4.addresses "$ap_ip" ipv6.method ignore connection.autoconnect no
    kv "result" "profile-created-or-updated"
  fi
}

cmd_start_hotspot() {
  ssid=$(effective_ap_ssid)
  section "nm-ap-lab-start-hotspot"
  kv "status" "$([ "$apply" = "1" ] && printf applying || printf dry-run)"
  kv "network_writes" "$([ "$apply" = "1" ] && printf true || printf false)"
  kv "command" "nmcli connection up $ap_profile ifname $iface"
  kv "follow_up" "start-ui"
  kv "follow_up_command" "$(ui_start_command "$ssid")"
  if [ "$apply" = "1" ]; then
    nmcli_bin=$(require_apply_tool nmcli)
    "$nmcli_bin" connection up "$ap_profile" ifname "$iface"
    kv "result" "hotspot-start-requested"
    cmd_start_ui
  fi
}

cmd_stop_hotspot() {
  section "nm-ap-lab-stop-hotspot"
  kv "status" "$([ "$apply" = "1" ] && printf applying || printf dry-run)"
  kv "network_writes" "$([ "$apply" = "1" ] && printf true || printf false)"
  kv "command_01" "nmcli connection down $ap_profile"
  kv "command_02" "nmcli connection delete $ap_profile"
  if [ "$apply" = "1" ]; then
    nmcli_bin=$(require_apply_tool nmcli)
    "$nmcli_bin" connection down "$ap_profile" 2>/dev/null || true
    "$nmcli_bin" connection delete "$ap_profile" 2>/dev/null || true
    kv "result" "hotspot-stopped-and-lab-profile-deleted"
  fi
}

cmd_start_ui() {
  ssid=$(effective_ap_ssid)
  section "nm-ap-lab-start-ui"
  kv "status" "$([ "$apply" = "1" ] && printf applying || printf dry-run)"
  kv "network_writes" "false"
  kv "ui_pidfile" "$ui_pidfile"
  kv "ui_log" "$ui_log"
  kv "env" "WIFI_KIT_RECOVERY_BACKEND=nm-hotspot WIFI_KIT_NM_AP_LAB=1 WIFI_KIT_RUNTIME_CONFIG=$runtime_config"
  kv "command" "$(ui_start_command "$ssid")"
  if [ "$apply" = "1" ]; then
    python_bin=$(require_apply_tool python3)
    if ui_is_active; then
      kv "result" "ui-already-running"
      kv "pid" "$(ui_pid)"
      return 0
    fi
    WIFI_KIT_RECOVERY_BACKEND=nm-hotspot \
    WIFI_KIT_NM_AP_LAB=1 \
    WIFI_KIT_RUNTIME_CONFIG="$runtime_config" \
      nohup "$python_bin" "$ui_script" --host "$ui_host" --port "$ui_port" --recovery-mode --recovery-ssid "$ssid" --recovery-ip "$ui_host" >"$ui_log" 2>&1 &
    printf '%s\n' "$!" > "$ui_pidfile"
    kv "result" "ui-started"
    kv "pid" "$!"
  fi
}

cmd_stop_ui() {
  section "nm-ap-lab-stop-ui"
  kv "status" "$([ "$apply" = "1" ] && printf applying || printf dry-run)"
  kv "network_writes" "false"
  kv "pidfile" "$ui_pidfile"
  kv "command" "kill pid from $ui_pidfile"
  if [ "$apply" = "1" ]; then
    if [ -r "$ui_pidfile" ]; then
      pid=$(cat "$ui_pidfile")
      case "$pid" in
        ''|*[!0-9]*) kv "result" "invalid-pidfile" ;;
        *) kill "$pid" 2>/dev/null || true; rm -f "$ui_pidfile"; kv "result" "ui-stop-requested" ;;
      esac
    else
      kv "result" "ui-not-running"
    fi
  fi
}

cmd_status() {
  last_good_target=$(resolve_return_target last-good)
  primary_target=$(resolve_return_target primary)
  last_good_configured_connection=${last_good_target%%|*}
  last_good_tail=${last_good_target#*|}
  last_good_configured_ssid=${last_good_tail%%|*}
  last_good_resolved_connection=${last_good_tail#*|}
  primary_configured_connection=${primary_target%%|*}
  primary_tail=${primary_target#*|}
  primary_configured_ssid=${primary_tail%%|*}
  primary_resolved_connection=${primary_tail#*|}

  section "nm-ap-lab-status"
  kv "status" "ok"
  kv "network_writes" "false"
  if hotspot_is_active; then
    kv "hotspot_active" "true"
  else
    kv "hotspot_active" "false"
  fi
  if ui_is_active; then
    kv "ui_recovery_active" "true"
    kv "ui_pid" "$(ui_pid)"
  else
    kv "ui_recovery_active" "false"
    kv "ui_pid" "${ui_pid:-missing}"
  fi
  if port_is_listening; then
    kv "port_80_listening" "true"
  else
    kv "port_80_listening" "false"
  fi
  kv "ui_url" "http://$ui_host:$ui_port"
  kv "ui_pidfile" "$ui_pidfile"
  kv "ui_log" "$ui_log"
  kv "last_good_ssid" "${last_good_configured_ssid:-missing}"
  kv "last_good_connection" "${last_good_configured_connection:-missing}"
  kv "last_good_nm_connection" "${last_good_resolved_connection:-missing}"
  kv "primary_ssid" "${primary_configured_ssid:-missing}"
  kv "primary_connection" "${primary_configured_connection:-missing}"
  kv "primary_nm_connection" "${primary_resolved_connection:-missing}"
}

cmd_rollback() {
  section "nm-ap-lab-rollback"
  kv "status" "$([ "$apply" = "1" ] && printf applying || printf dry-run)"
  kv "network_writes" "$([ "$apply" = "1" ] && printf true || printf false)"
  kv "command_01" "stop-ui"
  kv "command_02" "nmcli connection down $ap_profile"
  kv "command_03" "nmcli connection delete $ap_profile"
  kv "return_policy" "cleanup-only; use return-last-good or return-primary to reconnect"
  if [ "$apply" = "1" ]; then
    cmd_stop_ui
    nmcli_bin=$(require_apply_tool nmcli)
    "$nmcli_bin" connection down "$ap_profile" 2>/dev/null || true
    "$nmcli_bin" connection delete "$ap_profile" 2>/dev/null || true
    kv "result" "rollback-cleanup-requested"
  fi
}

cmd_return_target() {
  kind=$1
  target=$(resolve_return_target "$kind")
  configured_connection=${target%%|*}
  tail=${target#*|}
  configured_ssid=${tail%%|*}
  resolved_connection=${tail#*|}

  section "nm-ap-lab-return-$kind"
  kv "status" "$([ "$apply" = "1" ] && printf applying || printf dry-run)"
  kv "network_writes" "$([ "$apply" = "1" ] && printf true || printf false)"
  kv "target_kind" "$kind"
  kv "configured_ssid" "${configured_ssid:-missing}"
  kv "configured_connection" "${configured_connection:-missing}"
  kv "resolved_connection" "${resolved_connection:-missing}"
  kv "command_01" "stop-ui"
  kv "command_02" "nmcli connection down $ap_profile"
  kv "command_03" "nmcli connection delete $ap_profile"
  if [ -n "$resolved_connection" ]; then
    kv "command_04_return" "nmcli connection up $resolved_connection ifname $iface"
  else
    kv "command_04_return" "refused: target connection unknown"
  fi

  if [ "$apply" = "1" ]; then
    if [ -z "$resolved_connection" ]; then
      kv "result" "refused"
      kv "reason" "target-connection-unknown"
      exit 1
    fi
    cmd_stop_ui
    nmcli_bin=$(require_apply_tool nmcli)
    "$nmcli_bin" connection down "$ap_profile" 2>/dev/null || true
    "$nmcli_bin" connection delete "$ap_profile" 2>/dev/null || true
    "$nmcli_bin" connection up "$resolved_connection" ifname "$iface"
    kv "result" "return-requested"
  fi
}

cmd_dry_run_ap_start() {
  cmd_create_profile
  cmd_start_hotspot
  cmd_start_ui
}

cmd_dry_run_ap_stop() {
  cmd_stop_ui
  cmd_stop_hotspot
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
  create-profile) cmd_create_profile ;;
  start-hotspot) cmd_start_hotspot ;;
  stop-hotspot) cmd_stop_hotspot ;;
  start-ui) cmd_start_ui ;;
  stop-ui) cmd_stop_ui ;;
  status) cmd_status ;;
  rollback) cmd_rollback ;;
  return-last-good) cmd_return_target last-good ;;
  return-primary) cmd_return_target primary ;;
  -h|--help|help) usage ;;
  *)
    usage
    exit 2
    ;;
esac
