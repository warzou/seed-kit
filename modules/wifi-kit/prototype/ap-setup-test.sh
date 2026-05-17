#!/bin/sh
set -eu

mode=""
iface="wlan0"
ap_iface="wlan0_ap"
ap_ssid=""
ap_channel=""
ap_duration_seconds="30"
ap_max_seconds="300"
ap_max_seconds_set="0"
temporary_hostapd_conf="/tmp/wifi-kit-hostapd-test.conf"
temporary_hostapd_conf_public="/tmp/wifi-kit-hostapd-test.conf.redacted"
temporary_hostapd_log="/tmp/wifi-kit-hostapd-test.log"
temporary_hostapd_pid="/tmp/wifi-kit-hostapd-test.pid"
ap_only_nm_state="/tmp/wifi-kit-ap-only-nm-state"
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

Options:
  --iface <name>           Wi-Fi interface. Default: wlan0
  --ap-iface <name>        Future virtual AP interface. Default: wlan0_ap
  --ssid <name>            Future AP SSID. Default: Wifi-Kit-<hostname>
  --channel <number>       Future AP channel. Default: current wlan0 channel if detected
  --duration-seconds <n>   Future short AP test duration. Default: 30
  --max-seconds <n>        Future manual AP max duration. Default: 300
                            AP+STA dedicated-interface default: 600
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

  printf '[wifi-kit] AP setup test status\n'
  kv "mode" "status-readonly"
  kv "pidfile" "$temporary_hostapd_pid"
  kv "log_path" "$temporary_hostapd_log"
  kv "temporary_hostapd_conf" "$temporary_hostapd_conf"
  if [ -n "$pid" ] && is_test_hostapd_pid "$pid"; then
    kv "test_hostapd_running" "yes"
    kv "pid" "$pid"
    kv "stop_command" "sudo sh modules/wifi-kit/prototype/ap-setup-test.sh stop"
  else
    kv "test_hostapd_running" "no"
    kv "pid" "${pid:-missing}"
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
    write_redacted_hostapd_config_copy
    cleanup_test_ap_interface_best_effort
    restore_nm_from_ap_only_state_best_effort
    rm -f "$temporary_hostapd_conf" "$temporary_hostapd_pid" 2>/dev/null || true
    return 0
  fi
  if ! is_test_hostapd_pid "$pid"; then
    kv "stop_status" "pid-not-matching-wifi-kit-hostapd"
    kv "pid" "$pid"
    return 1
  fi
  if kill "$pid" 2>/dev/null; then
    kv "stop_status" "signal-sent"
    kv "pid" "$pid"
    write_redacted_hostapd_config_copy
    cleanup_test_ap_interface_best_effort
    restore_nm_from_ap_only_state_best_effort
    rm -f "$temporary_hostapd_conf" "$temporary_hostapd_pid" 2>/dev/null || true
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
    preflight|plan|apply|apply-short-test|apply-manual-test|status|stop|diagnose-last|plan-ap-sta|apply-ap-sta-manual-test|plan-ap-only|apply-ap-only-manual-test)
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
  *)
    usage
    exit 2
    ;;
esac
