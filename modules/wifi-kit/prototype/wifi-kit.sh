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

SCAN_REFRESH_ATTEMPTED="false"
SCAN_REFRESH_STATUS="not-requested"
SCAN_REFRESH_BACKEND=""
SCAN_REFRESH_ERROR=""

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

recommended_backend() {
  os_id="$(os_field ID || true)"
  os_name="$(os_field NAME || true)"
  os_like="$(os_field ID_LIKE || true)"

  backend="generic-readonly"
  case "$os_id $os_name $os_like" in
    *raspbian*|*raspberry*|*debian*)
      if has_tool wpa_supplicant || has_tool wpa_cli; then
        backend="rpios-wpa"
      fi
      ;;
  esac

  printf '%s\n' "$backend"
}

current_ip_for_iface() {
  iface="$1"
  ip_bin="$(find_tool ip 2>/dev/null || true)"
  if [ -n "$ip_bin" ]; then
    "$ip_bin" -o addr show dev "$iface" 2>/dev/null | awk 'NR == 1 { print $4 }'
  fi
}

default_route_line() {
  ip_bin="$(find_tool ip 2>/dev/null || true)"
  if [ -n "$ip_bin" ]; then
    "$ip_bin" route show default 2>/dev/null | sed -n '1p'
  fi
}

power_save_for_iface() {
  iface="$1"
  iw_bin="$(find_tool iw 2>/dev/null || true)"
  if [ -n "$iw_bin" ]; then
    "$iw_bin" dev "$iface" get power_save 2>/dev/null
  fi
}

current_ssid_for_iface() {
  iface="$1"
  iw_bin="$(find_tool iw 2>/dev/null || true)"
  if [ -n "$iw_bin" ]; then
    "$iw_bin" dev "$iface" link 2>/dev/null | awk -F'SSID: ' '/SSID:/ { print $2; exit }'
  fi
}

ssh_client_address() {
  printf '%s\n' "${SSH_CLIENT:-}" | awk '{ print $1 }'
}

ssh_route_interface() {
  ssh_client="$(ssh_client_address)"
  ip_bin="$(find_tool ip 2>/dev/null || true)"
  if [ -n "$ssh_client" ] && [ -n "$ip_bin" ]; then
    "$ip_bin" route get "$ssh_client" 2>/dev/null | awk '
      {
        for (i = 1; i <= NF; i++) {
          if ($i == "dev" && (i + 1) <= NF) {
            print $(i + 1)
            exit
          }
        }
      }
    '
  fi
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

  ui "recommended_backend=$(recommended_backend)"
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

runtime_tool_state() {
  tool_name="$1"
  if has_tool "$tool_name"; then
    echo "present"
  else
    echo "missing"
  fi
}

cmd_runtime_state_show() {
  ui_header "runtime-state show"
  ui "safety: read-only snapshot preview; no network writes, no secrets"

  ui "timestamp=$(timestamp_utc)"
  ui "hostname=$(hostname 2>/dev/null || echo unknown)"
  ui "os_id=$(os_field ID || echo unknown)"
  ui "os_like=$(os_field ID_LIKE || echo unknown)"
  ui "backend_hint=$(recommended_backend)"

  ssh_client="unknown"
  if [ -n "${SSH_CONNECTION:-}" ]; then
    ssh_client="$(printf '%s\n' "$SSH_CONNECTION" | awk '{print $1}')"
  fi
  ui "ssh_client=$ssh_client"

  ip_bin="$(find_tool ip || true)"
  if [ -n "$ip_bin" ] && [ "$ssh_client" != "unknown" ]; then
    ssh_route="$($ip_bin route get "$ssh_client" 2>/dev/null | sed -n '1p' || true)"
  else
    ssh_route=""
  fi
  ui "ssh_route=${ssh_route:-unknown}"

  ui "default_routes:"
  if [ -n "$ip_bin" ]; then
    routes="$($ip_bin route show default 2>/dev/null || true)"
    if [ -n "$routes" ]; then
      printf '%s\n' "$routes" | sed 's/^/  - /'
    else
      ui "  - none"
    fi
  else
    ui "  - ip command missing"
  fi

  ui "wifi_interfaces:"
  interfaces="$(detect_wifi_interfaces || true)"
  if [ -z "$interfaces" ]; then
    ui "  - none"
  else
    for iface in $interfaces; do
      operstate="unknown"
      carrier="unknown"
      [ -r "/sys/class/net/$iface/operstate" ] && operstate="$(sed -n '1p' "/sys/class/net/$iface/operstate" 2>/dev/null || echo unknown)"
      [ -r "/sys/class/net/$iface/carrier" ] && carrier="$(sed -n '1p' "/sys/class/net/$iface/carrier" 2>/dev/null || echo unknown)"

      ui "  - iface=$iface"
      ui "    operstate=$operstate"
      ui "    carrier=$carrier"

      if [ -n "$ip_bin" ]; then
        addrs="$($ip_bin -o addr show dev "$iface" 2>/dev/null | awk '{print $3 ":" $4}' || true)"
        if [ -n "$addrs" ]; then
          printf '%s\n' "$addrs" | sed 's/^/    addr=/'
        else
          ui "    addr=none"
        fi
      else
        ui "    addr=unknown"
      fi

      iw_bin="$(find_tool iw || true)"
      if [ -n "$iw_bin" ]; then
        power_save="$($iw_bin dev "$iface" get power_save 2>/dev/null | awk '{print $2}' || true)"
        link_raw="$($iw_bin dev "$iface" link 2>/dev/null || true)"
        case "$link_raw" in
          *"Connected to "*)
            link_state="connected"
            ;;
          *"Not connected."*)
            link_state="not-connected"
            ;;
          *)
            link_state="unknown"
            ;;
        esac
        ui "    power_save=${power_save:-unknown}"
        ui "    link=$link_state"
      else
        ui "    power_save=unknown"
        ui "    link=unknown"
      fi
    done
  fi

  ui "runtime_fingerprint:"
  for tool_name in ip iw wpa_cli wpa_supplicant nmcli systemctl; do
    ui "  $tool_name=$(runtime_tool_state "$tool_name")"
  done
}

emit_scan_json_unavailable() {
  reason="$1"
  iface="${2:-unknown}"
  backend="${3:-wpa_cli}"
  timestamp="$(timestamp_utc)"

  awk -v iface="${iface:-unknown}" \
      -v timestamp="$timestamp" \
      -v reason="$reason" \
      -v backend="$backend" \
      -v refresh_attempted="$SCAN_REFRESH_ATTEMPTED" \
      -v refresh_status="$SCAN_REFRESH_STATUS" \
      -v refresh_backend="$SCAN_REFRESH_BACKEND" \
      -v refresh_error="$SCAN_REFRESH_ERROR" '
    function json_escape(value, escaped) {
      escaped=value
      gsub(/\\/, "\\\\", escaped)
      gsub(/"/, "\\\"", escaped)
      return escaped
    }
    BEGIN {
      printf "{\n"
      printf "  \"backend\":\"%s\",\n", json_escape(backend)
      printf "  \"interface\":\"%s\",\n", json_escape(iface)
      printf "  \"timestamp\":\"%s\",\n", json_escape(timestamp)
      printf "  \"status\":\"unavailable\",\n"
      printf "  \"reason\":\"%s\",\n", json_escape(reason)
      printf "  \"refresh_attempted\":%s,\n", refresh_attempted
      printf "  \"refresh_status\":\"%s\",\n", json_escape(refresh_status)
      printf "  \"refresh_backend\":\"%s\",\n", json_escape(refresh_backend)
      printf "  \"refresh_error\":\"%s\",\n", json_escape(refresh_error)
      printf "  \"networks\":[]\n"
      printf "}\n"
    }
  '
}

emit_scan_from_wpa_cli() {
  scan_file="$1"
  iface="$2"
  output_json="$3"

  if [ "$output_json" -eq 1 ]; then
    timestamp="$(timestamp_utc)"
    awk -v iface="$iface" \
        -v timestamp="$timestamp" \
        -v refresh_attempted="$SCAN_REFRESH_ATTEMPTED" \
        -v refresh_status="$SCAN_REFRESH_STATUS" \
        -v refresh_backend="$SCAN_REFRESH_BACKEND" \
        -v refresh_error="$SCAN_REFRESH_ERROR" '
      function json_escape(value, escaped) {
        escaped=value
        gsub(/\\/, "\\\\", escaped)
        gsub(/"/, "\\\"", escaped)
        return escaped
      }
      function channel_from_freq(freq) {
        if (freq == 2484) return 14
        if (freq >= 2412 && freq <= 2472) return int((freq - 2407) / 5)
        if (freq >= 5000 && freq <= 5900) return int((freq - 5000) / 5)
        return ""
      }
      function security_from_flags(flags) {
        if (flags ~ /SAE/ || flags ~ /WPA3/) return "WPA3"
        if (flags ~ /WPA2/ && flags ~ /WPA-/) return "WPA/WPA2"
        if (flags ~ /WPA2/ || flags ~ /RSN/) return "WPA2"
        if (flags ~ /WPA-/ || flags ~ /WPA\]/) return "WPA"
        if (flags ~ /WEP/) return "WEP"
        return "open"
      }
      BEGIN {
        printf "{\n"
        printf "  \"backend\":\"wpa_cli\",\n"
        printf "  \"interface\":\"%s\",\n", json_escape(iface)
        printf "  \"timestamp\":\"%s\",\n", json_escape(timestamp)
        printf "  \"status\":\"ok\",\n"
        printf "  \"refresh_attempted\":%s,\n", refresh_attempted
        printf "  \"refresh_status\":\"%s\",\n", json_escape(refresh_status)
        printf "  \"refresh_backend\":\"%s\",\n", json_escape(refresh_backend)
        printf "  \"refresh_error\":\"%s\",\n", json_escape(refresh_error)
        printf "  \"networks\":[\n"
      }
      NR == 1 { next }
      NF >= 4 {
        bssid=$1
        freq=$2
        signal=$3
        flags=$4
        ssid=$0
        sub(/^[^\t]*\t[^\t]*\t[^\t]*\t[^\t]*\t?/, "", ssid)
        if (count > 0) printf ",\n"
        hidden = (ssid == "") ? "true" : "false"
        channel = channel_from_freq(freq)
        printf "    {\"ssid\":\"%s\",\"ssid_hidden\":%s,\"signal\":\"%s dBm\",\"freq\":\"%s\",\"channel\":\"%s\",\"security\":\"%s\"}", json_escape(ssid), hidden, json_escape(signal), json_escape(freq), json_escape(channel), json_escape(security_from_flags(flags))
        count++
      }
      END {
        printf "\n  ]\n"
        printf "}\n"
      }
    ' "$scan_file"
    return 0
  fi

  ui "backend=wpa_cli"
  ui "interface=$iface"
  ui "timestamp=$(timestamp_utc)"
  awk '
    function channel_from_freq(freq) {
      if (freq == 2484) return 14
      if (freq >= 2412 && freq <= 2472) return int((freq - 2407) / 5)
      if (freq >= 5000 && freq <= 5900) return int((freq - 5000) / 5)
      return "unknown"
    }
    function security_from_flags(flags) {
      if (flags ~ /SAE/ || flags ~ /WPA3/) return "WPA3"
      if (flags ~ /WPA2/ && flags ~ /WPA-/) return "WPA/WPA2"
      if (flags ~ /WPA2/ || flags ~ /RSN/) return "WPA2"
      if (flags ~ /WPA-/ || flags ~ /WPA\]/) return "WPA"
      if (flags ~ /WEP/) return "WEP"
      return "open"
    }
    NR == 1 { next }
    NF >= 4 {
      freq=$2
      signal=$3
      flags=$4
      ssid=$0
      sub(/^[^\t]*\t[^\t]*\t[^\t]*\t[^\t]*\t?/, "", ssid)
      display_ssid = (ssid == "") ? "<hidden>" : ssid
      printf "  - ssid=%s signal=%s dBm channel=%s security=%s\n", display_ssid, signal, channel_from_freq(freq), security_from_flags(flags)
      count++
    }
    END {
      if (count == 0) print "  - no scan results reported by wpa_cli"
    }
  ' "$scan_file"
}

wpa_cli_scan_results_to_file() {
  iface="$1"
  output_file="$2"
  wpa_cli_bin="$(find_tool wpa_cli 2>/dev/null || true)"
  [ -n "$wpa_cli_bin" ] || return 2
  "$wpa_cli_bin" -i "$iface" scan_results > "$output_file" 2>/dev/null
}

wpa_cli_scan_results_count() {
  scan_file="$1"
  awk 'NR > 1 && NF >= 4 { count++ } END { print count + 0 }' "$scan_file" 2>/dev/null || echo 0
}

try_scan_refresh_wpa_cli_json() {
  iface="$1"
  before_file="$2"
  after_file="$3"
  err_file="$4"

  SCAN_REFRESH_ATTEMPTED="true"
  SCAN_REFRESH_BACKEND="wpa_cli"
  SCAN_REFRESH_ERROR=""

  wpa_cli_bin="$(find_tool wpa_cli 2>/dev/null || true)"
  if [ -z "$wpa_cli_bin" ]; then
    SCAN_REFRESH_STATUS="wpa-cli-missing"
    SCAN_REFRESH_ERROR="wpa_cli not found"
    return 2
  fi

  wpa_cli_scan_results_to_file "$iface" "$before_file" || true

  timeout_bin="$(find_tool timeout 2>/dev/null || true)"
  if [ -z "$timeout_bin" ]; then
    SCAN_REFRESH_STATUS="timeout-tool-missing"
    SCAN_REFRESH_ERROR="timeout command not found; refusing unbounded wpa_cli scan"
    return 3
  fi

  if "$timeout_bin" 3 "$wpa_cli_bin" -i "$iface" scan > "$err_file" 2>&1; then
    sleep 1
    if wpa_cli_scan_results_to_file "$iface" "$after_file"; then
      SCAN_REFRESH_STATUS="ok"
      return 0
    fi
    SCAN_REFRESH_STATUS="scan-results-after-refresh-failed"
    SCAN_REFRESH_ERROR="wpa_cli scan succeeded but scan_results failed"
    return 1
  fi

  SCAN_REFRESH_STATUS="scan-command-failed"
  SCAN_REFRESH_ERROR="$(sed -n '1p' "$err_file" 2>/dev/null || true)"
  [ -n "$SCAN_REFRESH_ERROR" ] || SCAN_REFRESH_ERROR="wpa_cli scan failed or timed out"
  return 1
}

try_scan_real_wpa_cli() {
  iface="$1"
  output_json="$2"
  wpa_cli_bin="$(find_tool wpa_cli 2>/dev/null || true)"
  [ -n "$wpa_cli_bin" ] || return 2

  tmp="${TMPDIR:-/tmp}/wifi-kit-wpa-cli-scan.$$"
  err="${TMPDIR:-/tmp}/wifi-kit-wpa-cli-scan-err.$$"

  if "$wpa_cli_bin" -i "$iface" scan_results > "$tmp" 2> "$err"; then
    emit_scan_from_wpa_cli "$tmp" "$iface" "$output_json"
    rm -f "$tmp" "$err"
    return 0
  fi

  rm -f "$tmp" "$err"
  return 1
}

try_scan_real_iw() {
  iface="$1"
  output_json="$2"

  iw_bin="$(find_tool iw 2>/dev/null || true)"
  [ -n "$iw_bin" ] || return 2

  tmp="${TMPDIR:-/tmp}/wifi-kit-iw-scan.$$"
  err="${TMPDIR:-/tmp}/wifi-kit-iw-scan-err.$$"

  if "$iw_bin" dev "$iface" scan > "$tmp" 2> "$err"; then
    if [ "$output_json" -eq 1 ]; then
      timestamp="$(timestamp_utc)"
      awk -v iface="$iface" \
          -v timestamp="$timestamp" \
          -v refresh_attempted="$SCAN_REFRESH_ATTEMPTED" \
          -v refresh_status="$SCAN_REFRESH_STATUS" \
          -v refresh_backend="$SCAN_REFRESH_BACKEND" \
          -v refresh_error="$SCAN_REFRESH_ERROR" '
        function json_escape(value, escaped) {
          escaped=value
          gsub(/\\/, "\\\\", escaped)
          gsub(/"/, "\\\"", escaped)
          return escaped
        }
        function channel_from_freq(freq) {
          if (freq == 2484) return 14
          if (freq >= 2412 && freq <= 2472) return int((freq - 2407) / 5)
          if (freq >= 5000 && freq <= 5900) return int((freq - 5000) / 5)
          return ""
        }
        function security_value() {
          if (sae) return "WPA3"
          if (rsn && wpa) return "WPA/WPA2"
          if (rsn) return "WPA2"
          if (wpa) return "WPA"
          if (privacy) return "protected"
          return "open"
        }
        function emit_network() {
          if (!seen_bss) return
          if (count > 0) printf ",\n"
          hidden = (ssid == "") ? "true" : "false"
          channel = channel_from_freq(freq)
          printf "    {\"ssid\":\"%s\",\"ssid_hidden\":%s,\"signal\":\"%s\",\"freq\":\"%s\",\"channel\":\"%s\",\"security\":\"%s\"}", json_escape(ssid), hidden, json_escape(signal), json_escape(freq), json_escape(channel), json_escape(security_value())
          count++
        }
        BEGIN {
          printf "{\n"
          printf "  \"backend\":\"iw\",\n"
          printf "  \"interface\":\"%s\",\n", json_escape(iface)
          printf "  \"timestamp\":\"%s\",\n", json_escape(timestamp)
          printf "  \"status\":\"ok\",\n"
          printf "  \"refresh_attempted\":%s,\n", refresh_attempted
          printf "  \"refresh_status\":\"%s\",\n", json_escape(refresh_status)
          printf "  \"refresh_backend\":\"%s\",\n", json_escape(refresh_backend)
          printf "  \"refresh_error\":\"%s\",\n", json_escape(refresh_error)
          printf "  \"networks\":[\n"
        }
        /^BSS / {
          emit_network()
          seen_bss=1
          ssid=""
          signal=""
          freq=""
          privacy=0
          rsn=0
          wpa=0
          sae=0
        }
        /^[[:space:]]*freq:/ { freq=$2 }
        /^[[:space:]]*signal:/ { signal=$2 " " $3 }
        /^[[:space:]]*SSID:/ {
          ssid=$0
          sub(/^[[:space:]]*SSID:[[:space:]]*/, "", ssid)
        }
        /^[[:space:]]*capability:/ {
          if ($0 ~ /Privacy/) privacy=1
        }
        /^[[:space:]]*RSN:/ { rsn=1 }
        /^[[:space:]]*WPA:/ { wpa=1 }
        /SAE/ { sae=1 }
        END {
          emit_network()
          printf "\n  ]\n"
          printf "}\n"
        }
      ' "$tmp"
    else
      ui "backend=iw"
      ui "interface=$iface"
      ui "timestamp=$(timestamp_utc)"
      awk '
        function channel_from_freq(freq) {
          if (freq == 2484) return 14
          if (freq >= 2412 && freq <= 2472) return int((freq - 2407) / 5)
          if (freq >= 5000 && freq <= 5900) return int((freq - 5000) / 5)
          return "unknown"
        }
        function security_value() {
          if (sae) return "WPA3"
          if (rsn && wpa) return "WPA/WPA2"
          if (rsn) return "WPA2"
          if (wpa) return "WPA"
          if (privacy) return "protected"
          return "open"
        }
        function emit_network() {
          if (!seen_bss) return
          display_ssid = (ssid == "") ? "<hidden>" : ssid
          printf "  - ssid=%s signal=%s channel=%s security=%s\n", display_ssid, signal, channel_from_freq(freq), security_value()
        }
        /^BSS / {
          emit_network()
          seen_bss=1
          ssid=""
          signal=""
          freq=""
          privacy=0
          rsn=0
          wpa=0
          sae=0
        }
        /^[[:space:]]*freq:/ { freq=$2 }
        /^[[:space:]]*signal:/ { signal=$2 " " $3 }
        /^[[:space:]]*SSID:/ {
          ssid=$0
          sub(/^[[:space:]]*SSID:[[:space:]]*/, "", ssid)
        }
        /^[[:space:]]*capability:/ {
          if ($0 ~ /Privacy/) privacy=1
        }
        /^[[:space:]]*RSN:/ { rsn=1 }
        /^[[:space:]]*WPA:/ { wpa=1 }
        /SAE/ { sae=1 }
        END {
          emit_network()
        }
      ' "$tmp"
    fi
    rm -f "$tmp" "$err"
    return 0
  fi

  if [ "$output_json" -eq 1 ]; then
    rm -f "$tmp" "$err"
    return 1
  fi

  ui "scan-real unavailable on $iface: iw scan failed"
  ui "hint: this may require root/CAP_NET_ADMIN or an idle Wi-Fi interface"
  if [ -s "$err" ]; then
    sed -n '1,3p' "$err" | sed 's/^/  detail: /'
  fi
  rm -f "$tmp" "$err"
  return 1
}

cmd_scan_real() {
  SCAN_REFRESH_ATTEMPTED="false"
  SCAN_REFRESH_STATUS="not-requested"
  SCAN_REFRESH_BACKEND=""
  SCAN_REFRESH_ERROR=""

  output_json=0
  refresh=0
  iface=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --json)
        output_json=1
        ;;
      --refresh)
        refresh=1
        ;;
      *)
        if [ -z "$iface" ]; then
          iface="$1"
        else
          ui "scan-real unknown argument: $1"
          return 1
        fi
        ;;
    esac
    shift
  done

  if [ "$output_json" -eq 0 ]; then
    ui_header "scan-real (read-only)"
    ui "safety: read-only, no connection, no network writes, no secrets"
    ui "backend_order=wpa_cli,iw"
    if [ "$refresh" -eq 1 ]; then
      ui "refresh=opt-in"
      ui "refresh_safety=bounded wpa_cli scan only; no config writes"
    fi
  fi

  if [ -z "$iface" ]; then
    iface="$(detect_wifi_interfaces | sed -n '1p')"
  fi

  if [ -z "$iface" ]; then
    if [ "$output_json" -eq 1 ]; then
      emit_scan_json_unavailable "no-wifi-interface" "unknown" "wpa_cli"
      return 0
    fi
    ui "scan-real unavailable: no Wi-Fi interface detected"
    return 0
  fi

  if [ "$refresh" -eq 1 ]; then
    if [ "$output_json" -ne 1 ]; then
      ui "scan-real --refresh currently requires --json"
      ui "reason: refresh metadata is part of the stable JSON contract"
      return 2
    fi

    before="${TMPDIR:-/tmp}/wifi-kit-wpa-cli-scan-before.$$"
    after="${TMPDIR:-/tmp}/wifi-kit-wpa-cli-scan-after.$$"
    err="${TMPDIR:-/tmp}/wifi-kit-wpa-cli-refresh-err.$$"

    if try_scan_refresh_wpa_cli_json "$iface" "$before" "$after" "$err"; then
      emit_scan_from_wpa_cli "$after" "$iface" "$output_json"
      rm -f "$before" "$after" "$err"
      return 0
    fi

    if [ -s "$before" ] && [ "$(wpa_cli_scan_results_count "$before")" -gt 0 ]; then
      case "$SCAN_REFRESH_STATUS" in
        ok) ;;
        *) SCAN_REFRESH_STATUS="failed-used-existing-results" ;;
      esac
      emit_scan_from_wpa_cli "$before" "$iface" "$output_json"
      rm -f "$before" "$after" "$err"
      return 0
    fi

    reason="refresh-failed-no-results"
    case "$SCAN_REFRESH_STATUS" in
      timeout-tool-missing) reason="refresh-timeout-tool-missing" ;;
      wpa-cli-missing) reason="wpa-cli-missing" ;;
    esac
    emit_scan_json_unavailable "$reason" "$iface" "wpa_cli"
    rm -f "$before" "$after" "$err"
    return 0
  fi

  if try_scan_real_wpa_cli "$iface" "$output_json"; then
    return 0
  fi

  if try_scan_real_iw "$iface" "$output_json"; then
    return 0
  fi

  if [ "$output_json" -eq 1 ]; then
    if ! has_tool wpa_cli && ! has_tool iw; then
      emit_scan_json_unavailable "scan-tools-missing" "$iface" "wpa_cli"
    else
      emit_scan_json_unavailable "scan-readonly-failed" "$iface" "wpa_cli"
    fi
    return 0
  fi

  ui "scan-real unavailable on $iface: wpa_cli scan_results and iw scan both failed"
  ui "hint: this command did not trigger a new scan and did not modify Wi-Fi state"
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

cmd_connect_safe_simulate() {
  failure="${1:-}"

  ui_header "connect-safe-simulate"
  ui "safety: simulation only; no Wi-Fi connection, no network writes, no secrets"
  ui "note: no persistent state file is created"

  ui "state=readonly"
  ui "state=snapshot-created"
  ui "state=connecting"
  ui "state=waiting-ip"

  case "$failure" in
    "")
      ui "state=validating"
      ui "state=committed"
      ui "result: simulated success"
      ;;
    --fail-ip)
      ui "event: simulated DHCP/IP timeout"
      ui "state=rollback-started"
      ui "state=rollback-complete"
      ui "result: simulated rollback after IP failure"
      ;;
    --fail-validation)
      ui "state=validating"
      ui "event: simulated validation failure"
      ui "state=rollback-started"
      ui "state=recovery-required"
      ui "result: simulated rollback incomplete, recovery required"
      ;;
    *)
      ui "unknown option: $failure"
      ui "supported options: --fail-ip, --fail-validation"
      return 1
      ;;
  esac
}

cmd_snapshot_simulate() {
  ui_header "snapshot-simulate"
  ui "safety: simulation only; no system reads required, no network writes, no secrets"
  ui "note: no persistent snapshot file is created"
  ui "mode=readonly"
  ui "interface=wlan0"
  ui "ssid=current-network"
  ui "ip=192.168.x.x"
  ui "route=default via 192.168.x.1"
  ui "power_save=off"
  ui "backend=rpios-wpa"
  ui "timestamp=demo-2026-05-14T00:00:00Z"
}

cmd_restore_simulate() {
  failure="${1:-}"

  ui_header "restore-simulate"
  ui "safety: simulation only; no Wi-Fi connection, no network writes, no secrets"
  ui "note: no persistent snapshot file is read or written"

  case "$failure" in
    "")
      ui "restoring previous snapshot"
      ui "reconnect previous ssid"
      ui "state=waiting-ip"
      ui "state=validation"
      ui "state=rollback-complete"
      ui "result: simulated restore success"
      ;;
    --fail)
      ui "restoring previous snapshot"
      ui "state=rollback-started"
      ui "event: simulated restore failure"
      ui "state=recovery-required"
      ui "result: simulated restore failed, recovery required"
      ;;
    *)
      ui "unknown option: $failure"
      ui "supported option: --fail"
      return 1
      ;;
  esac
}

cmd_ssh_safety_simulate() {
  scenario="${1:-}"

  ui_header "ssh-safety-simulate"
  ui "safety: simulation only; no SSH session inspection, no route changes, no network writes"

  case "$scenario" in
    "")
      ui "ssh_client=unknown"
      ui "ssh_route_interface=unknown"
      ui "risk=unknown"
      ui "decision=manual-review-required"
      ;;
    --safe)
      ui "ssh_client=100.x.x.x"
      ui "ssh_route_interface=tailscale0"
      ui "risk=low"
      ui "decision=connect-safe-allowed"
      ;;
    --danger)
      ui "ssh_client=192.168.x.x"
      ui "ssh_route_interface=wlan0"
      ui "risk=high"
      ui "reason=SSH appears to use wlan0"
      ui "decision=refuse-by-default"
      ;;
    *)
      ui "unknown option: $scenario"
      ui "supported options: --safe, --danger"
      return 1
      ;;
  esac
}

cmd_connect_safe_timeout_simulate() {
  scenario="${1:-}"

  ui_header "connect-safe-timeout-simulate"
  ui "safety: simulation only; no Wi-Fi connection, no network writes, no secrets"

  case "$scenario" in
    "")
      ui "state=connecting"
      ui "timeout=waiting-ip"
      ui "action=rollback"
      ui "state=rollback-started"
      ui "state=rollback-complete"
      ui "result=simulated timeout rollback"
      ;;
    --validation-timeout)
      ui "state=validating"
      ui "timeout=validation"
      ui "action=rollback"
      ui "state=rollback-started"
      ui "state=rollback-complete"
      ui "result=simulated validation timeout rollback"
      ;;
    --rollback-timeout)
      ui "state=rollback-started"
      ui "timeout=rollback"
      ui "action=stop"
      ui "state=recovery-required"
      ui "result=simulated rollback timeout recovery"
      ;;
    *)
      ui "unknown option: $scenario"
      ui "supported options: --validation-timeout, --rollback-timeout"
      return 1
      ;;
  esac
}

cmd_connect_safe() {
  mode="${1:-}"

  case "$mode" in
    --simulate)
      ;;
    "")
      ui "connect-safe requires --simulate in this prototype"
      ui "real connect-safe is intentionally not implemented"
      return 1
      ;;
    *)
      ui "unknown connect-safe option: $mode"
      ui "supported option: --simulate"
      return 1
      ;;
  esac

  ui_header "connect-safe --simulate"
  ui "safety: simulation only; no Wi-Fi connection, no network writes, no secrets"
  ui "real_apply_allowed=false"
  ui "requires_strong_confirmation=true"

  ui ""
  ui "phase=1 preflight"
  ui "  check=wifi-stability-installed"
  ui "  check=tools-present"
  ui "  check=no-active-unsafe-ssh-path"
  ui "  abort_if=ssh-over-target-wifi-interface"
  ui "  abort_if=missing-rollback-path"

  ui "phase=2 detect-interface"
  ui "  interface=wlan0 (example)"
  ui "  backend=rpios-wpa (example)"
  ui "  note=real implementation must detect, not assume"

  ui "phase=3 snapshot-current-state"
  ui "  snapshot=current-ssid,current-ip,default-route,power-save,backend,wpa-state,timestamp"
  ui "  secret_policy=no-psk-in-wifi-kit-state"
  ui "  rollback_point=snapshot-created"

  ui "phase=4 build-change-plan"
  ui "  plan=candidate-ssid-metadata-only"
  ui "  no_psk_prompt=true"
  ui "  no_wpa_supplicant_write=true"

  ui "phase=5 strong-confirmation"
  ui "  required=true"
  ui "  warning=headless-node-may-become-unreachable"
  ui "  abort_condition=operator-declines"

  ui "phase=6 future-controlled-attempt"
  ui "  state=connecting"
  ui "  timeout=waiting-ip"
  ui "  rollback_on=auth-failure,ip-timeout,interface-down,route-missing"
  ui "  simulated_only=true"

  ui "phase=7 validation"
  ui "  validate=ip-present"
  ui "  validate=default-route-present"
  ui "  validate=minimal-reachability"
  ui "  validate=ssh-session-still-safe"
  ui "  rollback_on=validation-failed"

  ui "phase=8 commit-or-rollback"
  ui "  commit_if=all-validation-passed"
  ui "  rollback_if=any-validation-failed"
  ui "  recovery_if=rollback-cannot-be-proven"

  ui "phase=9 state-journal"
  ui "  journal=preflight,snapshot,attempt,validation,commit-or-rollback"
  ui "  storage=future-runtime-state"
  ui "  secret_policy=no-secrets"

  ui ""
  ui "decision=simulation-only"
  ui "next_safe_step=review-plan-or-run-read-only-diagnostics"
}

cmd_state_snapshot() {
  mode="${1:-}"
  output_json=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --simulate)
        mode="--simulate"
        ;;
      --json)
        output_json=1
        ;;
      *)
        ui "unknown state-snapshot option: $1"
        ui "supported options: --simulate, --json"
        return 1
        ;;
    esac
    shift
  done

  if [ "$mode" != "--simulate" ]; then
    ui "state-snapshot requires --simulate in this prototype"
    return 1
  fi

  iface="$(first_wifi_interface || true)"
  backend="$(recommended_backend)"
  current_ip=""
  current_ssid_state="unknown"
  power_save=""
  if [ -n "$iface" ]; then
    current_ip="$(current_ip_for_iface "$iface" || true)"
    current_ssid_probe="$(current_ssid_for_iface "$iface" || true)"
    if [ -n "$current_ssid_probe" ]; then
      current_ssid_state="present"
    fi
    power_save="$(power_save_for_iface "$iface" || true)"
  fi
  default_route="$(default_route_line || true)"
  ssh_client="$(ssh_client_address)"
  ssh_iface="$(ssh_route_interface || true)"
  timestamp="$(timestamp_utc)"
  runtime_fingerprint="$(printf '%s|%s|%s|%s\n' "${backend:-unknown}" "${iface:-unknown}" "${ssh_iface:-unknown}" "${timestamp:-unknown}")"

  if [ "$output_json" -eq 1 ]; then
    awk -v backend="${backend:-unknown}" \
        -v iface="${iface:-unknown}" \
        -v current_ssid_state="${current_ssid_state:-unknown}" \
        -v current_ip="${current_ip:-unknown}" \
        -v default_route="${default_route:-unknown}" \
        -v power_save="${power_save:-unknown}" \
        -v ssh_client="${ssh_client:-unknown}" \
        -v ssh_iface="${ssh_iface:-unknown}" \
        -v timestamp="$timestamp" \
        -v runtime_fingerprint="$runtime_fingerprint" '
      function json_escape(value, escaped) {
        escaped=value
        gsub(/\\/, "\\\\", escaped)
        gsub(/"/, "\\\"", escaped)
        return escaped
      }
      BEGIN {
        printf "{\n"
        printf "  \"mode\":\"simulate\",\n"
        printf "  \"backend\":\"%s\",\n", json_escape(backend)
        printf "  \"interface\":\"%s\",\n", json_escape(iface)
        printf "  \"current_ssid_state\":\"%s\",\n", json_escape(current_ssid_state)
        printf "  \"current_ip\":\"%s\",\n", json_escape(current_ip)
        printf "  \"default_route\":\"%s\",\n", json_escape(default_route)
        printf "  \"power_save\":\"%s\",\n", json_escape(power_save)
        printf "  \"ssh_client\":\"%s\",\n", json_escape(ssh_client)
        printf "  \"ssh_route_interface\":\"%s\",\n", json_escape(ssh_iface)
        printf "  \"runtime_fingerprint\":\"%s\",\n", json_escape(runtime_fingerprint)
        printf "  \"timestamp\":\"%s\",\n", json_escape(timestamp)
        printf "  \"secret_policy\":\"no-secrets\",\n"
        printf "  \"persistence\":\"none\"\n"
        printf "}\n"
      }
    '
    return 0
  fi

  ui_header "state-snapshot --simulate"
  ui "safety: simulation only; no network writes, no secrets, no persistence"
  ui "mode=simulate"
  ui "backend=${backend:-unknown}"
  ui "interface=${iface:-unknown}"
  ui "current_ssid_state=${current_ssid_state:-unknown}"
  ui "current_ip=${current_ip:-unknown}"
  ui "default_route=${default_route:-unknown}"
  ui "power_save=${power_save:-unknown}"
  ui "ssh_client=${ssh_client:-unknown}"
  ui "ssh_route_interface=${ssh_iface:-unknown}"
  ui "runtime_fingerprint=$runtime_fingerprint"
  ui "timestamp=$timestamp"
  ui "secret_policy=no-secrets"
  ui "persistence=none"
}

cmd_safe_diagnose() {
  output_json=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --json)
        output_json=1
        ;;
      *)
        ui "unknown safe-diagnose option: $1"
        ui "supported option: --json"
        return 1
        ;;
    esac
    shift
  done

  iface="$(first_wifi_interface || true)"
  backend="$(recommended_backend)"
  timestamp="$(timestamp_utc)"
  default_route="$(default_route_line || true)"
  ssh_client="$(ssh_client_address)"
  ssh_iface="$(ssh_route_interface || true)"
  current_ip=""
  current_ssid_state="unknown"
  power_save=""

  if [ -n "$iface" ]; then
    current_ip="$(current_ip_for_iface "$iface" || true)"
    current_ssid_probe="$(current_ssid_for_iface "$iface" || true)"
    if [ -n "$current_ssid_probe" ]; then
      current_ssid_state="present"
    fi
    power_save="$(power_save_for_iface "$iface" || true)"
  fi

  iw_bin="$(find_tool iw 2>/dev/null || true)"
  scan_status="available"
  if [ -z "$iw_bin" ]; then
    scan_status="iw-missing"
  elif [ -z "$iface" ]; then
    scan_status="no-wifi-interface"
  fi

  if [ "$output_json" -eq 1 ]; then
    awk -v timestamp="$timestamp" \
        -v backend="${backend:-unknown}" \
        -v iface="${iface:-unknown}" \
        -v current_ip="${current_ip:-unknown}" \
        -v default_route="${default_route:-unknown}" \
        -v power_save="${power_save:-unknown}" \
        -v current_ssid_state="${current_ssid_state:-unknown}" \
        -v ssh_client="${ssh_client:-unknown}" \
        -v ssh_iface="${ssh_iface:-unknown}" \
        -v scan_status="$scan_status" '
      function json_escape(value, escaped) {
        escaped=value
        gsub(/\\/, "\\\\", escaped)
        gsub(/"/, "\\\"", escaped)
        return escaped
      }
      BEGIN {
        printf "{\n"
        printf "  \"mode\":\"safe-diagnose\",\n"
        printf "  \"timestamp\":\"%s\",\n", json_escape(timestamp)
        printf "  \"dry_run_only\":true,\n"
        printf "  \"real_apply_allowed\":false,\n"
        printf "  \"backend\":\"%s\",\n", json_escape(backend)
        printf "  \"interface\":\"%s\",\n", json_escape(iface)
        printf "  \"current_ssid_state\":\"%s\",\n", json_escape(current_ssid_state)
        printf "  \"current_ip\":\"%s\",\n", json_escape(current_ip)
        printf "  \"default_route\":\"%s\",\n", json_escape(default_route)
        printf "  \"power_save\":\"%s\",\n", json_escape(power_save)
        printf "  \"ssh_client\":\"%s\",\n", json_escape(ssh_client)
        printf "  \"ssh_route_interface\":\"%s\",\n", json_escape(ssh_iface)
        printf "  \"scan_status\":\"%s\",\n", json_escape(scan_status)
        printf "  \"connect_safe\":\"simulation-only\",\n"
        printf "  \"secret_policy\":\"no-secrets\",\n"
        printf "  \"network_writes\":false,\n"
        printf "  \"services_started\":false\n"
        printf "}\n"
      }
    '
    return 0
  fi

  ui_header "safe-diagnose"
  ui "safety: read-only/simulation only; no network writes, no secrets, no services"
  ui "dry_run_only=true"
  ui "real_apply_allowed=false"

  ui ""
  ui "section=backend"
  ui "backend=$backend"
  ui "interface=${iface:-unknown}"

  ui ""
  ui "section=runtime-state"
  cmd_runtime_state_show

  ui ""
  ui "section=snapshot-preview"
  cmd_state_snapshot --simulate

  ui ""
  ui "section=scan"
  cmd_scan_real

  ui ""
  ui "section=connect-safe-simulation"
  cmd_connect_safe --simulate
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
  sh prototype/wifi-kit.sh runtime-state show
  sh prototype/wifi-kit.sh scan-real [--json] [--refresh] [IFACE]
  sh prototype/wifi-kit.sh stability-status
  sh prototype/wifi-kit.sh stability-plan
  sh prototype/wifi-kit.sh stability-apply-current-boot [IFACE]
  sh prototype/wifi-kit.sh connect-safe-simulate [--fail-ip|--fail-validation]
  sh prototype/wifi-kit.sh snapshot-simulate
  sh prototype/wifi-kit.sh restore-simulate [--fail]
  sh prototype/wifi-kit.sh ssh-safety-simulate [--safe|--danger]
  sh prototype/wifi-kit.sh connect-safe-timeout-simulate [--validation-timeout|--rollback-timeout]
  sh prototype/wifi-kit.sh connect-safe --simulate
  sh prototype/wifi-kit.sh state-snapshot --simulate [--json]
  sh prototype/wifi-kit.sh safe-diagnose [--json]

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
    runtime-state)
      shift
      case "${1:-}" in
        show) cmd_runtime_state_show ;;
        *) usage; exit 2 ;;
      esac
      ;;
    scan-real) shift; cmd_scan_real "$@" ;;
    stability-status) cmd_stability_status ;;
    stability-plan) cmd_stability_plan ;;
    stability-apply-current-boot) shift; cmd_stability_apply_current_boot "${1:-}" ;;
    connect-safe-simulate) shift; cmd_connect_safe_simulate "${1:-}" ;;
    snapshot-simulate) cmd_snapshot_simulate ;;
    restore-simulate) shift; cmd_restore_simulate "${1:-}" ;;
    ssh-safety-simulate) shift; cmd_ssh_safety_simulate "${1:-}" ;;
    connect-safe-timeout-simulate) shift; cmd_connect_safe_timeout_simulate "${1:-}" ;;
    connect-safe) shift; cmd_connect_safe "${1:-}" ;;
    state-snapshot) shift; cmd_state_snapshot "$@" ;;
    safe-diagnose) shift; cmd_safe_diagnose "$@" ;;
    *) usage ;;
  esac
}

if [ "${1-}" = "--help" ] || [ -z "${1-}" ]; then
  usage
  exit 0
fi

main "$@"
