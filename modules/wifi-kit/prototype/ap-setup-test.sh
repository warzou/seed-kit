#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mode=""
iface="wlan0"
ap_iface="wlan0_ap"
ap_ssid=""
ap_channel=""
ap_duration_seconds="30"
ap_max_seconds="300"
ap_max_seconds_set="0"
ap_stay_up_until_stop="0"
runtime_user="${SUDO_USER:-${USER:-root}}"
temporary_hostapd_conf="/tmp/wifi-kit-hostapd-test.conf"
temporary_hostapd_conf_public="/tmp/wifi-kit-hostapd-test.conf.redacted"
temporary_hostapd_log="/tmp/wifi-kit-hostapd-test.log"
temporary_hostapd_pid="/tmp/wifi-kit-hostapd-test.pid"
ap_only_nm_state="/tmp/wifi-kit-ap-only-nm-state"
ap_recovery_ip="192.168.50.1"
ap_recovery_cidr="24"
ap_recovery_dhcp_start="192.168.50.20"
ap_recovery_dhcp_end="192.168.50.80"
ap_recovery_dhcp_lease="1h"
ap_recovery_test_psk="12345678"
temporary_dnsmasq_conf="/tmp/wifi-kit-dnsmasq-recovery.conf"
temporary_dnsmasq_conf_public="/tmp/wifi-kit-dnsmasq-recovery.conf.redacted"
temporary_dnsmasq_log="/tmp/wifi-kit-dnsmasq-recovery.log"
temporary_dnsmasq_pid="/tmp/wifi-kit-dnsmasq-recovery.pid"
temporary_ui_log="/tmp/wifi-kit-ui-recovery-${runtime_user}.log"
temporary_ui_pid="/tmp/wifi-kit-ui-recovery.pid"
normal_ui_service="${WIFI_KIT_UI_SERVICE:-wifi-kit-ui.service}"
normal_ui_stopped_state="/tmp/wifi-kit-normal-ui-stopped-for-recovery"
recovery_ui_script="$script_dir/ui/serve-readonly.py"
ap_return_check_script="$script_dir/wifi-kit-ap-return-check.sh"
ui_port="80"
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
  sh modules/wifi-kit/prototype/ap-setup-test.sh apply-manual-test \
    --confirm "WIFI-KIT AP MANUAL TEST"
  sh modules/wifi-kit/prototype/ap-setup-test.sh status
  sh modules/wifi-kit/prototype/ap-setup-test.sh stop
  sh modules/wifi-kit/prototype/ap-setup-test.sh diagnose-last
  sh modules/wifi-kit/prototype/ap-setup-test.sh plan-ap-sta
  sh modules/wifi-kit/prototype/ap-setup-test.sh apply-ap-sta-manual-test \
    --confirm "WIFI-KIT AP STA MANUAL TEST"
  sh modules/wifi-kit/prototype/ap-setup-test.sh plan-ap-only
  sh modules/wifi-kit/prototype/ap-setup-test.sh apply-ap-only-manual-test \
    --confirm "WIFI-KIT AP ONLY MANUAL TEST"
  sh modules/wifi-kit/prototype/ap-setup-test.sh plan-ap-recovery
  sh modules/wifi-kit/prototype/ap-setup-test.sh apply-ap-recovery-manual-test \
    --confirm "WIFI-KIT AP RECOVERY MANUAL TEST"

Options:
  --iface <name>           Wi-Fi interface. Default: wlan0
  --ap-iface <name>        Future virtual AP interface. Default: wlan0_ap
  --ssid <name>            Future AP SSID. Default: Wifi-Kit-<hostname>
  --channel <number>       Future AP channel. Default: current wlan0 channel if detected
  --duration-seconds <n>   Future short AP test duration. Default: 30
  --max-seconds <n>        Future manual AP max duration. Default: 300
                            AP+STA dedicated-interface default: 600
  --stay-up-until-stop     For explicit AP recovery activation, leave AP,
                           dnsmasq, and recovery UI running until stop.
  --ui-port <n>            Recovery UI port. Default: 80
  --confirm <phrase>       Required for apply-short-test: WIFI-KIT AP SHORT TEST
                            Required for apply-manual-test: WIFI-KIT AP MANUAL TEST
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

pid_alive() {
  pid=$1
  [ -n "$pid" ] || return 1
  case "$pid" in *[!0-9]*|'') return 1 ;; esac
  kill -0 "$pid" 2>/dev/null
}

log_tail_if_readable() {
  label=$1
  path=$2
  section "$label"
  if [ -r "$path" ]; then
    tail -n 60 "$path" 2>/dev/null || true
  else
    kv "log_path" "$path"
    kv "log_readable" "no"
  fi
}

is_test_hostapd_pid() {
  pid=$1
  [ -n "$pid" ] || return 1
  case "$pid" in *[!0-9]*|'') return 1 ;; esac
  [ -d "/proc/$pid" ] || return 1
  cmdline="$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)"
  case "$cmdline" in
    *hostapd*" $temporary_hostapd_conf"*) return 0 ;;
    *hostapd*"$temporary_hostapd_conf"*) return 0 ;;
    *) return 1 ;;
  esac
}

test_pid_from_file() {
  [ -r "$temporary_hostapd_pid" ] || return 0
  sed -n '1p' "$temporary_hostapd_pid" 2>/dev/null || true
}

is_test_dnsmasq_pid() {
  pid=$1
  [ -n "$pid" ] || return 1
  case "$pid" in *[!0-9]*|'') return 1 ;; esac
  [ -d "/proc/$pid" ] || return 1
  cmdline="$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)"
  case "$cmdline" in
    *dnsmasq*"--conf-file=$temporary_dnsmasq_conf"*) return 0 ;;
    *dnsmasq*"--conf-file $temporary_dnsmasq_conf"*) return 0 ;;
    *dnsmasq*"$temporary_dnsmasq_conf"*) return 0 ;;
    *) return 1 ;;
  esac
}

test_dnsmasq_pid_from_file() {
  [ -r "$temporary_dnsmasq_pid" ] || return 0
  sed -n '1p' "$temporary_dnsmasq_pid" 2>/dev/null || true
}

is_test_ui_pid() {
  pid=$1
  [ -n "$pid" ] || return 1
  case "$pid" in *[!0-9]*|'') return 1 ;; esac
  [ -d "/proc/$pid" ] || return 1
  cmdline="$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)"
  case "$cmdline" in
    *python*modules/wifi-kit/prototype/ui/serve-readonly.py*"--host $ap_recovery_ip"*"--port $ui_port"*) return 0 ;;
    *python*serve-readonly.py*"--host $ap_recovery_ip"*"--port $ui_port"*) return 0 ;;
    *) return 1 ;;
  esac
}

test_ui_pid_from_file() {
  [ -r "$temporary_ui_pid" ] || return 0
  sed -n '1p' "$temporary_ui_pid" 2>/dev/null || true
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

systemctl_bin() {
  find_tool systemctl 2>/dev/null || true
}

suspend_normal_ui_service_best_effort() {
  [ "$(id -u 2>/dev/null || printf 1)" = "0" ] || return 0
  systemctl_path="$(systemctl_bin)"
  [ -n "$systemctl_path" ] || return 0
  if "$systemctl_path" is-active --quiet "$normal_ui_service" 2>/dev/null; then
    umask 077
    {
      printf 'service=%s\n' "$normal_ui_service"
      printf 'stopped_by=ap-recovery\n'
    } >"$normal_ui_stopped_state"
    "$systemctl_path" stop "$normal_ui_service" >/dev/null 2>&1 || true
    kv "normal_ui_service" "stopped-for-ap-recovery"
  else
    rm -f "$normal_ui_stopped_state" 2>/dev/null || true
    kv "normal_ui_service" "not-active"
  fi
}

restore_normal_ui_service_best_effort() {
  [ -r "$normal_ui_stopped_state" ] || return 0
  [ "$(id -u 2>/dev/null || printf 1)" = "0" ] || return 0
  if [ "${WIFI_KIT_AP_SKIP_UI_RESTORE:-0}" = "1" ]; then
    kv "normal_ui_restore" "skipped"
    kv "normal_ui_restore_reason" "caller-keeps-recovery-active"
    return 0
  fi
  systemctl_path="$(systemctl_bin)"
  [ -n "$systemctl_path" ] || return 0
  "$systemctl_path" start "$normal_ui_service" >/dev/null 2>&1 || true
  rm -f "$normal_ui_stopped_state" 2>/dev/null || true
  kv "normal_ui_service" "restored"
}

write_ap_only_nm_state() {
  state_iface=$1
  state_connection=$2
  umask 077
  {
    printf 'mode=ap-only\n'
    printf 'iface=%s\n' "$state_iface"
    printf 'active_connection=%s\n' "$state_connection"
  } >"$ap_only_nm_state"
  chmod 600 "$ap_only_nm_state" 2>/dev/null || true
}

read_ap_only_state_value() {
  key=$1
  [ -r "$ap_only_nm_state" ] || return 0
  sed -n "s/^$key=//p" "$ap_only_nm_state" | sed -n '1p'
}

restore_nm_from_ap_only_state_best_effort() {
  [ -r "$ap_only_nm_state" ] || return 0
  [ "$(id -u 2>/dev/null || printf 1)" = "0" ] || return 0
  nmcli_bin="$(find_tool nmcli 2>/dev/null || true)"
  [ -n "$nmcli_bin" ] || return 0
  if [ "${WIFI_KIT_AP_SKIP_NM_RESTORE:-0}" = "1" ]; then
    kv "networkmanager_restore" "skipped"
    kv "networkmanager_restore_reason" "caller-controls-wlan0"
    return 0
  fi

  restore_iface="$(read_ap_only_state_value iface || true)"
  restore_connection="$(read_ap_only_state_value active_connection || true)"
  [ -n "$restore_iface" ] || restore_iface="$iface"

  "$nmcli_bin" device set "$restore_iface" managed yes >/dev/null 2>&1 || true
  if [ -n "$restore_connection" ] && [ "$restore_connection" != "--" ]; then
    "$nmcli_bin" connection up "$restore_connection" ifname "$restore_iface" >/dev/null 2>&1 ||
      "$nmcli_bin" device connect "$restore_iface" >/dev/null 2>&1 || true
  else
    "$nmcli_bin" device connect "$restore_iface" >/dev/null 2>&1 || true
  fi
  rm -f "$ap_only_nm_state" 2>/dev/null || true
}

interface_exists() {
  dev=$1
  ip link show "$dev" >/dev/null 2>&1
}

ap_interface_type() {
  iw_bin="$(find_tool iw 2>/dev/null || true)"
  [ -n "$iw_bin" ] || return 0
  "$iw_bin" dev "$ap_iface" info 2>/dev/null |
    awk '$1 == "type" { print $2; exit }'
}

delete_test_ap_interface_if_exists() {
  [ "$(id -u 2>/dev/null || printf 1)" = "0" ] ||
    fail "deleting $ap_iface requires root"
  iw_bin="$(find_tool iw 2>/dev/null || true)"
  [ -n "$iw_bin" ] || fail "iw is required"

  if ! interface_exists "$ap_iface"; then
    return 0
  fi

  if [ "$ap_iface" != "wlan0_ap" ]; then
    fail "$ap_iface already exists; refusing to delete non-default AP interface name"
  fi

  ap_type="$(ap_interface_type || true)"
  case "$ap_type" in
    AP|__ap|'')
      ip link set "$ap_iface" down 2>/dev/null || true
      "$iw_bin" dev "$ap_iface" del 2>/dev/null ||
        fail "could not delete existing test AP interface $ap_iface"
      ;;
    *)
      fail "$ap_iface exists with type $ap_type; refusing to treat it as a Wifi-Kit test interface"
      ;;
  esac
}

cleanup_test_ap_interface_best_effort() {
  if [ "$ap_iface" != "wlan0_ap" ]; then
    return 0
  fi
  if interface_exists "$ap_iface"; then
    iw_bin="$(find_tool iw 2>/dev/null || true)"
    ip link set "$ap_iface" down 2>/dev/null || true
    if [ -n "$iw_bin" ]; then
      "$iw_bin" dev "$ap_iface" del 2>/dev/null || true
    fi
  fi
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

port53_listeners() {
  ss -lnutp 2>/dev/null |
    awk 'NR > 1 && ($5 ~ /:53$/ || $5 ~ /[.]53$/ || $5 ~ /[*]:53$/) { print }' |
    sed -n '1,5p'
}

port_listeners() {
  port=$1
  ss -lnutp 2>/dev/null |
    awk -v port="$port" 'NR > 1 && ($5 ~ ":" port "$" || $5 ~ "[.]" port "$" || $5 ~ "[*]:" port "$") { print }' |
    sed -n '1,5p'
}

write_dnsmasq_recovery_config_plan() {
  cat <<EOF
interface=$iface
bind-interfaces
except-interface=lo
dhcp-range=$ap_recovery_dhcp_start,$ap_recovery_dhcp_end,255.255.255.0,$ap_recovery_dhcp_lease
dhcp-option=3,$ap_recovery_ip
dhcp-option=6,$ap_recovery_ip
address=/#/$ap_recovery_ip
log-queries
log-dhcp
pid-file=$temporary_dnsmasq_pid
EOF
}

write_dnsmasq_recovery_config_real() {
  write_dnsmasq_recovery_config_plan >"$temporary_dnsmasq_conf"
  chmod 600 "$temporary_dnsmasq_conf"
}

prepare_root_log_file() {
  log_path=$1
  log_mode=$2

  rm -f "$log_path"
  : >"$log_path" || fail "could not create $log_path"
  chmod "$log_mode" "$log_path" 2>/dev/null || true
}

prepare_dnsmasq_recovery_log() {
  prepare_root_log_file "$temporary_dnsmasq_log" 644
}

prepare_recovery_runtime_files() {
  rm -f \
    "$temporary_hostapd_conf" \
    "$temporary_hostapd_pid" \
    "$temporary_dnsmasq_conf" \
    "$temporary_dnsmasq_pid" \
    "$temporary_ui_pid"

  prepare_root_log_file "$temporary_hostapd_log" 644
  prepare_dnsmasq_recovery_log
  prepare_root_log_file "$temporary_ui_log" 644
}

write_redacted_dnsmasq_config_copy() {
  [ -r "$temporary_dnsmasq_conf" ] || return 0
  cp "$temporary_dnsmasq_conf" "$temporary_dnsmasq_conf_public"
  chmod 600 "$temporary_dnsmasq_conf_public" 2>/dev/null || true
}

stop_test_dnsmasq_best_effort() {
  dnsmasq_pid="$(test_dnsmasq_pid_from_file || true)"
  if [ -n "$dnsmasq_pid" ] && is_test_dnsmasq_pid "$dnsmasq_pid"; then
    kill "$dnsmasq_pid" 2>/dev/null || true
    wait "$dnsmasq_pid" 2>/dev/null || true
  fi
  rm -f "$temporary_dnsmasq_pid" 2>/dev/null || true
}

stop_return_check_loop_best_effort() {
  [ "${WIFI_KIT_AP_RETURN_CHECK_INTERNAL:-0}" != "1" ] || return 0
  [ -f "$ap_return_check_script" ] || return 0
  sh "$ap_return_check_script" stop-loop >/dev/null 2>&1 || true
}

start_return_check_loop_best_effort() {
  [ -f "$ap_return_check_script" ] || return 0
  if [ "${WIFI_KIT_AP_START_RETURN_CHECK_LOOP:-0}" != "1" ]; then
    kv "return_check_loop" "not-started"
    kv "return_check_loop_reason" "not-requested-for-manual-ap"
    return 0
  fi
  mkdir -p /tmp/wifi-kit-actions 2>/dev/null || true
  chmod 1777 /tmp/wifi-kit-actions 2>/dev/null || true
  enabled=$(
    WIFI_KIT_RUNTIME_CONFIG="${WIFI_KIT_RUNTIME_CONFIG:-}" sh "$ap_return_check_script" audit 2>/dev/null |
      sed -n 's/^return_check_enabled=//p' |
      sed -n '1p'
  )
  [ "$enabled" = "true" ] || return 0
  WIFI_KIT_RUNTIME_CONFIG="${WIFI_KIT_RUNTIME_CONFIG:-}" \
    sh "$ap_return_check_script" run-loop >> /tmp/wifi-kit-actions/ap-return-check-loop.log 2>&1 &
  kv "return_check_loop" "started"
  kv "return_check_loop_pid" "$!"
}

stop_test_ui_best_effort() {
  ui_pid="$(test_ui_pid_from_file || true)"
  if [ -n "$ui_pid" ] && is_test_ui_pid "$ui_pid"; then
    kill "$ui_pid" 2>/dev/null || true
    wait "$ui_pid" 2>/dev/null || true
  fi
  rm -f "$temporary_ui_pid" 2>/dev/null || true
}

remove_ap_recovery_ip_best_effort() {
  [ "$(id -u 2>/dev/null || printf 1)" = "0" ] || return 0
  ip_bin="$(find_tool ip 2>/dev/null || true)"
  [ -n "$ip_bin" ] || return 0
  "$ip_bin" addr del "$ap_recovery_ip/$ap_recovery_cidr" dev "$iface" >/dev/null 2>&1 || true
}

wait_recovery_startup() {
  startup_elapsed=0
  startup_timeout=8

  section "startup-grace"
  kv "startup_timeout_seconds" "$startup_timeout"
  while [ "$startup_elapsed" -le "$startup_timeout" ]; do
    hostapd_ready="$(pid_alive "$hostapd_pid" && printf yes || printf no)"
    dnsmasq_ready="$(pid_alive "$dnsmasq_pid" && printf yes || printf no)"
    ui_ready="$(pid_alive "$ui_pid" && printf yes || printf no)"

    kv "startup_second" "$startup_elapsed"
    kv "hostapd_ready" "$hostapd_ready"
    kv "dnsmasq_ready" "$dnsmasq_ready"
    kv "ui_ready" "$ui_ready"

    if [ "$hostapd_ready" = "yes" ] &&
      [ "$dnsmasq_ready" = "yes" ] &&
      [ "$ui_ready" = "yes" ]; then
      kv "startup_status" "ready"
      return 0
    fi

    sleep 1
    startup_elapsed=$((startup_elapsed + 1))
  done

  kv "startup_status" "failed"
  kv "hostapd_not_ready" "$([ "$hostapd_ready" = "yes" ] && printf no || printf yes)"
  kv "dnsmasq_not_ready" "$([ "$dnsmasq_ready" = "yes" ] && printf no || printf yes)"
  kv "ui_not_ready" "$([ "$ui_ready" = "yes" ] && printf no || printf yes)"
  log_tail_if_readable "hostapd-log-tail" "$temporary_hostapd_log"
  log_tail_if_readable "dnsmasq-log-tail" "$temporary_dnsmasq_log"
  log_tail_if_readable "ui-log-tail" "$temporary_ui_log"
  return 1
}

cmd_plan_ap_recovery() {
  channel="$(current_channel || true)"
  active="$(active_connection || true)"
  state="$(device_state || true)"
  ssid="$(effective_ap_ssid)"
  if [ -z "$ap_channel" ]; then
    ap_channel="${channel:-6}"
  fi
  if [ "$ap_max_seconds_set" = "0" ]; then
    ap_max_seconds="600"
  fi

  dnsmasq_path="$(find_tool dnsmasq 2>/dev/null || true)"
  python3_path="$(find_tool python3 2>/dev/null || true)"
  port53="$(port53_listeners || true)"
  portui="$(port_listeners "$ui_port" || true)"

  printf '[wifi-kit] AP recovery UX plan\n'
  kv "mode" "plan-ap-recovery"
  kv "network_writes" "false"
  kv "real_apply_allowed" "false"
  kv "interface" "$iface"
  kv "nm_device_state" "${state:-unknown}"
  kv "nm_active_connection" "${active:-unknown}"
  kv "current_channel" "${channel:-unknown}"
  kv "future_ap_channel" "$ap_channel"
  kv "future_ap_ssid" "$ssid"
  kv "recovery_ap_test_password" "$ap_recovery_test_psk"
  kv "recovery_ap_password_source" "WIFI_KIT_AP_PSK runtime override or test default"
  kv "ap_ip" "$ap_recovery_ip/$ap_recovery_cidr"
  kv "dhcp_range" "$ap_recovery_dhcp_start-$ap_recovery_dhcp_end"
  kv "dhcp_lease" "$ap_recovery_dhcp_lease"
  kv "ui_bind" "$ap_recovery_ip:$ui_port"
  kv "max_seconds" "$ap_max_seconds"
  kv "stay_up_until_stop" "$ap_stay_up_until_stop"
  kv "hostapd_conf" "$temporary_hostapd_conf"
  kv "hostapd_log" "$temporary_hostapd_log"
  kv "hostapd_pidfile" "$temporary_hostapd_pid"
  kv "dnsmasq_present" "$([ -n "$dnsmasq_path" ] && printf yes || printf no)"
  kv "dnsmasq_path" "${dnsmasq_path:-missing}"
  kv "dnsmasq_conf" "$temporary_dnsmasq_conf"
  kv "dnsmasq_redacted_conf" "$temporary_dnsmasq_conf_public"
  kv "dnsmasq_log" "$temporary_dnsmasq_log"
  kv "dnsmasq_pidfile" "$temporary_dnsmasq_pid"
  kv "python3_present" "$([ -n "$python3_path" ] && printf yes || printf no)"
  kv "python3_path" "${python3_path:-missing}"
  kv "ui_log" "$temporary_ui_log"
  kv "ui_pidfile" "$temporary_ui_pid"
  kv "port53_listener_detected" "$([ -n "$port53" ] && printf yes || printf no)"
  kv "ui_port_listener_detected" "$([ -n "$portui" ] && printf yes || printf no)"
  kv "root_required" "yes"

  section "port-53-listeners"
  if [ -n "$port53" ]; then
    printf '%s\n' "$port53"
  else
    kv "port53" "free-or-not-visible"
  fi
  section "ui-port-listeners"
  if [ -n "$portui" ]; then
    printf '%s\n' "$portui"
  else
    kv "ui_port" "free-or-not-visible"
  fi

  section "target-architecture"
  kv "01.mode" "AP-only recovery UX"
  kv "02.radio" "$iface leaves NetworkManager client mode and becomes AP-only"
  kv "03.address" "assign $ap_recovery_ip/$ap_recovery_cidr to $iface"
  kv "04.hostapd" "serve SSID $ssid on channel $ap_channel"
  kv "05.dnsmasq_dhcp" "lease $ap_recovery_dhcp_start-$ap_recovery_dhcp_end"
  kv "06.dnsmasq_dns" "answer local DNS and redirect unknown names to $ap_recovery_ip"
  kv "07.ui" "python3 UI listens on http://$ap_recovery_ip:$ui_port/"
  kv "08.captive_portal" "basic Android/iOS/Windows detection endpoints redirect to local UI"
  kv "09.current_test_scope" "hostapd plus dnsmasq DHCP/DNS plus local UI; actions are plan-only"
  kv "10.exit" "future UI reconnects normal Wi-Fi, stops AP recovery, restores NetworkManager"

  section "planned-hostapd-config"
  write_hostapd_config_plan "$ssid" "$ap_channel"

  section "planned-dnsmasq-config"
  write_dnsmasq_recovery_config_plan

  section "future-command-sequence"
  kv "01.preflight" "sh modules/wifi-kit/prototype/ap-setup-test.sh preflight"
  kv "02.snapshot_nm" "record current $iface NetworkManager state and active connection in $ap_only_nm_state"
  kv "03.disconnect_nm" "sudo nmcli device disconnect $iface; sudo nmcli device set $iface managed no"
  kv "04.assign_ap_ip" "sudo ip addr flush dev $iface; sudo ip addr add $ap_recovery_ip/$ap_recovery_cidr dev $iface; sudo ip link set $iface up"
  kv "05.write_hostapd" "create $(shell_quote "$temporary_hostapd_conf") mode 600 with WIFI_KIT_AP_PSK runtime passphrase; test value $ap_recovery_test_psk"
  kv "06.start_hostapd" "sudo hostapd -d $(shell_quote "$temporary_hostapd_conf") > $(shell_quote "$temporary_hostapd_log") 2>&1"
  kv "07.write_dnsmasq" "create $(shell_quote "$temporary_dnsmasq_conf")"
  kv "08.start_dnsmasq" "sudo dnsmasq --no-daemon --conf-file=$(shell_quote "$temporary_dnsmasq_conf") > $(shell_quote "$temporary_dnsmasq_log") 2>&1"
  kv "09.start_ui" "sudo python3 $(shell_quote "$recovery_ui_script") --host $ap_recovery_ip --port $ui_port --recovery-mode --recovery-ssid $ssid"
  kv "10.captive_portal" "basic endpoints redirect or serve local recovery UI"
  kv "11.explicit_stop" "sudo sh modules/wifi-kit/prototype/ap-setup-test.sh stop"
  kv "12.cleanup" "stop UI/dnsmasq/hostapd only on explicit stop or startup failure"
  kv "13.restore_nm" "only on explicit stop: sudo nmcli device set $iface managed yes; sudo nmcli connection up <previous> ifname $iface || sudo nmcli device connect $iface"

  section "guards"
  kv "real_execution" "requires --dangerous-real-apply and exact confirmation"
  kv "test_password_command_prefix" "WIFI_KIT_AP_PSK='$ap_recovery_test_psk'"
  kv "confirmation" "WIFI-KIT AP RECOVERY MANUAL TEST"
  kv "dnsmasq_start" "no"
  kv "hostapd_start" "no"
  kv "ui_start" "only-in-confirmed-real-apply"
  kv "network_changes" "no"
  kv "persistent_system_files" "none"
  kv "save_config" "not-called"
  kv "reboot" "not-used"
  kv "rollback" "none-for-voluntary-ap-start; restore only through explicit stop/return action"
}

cmd_apply_ap_recovery_manual_test() {
  [ "$confirm_phrase" = "WIFI-KIT AP RECOVERY MANUAL TEST" ] ||
    fail "apply-ap-recovery-manual-test requires --confirm \"WIFI-KIT AP RECOVERY MANUAL TEST\""

  cmd_plan_ap_recovery
  section "apply"
  if [ "$dangerous_real_apply" != "1" ]; then
    kv "apply_status" "refused-plan-only"
    kv "reason" "AP recovery real apply needs --dangerous-real-apply plus separate validation"
    kv "future_command" "sudo env WIFI_KIT_AP_PSK='$ap_recovery_test_psk' sh modules/wifi-kit/prototype/ap-setup-test.sh apply-ap-recovery-manual-test --dangerous-real-apply --confirm \"WIFI-KIT AP RECOVERY MANUAL TEST\" --max-seconds 600"
    return 0
  fi

  if [ "$(id -u 2>/dev/null || printf 1)" != "0" ]; then
    fail "real AP recovery manual test requires root; run: sudo env WIFI_KIT_AP_PSK='$ap_recovery_test_psk' sh modules/wifi-kit/prototype/ap-setup-test.sh apply-ap-recovery-manual-test --dangerous-real-apply --confirm \"WIFI-KIT AP RECOVERY MANUAL TEST\" --max-seconds 600"
  fi
  require_number "--max-seconds" "$ap_max_seconds"
  if [ "$ap_max_seconds" -lt 1 ]; then
    fail "--max-seconds must be greater than 0"
  fi
  find_tool hostapd >/dev/null 2>&1 || fail "hostapd is required"
  find_tool dnsmasq >/dev/null 2>&1 || fail "dnsmasq is required for AP recovery DHCP"
  find_tool nmcli >/dev/null 2>&1 || fail "nmcli is required for AP recovery rollback"
  find_tool ip >/dev/null 2>&1 || fail "ip is required for AP recovery addressing"
  find_tool python3 >/dev/null 2>&1 || fail "python3 is required for AP recovery UI"

  port53="$(port53_listeners || true)"
  [ -z "$port53" ] || fail "port 53 is already in use; refusing to start temporary dnsmasq"
  portui="$(port_listeners "$ui_port" || true)"
  [ -z "$portui" ] || fail "UI port $ui_port is already in use; refusing to start temporary recovery UI"

  hostapd_bin="$(find_tool hostapd)"
  dnsmasq_bin="$(find_tool dnsmasq)"
  nmcli_bin="$(find_tool nmcli)"
  ip_bin="$(find_tool ip)"
  python3_bin="$(find_tool python3)"
  ssid="$(effective_ap_ssid)"
  channel="$(current_channel || true)"
  if [ -z "$ap_channel" ]; then
    ap_channel="${channel:-6}"
  fi

  existing_hostapd_pid="$(test_pid_from_file || true)"
  if [ -n "$existing_hostapd_pid" ] && is_test_hostapd_pid "$existing_hostapd_pid"; then
    fail "wifi-kit test hostapd already running with pid $existing_hostapd_pid"
  fi
  existing_dnsmasq_pid="$(test_dnsmasq_pid_from_file || true)"
  if [ -n "$existing_dnsmasq_pid" ] && is_test_dnsmasq_pid "$existing_dnsmasq_pid"; then
    fail "wifi-kit test dnsmasq already running with pid $existing_dnsmasq_pid"
  fi
  existing_ui_pid="$(test_ui_pid_from_file || true)"
  if [ -n "$existing_ui_pid" ] && is_test_ui_pid "$existing_ui_pid"; then
    fail "wifi-kit recovery UI already running with pid $existing_ui_pid"
  fi

  passphrase="$(runtime_ap_passphrase)"
  case "$passphrase" in
    ????????*) ;;
    *) fail "runtime AP passphrase must be at least 8 characters" ;;
  esac

  previous_connection="$(active_connection || true)"
  previous_state="$(device_state || true)"
  hostapd_pid=""
  dnsmasq_pid=""
  ui_pid=""
  cleanup_ap_recovery() {
    stop_return_check_loop_best_effort
    if [ -n "${ui_pid:-}" ] && is_test_ui_pid "$ui_pid"; then
      kill "$ui_pid" 2>/dev/null || true
      wait "$ui_pid" 2>/dev/null || true
    fi
    stop_test_ui_best_effort
    if [ -n "${dnsmasq_pid:-}" ] && is_test_dnsmasq_pid "$dnsmasq_pid"; then
      kill "$dnsmasq_pid" 2>/dev/null || true
      wait "$dnsmasq_pid" 2>/dev/null || true
    fi
    stop_test_dnsmasq_best_effort
    if [ -n "${hostapd_pid:-}" ] && is_test_hostapd_pid "$hostapd_pid"; then
      kill "$hostapd_pid" 2>/dev/null || true
      wait "$hostapd_pid" 2>/dev/null || true
    fi
    write_redacted_hostapd_config_copy
    write_redacted_dnsmasq_config_copy
    rm -f "$temporary_hostapd_conf" "$temporary_hostapd_pid" "$temporary_dnsmasq_conf" "$temporary_dnsmasq_pid" "$temporary_ui_pid"
    remove_ap_recovery_ip_best_effort
    restore_nm_from_ap_only_state_best_effort
    restore_normal_ui_service_best_effort
  }
  trap cleanup_ap_recovery EXIT INT TERM HUP

  prepare_recovery_runtime_files
  write_ap_only_nm_state "$iface" "$previous_connection"
  suspend_normal_ui_service_best_effort

  section "real-apply"
  kv "apply_status" "starting"
  kv "interface" "$iface"
  kv "previous_nm_state" "${previous_state:-unknown}"
  kv "previous_nm_active_connection" "${previous_connection:-unknown}"
  kv "ap_ssid" "$ssid"
  kv "ap_channel" "$ap_channel"
  kv "ap_ip" "$ap_recovery_ip/$ap_recovery_cidr"
  kv "dhcp_range" "$ap_recovery_dhcp_start-$ap_recovery_dhcp_end"
  kv "max_seconds" "$ap_max_seconds"
  kv "stay_up_until_stop" "$ap_stay_up_until_stop"
  kv "hostapd_log" "$temporary_hostapd_log"
  kv "hostapd_pidfile" "$temporary_hostapd_pid"
  kv "dnsmasq_log" "$temporary_dnsmasq_log"
  kv "dnsmasq_pidfile" "$temporary_dnsmasq_pid"
  kv "ui_log" "$temporary_ui_log"
  kv "ui_pidfile" "$temporary_ui_pid"
  kv "ui_url" "http://$ap_recovery_ip:$ui_port/"
  kv "runtime_secret" "not-logged"
  kv "ap_password_source" "WIFI_KIT_AP_PSK runtime or test default"
  kv "captive_portal" "basic"
  kv "ui" "starting"
  kv "stop_command" "sudo sh modules/wifi-kit/prototype/ap-setup-test.sh stop"
  kv "runtime_files_prepare" "done"

  "$nmcli_bin" device disconnect "$iface"
  "$nmcli_bin" device set "$iface" managed no
  kv "recovery-enter" "ap-recovery"
  kv "nm-managed-no" "$iface"
  "$ip_bin" addr flush dev "$iface"
  "$ip_bin" addr add "$ap_recovery_ip/$ap_recovery_cidr" dev "$iface"
  "$ip_bin" link set "$iface" up

  umask 077
  write_hostapd_config_real "$ssid" "$ap_channel" "$passphrase"
  write_dnsmasq_recovery_config_real

  "$hostapd_bin" -d "$temporary_hostapd_conf" >"$temporary_hostapd_log" 2>&1 &
  hostapd_pid=$!
  printf '%s\n' "$hostapd_pid" >"$temporary_hostapd_pid"
  kv "hostapd_pid" "$hostapd_pid"

  "$dnsmasq_bin" --no-daemon --conf-file="$temporary_dnsmasq_conf" >"$temporary_dnsmasq_log" 2>&1 &
  dnsmasq_pid=$!
  printf '%s\n' "$dnsmasq_pid" >"$temporary_dnsmasq_pid"
  kv "dnsmasq_pid" "$dnsmasq_pid"
  WIFI_KIT_ENABLE_PRIVILEGED_ACTIONS=1 "$python3_bin" "$recovery_ui_script" \
    --host "$ap_recovery_ip" \
    --port "$ui_port" \
    --recovery-mode \
    --recovery-ssid "$ssid" \
    --recovery-ip "$ap_recovery_ip" \
    >"$temporary_ui_log" 2>&1 &
  ui_pid=$!
  printf '%s\n' "$ui_pid" >"$temporary_ui_pid"
  kv "ui_pid" "$ui_pid"
  kv "client_check" "connect to SSID $ssid and verify DHCP address 192.168.50.x"
  kv "browser_check" "open http://$ap_recovery_ip/ or captive portal prompt"

  if ! wait_recovery_startup; then
    cleanup_ap_recovery
    trap - EXIT INT TERM HUP
    section "post-check"
    kv "elapsed_seconds" "0"
    kv "hostapd_log" "$temporary_hostapd_log"
    kv "dnsmasq_log" "$temporary_dnsmasq_log"
    kv "ui_log" "$temporary_ui_log"
    kv "config_cleanup" "done"
    kv "ap_ip_cleanup" "attempted"
    kv "networkmanager_restore" "attempted"
    kv "final_nm_device_state" "$(device_state || true)"
    kv "final_nm_active_connection" "$(active_connection || true)"
    kv "apply_status" "startup-failed"
    return 1
  fi

  if [ "$ap_stay_up_until_stop" = "1" ]; then
    start_return_check_loop_best_effort
    trap - EXIT INT TERM HUP
    section "ready"
    kv "apply_status" "running-until-explicit-stop"
    kv "ap-hold-started" "yes"
    kv "ap-stay-up-until-stop" "yes"
    kv "no-auto-cleanup" "yes"
    kv "hostapd_pid" "$hostapd_pid"
    kv "dnsmasq_pid" "$dnsmasq_pid"
    kv "ui_pid" "$ui_pid"
    kv "ui_url" "http://$ap_recovery_ip:$ui_port/"
    kv "stop_command" "sudo sh modules/wifi-kit/prototype/ap-setup-test.sh stop"
    kv "auto_stop" "disabled"
    kv "networkmanager_restore" "not-attempted"
    return 0
  fi

  elapsed=0
  while pid_alive "$hostapd_pid" && pid_alive "$dnsmasq_pid" && pid_alive "$ui_pid"; do
    if [ "$elapsed" -ge "$ap_max_seconds" ]; then
      kv "auto_stop" "max-seconds-reached"
      break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  kv "hostapd_alive_final" "$(pid_alive "$hostapd_pid" && printf yes || printf no)"
  kv "dnsmasq_alive_final" "$(pid_alive "$dnsmasq_pid" && printf yes || printf no)"
  kv "ui_alive_final" "$(pid_alive "$ui_pid" && printf yes || printf no)"

  cleanup_ap_recovery
  trap - EXIT INT TERM HUP

  section "post-check"
  kv "elapsed_seconds" "$elapsed"
  kv "hostapd_log" "$temporary_hostapd_log"
  kv "dnsmasq_log" "$temporary_dnsmasq_log"
  kv "ui_log" "$temporary_ui_log"
  kv "config_cleanup" "done"
  kv "ap_ip_cleanup" "attempted"
  kv "networkmanager_restore" "attempted"
  kv "final_nm_device_state" "$(device_state || true)"
  kv "final_nm_active_connection" "$(active_connection || true)"
  kv "apply_status" "completed-or-stopped"
}

cmd_plan_ap_only() {
  channel="$(current_channel || true)"
  active="$(active_connection || true)"
  state="$(device_state || true)"
  ssid="$(effective_ap_ssid)"
  if [ -z "$ap_channel" ]; then
    ap_channel="${channel:-6}"
  fi
  if [ "$ap_max_seconds_set" = "0" ]; then
    ap_max_seconds="600"
  fi

  printf '[wifi-kit] AP-only recovery test plan\n'
  kv "mode" "plan-ap-only"
  kv "network_writes" "false"
  kv "real_apply_allowed" "false"
  kv "interface" "$iface"
  kv "nm_device_state" "${state:-unknown}"
  kv "nm_active_connection" "${active:-unknown}"
  kv "current_channel" "${channel:-unknown}"
  kv "future_ap_channel" "$ap_channel"
  kv "future_ap_ssid" "$ssid"
  kv "max_seconds" "$ap_max_seconds"
  kv "hostapd_log" "$temporary_hostapd_log"
  kv "hostapd_pidfile" "$temporary_hostapd_pid"
  kv "temporary_hostapd_conf" "$temporary_hostapd_conf"
  kv "redacted_config_path" "$temporary_hostapd_conf_public"
  kv "ap_only_nm_state" "$ap_only_nm_state"
  kv "root_required" "yes"

  section "v1-strategy"
  kv "ap_sta_single_radio" "not-retained-for-v1"
  kv "normal_mode" "NetworkManager client"
  kv "recovery_mode" "AP-only when no usable Wi-Fi exists or explicit recovery is requested"
  kv "wifi_connected_without_internet" "do-not-force-ap-automatically-without-policy"

  section "planned-hostapd-config"
  write_hostapd_config_plan "$ssid" "$ap_channel"

  section "future-command-sequence"
  kv "01.preflight" "sh modules/wifi-kit/prototype/ap-setup-test.sh preflight"
  kv "02.snapshot_nm" "record current $iface NetworkManager state and active connection in $ap_only_nm_state"
  kv "03.disconnect_nm" "sudo nmcli device disconnect $iface"
  kv "04.write_config" "create $(shell_quote "$temporary_hostapd_conf") mode 600 with runtime-only passphrase"
  kv "05.start_hostapd" "sudo hostapd -d $(shell_quote "$temporary_hostapd_conf") > $(shell_quote "$temporary_hostapd_log") 2>&1"
  kv "06.observe" "scan for SSID $ssid from phone/Windows"
  kv "07.stop" "sudo sh modules/wifi-kit/prototype/ap-setup-test.sh stop"
  kv "08.cleanup" "stop hostapd; delete secret config and pidfile; keep log and redacted config"
  kv "09.restore_nm" "sudo nmcli device set $iface managed yes; sudo nmcli connection up <previous> ifname $iface || sudo nmcli device connect $iface"
  kv "10.verify" "nmcli device status; ip addr show $iface; iw dev"

  section "guards"
  kv "real_execution" "requires --dangerous-real-apply and exact confirmation"
  kv "confirmation" "WIFI-KIT AP ONLY MANUAL TEST"
  kv "dnsmasq" "not-used"
  kv "captive_portal" "not-used"
  kv "persistent_system_files" "none"
  kv "save_config" "not-called"
  kv "reboot" "not-used"
  kv "rollback" "best-effort NetworkManager reconnect to previous active connection"
}

cmd_plan_ap_sta() {
  channel="$(current_channel || true)"
  active="$(active_connection || true)"
  state="$(device_state || true)"
  ssid="$(effective_ap_ssid)"
  if [ -z "$ap_channel" ]; then
    ap_channel="${channel:-6}"
  fi
  if [ "$ap_max_seconds_set" = "0" ]; then
    ap_max_seconds="600"
  fi

  printf '[wifi-kit] AP+STA dedicated-interface test plan\n'
  kv "mode" "plan-ap-sta-only"
  kv "network_writes" "false"
  kv "real_apply_allowed" "false"
  kv "sta_interface" "$iface"
  kv "ap_interface" "$ap_iface"
  kv "ap_interface_exists" "$(interface_exists "$ap_iface" && printf yes || printf no)"
  kv "nm_device_state" "${state:-unknown}"
  kv "nm_active_connection" "${active:-unknown}"
  kv "current_sta_channel" "${channel:-unknown}"
  kv "future_ap_channel" "$ap_channel"
  kv "same_channel_required" "yes"
  kv "ap_sta_same_channel_supported" "$(supports_ap_sta_same_channel && printf yes || printf no)"
  kv "future_ap_ssid" "$ssid"
  kv "max_seconds" "$ap_max_seconds"
  kv "hostapd_log" "$temporary_hostapd_log"
  kv "hostapd_pidfile" "$temporary_hostapd_pid"
  kv "temporary_hostapd_conf" "$temporary_hostapd_conf"
  kv "redacted_config_path" "$temporary_hostapd_conf_public"
  kv "root_required" "yes"

  section "read-only-interpretation"
  kv "wlan0_direct_result" "unstable-under-NetworkManager"
  kv "reason" "NetworkManager keeps STA ownership of wlan0 and can trigger STOP_AP"
  kv "next_hypothesis" "hostapd on dedicated $ap_iface while $iface remains NM-managed STA"

  section "planned-hostapd-config"
  cat <<EOF
interface=$ap_iface
driver=nl80211
ssid=$ssid
hw_mode=g
channel=$ap_channel
ieee80211n=1
wmm_enabled=1
auth_algs=1
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
ignore_broadcast_ssid=0
wpa_passphrase=<runtime-only-secret>
EOF

  section "future-command-sequence"
  kv "01.preflight" "iw dev; iw list; nmcli device status; ip link show $ap_iface || true"
  kv "02.cleanup_stale_ap_interface" "if $ap_iface exists and is the default Wifi-Kit test AP interface, delete it first"
  kv "03.create_ap_interface" "sudo iw dev $iface interface add $ap_iface type __ap"
  kv "04.bring_ap_interface_up" "sudo ip link set $ap_iface up"
  kv "05.write_config" "create $(shell_quote "$temporary_hostapd_conf") mode 600 with interface=$ap_iface and runtime-only passphrase"
  kv "06.start_hostapd" "sudo hostapd -d $(shell_quote "$temporary_hostapd_conf") > $(shell_quote "$temporary_hostapd_log") 2>&1"
  kv "07.verify" "iw dev should show $iface type managed and $ap_iface type AP on channel $ap_channel"
  kv "08.observe" "scan for SSID $ssid from phone/Windows"
  kv "09.stop" "sudo sh modules/wifi-kit/prototype/ap-setup-test.sh stop"
  kv "10.cleanup_ap_interface" "sudo ip link set $ap_iface down || true; sudo iw dev $ap_iface del || true"

  section "guards"
  kv "real_execution" "refused-in-this-prototype"
  kv "networkmanager_changes" "none-planned"
  kv "dnsmasq" "not-used"
  kv "captive_portal" "not-used"
  kv "save_config" "not-called"
  kv "reboot" "not-used"
  kv "cleanup_required" "hostapd-stop config-delete pidfile-delete log-retain-or-delete ap-interface-delete"
}

cmd_apply_ap_sta_manual_test() {
  [ "$confirm_phrase" = "WIFI-KIT AP STA MANUAL TEST" ] ||
    fail "apply-ap-sta-manual-test requires --confirm \"WIFI-KIT AP STA MANUAL TEST\""

  cmd_plan_ap_sta
  section "apply"
  if [ "$dangerous_real_apply" != "1" ]; then
    kv "apply_status" "refused-plan-only"
    kv "reason" "dedicated-interface AP+STA real apply needs --dangerous-real-apply plus separate validation"
    kv "future_command" "sudo sh modules/wifi-kit/prototype/ap-setup-test.sh apply-ap-sta-manual-test --dangerous-real-apply --confirm \"WIFI-KIT AP STA MANUAL TEST\" --max-seconds 600"
    return 0
  fi

  if [ "$(id -u 2>/dev/null || printf 1)" != "0" ]; then
    fail "real AP+STA manual test requires root; run: sudo sh modules/wifi-kit/prototype/ap-setup-test.sh apply-ap-sta-manual-test --dangerous-real-apply --confirm \"WIFI-KIT AP STA MANUAL TEST\" --max-seconds 600"
  fi
  require_number "--max-seconds" "$ap_max_seconds"
  if [ "$ap_max_seconds" -lt 1 ]; then
    fail "--max-seconds must be greater than 0"
  fi
  find_tool iw >/dev/null 2>&1 || fail "iw is required"
  find_tool hostapd >/dev/null 2>&1 || fail "hostapd is required"
  supports_ap_sta_same_channel ||
    fail "AP+STA same-channel interface combination is not advertised by iw list"

  hostapd_bin="$(find_tool hostapd)"
  iw_bin="$(find_tool iw)"
  ssid="$(effective_ap_ssid)"
  channel="$(current_channel || true)"
  if [ -z "$ap_channel" ]; then
    ap_channel="${channel:-6}"
  fi
  if [ -n "$channel" ] && [ "$ap_channel" != "$channel" ]; then
    fail "AP channel $ap_channel must match current STA channel $channel"
  fi

  existing_pid="$(test_pid_from_file || true)"
  if [ -n "$existing_pid" ] && is_test_hostapd_pid "$existing_pid"; then
    fail "wifi-kit test hostapd already running with pid $existing_pid"
  fi

  passphrase="$(runtime_ap_passphrase)"
  case "$passphrase" in
    ????????*) ;;
    *) fail "runtime AP passphrase must be at least 8 characters" ;;
  esac

  hostapd_pid=""
  cleanup_ap_sta() {
    if [ -n "${hostapd_pid:-}" ] && is_test_hostapd_pid "$hostapd_pid"; then
      kill "$hostapd_pid" 2>/dev/null || true
      wait "$hostapd_pid" 2>/dev/null || true
    fi
    write_redacted_hostapd_config_copy
    rm -f "$temporary_hostapd_conf" "$temporary_hostapd_pid"
    if interface_exists "$ap_iface"; then
      ip link set "$ap_iface" down 2>/dev/null || true
      "$iw_bin" dev "$ap_iface" del 2>/dev/null || true
    fi
  }
  trap cleanup_ap_sta EXIT INT TERM HUP

  delete_test_ap_interface_if_exists
  rm -f "$temporary_hostapd_conf" "$temporary_hostapd_pid"
  : >"$temporary_hostapd_log"
  chmod 600 "$temporary_hostapd_log"

  section "real-apply"
  kv "apply_status" "starting"
  kv "sta_interface" "$iface"
  kv "ap_interface" "$ap_iface"
  kv "ap_ssid" "$ssid"
  kv "ap_channel" "$ap_channel"
  kv "max_seconds" "$ap_max_seconds"
  kv "log_path" "$temporary_hostapd_log"
  kv "pidfile" "$temporary_hostapd_pid"
  kv "redacted_config_path" "$temporary_hostapd_conf_public"
  kv "runtime_secret" "not-logged"
  kv "networkmanager_changes" "none"
  kv "dnsmasq" "not-used"
  kv "captive_portal" "not-used"

  "$iw_bin" dev "$iface" interface add "$ap_iface" type __ap
  ip link set "$ap_iface" up

  umask 077
  write_hostapd_config_for_interface "$ap_iface" "$ssid" "$ap_channel" "$passphrase"
  "$hostapd_bin" -d "$temporary_hostapd_conf" >"$temporary_hostapd_log" 2>&1 &
  hostapd_pid=$!
  printf '%s\n' "$hostapd_pid" >"$temporary_hostapd_pid"
  kv "hostapd_pid" "$hostapd_pid"
  kv "phone_check" "look for SSID $ssid now"
  kv "stop_command" "sudo sh modules/wifi-kit/prototype/ap-setup-test.sh stop"

  elapsed=0
  while is_test_hostapd_pid "$hostapd_pid"; do
    if [ "$elapsed" -ge "$ap_max_seconds" ]; then
      kv "auto_stop" "max-seconds-reached"
      break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  cleanup_ap_sta
  trap - EXIT INT TERM HUP

  section "post-check"
  kv "elapsed_seconds" "$elapsed"
  kv "log_path" "$temporary_hostapd_log"
  kv "config_cleanup" "done"
  kv "ap_interface_cleanup" "done"
  kv "apply_status" "completed-or-stopped"
}

cmd_apply_ap_only_manual_test() {
  [ "$confirm_phrase" = "WIFI-KIT AP ONLY MANUAL TEST" ] ||
    fail "apply-ap-only-manual-test requires --confirm \"WIFI-KIT AP ONLY MANUAL TEST\""

  if [ "$ap_max_seconds_set" = "0" ]; then
    ap_max_seconds="600"
  fi
  require_number "--max-seconds" "$ap_max_seconds"
  if [ "$ap_max_seconds" -lt 1 ]; then
    fail "--max-seconds must be greater than 0"
  fi

  cmd_plan_ap_only
  section "apply"
  if [ "$dangerous_real_apply" != "1" ]; then
    kv "apply_status" "refused-plan-only"
    kv "reason" "AP-only real apply needs --dangerous-real-apply plus separate validation"
    kv "future_command" "sudo sh modules/wifi-kit/prototype/ap-setup-test.sh apply-ap-only-manual-test --dangerous-real-apply --confirm \"WIFI-KIT AP ONLY MANUAL TEST\" --max-seconds 600"
    return 0
  fi

  if [ "$(id -u 2>/dev/null || printf 1)" != "0" ]; then
    fail "real AP-only manual test requires root; run: sudo sh modules/wifi-kit/prototype/ap-setup-test.sh apply-ap-only-manual-test --dangerous-real-apply --confirm \"WIFI-KIT AP ONLY MANUAL TEST\" --max-seconds 600"
  fi
  find_tool hostapd >/dev/null 2>&1 || fail "hostapd is required"
  find_tool nmcli >/dev/null 2>&1 || fail "nmcli is required for AP-only rollback"

  hostapd_bin="$(find_tool hostapd)"
  nmcli_bin="$(find_tool nmcli)"
  ssid="$(effective_ap_ssid)"
  channel="$(current_channel || true)"
  if [ -z "$ap_channel" ]; then
    ap_channel="${channel:-6}"
  fi

  existing_pid="$(test_pid_from_file || true)"
  if [ -n "$existing_pid" ] && is_test_hostapd_pid "$existing_pid"; then
    fail "wifi-kit test hostapd already running with pid $existing_pid"
  fi

  passphrase="$(runtime_ap_passphrase)"
  case "$passphrase" in
    ????????*) ;;
    *) fail "runtime AP passphrase must be at least 8 characters" ;;
  esac

  previous_connection="$(active_connection || true)"
  previous_state="$(device_state || true)"
  hostapd_pid=""
  cleanup_ap_only() {
    if [ -n "${hostapd_pid:-}" ] && is_test_hostapd_pid "$hostapd_pid"; then
      kill "$hostapd_pid" 2>/dev/null || true
      wait "$hostapd_pid" 2>/dev/null || true
    fi
    write_redacted_hostapd_config_copy
    rm -f "$temporary_hostapd_conf" "$temporary_hostapd_pid"
    restore_nm_from_ap_only_state_best_effort
  }
  trap cleanup_ap_only EXIT INT TERM HUP

  rm -f "$temporary_hostapd_conf" "$temporary_hostapd_pid"
  : >"$temporary_hostapd_log"
  chmod 600 "$temporary_hostapd_log"
  write_ap_only_nm_state "$iface" "$previous_connection"

  section "real-apply"
  kv "apply_status" "starting"
  kv "interface" "$iface"
  kv "previous_nm_state" "${previous_state:-unknown}"
  kv "previous_nm_active_connection" "${previous_connection:-unknown}"
  kv "ap_ssid" "$ssid"
  kv "ap_channel" "$ap_channel"
  kv "max_seconds" "$ap_max_seconds"
  kv "log_path" "$temporary_hostapd_log"
  kv "pidfile" "$temporary_hostapd_pid"
  kv "redacted_config_path" "$temporary_hostapd_conf_public"
  kv "runtime_secret" "not-logged"
  kv "dnsmasq" "not-used"
  kv "captive_portal" "not-used"
  kv "stop_command" "sudo sh modules/wifi-kit/prototype/ap-setup-test.sh stop"

  "$nmcli_bin" device disconnect "$iface"
  umask 077
  write_hostapd_config_real "$ssid" "$ap_channel" "$passphrase"
  "$hostapd_bin" -d "$temporary_hostapd_conf" >"$temporary_hostapd_log" 2>&1 &
  hostapd_pid=$!
  printf '%s\n' "$hostapd_pid" >"$temporary_hostapd_pid"
  kv "hostapd_pid" "$hostapd_pid"
  kv "phone_check" "look for SSID $ssid now"

  elapsed=0
  while is_test_hostapd_pid "$hostapd_pid"; do
    if [ "$elapsed" -ge "$ap_max_seconds" ]; then
      kv "auto_stop" "max-seconds-reached"
      break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  cleanup_ap_only
  trap - EXIT INT TERM HUP

  section "post-check"
  kv "elapsed_seconds" "$elapsed"
  kv "log_path" "$temporary_hostapd_log"
  kv "config_cleanup" "done"
  kv "networkmanager_restore" "attempted"
  kv "final_nm_device_state" "$(device_state || true)"
  kv "final_nm_active_connection" "$(active_connection || true)"
  kv "apply_status" "completed-or-stopped"
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
  kv "future_ap_interface" "$ap_iface"
  kv "future_ap_interface_exists" "$(interface_exists "$ap_iface" && printf yes || printf no)"
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
  kv "future_ap_interface" "$ap_iface"
  kv "future_ap_ssid" "$ssid"
  kv "future_ap_channel" "$ap_channel"
  kv "duration_seconds" "$ap_duration_seconds"
  kv "manual_max_seconds" "$ap_max_seconds"
  kv "ap_sta_same_channel_constraint" "yes"
  kv "recommended_first_test" "ap-only-short-duration"

  section "future-ap-only-short-test"
  kv "01.preflight" "sh modules/wifi-kit/prototype/ap-setup-test.sh preflight"
  kv "02.write_temp_hostapd_config" "create $temporary_hostapd_conf with ssid=$ssid channel=$ap_channel wpa=2"
  kv "03.runtime_secret" "WPA2 passphrase supplied at runtime only; never repo/log/diff"
  kv "04.start_hostapd_foreground" "hostapd -d $temporary_hostapd_conf"
  kv "05.observe_phone_visibility" "confirm SSID appears from phone"
  kv "06.stop_hostapd" "terminate foreground hostapd after ${ap_duration_seconds}s or manual stop"
  kv "07.cleanup" "remove $temporary_hostapd_conf"
  kv "08.verify" "iw dev; nmcli device status; SSH route still expected via wlan0"

  section "future-ap-manual-test"
  kv "01.preflight" "sh modules/wifi-kit/prototype/ap-setup-test.sh preflight"
  kv "02.write_temp_hostapd_config" "create $temporary_hostapd_conf with ssid=$ssid channel=$ap_channel wpa=2"
  kv "03.runtime_secret" "WPA2 passphrase supplied at runtime only; never repo/log/diff"
  kv "04.start_hostapd" "sudo sh modules/wifi-kit/prototype/ap-setup-test.sh apply-manual-test --dangerous-real-apply --confirm \"WIFI-KIT AP MANUAL TEST\""
  kv "05.observe_phone_visibility" "confirm SSID appears from phone and Windows scan"
  kv "06.logs" "$temporary_hostapd_log"
  kv "07.stop" "sudo sh modules/wifi-kit/prototype/ap-setup-test.sh stop"
  kv "08.auto_stop" "after ${ap_max_seconds}s if not stopped earlier"

  section "future-ap-sta-test"
  kv "01.require_same_channel" "AP channel must match STA channel on Raspberry Pi Zero 2 W"
  kv "02.current_sta_channel" "${channel:-unknown}"
  kv "03.ap_channel_candidate" "$ap_channel"
  kv "04.ap_interface" "$ap_iface"
  kv "05.create_virtual_interface" "sudo iw dev $iface interface add $ap_iface type __ap"
  kv "06.hostapd_interface" "$ap_iface"
  kv "07.networkmanager_coordination" "keep $iface managed by NM; do not modify NM in this prototype"
  kv "08.plan_command" "sh modules/wifi-kit/prototype/ap-setup-test.sh plan-ap-sta"

  section "forbidden-now"
  kv "hostapd_start" "no"
  kv "dnsmasq_start" "no"
  kv "networkmanager_changes" "no"
  kv "wlan0_changes" "no"
  kv "reboot" "no"
  kv "save_config" "no"
  kv "captive_portal" "no"
}

cmd_status() {
  pid="$(test_pid_from_file || true)"
  dnsmasq_pid="$(test_dnsmasq_pid_from_file || true)"
  ui_pid="$(test_ui_pid_from_file || true)"

  printf '[wifi-kit] AP setup test status\n'
  kv "mode" "status-readonly"
  kv "pidfile" "$temporary_hostapd_pid"
  kv "log_path" "$temporary_hostapd_log"
  kv "temporary_hostapd_conf" "$temporary_hostapd_conf"
  kv "dnsmasq_pidfile" "$temporary_dnsmasq_pid"
  kv "dnsmasq_log_path" "$temporary_dnsmasq_log"
  kv "temporary_dnsmasq_conf" "$temporary_dnsmasq_conf"
  kv "ui_pidfile" "$temporary_ui_pid"
  kv "ui_log_path" "$temporary_ui_log"
  kv "ui_bind" "$ap_recovery_ip:$ui_port"
  if [ -n "$pid" ] && is_test_hostapd_pid "$pid"; then
    kv "test_hostapd_running" "yes"
    kv "pid" "$pid"
    kv "stop_command" "sudo sh modules/wifi-kit/prototype/ap-setup-test.sh stop"
  else
    kv "test_hostapd_running" "no"
    kv "pid" "${pid:-missing}"
  fi
  if [ -n "$dnsmasq_pid" ] && is_test_dnsmasq_pid "$dnsmasq_pid"; then
    kv "test_dnsmasq_running" "yes"
    kv "dnsmasq_pid" "$dnsmasq_pid"
  else
    kv "test_dnsmasq_running" "no"
    kv "dnsmasq_pid" "${dnsmasq_pid:-missing}"
  fi
  if [ -n "$ui_pid" ] && is_test_ui_pid "$ui_pid"; then
    kv "test_ui_running" "yes"
    kv "ui_pid" "$ui_pid"
  else
    kv "test_ui_running" "no"
    kv "ui_pid" "${ui_pid:-missing}"
  fi
}

cmd_diagnose_last() {
  printf '[wifi-kit] AP setup last-run diagnosis\n'
  kv "mode" "diagnose-last-readonly"
  kv "log_path" "$temporary_hostapd_log"
  kv "redacted_config_path" "$temporary_hostapd_conf_public"

  if [ ! -r "$temporary_hostapd_log" ]; then
    kv "log_present" "no"
    kv "diagnose_status" "WARN"
    kv "warning" "hostapd log is missing or not readable"
    return 0
  fi

  kv "log_present" "yes"
  kv "ap_enabled" "$(grep -q 'AP-ENABLED' "$temporary_hostapd_log" && printf yes || printf no)"
  kv "ap_disabled" "$(grep -q 'AP-DISABLED' "$temporary_hostapd_log" && printf yes || printf no)"
  kv "beacon_seen" "$(grep -Eiq 'beacon' "$temporary_hostapd_log" && printf yes || printf no)"
  kv "ignore_broadcast_ssid_seen" "$(grep -q 'ignore_broadcast_ssid' "$temporary_hostapd_log" && printf yes || printf no)"
  kv "nl80211_issue_seen" "$(grep -Eiq 'nl80211|Could not|failed|error' "$temporary_hostapd_log" && printf yes || printf no)"
  kv "ap_only_nm_state_present" "$([ -r "$ap_only_nm_state" ] && printf yes || printf no)"
  kv "estimated_duration" "unknown"

  section "important-log-lines"
  grep -Ei 'ignore_broadcast_ssid|beacon|AP-ENABLED|AP-DISABLED|nl80211|Could not|failed|error|interface state|mode|wlan0|wlan0_ap' "$temporary_hostapd_log" |
    tail -n 80 || true

  section "last-log-lines"
  tail -n 40 "$temporary_hostapd_log" || true

  if [ -r "$temporary_hostapd_conf_public" ]; then
    section "redacted-hostapd-config"
    cat "$temporary_hostapd_conf_public"
  fi
}

cmd_stop() {
  pid="$(test_pid_from_file || true)"

  printf '[wifi-kit] AP setup test stop\n'
  kv "mode" "stop"
  kv "pidfile" "$temporary_hostapd_pid"
  if [ -z "$pid" ]; then
    kv "stop_status" "no-pidfile"
    stop_return_check_loop_best_effort
    write_redacted_hostapd_config_copy
    write_redacted_dnsmasq_config_copy
    stop_test_ui_best_effort
    stop_test_dnsmasq_best_effort
    cleanup_test_ap_interface_best_effort
    remove_ap_recovery_ip_best_effort
    restore_nm_from_ap_only_state_best_effort
    restore_normal_ui_service_best_effort
    rm -f "$temporary_hostapd_conf" "$temporary_hostapd_pid" "$temporary_dnsmasq_conf" "$temporary_dnsmasq_pid" "$temporary_ui_pid" 2>/dev/null || true
    return 0
  fi
  if ! is_test_hostapd_pid "$pid"; then
    kv "stop_status" "pid-not-matching-wifi-kit-hostapd"
    kv "pid" "$pid"
    stop_return_check_loop_best_effort
    write_redacted_dnsmasq_config_copy
    stop_test_ui_best_effort
    stop_test_dnsmasq_best_effort
    remove_ap_recovery_ip_best_effort
    restore_nm_from_ap_only_state_best_effort
    restore_normal_ui_service_best_effort
    return 1
  fi
  if kill "$pid" 2>/dev/null; then
    kv "stop_status" "signal-sent"
    kv "pid" "$pid"
    stop_return_check_loop_best_effort
    write_redacted_hostapd_config_copy
    write_redacted_dnsmasq_config_copy
    stop_test_ui_best_effort
    stop_test_dnsmasq_best_effort
    cleanup_test_ap_interface_best_effort
    remove_ap_recovery_ip_best_effort
    restore_nm_from_ap_only_state_best_effort
    restore_normal_ui_service_best_effort
    rm -f "$temporary_hostapd_conf" "$temporary_hostapd_pid" "$temporary_dnsmasq_conf" "$temporary_dnsmasq_pid" "$temporary_ui_pid" 2>/dev/null || true
    return 0
  fi
  fail "could not stop test hostapd pid $pid; run with sudo if it was started as root"
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
ignore_broadcast_ssid=0
wpa_passphrase=<runtime-only-secret>
EOF
}

write_hostapd_config_real() {
  ssid=$1
  channel=$2
  passphrase=$3

  write_hostapd_config_for_interface "$iface" "$ssid" "$channel" "$passphrase"
}

write_hostapd_config_for_interface() {
  config_iface=$1
  ssid=$2
  channel=$3
  passphrase=$4

  cat >"$temporary_hostapd_conf" <<EOF
interface=$config_iface
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
ignore_broadcast_ssid=0
wpa_passphrase=$passphrase
EOF
  chmod 600 "$temporary_hostapd_conf"
}

write_redacted_hostapd_config_copy() {
  [ -r "$temporary_hostapd_conf" ] || return 0
  awk '
    /^wpa_passphrase=/ {
      print "wpa_passphrase=<redacted>"
      next
    }
    { print }
  ' "$temporary_hostapd_conf" >"$temporary_hostapd_conf_public"
  chmod 600 "$temporary_hostapd_conf_public" 2>/dev/null || true
}

runtime_ap_passphrase() {
  if [ -n "${WIFI_KIT_AP_PSK:-}" ]; then
    printf '%s\n' "$WIFI_KIT_AP_PSK"
    return 0
  fi
  printf '%s\n' "$ap_recovery_test_psk"
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
  kv "redacted_config_path" "$temporary_hostapd_conf_public"
  kv "log_path" "$temporary_hostapd_log"
  kv "pidfile" "$temporary_hostapd_pid"
  kv "hostapd_present" "$(find_tool hostapd >/dev/null 2>&1 && printf yes || printf no)"
  kv "hostapd_command" "$hostapd_bin -d $temporary_hostapd_conf"

  section "temporary-hostapd-config"
  write_hostapd_config_plan "$ssid" "$ap_channel"

  section "exact-command"
  kv "01.write_config" "create $quoted_conf mode 600 with runtime-only passphrase"
  kv "02.run_foreground" "timeout ${ap_duration_seconds}s $quoted_hostapd -d $quoted_conf"
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
    write_redacted_hostapd_config_copy
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
  kv "hostapd_command" "$hostapd_bin -d $temporary_hostapd_conf"
  kv "runtime_secret" "not-logged"
  kv "phone_check" "look for SSID $ssid now"

  set +e
  timeout "${ap_duration_seconds}s" "$hostapd_bin" -d "$temporary_hostapd_conf"
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

cmd_apply_manual_test() {
  [ "$confirm_phrase" = "WIFI-KIT AP MANUAL TEST" ] ||
    fail "apply-manual-test requires --confirm \"WIFI-KIT AP MANUAL TEST\""

  channel="$(current_channel || true)"
  ssid="$(effective_ap_ssid)"
  if [ -z "$ap_channel" ]; then
    ap_channel="${channel:-6}"
  fi
  require_number "--max-seconds" "$ap_max_seconds"
  if [ "$ap_max_seconds" -lt 1 ]; then
    fail "--max-seconds must be greater than 0"
  fi

  hostapd_bin="$(find_tool hostapd 2>/dev/null || true)"
  if [ -z "$hostapd_bin" ]; then
    hostapd_bin="hostapd"
  fi

  printf '[wifi-kit] AP setup manual test gated plan\n'
  kv "mode" "apply-manual-test-plan"
  kv "real_apply_requested" "$dangerous_real_apply"
  kv "network_writes" "false"
  kv "hostapd_started" "false"
  kv "dnsmasq_started" "false"
  kv "networkmanager_modified" "false"
  kv "save_config" "not-called"
  kv "interface" "$iface"
  kv "ap_ssid" "$ssid"
  kv "ap_channel" "$ap_channel"
  kv "max_seconds" "$ap_max_seconds"
  kv "temporary_hostapd_conf" "$temporary_hostapd_conf"
  kv "redacted_config_path" "$temporary_hostapd_conf_public"
  kv "log_path" "$temporary_hostapd_log"
  kv "pidfile" "$temporary_hostapd_pid"
  kv "hostapd_present" "$(find_tool hostapd >/dev/null 2>&1 && printf yes || printf no)"
  kv "hostapd_command" "$hostapd_bin -d $temporary_hostapd_conf"

  section "temporary-hostapd-config"
  write_hostapd_config_plan "$ssid" "$ap_channel"

  section "exact-command"
  kv "01.write_config" "create $(shell_quote "$temporary_hostapd_conf") mode 600 with runtime-only passphrase"
  kv "02.run_hostapd" "$hostapd_bin -d $temporary_hostapd_conf > $(shell_quote "$temporary_hostapd_log") 2>&1"
  kv "03.pidfile" "$temporary_hostapd_pid"
  kv "04.stop" "sudo sh modules/wifi-kit/prototype/ap-setup-test.sh stop"
  kv "05.auto_stop" "after ${ap_max_seconds}s if not manually stopped"
  kv "06.status" "sh modules/wifi-kit/prototype/ap-setup-test.sh status"

  section "guards"
  kv "apply_without_extra_gate" "plan-only"
  kv "real_execution_requires" "--dangerous-real-apply plus separate explicit validation"
  kv "root_required" "yes"
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
    fail "real AP manual test requires root; run: sudo sh modules/wifi-kit/prototype/ap-setup-test.sh apply-manual-test --dangerous-real-apply --confirm \"WIFI-KIT AP MANUAL TEST\""
  fi
  find_tool hostapd >/dev/null 2>&1 || fail "hostapd is required"

  existing_pid="$(test_pid_from_file || true)"
  if [ -n "$existing_pid" ] && is_test_hostapd_pid "$existing_pid"; then
    fail "wifi-kit test hostapd already running with pid $existing_pid"
  fi

  passphrase="$(runtime_ap_passphrase)"
  case "$passphrase" in
    ????????*) ;;
    *) fail "runtime AP passphrase must be at least 8 characters" ;;
  esac

  hostapd_pid=""
  cleanup_manual() {
    if [ -n "${hostapd_pid:-}" ] && is_test_hostapd_pid "$hostapd_pid"; then
      kill "$hostapd_pid" 2>/dev/null || true
      wait "$hostapd_pid" 2>/dev/null || true
    fi
    write_redacted_hostapd_config_copy
    rm -f "$temporary_hostapd_conf" "$temporary_hostapd_pid"
  }
  trap cleanup_manual EXIT INT TERM HUP
  rm -f "$temporary_hostapd_conf" "$temporary_hostapd_pid"
  : >"$temporary_hostapd_log"
  chmod 600 "$temporary_hostapd_log"

  umask 077
  write_hostapd_config_real "$ssid" "$ap_channel" "$passphrase"

  section "real-apply"
  kv "apply_status" "starting"
  kv "ap_ssid" "$ssid"
  kv "ap_channel" "$ap_channel"
  kv "max_seconds" "$ap_max_seconds"
  kv "log_path" "$temporary_hostapd_log"
  kv "pidfile" "$temporary_hostapd_pid"
  kv "redacted_config_path" "$temporary_hostapd_conf_public"
  kv "runtime_secret" "not-logged"
  kv "phone_check" "look for SSID $ssid now"
  kv "stop_command" "sudo sh modules/wifi-kit/prototype/ap-setup-test.sh stop"

  "$hostapd_bin" -d "$temporary_hostapd_conf" >"$temporary_hostapd_log" 2>&1 &
  hostapd_pid=$!
  printf '%s\n' "$hostapd_pid" >"$temporary_hostapd_pid"
  kv "hostapd_pid" "$hostapd_pid"

  elapsed=0
  while is_test_hostapd_pid "$hostapd_pid"; do
    if [ "$elapsed" -ge "$ap_max_seconds" ]; then
      kv "auto_stop" "max-seconds-reached"
      break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  if is_test_hostapd_pid "$hostapd_pid"; then
    kill "$hostapd_pid" 2>/dev/null || true
    wait "$hostapd_pid" 2>/dev/null || true
  fi

  section "post-check"
  kv "elapsed_seconds" "$elapsed"
  kv "log_path" "$temporary_hostapd_log"
  kv "config_cleanup" "done"
  rm -f "$temporary_hostapd_conf" "$temporary_hostapd_pid"
  trap - EXIT INT TERM HUP
  kv "apply_status" "completed-or-stopped"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    preflight|plan|apply|apply-short-test|apply-manual-test|status|stop|diagnose-last|plan-ap-sta|apply-ap-sta-manual-test|plan-ap-only|apply-ap-only-manual-test|plan-ap-recovery|apply-ap-recovery-manual-test)
      [ -z "$mode" ] || fail "choose only one mode"
      mode="$1"
      ;;
    --iface)
      [ "$#" -gt 1 ] || fail "--iface requires a value"
      iface="$2"
      shift
      ;;
    --ap-iface)
      [ "$#" -gt 1 ] || fail "--ap-iface requires a value"
      ap_iface="$2"
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
    --max-seconds)
      [ "$#" -gt 1 ] || fail "--max-seconds requires a value"
      ap_max_seconds="$2"
      ap_max_seconds_set="1"
      shift
      ;;
    --stay-up-until-stop)
      ap_stay_up_until_stop="1"
      ;;
    --ui-port)
      [ "$#" -gt 1 ] || fail "--ui-port requires a value"
      ui_port="$2"
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
  apply-manual-test) cmd_apply_manual_test ;;
  status) cmd_status ;;
  stop) cmd_stop ;;
  diagnose-last) cmd_diagnose_last ;;
  plan-ap-sta) cmd_plan_ap_sta ;;
  apply-ap-sta-manual-test) cmd_apply_ap_sta_manual_test ;;
  plan-ap-only) cmd_plan_ap_only ;;
  apply-ap-only-manual-test) cmd_apply_ap_only_manual_test ;;
  plan-ap-recovery) cmd_plan_ap_recovery ;;
  apply-ap-recovery-manual-test) cmd_apply_ap_recovery_manual_test ;;
  *)
    usage
    exit 2
    ;;
esac
