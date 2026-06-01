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
captive_conf_dir="${WIFI_KIT_NM_AP_CAPTIVE_CONF_DIR:-/etc/NetworkManager/dnsmasq-shared.d}"
captive_conf_name="${WIFI_KIT_NM_AP_CAPTIVE_CONF_NAME:-wifi-kit-nm-hotspot-captive.conf}"
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

Captive portal lab modes, dry-run by default:
  sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh captive-audit
  sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh captive-plan
  sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh captive-enable-dry-run
  sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh captive-enable
  sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh captive-disable
  sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh captive-status

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

ip_path() {
  find_tool ip 2>/dev/null || true
}

python_path() {
  find_tool python3 2>/dev/null || find_tool python 2>/dev/null || true
}

ss_path() {
  find_tool ss 2>/dev/null || true
}

curl_path() {
  find_tool curl 2>/dev/null || true
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

preferred_connection() {
  runtime_value preferred_connection ""
}

preferred_ssid() {
  runtime_value preferred_ssid ""
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

captive_ap_ip() {
  printf '%s\n' "${ap_ip%%/*}"
}

captive_conf_path() {
  printf '%s/%s\n' "$captive_conf_dir" "$captive_conf_name"
}

captive_domains() {
  printf '%s\n' \
    "msftconnecttest.com" \
    "www.msftconnecttest.com" \
    "ipv6.msftconnecttest.com" \
    "dns.msftncsi.com" \
    "www.msftncsi.com" \
    "captive.apple.com" \
    "www.apple.com" \
    "connectivitycheck.gstatic.com" \
    "clients3.google.com"
}

print_captive_dnsmasq_config() {
  ip=$(captive_ap_ip)
  printf '%s\n' \
    "# Wifi-Kit NM-hotspot captive DNS lab." \
    "# Intended for NetworkManager shared-mode dnsmasq." \
    "# Installed before the recovery hotspot starts; no NetworkManager restart." \
    "address=/msftconnecttest.com/$ip" \
    "address=/www.msftconnecttest.com/$ip" \
    "address=/ipv6.msftconnecttest.com/$ip" \
    "address=/dns.msftncsi.com/$ip" \
    "address=/www.msftncsi.com/$ip" \
    "address=/captive.apple.com/$ip" \
    "address=/www.apple.com/$ip" \
    "address=/connectivitycheck.gstatic.com/$ip" \
    "address=/clients3.google.com/$ip"
}

captive_conf_generated() {
  path=$(captive_conf_path)
  [ -r "$path" ] || return 1
  grep -q "Wifi-Kit NM-hotspot captive DNS lab" "$path" 2>/dev/null
}

captive_conf_expected_ok() {
  path=$(captive_conf_path)
  ip=$(captive_ap_ip)
  [ -r "$path" ] || return 1
  grep -qxF "# Wifi-Kit NM-hotspot captive DNS lab." "$path" 2>/dev/null || return 1
  captive_domains | while IFS= read -r domain; do
    [ -n "$domain" ] || continue
    grep -qxF "address=/$domain/$ip" "$path" 2>/dev/null || exit 1
  done
}

captive_disabled_count() {
  path=$(captive_conf_path)
  count=0
  for disabled in "$path".disabled*; do
    [ -e "$disabled" ] || continue
    count=$((count + 1))
  done
  printf '%s\n' "$count"
}

captive_backup_path() {
  path=$(captive_conf_path)
  printf '%s.backup.%s\n' "$path" "$(date -u +%Y%m%dT%H%M%SZ)"
}

captive_disabled_path() {
  path=$(captive_conf_path)
  printf '%s.disabled.%s\n' "$path" "$(date -u +%Y%m%dT%H%M%SZ)"
}

install_captive_conf() {
  path=$(captive_conf_path)
  tmp="$path.tmp.$$"
  mkdir -p "$captive_conf_dir" || return 1
  print_captive_dnsmasq_config > "$tmp" || {
    rm -f "$tmp" 2>/dev/null || true
    return 1
  }
  chmod 0644 "$tmp" || {
    rm -f "$tmp" 2>/dev/null || true
    return 1
  }
  if [ -e "$path" ] && ! cmp -s "$path" "$tmp"; then
    backup=$(captive_backup_path)
    cp -p "$path" "$backup" || {
      rm -f "$tmp" 2>/dev/null || true
      return 1
    }
    kv "captive_backup" "$backup"
  fi
  mv "$tmp" "$path" || {
    rm -f "$tmp" 2>/dev/null || true
    return 1
  }
  chmod 0644 "$path" || return 1
  kv "captive_result" "captive-conf-installed"
  kv "captive_conf_path" "$path"
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

ui_http_healthy() {
  port_is_listening || return 1
  curl_bin=$(curl_path)
  if [ -n "$curl_bin" ]; then
    "$curl_bin" -fsS --max-time 2 "http://$ui_host:$ui_port/recovery" >/dev/null 2>&1 && return 0
  fi
  port_is_listening
}

ui_recovery_healthy() {
  port_is_listening || return 1
  ui_http_healthy || return 1
  pid=$(ui_pid)
  [ -z "$pid" ] || pid_is_alive "$pid" || return 1
  return 0
}

cleanup_stale_ui() {
  pid=$(ui_pid)
  if [ -n "$pid" ] && ! pid_is_alive "$pid"; then
    kv "recovery-ui-stale-process" "$pid"
    rm -f "$ui_pidfile" 2>/dev/null || true
    return 0
  fi
  if [ -n "$pid" ] && ! ui_recovery_healthy; then
    kv "recovery-ui-stale-process" "$pid"
    kill "$pid" 2>/dev/null || true
    rm -f "$ui_pidfile" 2>/dev/null || true
  fi
}

wait_ui_recovery_healthy() {
  tries=${1:-10}
  while [ "$tries" -gt 0 ]; do
    ui_recovery_healthy && return 0
    sleep 1
    tries=$((tries - 1))
  done
  return 1
}

hotspot_is_active() {
  nmcli_bin=$(nmcli_path)
  [ -n "$nmcli_bin" ] || return 1
  "$nmcli_bin" -t --escape no -f NAME,TYPE,DEVICE connection show --active 2>/dev/null |
    awk -F: -v profile="$ap_profile" -v iface="$iface" '$1 == profile && ($2 == "wifi" || $2 == "802-11-wireless") && $3 == iface { found = 1 } END { exit found ? 0 : 1 }'
}

iw_ap_type() {
  iw_bin=$(iw_path)
  [ -n "$iw_bin" ] || return 1
  "$iw_bin" dev "$iface" info 2>/dev/null | awk '$1 == "type" { print $2; exit }'
}

ap_ipv4_addr() {
  ip_bin=$(ip_path)
  [ -n "$ip_bin" ] || return 1
  "$ip_bin" -o -4 addr show dev "$iface" 2>/dev/null | awk '{ print $4; exit }'
}

ap_ip_is_configured() {
  target=${ap_ip%%/*}
  [ -n "$target" ] || return 1
  ap_addr=$(ap_ipv4_addr 2>/dev/null || true)
  [ "$ap_addr" = "$ap_ip" ] || [ "${ap_addr%%/*}" = "$target" ]
}

http_local_is_ready() {
  curl_bin=$(curl_path)
  if [ -n "$curl_bin" ]; then
    "$curl_bin" -fsS --max-time 2 "http://$ui_host:$ui_port/" >/dev/null 2>&1 && return 0
    return 1
  fi
  port_is_listening
}

ap_local_ready_check() {
  nm_ready=no
  iw_ready=no
  ap_ip_ready=no
  port_ready=no
  http_ready=no
  iw_type=$(iw_ap_type 2>/dev/null || true)
  ap_addr=$(ap_ipv4_addr 2>/dev/null || true)

  if hotspot_is_active; then nm_ready=yes; fi
  if [ "$iw_type" = "AP" ]; then iw_ready=yes; fi
  if ap_ip_is_configured; then ap_ip_ready=yes; fi
  if port_is_listening; then port_ready=yes; fi
  if http_local_is_ready; then http_ready=yes; fi

  kv "ap-ready-check" "nm-active=$nm_ready"
  kv "ap-ready-check" "iw-type=${iw_type:-missing}"
  kv "ap-ready-check" "ap-ip=$ap_ip_ready current=${ap_addr:-missing} expected=$ap_ip"
  kv "ap-ready-check" "port-80=$port_ready"
  kv "ap-ready-check" "http-local=$http_ready url=http://$ui_host:$ui_port/"

  [ "$nm_ready" = "yes" ] &&
    [ "$iw_ready" = "yes" ] &&
    [ "$ap_ip_ready" = "yes" ] &&
    [ "$port_ready" = "yes" ] &&
    [ "$http_ready" = "yes" ]
}

wait_ap_local_ready() {
  timeout=${1:-60}
  elapsed=0
  while [ "$elapsed" -le "$timeout" ]; do
    kv "ap-ready-check-elapsed-seconds" "$elapsed"
    if ap_local_ready_check; then
      return 0
    fi
    [ "$elapsed" -ge "$timeout" ] && break
    sleep 2
    elapsed=$((elapsed + 2))
  done
  return 1
}

nm_device_status_line() {
  nmcli_bin=$(nmcli_path)
  [ -n "$nmcli_bin" ] || return 1
  LC_ALL=C "$nmcli_bin" -t --escape no -f DEVICE,TYPE,STATE,CONNECTION device status 2>/dev/null |
    awk -F: -v iface="$iface" '$1 == iface { print; exit }'
}

sta_ready_after_ap_stop_check() {
  ap_active=no
  iw_type=""
  ap_addr=""
  nm_line=""
  nm_type=""
  nm_state=""
  nm_connection=""
  ap_ip_present=no

  if hotspot_is_active; then ap_active=yes; fi
  iw_type=$(iw_ap_type 2>/dev/null || true)
  ap_addr=$(ap_ipv4_addr 2>/dev/null || true)
  nm_line=$(nm_device_status_line 2>/dev/null || true)
  nm_type=$(printf '%s\n' "$nm_line" | awk -F: '{ print $2 }')
  nm_state=$(printf '%s\n' "$nm_line" | awk -F: '{ print $3 }')
  nm_connection=$(printf '%s\n' "$nm_line" | awk -F: '{ print $4 }')

  if [ "$ap_addr" = "$ap_ip" ]; then
    ap_ip_present=yes
  fi

  kv "sta-ready-check" "ap-active=$ap_active"
  kv "sta-ready-check" "iw-type=${iw_type:-missing}"
  kv "sta-ready-check" "ap-ip-present=$ap_ip_present current=${ap_addr:-none} expected=$ap_ip"
  kv "sta-ready-check" "nm-type=${nm_type:-missing}"
  kv "sta-ready-check" "nm-state=${nm_state:-missing}"
  kv "sta-ready-check" "nm-connection=${nm_connection:-missing}"

  [ "$ap_active" = "no" ] &&
    [ "$iw_type" != "AP" ] &&
    [ "$ap_ip_present" = "no" ] &&
    [ "$nm_type" = "wifi" ] &&
    [ "$nm_state" = "disconnected" ]
}

wait_sta_ready_after_ap_stop() {
  timeout=${1:-30}
  elapsed=0
  while [ "$elapsed" -le "$timeout" ]; do
    kv "sta-ready-check-elapsed-seconds" "$elapsed"
    if sta_ready_after_ap_stop_check; then
      return 0
    fi
    [ "$elapsed" -ge "$timeout" ] && break
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

nm_debug_snapshot() {
  label=$1
  nmcli_bin=$(nmcli_path)
  if [ -z "$nmcli_bin" ]; then
    kv "nm_${label}_nmcli" "missing"
    return 0
  fi
  device_line=$("$nmcli_bin" -t --escape no -f DEVICE,TYPE,STATE,CONNECTION device status 2>/dev/null |
    awk -F: -v iface="$iface" '$1 == iface { print; exit }')
  kv "nm_${label}_device" "${device_line:-missing}"
  if connection_exists "$ap_profile"; then
    kv "nm_${label}_profile_exists" "true"
    profile_summary=$("$nmcli_bin" -t --escape no -f connection.id,802-11-wireless.ssid,802-11-wireless.mode,ipv4.method,ipv4.addresses connection show "$ap_profile" 2>/dev/null |
      tr '\n' ',' | sed 's/,$//')
    kv "nm_${label}_profile_summary" "${profile_summary:-unreadable}"
  else
    kv "nm_${label}_profile_exists" "false"
  fi
  active_line=$("$nmcli_bin" -t --escape no -f NAME,TYPE,DEVICE connection show --active 2>/dev/null |
    awk -F: -v profile="$ap_profile" '$1 == profile { print; exit }')
  kv "nm_${label}_active_profile" "${active_line:-missing}"
}

emit_radio_status() {
  prefix=$1
  kv "${prefix}_ap_band_configured" "$ap_band"
  kv "${prefix}_ap_channel_configured" "$ap_channel"
  nmcli_bin=$(nmcli_path)
  if [ -n "$nmcli_bin" ] && connection_exists "$ap_profile"; then
    profile_radio=$("$nmcli_bin" -t --escape no -f 802-11-wireless.band,802-11-wireless.channel connection show "$ap_profile" 2>/dev/null || true)
    profile_band=$(printf '%s\n' "$profile_radio" | awk -F: '$1 == "802-11-wireless.band" { print $2; exit }')
    profile_channel=$(printf '%s\n' "$profile_radio" | awk -F: '$1 == "802-11-wireless.channel" { print $2; exit }')
    kv "${prefix}_nm_profile_band" "${profile_band:-missing}"
    kv "${prefix}_nm_profile_channel" "${profile_channel:-missing}"
  else
    kv "${prefix}_nm_profile_band" "missing"
    kv "${prefix}_nm_profile_channel" "missing"
  fi
  iw_bin=$(iw_path)
  if [ -n "$iw_bin" ]; then
    iw_info=$("$iw_bin" dev "$iface" info 2>/dev/null || true)
    iw_type=$(printf '%s\n' "$iw_info" | awk '$1 == "type" { print $2; exit }')
    iw_channel=$(printf '%s\n' "$iw_info" | awk '$1 == "channel" { print $2; exit }')
    iw_frequency=$(printf '%s\n' "$iw_info" | awk '$1 == "channel" { gsub(/[^0-9]/, "", $3); print $3; exit }')
    iw_width=$(printf '%s\n' "$iw_info" | sed -n 's/.*width:[[:space:]]*//p' | sed -n '1p')
    kv "${prefix}_iw_type" "${iw_type:-missing}"
    kv "${prefix}_iw_channel" "${iw_channel:-missing}"
    kv "${prefix}_iw_frequency_mhz" "${iw_frequency:-missing}"
    kv "${prefix}_iw_width" "${iw_width:-missing}"
  else
    kv "${prefix}_iw_type" "iw-missing"
    kv "${prefix}_iw_channel" "iw-missing"
    kv "${prefix}_iw_frequency_mhz" "iw-missing"
    kv "${prefix}_iw_width" "iw-missing"
  fi
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
      target_source="missing"
      resolved_connection=""
      if [ -n "$configured_connection" ] && connection_exists "$configured_connection"; then
        resolved_connection=$configured_connection
        target_source="last_good_connection"
      elif [ -n "$configured_ssid" ]; then
        resolved_connection=$(connection_for_ssid "$configured_ssid")
        [ -n "$resolved_connection" ] && target_source="last_good_ssid"
      fi
      ;;
    primary)
      preferred_configured_connection=$(preferred_connection)
      preferred_configured_ssid=$(preferred_ssid)
      return_configured_connection=$(return_connection)
      return_configured_ssid=$(return_ssid)
      last_good_configured_connection=$(last_good_connection)
      last_good_configured_ssid=$(last_good_ssid)
      configured_connection=""
      configured_ssid=""
      resolved_connection=""
      target_source="missing"
      if [ -n "$preferred_configured_connection" ] && connection_exists "$preferred_configured_connection"; then
        configured_connection=$preferred_configured_connection
        configured_ssid=$preferred_configured_ssid
        resolved_connection=$preferred_configured_connection
        target_source="preferred_connection"
      elif [ -n "$preferred_configured_ssid" ] && resolved_connection=$(connection_for_ssid "$preferred_configured_ssid") && [ -n "$resolved_connection" ]; then
        configured_connection=$preferred_configured_connection
        configured_ssid=$preferred_configured_ssid
        target_source="preferred_ssid"
      elif [ -n "$return_configured_connection" ] && connection_exists "$return_configured_connection"; then
        configured_connection=$return_configured_connection
        configured_ssid=$return_configured_ssid
        resolved_connection=$return_configured_connection
        target_source="return_connection"
      elif [ -n "$return_configured_ssid" ] && resolved_connection=$(connection_for_ssid "$return_configured_ssid") && [ -n "$resolved_connection" ]; then
        configured_connection=$return_configured_connection
        configured_ssid=$return_configured_ssid
        target_source="return_ssid"
      elif [ -n "$last_good_configured_connection" ] && connection_exists "$last_good_configured_connection"; then
        configured_connection=$last_good_configured_connection
        configured_ssid=$last_good_configured_ssid
        resolved_connection=$last_good_configured_connection
        target_source="last_good_connection"
      elif [ -n "$last_good_configured_ssid" ] && resolved_connection=$(connection_for_ssid "$last_good_configured_ssid") && [ -n "$resolved_connection" ]; then
        configured_connection=$last_good_configured_connection
        configured_ssid=$last_good_configured_ssid
        target_source="last_good_ssid"
      fi
      ;;
    *)
      configured_connection=""
      configured_ssid=""
      resolved_connection=""
      target_source="missing"
      ;;
  esac
  printf '%s|%s|%s|%s\n' "$configured_connection" "$configured_ssid" "$resolved_connection" "$target_source"
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
  kv "01_ensure_ap" "create $ap_profile only if missing, then reconcile it explicitly"
  kv "01a_create_ap_if_missing" "nmcli connection add type wifi ifname $iface con-name $ap_profile autoconnect no ssid $(shell_quote "$ssid")"
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

cmd_captive_audit() {
  section "nm-ap-lab-captive-audit"
  kv "status" "ok"
  kv "mode" "captive-audit"
  kv "network_writes" "false"
  kv "apply_gate" "$apply"
  kv "ap_profile" "$ap_profile"
  kv "ap_ip" "$(captive_ap_ip)"
  kv "ui_url" "http://$ui_host:$ui_port"
  kv "backend_http_paths" "/generate_204,/gen_204,/hotspot-detect.html,/library/test/success.html,/connecttest.txt,/ncsi.txt"
  kv "windows_probe_hosts" "msftconnecttest.com,www.msftconnecttest.com,ipv6.msftconnecttest.com,dns.msftncsi.com,www.msftncsi.com"
  kv "android_probe_hosts" "connectivitycheck.gstatic.com,clients3.google.com"
  kv "ios_probe_hosts" "captive.apple.com"
  kv "dns_hijack_currently_configured_by_helper" "$(captive_conf_expected_ok && printf true || printf false)"
  kv "probable_windows_gap" "probe hostnames may not resolve to $ui_host in NM shared mode"
  kv "candidate_conf_dir" "$captive_conf_dir"
  kv "candidate_conf_path" "$(captive_conf_path)"
  if [ -d "$captive_conf_dir" ]; then
    kv "candidate_conf_dir_exists" "true"
  else
    kv "candidate_conf_dir_exists" "false"
  fi
  if [ -e "$(captive_conf_path)" ]; then
    kv "candidate_conf_exists" "true"
  else
    kv "candidate_conf_exists" "false"
  fi
  kv "policy" "start-hotspot installs captive DNS before starting the NM shared hotspot"
}

cmd_captive_plan() {
  section "nm-ap-lab-captive-plan"
  kv "status" "planned"
  kv "network_writes" "false"
  kv "apply_supported" "true"
  kv "goal" "make platform captive probe hostnames resolve to $(captive_ap_ip) while NM-hotspot recovery is active"
  kv "candidate_conf_path" "$(captive_conf_path)"
  kv "activation_policy" "installed automatically by start-hotspot in apply mode; manual captive-enable remains available"
  kv "rollback_policy" "remove only $(captive_conf_path), then restart/reconnect NM hotspot only after explicit validation"
  kv "risk" "NetworkManager may require reconnecting the shared hotspot or reloading its dnsmasq child before the file is used"

  section "target-hostnames"
  captive_domains | while IFS= read -r domain; do
    [ -n "$domain" ] || continue
    kv "$domain" "$(captive_ap_ip)"
  done

  section "candidate-dnsmasq-shared-config"
  print_captive_dnsmasq_config

  section "future-apply-commands-not-run"
  kv "01_create_dir" "install -d -m 0755 $captive_conf_dir"
  kv "02_write_conf" "write the candidate config to $(captive_conf_path)"
  kv "03_chmod" "chmod 0644 $(captive_conf_path)"
  kv "04_validate" "start or reconnect only the NM hotspot in a controlled lab window, then test Windows captive prompt"
}

cmd_captive_enable_dry_run() {
  section "nm-ap-lab-captive-enable-dry-run"
  kv "status" "dry-run"
  kv "network_writes" "false"
  kv "apply_ignored" "$apply"
  kv "reason" "dry-run only; start-hotspot apply installs this same config before NM shared dnsmasq starts"
  kv "candidate_conf_path" "$(captive_conf_path)"
  section "would-write"
  print_captive_dnsmasq_config
  section "would-test"
  kv "windows" "connect to NM hotspot and verify Windows opens or flags captive portal for http://www.msftconnecttest.com/connecttest.txt"
  kv "ios" "connect to NM hotspot and verify captive.apple.com probe reaches recovery UI"
  kv "android" "connect to NM hotspot and verify generate_204/connectivitycheck probe reaches recovery UI"
}

cmd_captive_status() {
  path=$(captive_conf_path)
  section "nm-ap-lab-captive-status"
  kv "status" "ok"
  kv "network_writes" "false"
  kv "candidate_conf_dir" "$captive_conf_dir"
  kv "candidate_conf_path" "$path"
  if [ -d "$captive_conf_dir" ]; then
    kv "candidate_conf_dir_exists" "true"
  else
    kv "candidate_conf_dir_exists" "false"
  fi
  if [ -e "$path" ]; then
    kv "candidate_conf_exists" "true"
  else
    kv "candidate_conf_exists" "false"
  fi
  if captive_conf_generated; then
    kv "candidate_conf_generated_by_wifi_kit" "true"
  else
    kv "candidate_conf_generated_by_wifi_kit" "false"
  fi
  if captive_conf_expected_ok; then
    kv "candidate_conf_expected_content" "ok"
  else
    kv "candidate_conf_expected_content" "missing-or-different"
  fi
  kv "disabled_versions_count" "$(captive_disabled_count)"
  kv "activation_note" "NetworkManager shared-mode dnsmasq will see this only after the NM hotspot is started or reconnected"
  kv "global_restart" "not-required-and-not-performed"
}

cmd_captive_enable() {
  path=$(captive_conf_path)
  tmp="$path.tmp.$$"
  section "nm-ap-lab-captive-enable"
  kv "status" "$([ "$apply" = "1" ] && printf applying || printf dry-run)"
  kv "network_writes" "$([ "$apply" = "1" ] && printf true || printf false)"
  kv "candidate_conf_dir" "$captive_conf_dir"
  kv "candidate_conf_path" "$path"
  if [ -d "$captive_conf_dir" ]; then
    kv "candidate_conf_dir_exists" "true"
  else
    kv "candidate_conf_dir_exists" "false"
  fi
  if [ -e "$path" ]; then
    kv "candidate_conf_exists" "true"
  else
    kv "candidate_conf_exists" "false"
  fi
  if captive_conf_expected_ok; then
    kv "candidate_conf_expected_content" "ok"
  else
    kv "candidate_conf_expected_content" "missing-or-different"
  fi
  kv "command_01" "mkdir -p $captive_conf_dir"
  kv "command_02" "write Wifi-Kit captive dnsmasq config to $path"
  kv "command_03" "chmod 0644 $path"
  kv "networkmanager_restart" "no"
  kv "hotspot_reconnect" "no"
  section "would-write"
  print_captive_dnsmasq_config

  if [ "$apply" = "1" ]; then
    install_captive_conf || {
      kv "result" "refused"
      kv "reason" "captive-conf-install-failed"
      exit 1
    }
    kv "result" "captive-conf-installed"
    kv "next_step" "restart or reconnect only the NM hotspot in a controlled lab window"
  fi
}

cmd_captive_disable() {
  path=$(captive_conf_path)
  section "nm-ap-lab-captive-disable"
  kv "status" "$([ "$apply" = "1" ] && printf applying || printf dry-run)"
  kv "network_writes" "$([ "$apply" = "1" ] && printf true || printf false)"
  kv "candidate_conf_path" "$path"
  if [ -e "$path" ]; then
    kv "candidate_conf_exists" "true"
  else
    kv "candidate_conf_exists" "false"
  fi
  if captive_conf_generated; then
    kv "candidate_conf_generated_by_wifi_kit" "true"
  else
    kv "candidate_conf_generated_by_wifi_kit" "false"
  fi
  kv "command" "rename $path to ${path}.disabled.<timestamp> only if generated by Wifi-Kit"
  kv "networkmanager_restart" "no"
  kv "hotspot_reconnect" "no"

  if [ "$apply" = "1" ]; then
    if [ ! -e "$path" ]; then
      kv "result" "already-disabled"
      return 0
    fi
    if ! captive_conf_generated; then
      kv "result" "refused"
      kv "reason" "existing-file-not-generated-by-wifi-kit"
      exit 1
    fi
    disabled=$(captive_disabled_path)
    mv "$path" "$disabled"
    kv "result" "captive-conf-disabled"
    kv "disabled_path" "$disabled"
    kv "next_step" "restart or reconnect only the NM hotspot in a controlled lab window"
  fi
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

cmd_ensure_profile() {
  ssid=$(effective_ap_ssid)
  section "nm-ap-lab-ensure-profile"
  kv "status" "$([ "$apply" = "1" ] && printf applying || printf dry-run)"
  kv "network_writes" "$([ "$apply" = "1" ] && printf true || printf false)"
  kv "profile_persistent_target" "true"
  kv "profile_delete_still_legacy" "true"
  create_profile_commands "$ssid"
  if [ "$apply" = "1" ]; then
    nmcli_bin=$(require_apply_tool nmcli)
    ap_password=$(runtime_value ap_password "")
    if [ -z "$ap_password" ]; then
      kv "status" "refused"
      kv "reason" "ap-password-missing-in-runtime-config"
      exit 1
    fi
    if connection_exists "$ap_profile"; then
      profile_action="reconciled"
    else
      "$nmcli_bin" connection add type wifi ifname "$iface" con-name "$ap_profile" autoconnect no ssid "$ssid"
      profile_action="created"
    fi
    "$nmcli_bin" connection modify "$ap_profile" connection.interface-name "$iface" 802-11-wireless.ssid "$ssid"
    "$nmcli_bin" connection modify "$ap_profile" 802-11-wireless.mode ap 802-11-wireless.band "$ap_band" 802-11-wireless.channel "$ap_channel"
    "$nmcli_bin" connection modify "$ap_profile" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$ap_password" wifi-sec.proto rsn wifi-sec.pairwise ccmp wifi-sec.group ccmp
    "$nmcli_bin" connection modify "$ap_profile" ipv4.method shared ipv4.addresses "$ap_ip" ipv6.method ignore connection.autoconnect no
    kv "profile_action" "$profile_action"
    kv "result" "profile-ensured"
  fi
}

cmd_create_profile() {
  cmd_ensure_profile
}

cmd_start_hotspot() {
  ssid=$(effective_ap_ssid)
  section "nm-ap-lab-start-hotspot"
  kv "status" "$([ "$apply" = "1" ] && printf applying || printf dry-run)"
  kv "network_writes" "$([ "$apply" = "1" ] && printf true || printf false)"
  kv "command" "nmcli connection up $ap_profile ifname $iface"
  kv "profile_persistent_target" "true"
  kv "profile_delete_still_legacy" "true"
  kv "captive_dns" "install $(captive_conf_path) before starting hotspot so NM shared dnsmasq can route captive probes"
  kv "follow_up" "start-ui"
  kv "follow_up_command" "$(ui_start_command "$ssid")"
  if [ "$apply" = "1" ]; then
    nmcli_bin=$(require_apply_tool nmcli)
    cmd_ensure_profile
    if install_captive_conf; then
      kv "captive_policy" "enabled-for-this-hotspot-start"
    else
      kv "captive_result" "failed-best-effort"
      kv "captive_policy" "manual-fallback-still-available"
    fi
    nm_debug_snapshot "before_start"
    set +e
    "$nmcli_bin" connection up "$ap_profile" ifname "$iface"
    nmcli_up_rc=$?
    set -e
    kv "nmcli_connection_up_exit_code" "$nmcli_up_rc"
    nm_debug_snapshot "after_start"
    emit_radio_status "radio_after_start"
    if [ "$nmcli_up_rc" -ne 0 ]; then
      kv "result" "hotspot-start-failed"
      exit "$nmcli_up_rc"
    fi
    if hotspot_is_active; then
      kv "hotspot_active_after_start" "true"
    else
      kv "hotspot_active_after_start" "false"
    fi
    kv "result" "hotspot-start-requested"
    cmd_start_ui
    if wait_ap_local_ready 60; then
      kv "result" "ap-local-ready"
    else
      kv "result" "ap-local-not-ready-timeout"
      exit 1
    fi
  fi
}

cmd_stop_hotspot() {
  section "nm-ap-lab-stop-hotspot"
  kv "status" "$([ "$apply" = "1" ] && printf applying || printf dry-run)"
  kv "network_writes" "$([ "$apply" = "1" ] && printf true || printf false)"
  kv "command_01" "nmcli connection down $ap_profile"
  kv "command_02" "nmcli connection delete $ap_profile"
  kv "profile_persistent_target" "true"
  kv "profile_delete_still_legacy" "true"
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
    if ui_recovery_healthy; then
      kv "recovery-ui-healthy" "true"
      kv "result" "ui-already-healthy"
      kv "pid" "$(ui_pid)"
      return 0
    fi
    kv "recovery-ui-missing" "true"
    cleanup_stale_ui
    WIFI_KIT_RECOVERY_BACKEND=nm-hotspot \
    WIFI_KIT_NM_AP_LAB=1 \
    WIFI_KIT_RUNTIME_CONFIG="$runtime_config" \
      nohup "$python_bin" "$ui_script" --host "$ui_host" --port "$ui_port" --recovery-mode --recovery-ssid "$ssid" --recovery-ip "$ui_host" >"$ui_log" 2>&1 &
    printf '%s\n' "$!" > "$ui_pidfile"
    kv "pid" "$!"
    if wait_ui_recovery_healthy 10; then
      kv "recovery-ui-restarted" "true"
      kv "recovery-ui-healthy" "true"
      kv "result" "ui-started"
    else
      kv "recovery-ui-healthy" "false"
      kv "result" "ui-start-requested-not-confirmed"
      return 1
    fi
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
  last_good_tail=${last_good_tail#*|}
  last_good_resolved_connection=${last_good_tail%%|*}
  last_good_target_source=${last_good_tail#*|}
  primary_configured_connection=${primary_target%%|*}
  primary_tail=${primary_target#*|}
  primary_configured_ssid=${primary_tail%%|*}
  primary_tail=${primary_tail#*|}
  primary_resolved_connection=${primary_tail%%|*}
  primary_target_source=${primary_tail#*|}

  section "nm-ap-lab-status"
  kv "status" "ok"
  kv "network_writes" "false"
  if hotspot_is_active; then
    kv "hotspot_active" "true"
  else
    kv "hotspot_active" "false"
  fi
  ui_pid_value=$(ui_pid)
  if ui_is_active; then kv "ui_process_active" "true"; else kv "ui_process_active" "false"; fi
  if ui_recovery_healthy; then kv "ui_recovery_active" "true"; else kv "ui_recovery_active" "false"; fi
  kv "ui_pid" "${ui_pid_value:-missing}"
  if port_is_listening; then
    kv "port_80_listening" "true"
  else
    kv "port_80_listening" "false"
  fi
  if ui_http_healthy; then kv "ui_http_healthy" "true"; else kv "ui_http_healthy" "false"; fi
  if ui_recovery_healthy; then kv "ui_recovery_healthy" "true"; else kv "ui_recovery_healthy" "false"; fi
  kv "ui_url" "http://$ui_host:$ui_port"
  emit_radio_status "radio_status"
  kv "ui_pidfile" "$ui_pidfile"
  kv "ui_log" "$ui_log"
  kv "last_good_ssid" "${last_good_configured_ssid:-missing}"
  kv "last_good_connection" "${last_good_configured_connection:-missing}"
  kv "last_good_nm_connection" "${last_good_resolved_connection:-missing}"
  kv "last_good_target_source" "${last_good_target_source:-missing}"
  kv "primary_ssid" "${primary_configured_ssid:-missing}"
  kv "primary_connection" "${primary_configured_connection:-missing}"
  kv "primary_nm_connection" "${primary_resolved_connection:-missing}"
  kv "primary_target_source" "${primary_target_source:-missing}"
}

cmd_rollback() {
  section "nm-ap-lab-rollback"
  kv "status" "$([ "$apply" = "1" ] && printf applying || printf dry-run)"
  kv "network_writes" "$([ "$apply" = "1" ] && printf true || printf false)"
  kv "command_01" "stop-ui"
  kv "command_02" "nmcli connection down $ap_profile"
  kv "command_03" "nmcli connection delete $ap_profile"
  kv "return_policy" "cleanup-only; use return-last-good or return-primary to reconnect"
  kv "profile_persistent_target" "true"
  kv "profile_delete_still_legacy" "true"
  if [ "$apply" = "1" ]; then
    cmd_stop_ui
    nmcli_bin=$(require_apply_tool nmcli)
    "$nmcli_bin" connection down "$ap_profile" 2>/dev/null || true
    if wait_sta_ready_after_ap_stop 30; then
      kv "result" "sta-ready-after-ap-stop"
    else
      kv "result" "sta-ready-after-ap-stop-timeout"
      nm_debug_snapshot "sta_not_ready_after_ap_stop"
      emit_radio_status "radio_sta_not_ready_after_ap_stop"
      exit 1
    fi
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
  tail=${tail#*|}
  resolved_connection=${tail%%|*}
  target_source=${tail#*|}

  section "nm-ap-lab-return-$kind"
  kv "status" "$([ "$apply" = "1" ] && printf applying || printf dry-run)"
  kv "network_writes" "$([ "$apply" = "1" ] && printf true || printf false)"
  kv "target_kind" "$kind"
  kv "configured_ssid" "${configured_ssid:-missing}"
  kv "configured_connection" "${configured_connection:-missing}"
  kv "resolved_connection" "${resolved_connection:-missing}"
  kv "target_source" "${target_source:-missing}"
  kv "command_01" "stop-ui"
  kv "command_02" "nmcli connection down $ap_profile"
  kv "command_03" "wait_sta_ready_after_ap_stop"
  kv "command_04" "nmcli connection delete $ap_profile"
  kv "profile_persistent_target" "true"
  kv "profile_delete_still_legacy" "true"
  if [ -n "$resolved_connection" ]; then
    kv "command_05_return" "nmcli connection up $resolved_connection ifname $iface"
  else
    kv "command_05_return" "refused: target connection unknown"
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
    if wait_sta_ready_after_ap_stop 30; then
      kv "result" "sta-ready-after-ap-stop"
    else
      kv "result" "sta-ready-after-ap-stop-timeout"
      nm_debug_snapshot "sta_not_ready_after_ap_stop"
      emit_radio_status "radio_sta_not_ready_after_ap_stop"
      exit 1
    fi
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
  captive-audit) cmd_captive_audit ;;
  captive-plan) cmd_captive_plan ;;
  captive-enable-dry-run) cmd_captive_enable_dry_run ;;
  captive-enable) cmd_captive_enable ;;
  captive-disable) cmd_captive_disable ;;
  captive-status) cmd_captive_status ;;
  -h|--help|help) usage ;;
  *)
    usage
    exit 2
    ;;
esac
