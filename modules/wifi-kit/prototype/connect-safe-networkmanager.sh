#!/bin/sh
set -eu

mode=""
iface="wlan0"
target_ssid="${WIFI_KIT_TARGET_SSID:-<target-ssid>}"
temporary_name="wifi-kit-temp-target"
active_name=""
gateway=""
reachability_probe="1.1.1.1"
validation_timeout="20"
stay_on_target_seconds="0"
keep_ap_active="1"
confirm_phrase=""
understand_ssh_may_drop="0"
dangerous_real_apply="0"
rollback_delay_seconds="${WIFI_KIT_NM_ROLLBACK_DELAY_SECONDS:-90}"
rollback_log="${WIFI_KIT_NM_ROLLBACK_LOG:-/tmp/wifi-kit-nm-rollback.log}"
state_log="${WIFI_KIT_NM_STATE_LOG:-/tmp/wifi-kit-nm-connect-safe.log}"

usage() {
  cat <<'EOF'
wifi-kit NetworkManager connect-safe prototype

By default this script only plans a future NetworkManager-backed temporary
connect-safe transaction. Real apply is guarded because SSH may currently
depend on the Wi-Fi interface being changed.

Usage:
  sh modules/wifi-kit/prototype/connect-safe-networkmanager.sh preflight
  sh modules/wifi-kit/prototype/connect-safe-networkmanager.sh --dry-run
  sh modules/wifi-kit/prototype/connect-safe-networkmanager.sh --apply \
    --i-understand-ssh-may-drop --confirm "NETWORKMANAGER TEMP CONNECT"

Options:
  --iface <name>                  Wi-Fi interface. Default: wlan0
  --to <ssid>                     Future target SSID label for the plan.
  --temporary-name <name>         Future temporary NM profile name.
  --active-connection <name>      Current connection name, if already known.
  --gateway <ip>                  Expected gateway validation target.
  --reachability-probe <target>   Reachability probe. Default: 1.1.1.1
  --validation-timeout <seconds>  Validation timeout. Default: 20
  --stay-on-target-seconds <sec>  Future bounded target duration. Default: 60 for apply, 0 for dry-run.
  --keep-ap-active                Future AP policy: keep setup AP active. Default.
  --no-keep-ap-active             Future AP policy: allow AP stop after validation.
  --i-understand-ssh-may-drop     Required with --apply.
  --confirm <phrase>              Required with --apply: NETWORKMANAGER TEMP CONNECT
  --dangerous-real-apply          Future execution gate. Do not use without a separate validation prompt.
  --apply                         Prints the gated real-apply plan unless --dangerous-real-apply is also present.
EOF
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

kv() {
  printf '%s=%s\n' "$1" "$2"
}

warn_count=0
error_count=0

warn() {
  warn_count=$((warn_count + 1))
  kv "warning_${warn_count}" "$1"
}

error() {
  error_count=$((error_count + 1))
  kv "error_${error_count}" "$1"
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

cmd_preflight() {
  nmcli_bin="$(find_tool nmcli 2>/dev/null || true)"
  ip_bin="$(find_tool ip 2>/dev/null || true)"

  printf '[wifi-kit] connect-safe NetworkManager preflight\n'
  kv "mode" "preflight-readonly"
  kv "backend" "raspberrypi-networkmanager"
  kv "network_writes" "false"
  kv "secrets" "not-read-not-logged"
  kv "interface" "$iface"
  kv "temporary_connection" "$temporary_name"

  if [ -z "$nmcli_bin" ]; then
    kv "nmcli" "missing"
    error "nmcli-missing"
    kv "preflight_status" "ERROR"
    return 1
  fi
  kv "nmcli" "$nmcli_bin"

  nm_running="$("$nmcli_bin" -t -f RUNNING general 2>/dev/null | sed -n '1p' || true)"
  if [ "$nm_running" = "running" ]; then
    kv "networkmanager_active" "yes"
  else
    kv "networkmanager_active" "no"
    error "networkmanager-not-running"
  fi

  device_line="$("$nmcli_bin" -t -f DEVICE,TYPE,STATE,CONNECTION device status 2>/dev/null |
    awk -F: -v iface="$iface" '$1 == iface { print; exit }')"
  if [ -n "$device_line" ]; then
    device_type=$(printf '%s\n' "$device_line" | awk -F: '{print $2}')
    device_state=$(printf '%s\n' "$device_line" | awk -F: '{print $3}')
    detected_active=$(printf '%s\n' "$device_line" | awk -F: '{print $4}')
    kv "device_present" "yes"
    kv "device_type" "${device_type:-unknown}"
    kv "device_state" "${device_state:-unknown}"
    kv "active_connection" "${detected_active:-unknown}"
  else
    detected_active=""
    kv "device_present" "no"
    error "interface-not-found-in-networkmanager"
  fi

  case "${device_state:-}" in
    *connected*) ;;
    "") ;;
    *) warn "interface-not-connected" ;;
  esac

  if [ -z "${detected_active:-}" ] || [ "$detected_active" = "--" ]; then
    error "active-connection-missing"
  fi

  if "$nmcli_bin" connection show >/dev/null 2>&1; then
    kv "can_read_connections" "yes"
  else
    kv "can_read_connections" "no"
    error "cannot-read-networkmanager-connections"
  fi

  current_ssid=""
  if [ -n "${detected_active:-}" ] && [ "$detected_active" != "--" ]; then
    current_ssid="$("$nmcli_bin" -g 802-11-wireless.ssid connection show "$detected_active" 2>/dev/null | sed -n '1p' || true)"
  fi
  kv "current_ssid" "${current_ssid:-unknown}"

  current_gateway="$("$nmcli_bin" -g IP4.GATEWAY device show "$iface" 2>/dev/null | sed -n '1p' || true)"
  if [ -z "$current_gateway" ] && [ -n "$ip_bin" ]; then
    current_gateway="$("$ip_bin" route show default 2>/dev/null | awk '$1 == "default" {print $3; exit}' || true)"
  fi
  kv "current_gateway" "${current_gateway:-unknown}"
  [ -n "$current_gateway" ] || warn "gateway-not-detected"

  ssh_client="unknown"
  ssh_route="unknown"
  ssh_route_iface="unknown"
  if [ -n "${SSH_CONNECTION:-}" ]; then
    ssh_client="$(printf '%s\n' "$SSH_CONNECTION" | awk '{print $1}')"
  elif [ -n "${SSH_CLIENT:-}" ]; then
    ssh_client="$(printf '%s\n' "$SSH_CLIENT" | awk '{print $1}')"
  fi
  if [ "$ssh_client" != "unknown" ] && [ -n "$ip_bin" ]; then
    ssh_route="$("$ip_bin" route get "$ssh_client" 2>/dev/null | sed -n '1p' || true)"
    ssh_route_iface="$(printf '%s\n' "$ssh_route" | awk '{
      for (i = 1; i <= NF; i++) if ($i == "dev" && (i + 1) <= NF) { print $(i + 1); exit }
    }')"
  fi
  kv "ssh_client" "$ssh_client"
  kv "ssh_route" "${ssh_route:-unknown}"
  kv "ssh_route_interface" "${ssh_route_iface:-unknown}"
  [ "$ssh_route_iface" != "unknown" ] || warn "ssh-route-not-detected"

  temp_connection_line="$("$nmcli_bin" -t -f NAME,TYPE,DEVICE connection show 2>/dev/null |
    awk -F: -v name="$temporary_name" '$1 == name { print; exit }')"
  if [ -n "$temp_connection_line" ]; then
    temp_device=$(printf '%s\n' "$temp_connection_line" | awk -F: '{print $3}')
    kv "temporary_profile_present" "yes"
    kv "temporary_profile_device" "${temp_device:---}"
    warn "temporary-profile-residual-present"
    if [ -n "$temp_device" ] && [ "$temp_device" != "--" ]; then
      error "temporary-profile-residual-active"
    fi
  else
    kv "temporary_profile_present" "no"
    kv "temporary_profile_device" "--"
  fi

  if [ "$error_count" -gt 0 ]; then
    kv "preflight_status" "ERROR"
    return 1
  fi
  if [ "$warn_count" -gt 0 ]; then
    kv "preflight_status" "WARN"
    return 0
  fi
  kv "preflight_status" "OK"
}

require_apply_confirmation() {
  [ "$understand_ssh_may_drop" = "1" ] ||
    fail "--apply requires --i-understand-ssh-may-drop"
  [ "$confirm_phrase" = "NETWORKMANAGER TEMP CONNECT" ] ||
    fail "--apply requires --confirm \"NETWORKMANAGER TEMP CONNECT\""
}

require_number() {
  name=$1
  value=$2
  case "$value" in
    ''|*[!0-9]*) fail "$name must be a non-negative integer" ;;
  esac
}

cmd_apply_plan() {
  require_apply_confirmation
  require_number "--stay-on-target-seconds" "$stay_on_target_seconds"
  require_number "--validation-timeout" "$validation_timeout"
  require_number "rollback delay" "$rollback_delay_seconds"

  active_label=${active_name:-"<detect-and-require-current-active-connection>"}
  gateway_label=${gateway:-"<target-gateway-required-for-real-apply>"}
  quoted_temp=$(shell_quote "$temporary_name")
  quoted_iface=$(shell_quote "$iface")
  quoted_ssid=$(shell_quote "$target_ssid")
  quoted_active=$(shell_quote "$active_label")
  quoted_gateway=$(shell_quote "$gateway_label")
  quoted_probe=$(shell_quote "$reachability_probe")
  quoted_rollback_log=$(shell_quote "$rollback_log")
  quoted_state_log=$(shell_quote "$state_log")

  printf '[wifi-kit] connect-safe NetworkManager gated apply plan\n'
  kv "mode" "apply-plan"
  kv "backend" "raspberrypi-networkmanager"
  kv "real_apply_requested" "$dangerous_real_apply"
  kv "network_writes" "false"
  kv "secrets" "runtime-only-not-read-not-logged"
  kv "interface" "$iface"
  kv "active_connection_expected" "$active_label"
  kv "temporary_connection" "$temporary_name"
  kv "target_ssid" "$target_ssid"
  kv "target_gateway" "$gateway_label"
  kv "validation_timeout_seconds" "$validation_timeout"
  kv "stay_on_target_seconds" "$stay_on_target_seconds"
  kv "rollback_delay_seconds" "$rollback_delay_seconds"
  kv "rollback_log" "$rollback_log"
  kv "state_log" "$state_log"
  kv "save_config" "not-applicable"

  section "preflight-gates"
  kv "01.preflight" "sh $0 preflight --iface $quoted_iface --temporary-name $quoted_temp"
  kv "02.require_active_connection" "detected active connection must match $quoted_active when provided"
  kv "03.require_runtime_secret" "WIFI_KIT_TARGET_PSK must be present only in process environment"
  kv "04.require_no_residual_temp_profile" "nmcli -t -f NAME connection show must not contain $quoted_temp"

  section "future-real-transaction"
  kv "01.detect_active_connection" "nmcli -t -f DEVICE,CONNECTION device status"
  kv "02.snapshot_active_profile" "nmcli connection show $quoted_active"
  kv "03.create_temporary_profile" "nmcli connection add type wifi ifname $quoted_iface con-name $quoted_temp ssid $quoted_ssid"
  kv "04.attach_runtime_secret" "nmcli connection modify $quoted_temp 802-11-wireless-security.psk <runtime-only-secret>"
  kv "05.disable_autoconnect" "nmcli connection modify $quoted_temp connection.autoconnect no"
  kv "06.arm_rollback_guard" "(sleep $rollback_delay_seconds; nmcli connection up $quoted_active; nmcli connection delete $quoted_temp) > $quoted_rollback_log 2>&1 &"
  kv "07.rollback_guard_before_connect" "true"
  kv "08.connect_temporary" "nmcli connection up $quoted_temp"
  kv "09.validate_gateway_route" "ip route get $quoted_gateway"
  kv "10.validate_gateway_ping" "ping -c 1 -W $validation_timeout $quoted_gateway"
  kv "11.validate_reachability" "ping -c 1 -W $validation_timeout $quoted_probe"
  kv "12.write_non_secret_state" "append status only to $quoted_state_log"
  kv "13.bounded_stay" "sleep $stay_on_target_seconds"
  kv "14.rollback_active" "nmcli connection up $quoted_active"
  kv "15.cleanup_temporary_profile" "nmcli connection delete $quoted_temp"
  kv "16.verify_return_active" "nmcli -t -f DEVICE,CONNECTION device status"
  kv "17.verify_ssh_route" "ip route get <ssh-client-if-known>"

  section "guards"
  kv "apply_without_extra_gate" "plan-only"
  kv "real_execution_requires" "--dangerous-real-apply plus a separate explicit validation prompt"
  kv "must_not_modify_active_profile" "true"
  kv "temporary_profile_autoconnect" "off"
  kv "rollback_armed_before_bascule" "true"
  kv "cleanup_required" "true"
  kv "ap_actions" "none"
  kv "forbidden" "hostapd, dnsmasq, reboot, save_config, secret logging"

  if [ "$dangerous_real_apply" != "1" ]; then
    section "apply"
    kv "apply_status" "refused-plan-only"
    kv "next_real_command" "WIFI_KIT_TARGET_PSK=<runtime-secret> sh $0 --apply --dangerous-real-apply --i-understand-ssh-may-drop --confirm 'NETWORKMANAGER TEMP CONNECT' --to $quoted_ssid --active-connection $quoted_active --gateway $quoted_gateway --stay-on-target-seconds $stay_on_target_seconds"
    return 0
  fi
}

cmd_apply_real() {
  require_apply_confirmation
  require_number "--stay-on-target-seconds" "$stay_on_target_seconds"
  require_number "--validation-timeout" "$validation_timeout"
  require_number "rollback delay" "$rollback_delay_seconds"

  [ "$target_ssid" != "<target-ssid>" ] || fail "--to is required for real apply"
  [ -n "$gateway" ] || fail "--gateway is required for real apply"
  [ -n "${WIFI_KIT_TARGET_PSK:-}" ] || fail "WIFI_KIT_TARGET_PSK is required in the runtime environment"

  warn_count=0
  error_count=0
  cmd_preflight || fail "preflight failed; refusing real apply"

  nmcli_bin="$(find_tool nmcli 2>/dev/null || true)"
  ip_bin="$(find_tool ip 2>/dev/null || true)"
  ping_bin="$(find_tool ping 2>/dev/null || true)"
  [ -n "$nmcli_bin" ] || fail "nmcli is required"
  [ -n "$ip_bin" ] || fail "ip is required"
  [ -n "$ping_bin" ] || fail "ping is required"

  nm_running="$("$nmcli_bin" -t -f RUNNING general 2>/dev/null | sed -n '1p' || true)"
  [ "$nm_running" = "running" ] || fail "NetworkManager is not running"

  detected_active="$("$nmcli_bin" -t -f DEVICE,CONNECTION device status 2>/dev/null |
    awk -F: -v iface="$iface" '$1 == iface { print $2; exit }')"
  [ -n "$detected_active" ] && [ "$detected_active" != "--" ] ||
    fail "active NetworkManager connection not detected for $iface"

  if [ -n "$active_name" ] && [ "$detected_active" != "$active_name" ]; then
    fail "active connection mismatch: expected $active_name, got $detected_active"
  fi
  active_name=$detected_active

  if "$nmcli_bin" -t -f NAME connection show 2>/dev/null |
    awk -F: -v name="$temporary_name" '$1 == name { found=1 } END { exit found ? 0 : 1 }'; then
    fail "temporary profile already exists: $temporary_name"
  fi

  rollback_pid=""
  cleanup_after_failure() {
    "$nmcli_bin" connection up "$active_name" >/dev/null 2>&1 || true
    "$nmcli_bin" connection delete "$temporary_name" >/dev/null 2>&1 || true
    if [ -n "${rollback_pid:-}" ]; then
      kill "$rollback_pid" 2>/dev/null || true
    fi
  }
  trap cleanup_after_failure EXIT INT TERM HUP

  printf '[wifi-kit] connect-safe NetworkManager real apply\n'
  kv "mode" "apply-real"
  kv "backend" "raspberrypi-networkmanager"
  kv "network_writes" "true"
  kv "secrets" "runtime-only-not-logged"
  kv "interface" "$iface"
  kv "active_connection_initial" "$active_name"
  kv "temporary_connection" "$temporary_name"
  kv "target_ssid" "$target_ssid"
  kv "target_gateway" "$gateway"

  {
    printf 'started_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'interface=%s\n' "$iface"
    printf 'active_connection_initial=%s\n' "$active_name"
    printf 'temporary_connection=%s\n' "$temporary_name"
    printf 'target_ssid=%s\n' "$target_ssid"
  } >>"$state_log"

  "$nmcli_bin" connection add type wifi ifname "$iface" con-name "$temporary_name" ssid "$target_ssid" >/dev/null
  "$nmcli_bin" connection modify "$temporary_name" 802-11-wireless-security.key-mgmt wpa-psk >/dev/null
  "$nmcli_bin" connection modify "$temporary_name" 802-11-wireless-security.psk "$WIFI_KIT_TARGET_PSK" >/dev/null
  "$nmcli_bin" connection modify "$temporary_name" connection.autoconnect no >/dev/null

  (
    sleep "$rollback_delay_seconds"
    "$nmcli_bin" connection up "$active_name"
    "$nmcli_bin" connection delete "$temporary_name" >/dev/null 2>&1 || true
  ) >"$rollback_log" 2>&1 &
  rollback_pid=$!
  kv "rollback_guard_armed" "yes"
  kv "rollback_guard_pid" "$rollback_pid"

  "$nmcli_bin" connection up "$temporary_name" >/dev/null
  "$ip_bin" route get "$gateway" >/dev/null
  "$ping_bin" -c 1 -W "$validation_timeout" "$gateway" >/dev/null
  "$ping_bin" -c 1 -W "$validation_timeout" "$reachability_probe" >/dev/null
  sleep "$stay_on_target_seconds"
  "$nmcli_bin" connection up "$active_name" >/dev/null
  "$nmcli_bin" connection delete "$temporary_name" >/dev/null
  kill "$rollback_pid" 2>/dev/null || true
  trap - INT TERM HUP

  final_active="$("$nmcli_bin" -t -f DEVICE,CONNECTION device status 2>/dev/null |
    awk -F: -v iface="$iface" '$1 == iface { print $2; exit }')"
  kv "active_connection_final" "${final_active:-unknown}"
  [ "$final_active" = "$active_name" ] || fail "rollback verification failed"
  kv "apply_status" "OK"
}

if [ "${1:-}" = "preflight" ]; then
  mode="preflight"
  shift
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      [ -z "$mode" ] || fail "choose only one mode"
      mode="dry-run"
      ;;
    --apply)
      [ -z "$mode" ] || fail "choose only one mode"
      mode="apply"
      ;;
    --iface)
      [ "$#" -gt 1 ] || fail "--iface requires a value"
      iface="$2"
      shift
      ;;
    --to)
      [ "$#" -gt 1 ] || fail "--to requires a value"
      target_ssid="$2"
      shift
      ;;
    --temporary-name)
      [ "$#" -gt 1 ] || fail "--temporary-name requires a value"
      temporary_name="$2"
      shift
      ;;
    --active-connection)
      [ "$#" -gt 1 ] || fail "--active-connection requires a value"
      active_name="$2"
      shift
      ;;
    --gateway)
      [ "$#" -gt 1 ] || fail "--gateway requires a value"
      gateway="$2"
      shift
      ;;
    --reachability-probe)
      [ "$#" -gt 1 ] || fail "--reachability-probe requires a value"
      reachability_probe="$2"
      shift
      ;;
    --validation-timeout)
      [ "$#" -gt 1 ] || fail "--validation-timeout requires a value"
      validation_timeout="$2"
      shift
      ;;
    --stay-on-target-seconds)
      [ "$#" -gt 1 ] || fail "--stay-on-target-seconds requires a value"
      stay_on_target_seconds="$2"
      shift
      ;;
    --keep-ap-active)
      keep_ap_active="1"
      ;;
    --no-keep-ap-active)
      keep_ap_active="0"
      ;;
    --i-understand-ssh-may-drop)
      understand_ssh_may_drop="1"
      ;;
    --confirm)
      [ "$#" -gt 1 ] || fail "--confirm requires a value"
      confirm_phrase="$2"
      shift
      ;;
    --dangerous-real-apply)
      dangerous_real_apply="1"
      ;;
    --rollback-delay-seconds)
      [ "$#" -gt 1 ] || fail "--rollback-delay-seconds requires a value"
      rollback_delay_seconds="$2"
      shift
      ;;
    --state-log)
      [ "$#" -gt 1 ] || fail "--state-log requires a value"
      state_log="$2"
      shift
      ;;
    --rollback-log)
      [ "$#" -gt 1 ] || fail "--rollback-log requires a value"
      rollback_log="$2"
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

case "$mode" in
  preflight)
    cmd_preflight
    exit $?
    ;;
  dry-run) ;;
  apply)
    if [ "$stay_on_target_seconds" = "0" ]; then
      stay_on_target_seconds="60"
    fi
    cmd_apply_plan
    if [ "$dangerous_real_apply" = "1" ]; then
      cmd_apply_real
    fi
    exit $?
    ;;
  *) fail "explicit preflight or --dry-run is required" ;;
esac

active_label=${active_name:-"<detect-active-connection>"}
gateway_label=${gateway:-"<discover-after-target-dhcp>"}
quoted_temp=$(shell_quote "$temporary_name")
quoted_iface=$(shell_quote "$iface")
quoted_ssid=$(shell_quote "$target_ssid")
quoted_active=$(shell_quote "$active_label")

printf '[wifi-kit] connect-safe NetworkManager prototype\n'
kv "mode" "dry-run"
kv "backend" "raspberrypi-networkmanager"
kv "real_apply_allowed" "false"
kv "network_writes" "false"
kv "secrets" "runtime-only-not-read-not-logged"
kv "interface" "$iface"
kv "active_connection" "$active_label"
kv "temporary_connection" "$temporary_name"
kv "target_ssid" "$target_ssid"
kv "keep_ap_active_requested" "$keep_ap_active"
kv "stay_on_target_seconds" "$stay_on_target_seconds"
kv "save_config" "not-applicable"

section "future-networkmanager-transaction"
kv "01.detect_active_connection" "nmcli -t -f DEVICE,CONNECTION device status"
kv "02.snapshot_active_profile" "nmcli connection show $quoted_active"
kv "03.create_temporary_profile" "nmcli connection add type wifi ifname $quoted_iface con-name $quoted_temp ssid $quoted_ssid"
kv "04.attach_runtime_secret" "nmcli connection modify $quoted_temp 802-11-wireless-security.psk <runtime-only-secret>"
kv "05.disable_autoconnect" "nmcli connection modify $quoted_temp connection.autoconnect no"
kv "06.connect_temporary" "nmcli connection up $quoted_temp"
kv "07.validate_gateway" "ping -c 1 -W $validation_timeout $gateway_label"
kv "08.validate_reachability" "ping -c 1 -W $validation_timeout $reachability_probe"
kv "09.bounded_stay" "stay ${stay_on_target_seconds}s when requested, then continue"
kv "10.rollback_active" "nmcli connection up $quoted_active"
kv "11.cleanup_temporary_profile" "nmcli connection delete $quoted_temp"
kv "12.final_status" "nmcli device status; nmcli connection show --active"

section "guards"
kv "must_detect_networkmanager" "required"
kv "must_not_overwrite_active_profile" "true"
kv "temporary_profile_autoconnect" "off"
kv "secret_policy" "runtime-only; never repo/log/diff"
kv "rollback_required" "true"
kv "cleanup_required" "true"
kv "ap_policy" "keep_ap_active=$keep_ap_active; no AP action in this prototype"
kv "forbidden_now" "nmcli add/up/delete/modify, hostapd, dnsmasq, reboot, save_config"

section "apply"
kv "apply_status" "refused"
kv "next_step" "review dry-run, then build a separate explicitly gated NM apply"
