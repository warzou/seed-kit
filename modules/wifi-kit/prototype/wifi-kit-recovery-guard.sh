#!/bin/sh
set -eu

mode="audit"
mode_set="0"
iface="wlan0"
ap_iface="wlan0_ap"
ap_recovery_ip="192.168.50.1"
ap_recovery_cidr="24"
remove_logs="0"

temporary_hostapd_conf="/tmp/wifi-kit-hostapd-test.conf"
temporary_hostapd_conf_public="/tmp/wifi-kit-hostapd-test.conf.redacted"
temporary_hostapd_log="/tmp/wifi-kit-hostapd-test.log"
temporary_hostapd_pid="/tmp/wifi-kit-hostapd-test.pid"
temporary_dnsmasq_conf="/tmp/wifi-kit-dnsmasq-recovery.conf"
temporary_dnsmasq_conf_public="/tmp/wifi-kit-dnsmasq-recovery.conf.redacted"
temporary_dnsmasq_log="/tmp/wifi-kit-dnsmasq-recovery.log"
temporary_dnsmasq_pid="/tmp/wifi-kit-dnsmasq-recovery.pid"
temporary_ui_log="/tmp/wifi-kit-ui-recovery.log"
temporary_ui_pid="/tmp/wifi-kit-ui-recovery.pid"
ap_only_nm_state="/tmp/wifi-kit-ap-only-nm-state"

usage() {
  cat <<'EOF'
wifi-kit recovery guard prototype

Audit and cleanup helper for interrupted Wifi-Kit AP recovery tests.
Default mode is read-only audit. Cleanup is strict and only touches known
Wifi-Kit temporary files, PIDs whose cmdline points to those files, wlan0_ap,
and the Wifi-Kit recovery IP.

Usage:
  sh modules/wifi-kit/prototype/wifi-kit-recovery-guard.sh
  sh modules/wifi-kit/prototype/wifi-kit-recovery-guard.sh audit
  sh modules/wifi-kit/prototype/wifi-kit-recovery-guard.sh status
  sh modules/wifi-kit/prototype/wifi-kit-recovery-guard.sh cleanup

Options:
  --iface <name>       Wi-Fi client/AP recovery interface. Default: wlan0
  --ap-iface <name>    Test AP virtual interface. Default: wlan0_ap
  --remove-logs        Also remove Wifi-Kit temporary logs. Default: keep logs
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

file_state() {
  path=$1
  if [ -e "$path" ]; then
    kv "$path" "present"
  else
    kv "$path" "absent"
  fi
}

read_pidfile() {
  pidfile=$1
  [ -r "$pidfile" ] || return 0
  sed -n '1p' "$pidfile" 2>/dev/null || true
}

pid_cmdline() {
  pid=$1
  [ -n "$pid" ] || return 1
  case "$pid" in *[!0-9]*|'') return 1 ;; esac
  [ -d "/proc/$pid" ] || return 1
  tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true
}

is_wifi_kit_hostapd_pid() {
  pid=$1
  cmdline="$(pid_cmdline "$pid" 2>/dev/null || true)"
  case "$cmdline" in
    *hostapd*" $temporary_hostapd_conf"*) return 0 ;;
    *hostapd*"$temporary_hostapd_conf"*) return 0 ;;
    *) return 1 ;;
  esac
}

is_wifi_kit_dnsmasq_pid() {
  pid=$1
  cmdline="$(pid_cmdline "$pid" 2>/dev/null || true)"
  case "$cmdline" in
    *dnsmasq*"--conf-file=$temporary_dnsmasq_conf"*) return 0 ;;
    *dnsmasq*"--conf-file $temporary_dnsmasq_conf"*) return 0 ;;
    *dnsmasq*"$temporary_dnsmasq_conf"*) return 0 ;;
    *) return 1 ;;
  esac
}

hostapd_pid() {
  read_pidfile "$temporary_hostapd_pid"
}

dnsmasq_pid() {
  read_pidfile "$temporary_dnsmasq_pid"
}

interface_exists() {
  ip link show "$1" >/dev/null 2>&1
}

ap_interface_type() {
  iw_bin="$(find_tool iw 2>/dev/null || true)"
  [ -n "$iw_bin" ] || return 0
  "$iw_bin" dev "$ap_iface" info 2>/dev/null |
    awk '$1 == "type" { print $2; exit }'
}

ap_recovery_ip_present() {
  ip_bin="$(find_tool ip 2>/dev/null || true)"
  [ -n "$ip_bin" ] || return 1
  "$ip_bin" -o addr show dev "$iface" 2>/dev/null |
    awk -v ip="$ap_recovery_ip/$ap_recovery_cidr" '$0 ~ ip { found = 1 } END { exit found ? 0 : 1 }'
}

active_connection_from_state() {
  [ -r "$ap_only_nm_state" ] || return 0
  sed -n 's/^active_connection=//p' "$ap_only_nm_state" | sed -n '1p'
}

cmd_status() {
  hp="$(hostapd_pid || true)"
  dp="$(dnsmasq_pid || true)"
  ap_type="$(ap_interface_type || true)"

  printf '[wifi-kit] recovery guard status\n'
  kv "mode" "status-readonly"
  kv "iface" "$iface"
  kv "ap_iface" "$ap_iface"
  kv "ap_recovery_ip" "$ap_recovery_ip/$ap_recovery_cidr"
  kv "root" "$([ "$(id -u 2>/dev/null || printf 1)" = "0" ] && printf yes || printf no)"

  kv "wifi_kit_hostapd_pid" "${hp:-missing}"
  kv "wifi_kit_hostapd_running" "$([ -n "$hp" ] && is_wifi_kit_hostapd_pid "$hp" && printf yes || printf no)"
  kv "wifi_kit_dnsmasq_pid" "${dp:-missing}"
  kv "wifi_kit_dnsmasq_running" "$([ -n "$dp" ] && is_wifi_kit_dnsmasq_pid "$dp" && printf yes || printf no)"
  kv "ap_iface_exists" "$(interface_exists "$ap_iface" && printf yes || printf no)"
  kv "ap_iface_type" "${ap_type:-unknown}"
  kv "ap_recovery_ip_present" "$(ap_recovery_ip_present && printf yes || printf no)"
  kv "nm_state_file_present" "$([ -e "$ap_only_nm_state" ] && printf yes || printf no)"
}

cmd_audit() {
  printf '[wifi-kit] recovery guard audit\n'
  kv "mode" "audit-readonly"
  kv "cleanup_performed" "false"
  cmd_status

  section "temporary-files"
  file_state "$temporary_hostapd_conf"
  file_state "$temporary_hostapd_conf_public"
  file_state "$temporary_hostapd_log"
  file_state "$temporary_hostapd_pid"
  file_state "$temporary_dnsmasq_conf"
  file_state "$temporary_dnsmasq_conf_public"
  file_state "$temporary_dnsmasq_log"
  file_state "$temporary_dnsmasq_pid"
  file_state "$temporary_ui_log"
  file_state "$temporary_ui_pid"
  file_state "$ap_only_nm_state"

  section "networkmanager"
  nmcli_bin="$(find_tool nmcli 2>/dev/null || true)"
  if [ -n "$nmcli_bin" ]; then
    "$nmcli_bin" device status 2>/dev/null || true
    "$nmcli_bin" connection show --active 2>/dev/null || true
  else
    kv "nmcli" "missing"
  fi

  section "radio"
  iw_bin="$(find_tool iw 2>/dev/null || true)"
  if [ -n "$iw_bin" ]; then
    "$iw_bin" dev 2>/dev/null || true
  else
    kv "iw" "missing"
  fi
}

stop_wifi_kit_pid() {
  label=$1
  pid=$2
  [ -n "$pid" ] || {
    kv "${label}_stop" "no-pidfile"
    return 0
  }
  case "$label" in
    hostapd)
      is_wifi_kit_hostapd_pid "$pid" || {
        kv "hostapd_stop" "refused-pid-not-wifi-kit"
        kv "hostapd_pid" "$pid"
        return 0
      }
      ;;
    dnsmasq)
      is_wifi_kit_dnsmasq_pid "$pid" || {
        kv "dnsmasq_stop" "refused-pid-not-wifi-kit"
        kv "dnsmasq_pid" "$pid"
        return 0
      }
      ;;
    *) return 0 ;;
  esac

  if kill "$pid" 2>/dev/null; then
    kv "${label}_stop" "signal-sent"
    wait "$pid" 2>/dev/null || true
  else
    kv "${label}_stop" "kill-failed-or-already-exited"
  fi
}

cleanup_ap_iface() {
  if [ "$ap_iface" != "wlan0_ap" ]; then
    kv "ap_iface_cleanup" "refused-non-default-name"
    return 0
  fi
  if ! interface_exists "$ap_iface"; then
    kv "ap_iface_cleanup" "absent"
    return 0
  fi
  [ "$(id -u 2>/dev/null || printf 1)" = "0" ] || {
    kv "ap_iface_cleanup" "needs-root"
    return 0
  }
  iw_bin="$(find_tool iw 2>/dev/null || true)"
  [ -n "$iw_bin" ] || {
    kv "ap_iface_cleanup" "iw-missing"
    return 0
  }
  ap_type="$(ap_interface_type || true)"
  case "$ap_type" in
    AP|__ap|'')
      ip link set "$ap_iface" down 2>/dev/null || true
      "$iw_bin" dev "$ap_iface" del 2>/dev/null &&
        kv "ap_iface_cleanup" "deleted" ||
        kv "ap_iface_cleanup" "delete-failed"
      ;;
    *)
      kv "ap_iface_cleanup" "refused-type-$ap_type"
      ;;
  esac
}

cleanup_ap_ip() {
  if ! ap_recovery_ip_present; then
    kv "ap_ip_cleanup" "absent"
    return 0
  fi
  [ "$(id -u 2>/dev/null || printf 1)" = "0" ] || {
    kv "ap_ip_cleanup" "needs-root"
    return 0
  }
  ip_bin="$(find_tool ip 2>/dev/null || true)"
  [ -n "$ip_bin" ] || {
    kv "ap_ip_cleanup" "ip-missing"
    return 0
  }
  "$ip_bin" addr del "$ap_recovery_ip/$ap_recovery_cidr" dev "$iface" >/dev/null 2>&1 &&
    kv "ap_ip_cleanup" "removed" ||
    kv "ap_ip_cleanup" "remove-failed"
}

restore_networkmanager() {
  [ "$(id -u 2>/dev/null || printf 1)" = "0" ] || {
    kv "networkmanager_restore" "needs-root"
    return 0
  }
  nmcli_bin="$(find_tool nmcli 2>/dev/null || true)"
  [ -n "$nmcli_bin" ] || {
    kv "networkmanager_restore" "nmcli-missing"
    return 0
  }

  "$nmcli_bin" device set "$iface" managed yes >/dev/null 2>&1 || true
  previous="$(active_connection_from_state || true)"
  if [ -n "$previous" ] && [ "$previous" != "--" ]; then
    "$nmcli_bin" connection up "$previous" ifname "$iface" >/dev/null 2>&1 ||
      "$nmcli_bin" device connect "$iface" >/dev/null 2>&1 || true
  else
    "$nmcli_bin" device connect "$iface" >/dev/null 2>&1 || true
  fi
  kv "networkmanager_restore" "attempted"
}

cmd_cleanup() {
  printf '[wifi-kit] recovery guard cleanup\n'
  kv "mode" "cleanup"
  kv "scope" "wifi-kit-temporary-only"
  kv "systemctl" "not-used"
  kv "save_config" "not-called"

  stop_wifi_kit_pid "dnsmasq" "$(dnsmasq_pid || true)"
  stop_wifi_kit_pid "hostapd" "$(hostapd_pid || true)"

  cleanup_ap_iface
  cleanup_ap_ip
  restore_networkmanager

  rm -f "$temporary_hostapd_pid" "$temporary_dnsmasq_pid" "$temporary_ui_pid" 2>/dev/null || true
  rm -f "$temporary_hostapd_conf" "$temporary_hostapd_conf_public" 2>/dev/null || true
  rm -f "$temporary_dnsmasq_conf" "$temporary_dnsmasq_conf_public" 2>/dev/null || true
  rm -f "$ap_only_nm_state" 2>/dev/null || true
  if [ "$remove_logs" = "1" ]; then
    rm -f "$temporary_hostapd_log" "$temporary_dnsmasq_log" "$temporary_ui_log" 2>/dev/null || true
    kv "logs_cleanup" "removed"
  else
    kv "logs_cleanup" "kept"
  fi
  kv "configs_cleanup" "done"
  kv "pidfiles_cleanup" "done"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    audit|status|cleanup)
      [ "$mode_set" = "0" ] || fail "choose only one mode"
      mode="$1"
      mode_set="1"
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
    --remove-logs)
      remove_logs="1"
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
  audit) cmd_audit ;;
  status) cmd_status ;;
  cleanup) cmd_cleanup ;;
esac
