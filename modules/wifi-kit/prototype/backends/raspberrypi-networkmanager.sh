#!/bin/sh
set -eu

iface="${WIFI_KIT_IFACE:-wlan0}"

usage() {
  cat <<'EOF'
Usage:
  raspberrypi-networkmanager.sh status [IFACE]
  raspberrypi-networkmanager.sh active-connection [IFACE]
  raspberrypi-networkmanager.sh device-status
  raspberrypi-networkmanager.sh scan [IFACE]
  raspberrypi-networkmanager.sh fingerprint [IFACE]

Read-only NetworkManager helper. It never runs connection up/down/add/delete,
never modifies profiles, never starts services, and never reads secrets.
EOF
}

fail() {
  printf 'error=%s\n' "$*" >&2
  exit 1
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

nmcli_bin() {
  find_tool nmcli 2>/dev/null || fail "nmcli-missing"
}

systemctl_bin() {
  find_tool systemctl 2>/dev/null || true
}

kv() {
  printf '%s=%s\n' "$1" "$2"
}

networkmanager_state() {
  nmcli=$(nmcli_bin)
  running="$("$nmcli" -t -f RUNNING general 2>/dev/null | sed -n '1p' || true)"
  if [ "$running" = "running" ]; then
    printf 'active\n'
    return 0
  fi

  systemctl=$(systemctl_bin)
  if [ -n "$systemctl" ] && "$systemctl" is-active --quiet NetworkManager 2>/dev/null; then
    printf 'active\n'
    return 0
  fi

  printf 'inactive-or-unavailable\n'
}

device_connection() {
  wanted_iface=$1
  nmcli=$(nmcli_bin)
  "$nmcli" -t -f DEVICE,CONNECTION device status 2>/dev/null |
    awk -F: -v iface="$wanted_iface" '$1 == iface { print $2; exit }'
}

device_state() {
  wanted_iface=$1
  nmcli=$(nmcli_bin)
  "$nmcli" -t -f DEVICE,STATE device status 2>/dev/null |
    awk -F: -v iface="$wanted_iface" '$1 == iface { print $2; exit }'
}

cmd_status() {
  wanted_iface=$1
  nmcli=$(nmcli_bin)
  kv "backend" "raspberrypi-networkmanager"
  kv "mode" "read-only"
  kv "networkmanager_state" "$(networkmanager_state)"
  kv "interface" "$wanted_iface"
  kv "device_state" "$(device_state "$wanted_iface")"
  kv "active_connection" "$(device_connection "$wanted_iface")"
  "$nmcli" -f GENERAL.DEVICE,GENERAL.TYPE,GENERAL.STATE,GENERAL.CONNECTION,IP4.ADDRESS,IP4.GATEWAY device show "$wanted_iface" 2>/dev/null |
    sed 's/[[:space:]][[:space:]]*/ /g; s/: /_/; s/^/nmcli_/'
}

cmd_active_connection() {
  wanted_iface=$1
  nmcli=$(nmcli_bin)
  active="$(device_connection "$wanted_iface")"
  kv "backend" "raspberrypi-networkmanager"
  kv "mode" "read-only"
  kv "interface" "$wanted_iface"
  kv "active_connection" "$active"
  if [ -n "$active" ] && [ "$active" != "--" ]; then
    "$nmcli" -f connection.id,connection.uuid,connection.type,connection.interface-name,802-11-wireless.ssid,ipv4.method,ipv6.method connection show "$active" 2>/dev/null |
      sed 's/[[:space:]][[:space:]]*/ /g; s/: /_/; s/^/nmcli_/'
  fi
}

cmd_device_status() {
  nmcli=$(nmcli_bin)
  kv "backend" "raspberrypi-networkmanager"
  kv "mode" "read-only"
  "$nmcli" device status
}

cmd_scan() {
  wanted_iface=$1
  nmcli=$(nmcli_bin)
  kv "backend" "raspberrypi-networkmanager"
  kv "mode" "read-only"
  kv "interface" "$wanted_iface"
  kv "scan_command" "nmcli device wifi list ifname <iface> --rescan no"
  "$nmcli" -f SSID,BSSID,CHAN,FREQ,SIGNAL,SECURITY,IN-USE device wifi list ifname "$wanted_iface" --rescan no 2>/dev/null || {
    kv "scan_status" "unavailable"
    return 0
  }
}

cmd_fingerprint() {
  wanted_iface=$1
  nmcli=$(nmcli_bin)
  kv "backend" "raspberrypi-networkmanager"
  kv "mode" "read-only"
  kv "networkmanager_state" "$(networkmanager_state)"
  kv "interface" "$wanted_iface"
  kv "device_state" "$(device_state "$wanted_iface")"
  kv "active_connection" "$(device_connection "$wanted_iface")"
  "$nmcli" -t -f NAME,UUID,TYPE,DEVICE connection show --active 2>/dev/null |
    sed 's/^/active_connection_record=/'
}

command_name="${1:-}"
case "$command_name" in
  status)
    shift
    cmd_status "${1:-$iface}"
    ;;
  active-connection)
    shift
    cmd_active_connection "${1:-$iface}"
    ;;
  device-status)
    shift
    cmd_device_status
    ;;
  scan)
    shift
    cmd_scan "${1:-$iface}"
    ;;
  fingerprint)
    shift
    cmd_fingerprint "${1:-$iface}"
    ;;
  -h|--help|"")
    usage
    ;;
  *)
    fail "unknown-command-$command_name"
    ;;
esac
