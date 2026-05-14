#!/bin/sh
set -eu

WIFI_KIT_STATE_ROOT="${WIFI_KIT_STATE_ROOT:-/tmp/wifi-kit-sim-state}"
WIFI_KIT_STATE_FILE="${WIFI_KIT_STATE_ROOT}/state.conf"
WIFI_KIT_KNOWN_FILE="${WIFI_KIT_STATE_ROOT}/known_networks.txt"
WIFI_KIT_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# shellcheck source=helpers.sh
. "$WIFI_KIT_SCRIPT_DIR/helpers.sh"

ui() { printf '%s\n' "$*"; }
ui_header() { printf '\n[wifi-kit] %s\n' "$*"; }

tool_state() {
  tool_path="$(find_tool "$1" 2>/dev/null || true)"
  if [ -n "$tool_path" ]; then
    ui "  - $1: present ($tool_path)"
    return 0
  fi

  ui "  - $1: missing"
  return 1
}

os_field() {
  field="$1"
  if [ -r /etc/os-release ]; then
    (
      . /etc/os-release
      eval "printf '%s\n' \"\${$field:-}\""
    )
  fi
}

detect_wifi_interfaces() {
  found=0

  for wireless_dir in /sys/class/net/*/wireless; do
    [ -d "$wireless_dir" ] || continue
    iface=${wireless_dir%/wireless}
    iface=${iface##*/}
    ui "$iface"
    found=1
  done

  iw_bin="$(find_tool iw 2>/dev/null || true)"
  if [ "$found" -eq 0 ] && [ -n "$iw_bin" ]; then
    "$iw_bin" dev 2>/dev/null | awk '/^[[:space:]]*Interface / { print $2 }'
  fi
}

is_wifi_interface() {
  wanted="$1"
  detect_wifi_interfaces | awk -v wanted="$wanted" '
    $0 == wanted { found=1 }
    END { exit found ? 0 : 1 }
  '
}

wifi_interface_count() {
  detect_wifi_interfaces | awk 'NF { count++ } END { print count + 0 }'
}

first_wifi_interface() {
  detect_wifi_interfaces | sed -n '1p'
}

cmd_backend_detect() {
  ui_header "backend-detect (read-only)"
  ui "safety: read-only, no connection, no network writes, no secrets"

  os_id="$(os_field ID || true)"
  os_name="$(os_field NAME || true)"
  os_like="$(os_field ID_LIKE || true)"

  ui "os:"
  ui "  - id: ${os_id:-unknown}"
  ui "  - name: ${os_name:-unknown}"
  ui "  - like: ${os_like:-unknown}"

  ui "tools:"
  tool_state iw || true
  tool_state ip || true
  tool_state wpa_cli || true
  tool_state wpa_supplicant || true
  tool_state dhcpcd || true
  tool_state dhclient || true
  tool_state busybox || true

  recommended="generic-readonly"
  case "$os_id $os_name $os_like" in
    *raspbian*|*raspberry*|*debian*)
      if has_tool wpa_supplicant || has_tool wpa_cli; then
        recommended="rpios-wpa"
      fi
      ;;
  esac

  ui "recommended_backend=$recommended"
}

cmd_status_real() {
  ui_header "status-real (read-only)"
  ui "safety: read-only, no connection, no network writes, no secrets"

  interfaces="$(detect_wifi_interfaces || true)"
  if [ -z "$interfaces" ]; then
    ui "wifi_interfaces: none detected"
  else
    ui "wifi_interfaces:"
    printf '%s\n' "$interfaces" | while IFS= read -r iface; do
      [ -n "$iface" ] || continue
      ui "  - $iface"
      ip_bin="$(find_tool ip 2>/dev/null || true)"
      if [ -n "$ip_bin" ]; then
        "$ip_bin" -o addr show dev "$iface" 2>/dev/null | awk '{ print "    addr: "$3" "$4 }' || true
      else
        ui "    addr: unavailable (ip missing)"
      fi
    done
  fi

  ui "default_routes:"
  ip_bin="$(find_tool ip 2>/dev/null || true)"
  if [ -n "$ip_bin" ]; then
    "$ip_bin" route show default 2>/dev/null | sed 's/^/  - /' || ui "  - unavailable"
  else
    ui "  - unavailable (ip missing)"
  fi
}

cmd_scan_real() {
  ui_header "scan-real (read-only)"
  ui "safety: read-only, no connection, no network writes, no secrets"

  iw_bin="$(find_tool iw 2>/dev/null || true)"
  if [ -z "$iw_bin" ]; then
    ui "scan-real unavailable: iw is missing"
    return 0
  fi

  iface="${1:-}"
  if [ -z "$iface" ]; then
    iface="$(detect_wifi_interfaces | sed -n '1p')"
  fi

  if [ -z "$iface" ]; then
    ui "scan-real unavailable: no Wi-Fi interface detected"
    return 0
  fi

  tmp="${TMPDIR:-/tmp}/wifi-kit-iw-scan.$$"
  err="${TMPDIR:-/tmp}/wifi-kit-iw-scan-err.$$"

  if "$iw_bin" dev "$iface" scan > "$tmp" 2> "$err"; then
    ui "interface=$iface"
    awk '
      /^[[:space:]]*signal:/ {
        signal=$2 " " $3
      }
      /^[[:space:]]*SSID:/ {
        ssid=$0
        sub(/^[[:space:]]*SSID:[[:space:]]*/, "", ssid)
        if (ssid != "") {
          printf "  - ssid=%s signal=%s\n", ssid, signal
        }
      }
    ' "$tmp"
  else
    ui "scan-real unavailable on $iface: iw scan failed"
    ui "hint: this may require root/CAP_NET_ADMIN or an idle Wi-Fi interface"
    if [ -s "$err" ]; then
      sed -n '1,3p' "$err" | sed 's/^/  detail: /'
    fi
  fi

  rm -f "$tmp" "$err"
}

cmd_stability_status() {
  ui_header "stability-status (read-only)"
  ui "safety: read-only, no connection, no network writes, no secrets"

  iw_bin="$(find_tool iw 2>/dev/null || true)"
  if [ -z "$iw_bin" ]; then
    ui "stability-status unavailable: iw is missing"
    return 1
  fi

  interfaces="$(detect_wifi_interfaces || true)"
  if [ -z "$interfaces" ]; then
    ui "stability-status unavailable: no Wi-Fi interface detected"
    return 1
  fi

  printf '%s\n' "$interfaces" | while IFS= read -r iface; do
    [ -n "$iface" ] || continue
    power_save="$("$iw_bin" dev "$iface" get power_save 2>/dev/null || true)"
    if [ -z "$power_save" ]; then
      power_save="power_save: unavailable"
    fi
    ui "interface=$iface $power_save"
  done
}

cmd_stability_plan() {
  ui_header "stability-plan"
  ui "problem: Raspberry Pi Zero 2 W may become unstable in idle when wlan0 power_save=on"
  ui "validated current-boot fix: iw dev <iface> set power_save off"
  ui "scope: current boot only; not persistent after reboot"
  ui "no config files, services, SSID changes, or Wi-Fi connections are touched"
  ui "rollback: reboot, or run: iw dev <iface> set power_save on"
  ui "recommended before connect-safe/hotspot: verify Wi-Fi remains stable while idle"
  ui "manual apply command: sh modules/wifi-kit/prototype/wifi-kit.sh stability-apply-current-boot <iface>"
}

cmd_stability_apply_current_boot() {
  ui_header "stability-apply-current-boot"
  ui "safety: current-boot only; no persistence, no config writes, no services"
  ui "no secrets, no hostapd, no dnsmasq, no NetworkManager apply, no SSID/connection changes"

  iw_bin="$(find_tool iw 2>/dev/null || true)"
  if [ -z "$iw_bin" ]; then
    ui "refusing: iw is missing"
    return 1
  fi

  iface="${1:-}"
  if [ -z "$iface" ]; then
    count="$(wifi_interface_count)"
    if [ "$count" -eq 1 ]; then
      iface="$(first_wifi_interface)"
    else
      ui "refusing: pass an explicit Wi-Fi interface when none or multiple are detected"
      return 1
    fi
  fi

  if [ -z "$iface" ] || ! is_wifi_interface "$iface"; then
    ui "refusing: '$iface' is not a detected Wi-Fi interface"
    return 1
  fi

  ui "about to run: $iw_bin dev $iface set power_save off"
  if "$iw_bin" dev "$iface" set power_save off; then
    ui "applied: power_save off for $iface (current boot only)"
    ui "rollback: reboot, or run: iw dev $iface set power_save on"
    return 0
  fi

  ui "failed: iw could not set power_save off for $iface"
  ui "hint: this may require root/CAP_NET_ADMIN on the target Raspberry Pi"
  return 1
}

init_state_root() {
  mkdir -p "$WIFI_KIT_STATE_ROOT"
  # shell-safe simulation: local writable path by default
  chmod 700 "$WIFI_KIT_STATE_ROOT" 2>/dev/null || true
}

init_state_file() {
  if [ ! -f "$WIFI_KIT_STATE_FILE" ]; then
    cat > "$WIFI_KIT_STATE_FILE" <<'EOF'
mode=ap
last_successful_ssid=
known_networks=
last_error=
retry_count=0
EOF
  fi
}

init_known_file() {
  if [ ! -f "$WIFI_KIT_KNOWN_FILE" ]; then
    : > "$WIFI_KIT_KNOWN_FILE" 2>/dev/null || true
    chmod 600 "$WIFI_KIT_KNOWN_FILE" 2>/dev/null || true
  fi
}

load_state() {
  mode="ap"
  last_successful_ssid=""
  known_networks=""
  last_error=""
  retry_count="0"

  while IFS='=' read -r key value; do
    case "$key" in
      mode) mode="$value" ;;
      last_successful_ssid) last_successful_ssid="$value" ;;
      known_networks) known_networks="$value" ;;
      last_error) last_error="$value" ;;
      retry_count) retry_count="$value" ;;
      *) ;;
    esac
  done < "$WIFI_KIT_STATE_FILE"
}

save_state() {
  cat > "$WIFI_KIT_STATE_FILE" <<EOF
mode=$mode
last_successful_ssid=$last_successful_ssid
known_networks=$known_networks
last_error=$last_error
retry_count=$retry_count
EOF
}

is_known_ssid() {
  ssid="$1"
  if [ ! -f "$WIFI_KIT_KNOWN_FILE" ]; then
    return 1
  fi
  grep -Fq "$ssid|" "$WIFI_KIT_KNOWN_FILE"
}

timestamp_utc() {
  date -u +'%Y-%m-%dT%H:%M:%SZ'
}

list_known_networks() {
  if [ ! -f "$WIFI_KIT_KNOWN_FILE" ] || [ ! -s "$WIFI_KIT_KNOWN_FILE" ]; then
    ui "  - none (simulated)"
    return 0
  fi

  ui "  - known networks (safe metadata only)"
  while IFS='|' read -r ssid added last seen result; do
    [ -z "${ssid-}" ] && continue
    ui "    * $ssid | added=$added | last=$last | result=$result"
  done < "$WIFI_KIT_KNOWN_FILE"
}

ensure_runtime() {
  init_state_root
  init_state_file
  init_known_file
  load_state
}

cmd_status() {
  ensure_runtime
  ui_header "status"
  ui "mode=$mode"
  ui "last_successful_ssid=${last_successful_ssid:-<none>}"
  ui "last_error=${last_error:-<none>}"
  ui "retry_count=$retry_count"
  list_known_networks
}

cmd_scan() {
  ensure_runtime
  ui_header "scan (simulated)"
  ui "source: local fake scan table (no radio access, no wifi hardware calls)"
  ui "candidate networks:"
  ui "  - CafeLab (strength: good, open: no)"
  ui "  - HomeHub (strength: medium, open: no)"
  ui "  - GuestNet (strength: weak, open: yes)"
}

cmd_connect() {
  ensure_runtime
  ssid="$1"
  psk="$2"
  if [ -z "$ssid" ]; then
    ui "connect requires an SSID: connect <SSID>"
    exit 1
  fi
  mode=client
  if [ -n "$psk" ]; then
    ui "connect: credentials received for '$ssid' -> psk [REDACTED]"
  else
    ui "connect: no psk argument; continuing simulation only"
  fi

  if is_known_ssid "$ssid"; then
    last_error=""
    last_successful_ssid="$ssid"
    retry_count=0
    ui "connect result: success (simulated from known-network cache)"
  elif [ "$ssid" = "GuestNet" ]; then
    last_error="simulated association failed (simulated captive/unstable AP)"
    retry_count=$((retry_count + 1))
    mode=ap
    ui "connect result: failed (simulated)"
  else
    # deterministic but realistic V0 behavior: first attempt may still succeed
    if [ "$((retry_count % 2))" -eq 0 ]; then
      last_error=""
      last_successful_ssid="$ssid"
      retry_count=0
      ui "connect result: success (simulated new profile created)"
    else
      last_error="simulated auth timeout (no RF events observed)"
      retry_count=$((retry_count + 1))
      mode=ap
      ui "connect result: failed (simulated)"
    fi
  fi

  save_state
}

cmd_save_known_network() {
  ensure_runtime
  ssid="$1"
  if [ -z "$ssid" ]; then
    ui "save-known-network requires an SSID"
    exit 1
  fi

  if is_known_ssid "$ssid"; then
    ui "known network already present (no secret stored)"
    return 0
  fi

  now="$(timestamp_utc)"
  printf '%s|%s|%s|new\n' "$ssid" "$now" "$now" >> "$WIFI_KIT_KNOWN_FILE"
  chmod 600 "$WIFI_KIT_KNOWN_FILE" 2>/dev/null || true
  known_networks="$(printf '%s;known' "$ssid")"
  save_state
  ui "saved known network metadata only for '$ssid' (no psk)"
}

cmd_reconnect_plan() {
  ensure_runtime
  ui_header "reconnect-plan (simulated)"
  ui "input: mode=$mode, retry_count=$retry_count, last_error=${last_error:-<none>}"

  if [ "$mode" != "client" ] && [ "$mode" != "recovery" ]; then
    ui "plan: device currently in AP mode, prefer onboarding or manual trigger"
    return 0
  fi

  if [ "$retry_count" -ge 3 ]; then
    ui "plan: threshold reached -> recovery window"
    ui "  - schedule recovery mode"
    ui "  - keep AP/bootstrap for rescue"
    ui "  - rotate candidates from known networks"
    return 0
  fi

  if [ ! -f "$WIFI_KIT_KNOWN_FILE" ] || [ ! -s "$WIFI_KIT_KNOWN_FILE" ]; then
    ui "plan: no known networks => cannot auto-retry"
    return 0
  fi

  ui "plan: try known networks in this order (simulated)"
  while IFS='|' read -r ssid added last result; do
    [ -z "$ssid" ] && continue
    ui "  - $ssid (last=$last, result=$result)"
  done < "$WIFI_KIT_KNOWN_FILE"
  ui "plan: incrementally retry with backoff (simulation)"
}

cmd_recovery_plan() {
  ensure_runtime
  ui_header "recovery-plan (simulated)"
  ui "current mode: $mode"
  ui "action:"
  ui "  1) keep known networks metadata unchanged"
  ui "  2) switch to AP/bootstrap mode for manual rescue"
  ui "  3) avoid destructive operations on network config"
  ui "  4) wait for explicit re-onboarding input"
  ui "  5) record recovery attempt in state via reconnect-plan"
}

usage() {
  cat <<'EOF'
Usage:
  sh prototype/wifi-kit.sh status
  sh prototype/wifi-kit.sh scan
  sh prototype/wifi-kit.sh connect <SSID> [--psk <PSK>]
  sh prototype/wifi-kit.sh save-known-network <SSID>
  sh prototype/wifi-kit.sh reconnect-plan
  sh prototype/wifi-kit.sh recovery-plan
  sh prototype/wifi-kit.sh backend-detect
  sh prototype/wifi-kit.sh status-real
  sh prototype/wifi-kit.sh scan-real [IFACE]
  sh prototype/wifi-kit.sh stability-status
  sh prototype/wifi-kit.sh stability-plan
  sh prototype/wifi-kit.sh stability-apply-current-boot [IFACE]

This is a SAFE prototype. No hostapd/dnsmasq/NetworkManager actions are executed.
EOF
}

main() {
  command="$1"
  case "$command" in
    status) cmd_status ;;
    scan) cmd_scan ;;
    connect)
      shift
      ssid="${1:-}"
      shift || true
      psk=""
      if [ "${1-}" = "--psk" ]; then
        psk="${2-}"
      fi
      cmd_connect "$ssid" "$psk"
      ;;
    save-known-network) shift; cmd_save_known_network "${1-}" ;;
    reconnect-plan) cmd_reconnect_plan ;;
    recovery-plan) cmd_recovery_plan ;;
    backend-detect) cmd_backend_detect ;;
    status-real) cmd_status_real ;;
    scan-real) shift; cmd_scan_real "${1:-}" ;;
    stability-status) cmd_stability_status ;;
    stability-plan) cmd_stability_plan ;;
    stability-apply-current-boot) shift; cmd_stability_apply_current_boot "${1:-}" ;;
    *) usage ;;
  esac
}

if [ "${1-}" = "--help" ] || [ -z "${1-}" ]; then
  usage
  exit 0
fi

main "$@"
