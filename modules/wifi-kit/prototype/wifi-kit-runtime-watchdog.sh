#!/bin/sh
set -eu

runtime_config="${WIFI_KIT_RUNTIME_CONFIG:-${HOME:-/tmp}/.config/wifi-kit/runtime.conf}"
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
action_wrapper="$script_dir/wifi-kit-action-wrapper.sh"
ap_setup_script="$script_dir/ap-setup-test.sh"
nm_ap_lab_script="$script_dir/wifi-kit-nm-ap-lab.sh"
iface="${WIFI_KIT_RUNTIME_WATCHDOG_IFACE:-wlan0}"
poll_seconds="${WIFI_KIT_RUNTIME_WATCHDOG_POLL_SECONDS:-5}"
log_file="${WIFI_KIT_RUNTIME_WATCHDOG_LOG:-/tmp/wifi-kit-actions/runtime-watchdog-$(id -u).log}"
state_file="${WIFI_KIT_RUNTIME_WATCHDOG_STATE:-/tmp/wifi-kit-actions/runtime-watchdog-state}"
events_file="${WIFI_KIT_RUNTIME_WATCHDOG_EVENTS:-/tmp/wifi-kit-actions/runtime-watchdog-events.log}"
instability_file="${WIFI_KIT_RUNTIME_WATCHDOG_INSTABILITY:-/tmp/wifi-kit-actions/runtime-watchdog-instability}"
persistent_log_dir="${WIFI_KIT_RUNTIME_WATCHDOG_PERSISTENT_LOG_DIR:-/var/log/seed-kit/wifi-kit}"
persistent_log_file="${WIFI_KIT_RUNTIME_WATCHDOG_PERSISTENT_LOG:-$persistent_log_dir/runtime-watchdog.log}"
persistent_state_file="${WIFI_KIT_RUNTIME_WATCHDOG_PERSISTENT_STATE:-$persistent_log_dir/runtime-watchdog-state}"
persistent_max_bytes="${WIFI_KIT_RUNTIME_WATCHDOG_PERSISTENT_MAX_BYTES:-262144}"
gateway_ping_enabled="${WIFI_KIT_RUNTIME_WATCHDOG_GATEWAY_PING:-1}"
internet_probe="${WIFI_KIT_RUNTIME_WATCHDOG_INTERNET_PROBE:-1.1.1.1}"
normal_ui_port="${WIFI_KIT_NORMAL_UI_PORT:-54321}"
normal_ui_service="${WIFI_KIT_NORMAL_UI_SERVICE:-wifi-kit-ui.service}"
ui_repair_min_seconds="${WIFI_KIT_RUNTIME_WATCHDOG_UI_REPAIR_MIN_SECONDS:-60}"

usage() {
  cat <<'EOF'
wifi-kit runtime recovery watchdog

Usage:
  sh modules/wifi-kit/prototype/wifi-kit-runtime-watchdog.sh audit
  sh modules/wifi-kit/prototype/wifi-kit-runtime-watchdog.sh plan
  sudo sh modules/wifi-kit/prototype/wifi-kit-runtime-watchdog.sh run

Modes:
  audit  Read runtime config, active Wi-Fi, and AP recovery state only.
  plan   Print the runtime disconnect policy. No network writes.
  run    Watch last_good Wi-Fi during runtime. After a bounded grace period,
         start AP recovery through the Wifi-Kit wrapper if last_good did not
         return. It never tries return_connection.
EOF
}

kv() {
  printf '%s=%s\n' "$1" "$2"
}

section() {
  printf '\n[%s]\n' "$1"
}

timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

epoch_seconds() {
  date '+%s'
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

write_runtime_value() {
  key=$1
  value=$2
  wr_runtime_dir=$(dirname -- "$runtime_config")
  mkdir -p "$wr_runtime_dir" 2>/dev/null || return 1
  if [ ! -f "$runtime_config" ]; then
    {
      printf '# Wifi-Kit runtime config\n'
      printf '# Created by runtime watchdog bootstrap baseline.\n'
    } > "$runtime_config" 2>/dev/null || return 1
  fi
  wr_tmp="${runtime_config}.$$"
  awk -v key="$key" -v value="$value" '
    BEGIN { done = 0 }
    $0 ~ "^" key "=" { print key "=" value; done = 1; next }
    { print }
    END { if (!done) print key "=" value }
  ' "$runtime_config" > "$wr_tmp" 2>/dev/null || {
    rm -f "$wr_tmp" 2>/dev/null || true
    return 1
  }
  cat "$wr_tmp" > "$runtime_config" 2>/dev/null || {
    rm -f "$wr_tmp" 2>/dev/null || true
    return 1
  }
  chmod 0600 "$runtime_config" 2>/dev/null || true
  rm -f "$wr_tmp" 2>/dev/null || true
}

normalize_bool() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes|on) printf 'true' ;;
    false|0|no|off|'') printf 'false' ;;
    *) printf 'invalid' ;;
  esac
}

is_positive_integer() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    0) return 1 ;;
    *) return 0 ;;
  esac
}

ensure_action_dir() {
  mkdir -p /tmp/wifi-kit-actions 2>/dev/null || true
  chmod 1777 /tmp/wifi-kit-actions 2>/dev/null || true
}

ensure_persistent_log_dir() {
  mkdir -p "$persistent_log_dir" 2>/dev/null || return 1
  chmod 0750 "$persistent_log_dir" 2>/dev/null || true
}

rotate_persistent_log() {
  [ -f "$persistent_log_file" ] || return 0
  is_positive_integer "$persistent_max_bytes" || return 0
  size=$(wc -c < "$persistent_log_file" 2>/dev/null || printf '0')
  [ "${size:-0}" -gt "$persistent_max_bytes" ] || return 0
  rm -f "$persistent_log_file.3" 2>/dev/null || true
  [ -f "$persistent_log_file.2" ] && mv "$persistent_log_file.2" "$persistent_log_file.3" 2>/dev/null || true
  [ -f "$persistent_log_file.1" ] && mv "$persistent_log_file.1" "$persistent_log_file.2" 2>/dev/null || true
  mv "$persistent_log_file" "$persistent_log_file.1" 2>/dev/null || true
}

event_line() {
  status=$1
  detail=${2:-}
  printf 'timestamp=%s action=runtime-watchdog status=%s' "$(timestamp)" "$status"
  if [ -n "$detail" ]; then
    printf ' detail=%s' "$detail"
  fi
  printf ' health_status=%s health_reason=%s runtime_match=%s runtime_reason=%s current_connection=%s current_ssid=%s last_good_connection=%s last_good_ssid=%s ip=%s default_route=%s gateway=%s gateway_ping=%s internet_required=%s internet_probe=%s internet_ping=%s bootstrap_state=%s bootstrap_source=%s baseline_quality=%s config_readable=%s unstable_triggered=%s unstable_count=%s recovery_decision=%s\n' \
    "${health_status:-unknown}" \
    "${health_reason:-unknown}" \
    "${runtime_match:-}" \
    "${runtime_reason:-}" \
    "${current_connection:-}" \
    "${current_ssid:-}" \
    "${last_good_connection:-}" \
    "${last_good_ssid:-}" \
    "${iface_ipv4:-}" \
    "${default_route_present:-}" \
    "${gateway:-}" \
    "${gateway_ping_status:-}" \
    "${internet_required:-}" \
    "${internet_probe:-}" \
    "${internet_ping_status:-}" \
    "${bootstrap_state:-}" \
    "${bootstrap_source:-}" \
    "${baseline_quality:-}" \
    "${runtime_config_readable:-}" \
    "${unstable_triggered:-no}" \
    "${unstable_count:-}" \
    "${recovery_decision:-none}"
}

log_event() {
  status=$1
  detail=${2:-}
  ensure_action_dir
  event_line "$status" "$detail" >> "$log_file" 2>/dev/null || true
  if ensure_persistent_log_dir; then
    rotate_persistent_log
    event_line "$status" "$detail" >> "$persistent_log_file" 2>/dev/null || true
    chmod 0640 "$persistent_log_file" 2>/dev/null || true
  fi
}

write_state() {
  status=$1
  reason=${2:-}
  ssid=${3:-}
  ensure_action_dir
  {
    kv "timestamp" "$(timestamp)"
    kv "status" "$status"
    kv "reason" "$reason"
    kv "ssid" "$ssid"
    kv "runtime_match" "${runtime_match:-}"
    kv "runtime_reason" "${runtime_reason:-$reason}"
    kv "runtime_recovery_debug_passive" "${debug_passive:-false}"
    kv "health_status" "${health_status:-unknown}"
    kv "health_reason" "${health_reason:-$reason}"
    kv "config_readable" "${runtime_config_readable:-}"
    kv "last_good_configured" "${last_good_configured:-}"
    kv "current_connection" "${current_connection:-}"
    kv "current_ssid" "${current_ssid:-}"
    kv "last_good_connection" "${last_good_connection:-}"
    kv "last_good_ssid" "${last_good_ssid:-}"
    kv "ip" "${iface_ipv4:-}"
    kv "default_route" "${default_route_present:-}"
    kv "gateway" "${gateway:-}"
    kv "gateway_ping" "${gateway_ping_status:-}"
    kv "internet_required" "${internet_required:-}"
    kv "internet_probe" "${internet_probe:-}"
    kv "internet_ping" "${internet_ping_status:-}"
    kv "bootstrap_state" "${bootstrap_state:-}"
    kv "bootstrap_source" "${bootstrap_source:-}"
    kv "baseline_quality" "${baseline_quality:-}"
    kv "unstable_triggered" "${unstable_triggered:-no}"
    kv "unstable_count" "${unstable_count:-}"
    kv "unstable_threshold" "${threshold:-}"
    kv "recovery_decision" "${recovery_decision:-none}"
    kv "persistent_log_file" "$persistent_log_file"
    kv "persistent_state_file" "$persistent_state_file"
    kv "iface" "$iface"
    kv "runtime_config" "$runtime_config"
    kv "log_file" "$log_file"
  } > "$state_file" 2>/dev/null || true
  chmod 0666 "$state_file" 2>/dev/null || true
  if ensure_persistent_log_dir; then
    {
      kv "timestamp" "$(timestamp)"
      kv "status" "$status"
      kv "reason" "$reason"
      kv "health_status" "${health_status:-unknown}"
      kv "health_reason" "${health_reason:-$reason}"
      kv "runtime_match" "${runtime_match:-}"
      kv "runtime_reason" "${runtime_reason:-$reason}"
      kv "runtime_recovery_debug_passive" "${debug_passive:-false}"
      kv "config_readable" "${runtime_config_readable:-}"
      kv "last_good_configured" "${last_good_configured:-}"
      kv "current_connection" "${current_connection:-}"
      kv "current_ssid" "${current_ssid:-}"
      kv "last_good_connection" "${last_good_connection:-}"
      kv "last_good_ssid" "${last_good_ssid:-}"
      kv "ip" "${iface_ipv4:-}"
      kv "default_route" "${default_route_present:-}"
      kv "gateway" "${gateway:-}"
      kv "gateway_ping" "${gateway_ping_status:-}"
      kv "internet_required" "${internet_required:-}"
      kv "internet_probe" "${internet_probe:-}"
      kv "internet_ping" "${internet_ping_status:-}"
      kv "bootstrap_state" "${bootstrap_state:-}"
      kv "bootstrap_source" "${bootstrap_source:-}"
      kv "baseline_quality" "${baseline_quality:-}"
      kv "unstable_triggered" "${unstable_triggered:-no}"
      kv "unstable_count" "${unstable_count:-}"
      kv "unstable_threshold" "${threshold:-}"
      kv "recovery_decision" "${recovery_decision:-none}"
      kv "iface" "$iface"
      kv "runtime_config" "$runtime_config"
      kv "log_file" "$log_file"
      kv "persistent_log_file" "$persistent_log_file"
    } > "$persistent_state_file" 2>/dev/null || true
    chmod 0640 "$persistent_state_file" 2>/dev/null || true
  fi
}

state_value() {
  key=$1
  [ -r "$state_file" ] || return 0
  sed -n "s/^$key=//p" "$state_file" 2>/dev/null | sed -n '1p'
}

active_connection() {
  if [ -n "${WIFI_KIT_RUNTIME_WATCHDOG_MOCK_CURRENT_CONNECTION:-}" ]; then
    printf '%s\n' "$WIFI_KIT_RUNTIME_WATCHDOG_MOCK_CURRENT_CONNECTION"
    return 0
  fi
  nmcli_bin=$(find_tool nmcli 2>/dev/null || true)
  [ -n "$nmcli_bin" ] || return 0
  "$nmcli_bin" -t -f DEVICE,CONNECTION device status 2>/dev/null |
    awk -F: -v iface="$iface" '$1 == iface { print $2; exit }'
}

connection_ssid() {
  connection=$1
  nmcli_bin=$(find_tool nmcli 2>/dev/null || true)
  [ -n "$nmcli_bin" ] || return 0
  [ -n "$connection" ] || return 0
  "$nmcli_bin" -g 802-11-wireless.ssid connection show "$connection" 2>/dev/null | sed -n '1p' || true
}

active_ssid() {
  if [ -n "${WIFI_KIT_RUNTIME_WATCHDOG_MOCK_CURRENT_SSID:-}" ]; then
    printf '%s\n' "$WIFI_KIT_RUNTIME_WATCHDOG_MOCK_CURRENT_SSID"
    return 0
  fi
  connection=$(active_connection)
  ssid=$(connection_ssid "$connection")
  if [ -n "$ssid" ]; then
    printf '%s\n' "$ssid"
    return 0
  fi
  nmcli_bin=$(find_tool nmcli 2>/dev/null || true)
  [ -n "$nmcli_bin" ] || return 0
  "$nmcli_bin" -t -f ACTIVE,SSID device wifi list --rescan no 2>/dev/null |
    awk -F: '$1 == "yes" { print $2; exit }'
}

iface_ipv4_addr() {
  if [ -n "${WIFI_KIT_RUNTIME_WATCHDOG_MOCK_IP:-}" ]; then
    printf '%s\n' "$WIFI_KIT_RUNTIME_WATCHDOG_MOCK_IP"
    return 0
  fi
  ip_bin=$(find_tool ip 2>/dev/null || true)
  [ -n "$ip_bin" ] || return 0
  "$ip_bin" -o -4 addr show dev "$iface" 2>/dev/null |
    awk '{ print $4; exit }'
}

default_route_info() {
  if [ -n "${WIFI_KIT_RUNTIME_WATCHDOG_MOCK_DEFAULT_ROUTE:-}" ]; then
    printf '%s\n' "$WIFI_KIT_RUNTIME_WATCHDOG_MOCK_DEFAULT_ROUTE"
    return 0
  fi
  ip_bin=$(find_tool ip 2>/dev/null || true)
  [ -n "$ip_bin" ] || return 0
  "$ip_bin" route show default dev "$iface" 2>/dev/null | sed -n '1p'
}

route_gateway() {
  route=$1
  printf '%s\n' "$route" |
    awk '{ for (i = 1; i <= NF; i++) if ($i == "via") { print $(i + 1); exit } }'
}

ping_gateway() {
  if [ "$gateway_ping_enabled" = "0" ] || [ "$gateway_ping_enabled" = "false" ]; then
    printf 'skipped\n'
    return 0
  fi
  if [ -n "${WIFI_KIT_RUNTIME_WATCHDOG_MOCK_GATEWAY_PING:-}" ]; then
    printf '%s\n' "$WIFI_KIT_RUNTIME_WATCHDOG_MOCK_GATEWAY_PING"
    return 0
  fi
  [ -n "$gateway" ] || {
    printf 'unknown\n'
    return 0
  }
  ping_bin=$(find_tool ping 2>/dev/null || true)
  [ -n "$ping_bin" ] || {
    printf 'unknown\n'
    return 0
  }
  if "$ping_bin" -c 1 -W 1 "$gateway" >/dev/null 2>&1; then
    printf 'ok\n'
  else
    printf 'failed\n'
  fi
}

ping_internet_probe() {
  if [ -n "${WIFI_KIT_RUNTIME_WATCHDOG_MOCK_INTERNET_PING:-}" ]; then
    printf '%s\n' "$WIFI_KIT_RUNTIME_WATCHDOG_MOCK_INTERNET_PING"
    return 0
  fi
  [ -n "$internet_probe" ] || {
    printf 'unknown\n'
    return 0
  }
  ping_bin=$(find_tool ping 2>/dev/null || true)
  [ -n "$ping_bin" ] || {
    printf 'unknown\n'
    return 0
  }
  if "$ping_bin" -c 1 -W 1 "$internet_probe" >/dev/null 2>&1; then
    printf 'ok\n'
  else
    printf 'failed\n'
  fi
}

current_wifi_baseline_eligible() {
  [ "$last_good_configured" != "yes" ] || return 1
  [ -n "$current_connection" ] || return 1
  [ -n "$current_ssid" ] || return 1
  case "$current_ssid" in
    Wifi-Kit-*|wifi-kit-*) return 1 ;;
  esac
  [ -n "$iface_ipv4" ] || return 1
  [ "$default_route_present" = "yes" ] || return 1
  [ -n "$gateway" ] || return 1
  [ "$gateway_ping_status" = "ok" ] || return 1
  return 0
}

classify_bootstrap_state() {
  bootstrap_state=$(runtime_value bootstrap_state "")
  bootstrap_source=$(runtime_value bootstrap_source "")
  baseline_quality=$(runtime_value baseline_quality "")
  if [ "$last_good_configured" = "yes" ]; then
    [ -n "$bootstrap_state" ] || bootstrap_state="baselined"
    return 0
  fi
  if current_wifi_baseline_eligible; then
    bootstrap_state="baseline-pending"
    bootstrap_source="current-healthy-wifi"
    case "$(ping_internet_probe)" in
      ok) baseline_quality="internet" ;;
      *) baseline_quality="lan-only" ;;
    esac
  else
    bootstrap_state="onboarding-required"
    bootstrap_source=""
    baseline_quality=""
  fi
}

auto_baseline_current_wifi() {
  current_wifi_baseline_eligible || return 1
  internet_ping_status=$(ping_internet_probe)
  case "$internet_ping_status" in
    ok) new_baseline_quality="internet" ;;
    *) new_baseline_quality="lan-only" ;;
  esac
  log_event "bootstrap-baseline-started" "source=current-healthy-wifi current_connection=$current_connection current_ssid=$current_ssid baseline_quality=$new_baseline_quality internet_probe=$internet_probe internet_ping=$internet_ping_status"
  if [ -z "$(runtime_value original_connection "")" ]; then
    write_runtime_value original_connection "$current_connection" || return 1
  fi
  if [ -z "$(runtime_value original_ssid "")" ]; then
    write_runtime_value original_ssid "$current_ssid" || return 1
  fi
  if [ -z "$(runtime_value return_connection "")" ]; then
    write_runtime_value return_connection "$current_connection" || return 1
  fi
  if [ -z "$(runtime_value return_ssid "")" ]; then
    write_runtime_value return_ssid "$current_ssid" || return 1
  fi
  write_runtime_value last_good_connection "$current_connection" || return 1
  write_runtime_value last_good_ssid "$current_ssid" || return 1
  write_runtime_value bootstrap_state "baselined" || return 1
  write_runtime_value bootstrap_source "current-healthy-wifi" || return 1
  write_runtime_value bootstrap_at "$(timestamp)" || return 1
  write_runtime_value baseline_quality "$new_baseline_quality" || return 1
  log_event "bootstrap-baseline-created" "source=current-healthy-wifi current_connection=$current_connection current_ssid=$current_ssid baseline_quality=$new_baseline_quality"
  return 0
}

ap_recovery_active() {
  if [ -n "${WIFI_KIT_RUNTIME_WATCHDOG_MOCK_AP_ACTIVE:-}" ]; then
    [ "$WIFI_KIT_RUNTIME_WATCHDOG_MOCK_AP_ACTIVE" = "yes" ] || [ "$WIFI_KIT_RUNTIME_WATCHDOG_MOCK_AP_ACTIVE" = "true" ]
    return $?
  fi
  if [ -f "$nm_ap_lab_script" ]; then
    WIFI_KIT_RUNTIME_CONFIG="$runtime_config" sh "$nm_ap_lab_script" status 2>/dev/null | grep -q '^hotspot_active=true$' && return 0
  fi
  [ -f "$ap_setup_script" ] || return 1
  sh "$ap_setup_script" status 2>/dev/null | grep -q '^test_hostapd_running=yes$'
}

ap_recovery_ui_healthy() {
  if [ -n "${WIFI_KIT_RUNTIME_WATCHDOG_MOCK_AP_UI_HEALTHY:-}" ]; then
    [ "$WIFI_KIT_RUNTIME_WATCHDOG_MOCK_AP_UI_HEALTHY" = "yes" ] || [ "$WIFI_KIT_RUNTIME_WATCHDOG_MOCK_AP_UI_HEALTHY" = "true" ]
    return $?
  fi
  [ -f "$nm_ap_lab_script" ] || return 1
  WIFI_KIT_RUNTIME_CONFIG="$runtime_config" sh "$nm_ap_lab_script" status 2>/dev/null | grep -q '^ui_recovery_healthy=true$'
}

port_listening() {
  port=$1
  ss_bin=$(find_tool ss 2>/dev/null || true)
  if [ -n "$ss_bin" ]; then
    "$ss_bin" -ltn 2>/dev/null | awk '{ print $4 }' | grep -Eq "(^|:)$port$"
    return $?
  fi
  return 1
}

http_healthy() {
  url=$1
  curl_bin=$(find_tool curl 2>/dev/null || true)
  if [ -n "$curl_bin" ]; then
    "$curl_bin" -fsS --max-time 2 "$url" >/dev/null 2>&1
    return $?
  fi
  return 1
}

normal_ui_healthy() {
  if [ -n "${WIFI_KIT_RUNTIME_WATCHDOG_MOCK_NORMAL_UI_HEALTHY:-}" ]; then
    [ "$WIFI_KIT_RUNTIME_WATCHDOG_MOCK_NORMAL_UI_HEALTHY" = "yes" ] || [ "$WIFI_KIT_RUNTIME_WATCHDOG_MOCK_NORMAL_UI_HEALTHY" = "true" ]
    return $?
  fi
  if http_healthy "http://127.0.0.1:$normal_ui_port/api/backend-status"; then
    return 0
  fi
  port_listening "$normal_ui_port"
}

ensure_normal_ui() {
  if normal_ui_healthy; then
    return 0
  fi
  log_event "ui-http-unhealthy" "ui=normal port=$normal_ui_port action=restart-service"
  if [ "$debug_passive" = "true" ]; then
    log_event "debug-passive-suppressed-action" "would_restart_normal_ui=yes service=$normal_ui_service"
    return 0
  fi
  systemctl_bin=$(find_tool systemctl 2>/dev/null || true)
  [ -n "$systemctl_bin" ] || {
    log_event "ui-normal-restart-failed" "reason=systemctl-missing service=$normal_ui_service"
    return 1
  }
  set +e
  "$systemctl_bin" restart "$normal_ui_service" >> "$log_file" 2>&1
  ui_restart_rc=$?
  set -e
  if [ "$ui_restart_rc" -eq 0 ]; then
    log_event "ui-normal-restarted" "result=success service=$normal_ui_service port=$normal_ui_port"
    return 0
  fi
  log_event "ui-normal-restart-failed" "result=failure exit_code=$ui_restart_rc service=$normal_ui_service"
  return "$ui_restart_rc"
}

ensure_ap_recovery_ui() {
  if ap_recovery_ui_healthy; then
    log_event "recovery-ui-healthy" "ap_recovery_active=yes"
    return 0
  fi
  log_event "ui-http-unhealthy" "ui=recovery port=80 ap_recovery_active=yes"
  log_event "recovery-ui-missing" "ap_recovery_active=yes action=start-ui"
  if [ "$debug_passive" = "true" ]; then
    log_event "debug-passive-suppressed-action" "would_start_recovery_ui=yes"
    write_state "ap-recovery-active" "recovery-ui-missing-debug-passive" "$last_good_ssid"
    return 0
  fi
  [ -f "$nm_ap_lab_script" ] || {
    log_event "recovery-ui-restart-failed" "reason=nm-ap-lab-script-missing"
    return 1
  }
  set +e
  WIFI_KIT_RUNTIME_CONFIG="$runtime_config" WIFI_KIT_NM_AP_LAB_APPLY=1 sh "$nm_ap_lab_script" start-ui >> "$log_file" 2>&1
  ui_start_rc=$?
  set -e
  if [ "$ui_start_rc" -eq 0 ]; then
    log_event "recovery-ui-restarted" "result=success exit_code=$ui_start_rc"
    return 0
  fi
  log_event "recovery-ui-restart-failed" "result=failure exit_code=$ui_start_rc"
  return "$ui_start_rc"
}

config_values() {
  enabled_raw=$(runtime_value runtime_recovery_enabled true)
  enabled=$(normalize_bool "$enabled_raw")
  debug_passive_raw=$(runtime_value runtime_recovery_debug_passive true)
  debug_passive=$(normalize_bool "$debug_passive_raw")
  grace_seconds=$(runtime_value runtime_recovery_grace_seconds 30)
  internet_required_raw=$(runtime_value runtime_recovery_internet_required true)
  internet_required=$(normalize_bool "$internet_required_raw")
  internet_probe=$(runtime_value runtime_recovery_internet_probe "${WIFI_KIT_RUNTIME_WATCHDOG_INTERNET_PROBE:-1.1.1.1}")
  internet_ping_status=$(ping_internet_probe)
  minimal_ap_safety_seconds="${WIFI_KIT_RUNTIME_WATCHDOG_MINIMAL_AP_SAFETY_SECONDS:-300}"
  critical_link_loss_seconds=$(runtime_value runtime_recovery_critical_link_loss_seconds "${WIFI_KIT_RUNTIME_WATCHDOG_CRITICAL_LINK_LOSS_SECONDS:-300}")
  min_unavailable_seconds="${WIFI_KIT_RUNTIME_WATCHDOG_MIN_UNAVAILABLE_SECONDS:-0}"
  window_minutes=$(runtime_value runtime_recovery_instability_window_minutes 10)
  threshold=$(runtime_value runtime_recovery_instability_threshold 3)
  last_good_ssid=$(runtime_value last_good_ssid "")
  last_good_connection=$(runtime_value last_good_connection "")
  return_connection=$(runtime_value return_connection "")
  current_connection=$(active_connection)
  current_ssid=$(active_ssid)
  runtime_config_readable=$([ -r "$runtime_config" ] && printf yes || printf no)
  last_good_configured=no
  if [ -n "$last_good_ssid" ] || [ -n "$last_good_connection" ]; then
    last_good_configured=yes
  fi
  iface_ipv4=$(iface_ipv4_addr)
  default_route=$(default_route_info)
  default_route_present=no
  [ -n "$default_route" ] && default_route_present=yes
  gateway=$(route_gateway "$default_route")
  gateway_ping_status=$(ping_gateway)
  runtime_match="false"
  runtime_reason="disconnected"
  health_status="unhealthy"
  health_reason="disconnected"
  recovery_decision="none"
  unstable_ssid=$(state_value unstable_ssid)
  unstable_count=$(state_value unstable_count)
  unstable_triggered=$(state_value unstable_triggered)
  if [ -z "$unstable_ssid" ] && [ -r "$instability_file" ]; then
    unstable_ssid=$(sed -n 's/^unstable_ssid=//p' "$instability_file" 2>/dev/null | sed -n '1p')
  fi
  if [ -z "$unstable_count" ] && [ -r "$instability_file" ]; then
    unstable_count=$(sed -n 's/^unstable_count=//p' "$instability_file" 2>/dev/null | sed -n '1p')
  fi
  case "$unstable_count" in
    ''|*[!0-9]*) unstable_count=0 ;;
  esac
  case "$unstable_triggered" in
    yes|true) unstable_triggered=yes ;;
    *) unstable_triggered=no ;;
  esac
  watchdog_status=$(state_value status)
  status="ok"
  reason=""

  case "$enabled" in
    true|false) ;;
    *) status="refused"; reason="runtime-recovery-enabled-invalid" ;;
  esac
  case "$debug_passive" in
    true|false) ;;
    *) status="refused"; reason="${reason:-runtime-recovery-debug-passive-invalid}" ;;
  esac
  case "$internet_required" in
    true|false) ;;
    *) status="refused"; reason="${reason:-runtime-recovery-internet-required-invalid}" ;;
  esac
  case "$grace_seconds" in
    ''|*[!0-9]*)
      status="refused"
      reason="${reason:-runtime-recovery-grace-invalid}"
      grace_seconds=30
      ;;
  esac
  case "$min_unavailable_seconds" in
    ''|*[!0-9]*) min_unavailable_seconds=0 ;;
  esac
  case "$minimal_ap_safety_seconds" in
    ''|*[!0-9]*) minimal_ap_safety_seconds=300 ;;
  esac
  case "$critical_link_loss_seconds" in
    ''|*[!0-9]*) critical_link_loss_seconds=300 ;;
  esac
  if [ "$critical_link_loss_seconds" -lt 1 ]; then
    critical_link_loss_seconds=300
  fi
  if [ -z "$internet_probe" ]; then
    status="refused"
    reason="${reason:-runtime-recovery-internet-probe-invalid}"
  fi
  if ! is_positive_integer "$window_minutes"; then
    status="refused"
    reason="${reason:-runtime-recovery-window-invalid}"
  fi
  if ! is_positive_integer "$threshold"; then
    status="refused"
    reason="${reason:-runtime-recovery-threshold-invalid}"
  fi
  if is_positive_integer "$threshold" && [ "$unstable_count" -ge "$threshold" ]; then
    if [ -z "$unstable_ssid" ] || [ -z "$last_good_ssid" ] || [ "$unstable_ssid" = "$last_good_ssid" ]; then
      unstable_triggered=yes
    fi
  fi
  classify_bootstrap_state
  if [ "$enabled" = "true" ] && [ -z "$last_good_ssid" ] && [ -z "$last_good_connection" ]; then
    reason="${reason:-$bootstrap_state}"
  fi
  effective_grace_seconds=$grace_seconds
  if [ "$effective_grace_seconds" -gt 0 ] && [ "$effective_grace_seconds" -lt "$min_unavailable_seconds" ]; then
    effective_grace_seconds=$min_unavailable_seconds
  fi
  if [ -n "$last_good_connection" ] && [ "$current_connection" = "$last_good_connection" ]; then
    runtime_match="true"
    runtime_reason="matched-last-good"
  elif [ -n "$last_good_ssid" ] && [ "$current_ssid" = "$last_good_ssid" ]; then
    runtime_match="true"
    runtime_reason="matched-last-good"
  elif [ -z "$current_connection" ] && [ -z "$current_ssid" ]; then
    runtime_reason="disconnected"
  elif [ -n "$return_connection" ] && [ "$current_connection" = "$return_connection" ]; then
    runtime_reason="mismatch-return-connection"
  else
    runtime_reason="mismatch-last-good"
  fi
  classify_health
  if minimal_ap_safety_active && [ "$effective_grace_seconds" -lt "$minimal_ap_safety_seconds" ]; then
    effective_grace_seconds=$minimal_ap_safety_seconds
  fi
  critical_link_loss_active=no
  if critical_link_loss_active; then
    critical_link_loss_active=yes
    if [ "$effective_grace_seconds" -lt "$critical_link_loss_seconds" ]; then
      effective_grace_seconds=$critical_link_loss_seconds
    fi
  fi
  classify_recovery_decision
}

is_last_good_active() {
  [ "$runtime_match" = "true" ] && return 0
  return 1
}

is_runtime_healthy() {
  [ "$health_status" = "healthy" ] && return 0
  return 1
}

current_wifi_usable() {
  [ -n "$current_connection" ] || return 1
  [ -n "$current_ssid" ] || return 1
  case "$current_ssid" in
    Wifi-Kit-*|wifi-kit-*) return 1 ;;
  esac
  [ -n "$iface_ipv4" ] || return 1
  [ "$default_route_present" = "yes" ] || return 1
  if [ "$internet_required" = "true" ]; then
    [ "$internet_ping_status" = "ok" ] || return 1
  fi
  return 0
}

minimal_ap_safety_active() {
  [ -n "$current_connection" ] || return 1
  [ -n "$current_ssid" ] || return 1
  case "$current_ssid" in
    Wifi-Kit-*|wifi-kit-*) return 1 ;;
  esac
  [ -n "$iface_ipv4" ] || return 1
  [ "$default_route_present" = "yes" ] || return 1
  [ -n "$gateway" ] || return 1
  [ "$gateway_ping_status" = "failed" ] || return 1
  [ "$internet_ping_status" = "failed" ] || return 1
  return 0
}

critical_link_loss_active() {
  [ "$last_good_configured" = "yes" ] || return 1
  [ "$health_status" = "healthy" ] && return 1
  [ "$health_reason" = "ap-recovery-active" ] && return 1
  case "$health_reason" in
    disconnected|no-ip|no-default-route)
      return 0
      ;;
  esac
  if [ -z "$current_connection" ] || [ -z "$current_ssid" ]; then
    return 0
  fi
  case "$runtime_reason" in
    mismatch-last-good|mismatch-return-connection)
      if [ "$gateway_ping_status" = "failed" ] || [ "$default_route_present" != "yes" ] || [ -z "$iface_ipv4" ]; then
        return 0
      fi
      ;;
  esac
  return 1
}

classify_health() {
  if ap_recovery_active; then
    health_status="healthy"
    health_reason="ap-recovery-active"
    return 0
  fi
  if [ "$enabled" = "true" ] && [ "$runtime_config_readable" != "yes" ]; then
    health_status="unhealthy"
    health_reason="config-unreadable"
    return 0
  fi
  if minimal_ap_safety_active; then
    health_status="unhealthy"
    health_reason="gateway-and-internet-unreachable"
    return 0
  fi
  if [ "$enabled" = "true" ] && [ "$last_good_configured" != "yes" ]; then
    if [ "$bootstrap_state" = "baseline-pending" ]; then
      health_status="healthy"
      health_reason="bootstrap-baseline-pending"
      return 0
    fi
    health_status="unhealthy"
    health_reason="onboarding-required"
    return 0
  fi
  if [ "$runtime_match" != "true" ]; then
    if current_wifi_usable; then
      health_status="healthy"
      health_reason="available-current-wifi"
      return 0
    fi
    health_status="unhealthy"
    health_reason="$runtime_reason"
    return 0
  fi
  if [ -z "$iface_ipv4" ]; then
    health_status="unhealthy"
    health_reason="no-ip"
    return 0
  fi
  if [ "$default_route_present" != "yes" ]; then
    health_status="unhealthy"
    health_reason="no-default-route"
    return 0
  fi
  if [ "$internet_required" = "true" ] && [ "$internet_ping_status" = "failed" ]; then
    health_status="unhealthy"
    health_reason="internet-unreachable"
    return 0
  fi
  health_status="healthy"
  health_reason="available-last-good"
}

classify_recovery_decision() {
  recovery_decision="none"
  if ap_recovery_active; then
    recovery_decision="ap-recovery-active"
  elif [ "$effective_grace_seconds" = "0" ] && [ "$health_reason" = "internet-unreachable" ]; then
    recovery_decision="internet-check-disabled-by-timeout-zero"
  elif [ "$health_status" != "healthy" ]; then
    recovery_decision="start-ap-recovery-after-unavailable-grace"
  fi
  if [ "$critical_link_loss_active" = "yes" ] && [ "$recovery_decision" = "start-ap-recovery-after-unavailable-grace" ]; then
    recovery_decision="start-ap-recovery-after-critical-link-loss"
  fi
  if [ "$debug_passive" = "true" ] && [ "$health_reason" != "gateway-and-internet-unreachable" ] && [ "$critical_link_loss_active" != "yes" ] && [ "$recovery_decision" != "none" ] && [ "$recovery_decision" != "ap-recovery-active" ]; then
    recovery_decision="debug-passive-suppressed-$recovery_decision"
  fi
}

record_instability_event() {
  ssid=$1
  [ -n "$ssid" ] || return 0
  ensure_action_dir
  now=$(epoch_seconds)
  window_seconds=$((window_minutes * 60))
  cutoff=$((now - window_seconds))
  tmp="${events_file}.$$"
  if [ -r "$events_file" ]; then
    awk -F'|' -v cutoff="$cutoff" '$1 >= cutoff { print }' "$events_file" > "$tmp" 2>/dev/null || true
  else
    : > "$tmp"
  fi
  printf '%s|%s\n' "$now" "$ssid" >> "$tmp"
  mv "$tmp" "$events_file" 2>/dev/null || true
  chmod 0666 "$events_file" 2>/dev/null || true
  count=$(awk -F'|' -v ssid="$ssid" '$2 == ssid { c++ } END { print c + 0 }' "$events_file" 2>/dev/null || printf '0')
  unstable_count=$count
  if [ "$count" -ge "$threshold" ]; then
    unstable_triggered=yes
    log_event "unstable-ssid" "ssid=$ssid count=$count threshold=$threshold window_minutes=$window_minutes action=diagnostic-only"
    {
      kv "unstable_ssid" "$ssid"
      kv "unstable_count" "$count"
      kv "unstable_window_minutes" "$window_minutes"
      kv "unstable_threshold" "$threshold"
      kv "unstable_triggered" "yes"
      kv "instability_policy" "diagnostic-only"
    } > "$instability_file" 2>/dev/null || true
    chmod 0666 "$instability_file" 2>/dev/null || true
  fi
}

require_root() {
  if [ "$(id -u)" != "0" ]; then
    kv "status" "refused"
    kv "reason" "root-required"
    exit 1
  fi
}

start_ap_recovery() {
  trigger=$1
  if ap_recovery_active; then
    log_event "ap-recovery-already-active" "trigger=$trigger"
    write_state "ap-recovery-active" "$trigger" "$last_good_ssid"
    return 0
  fi
  if [ "$debug_passive" = "true" ] && [ "$trigger" != "gateway-and-internet-unreachable" ]; then
    if [ "$trigger" = "critical-link-loss" ]; then
      log_event "debug-passive-bypass-critical-link-loss" "trigger=$trigger health_reason=$health_reason runtime_reason=$runtime_reason elapsed_grace=$effective_grace_seconds critical_link_loss_seconds=$critical_link_loss_seconds"
    else
    log_event "debug-passive-suppressed-action" "would_start_ap_recovery=yes trigger=$trigger health_reason=$health_reason runtime_reason=$runtime_reason current_connection=${current_connection:-unknown} current_ssid=${current_ssid:-unknown} last_good_connection=${last_good_connection:-unknown} last_good_ssid=${last_good_ssid:-unknown} unstable_count=${unstable_count:-0} threshold=$threshold"
    write_state "debug-passive-suppressed-action" "$trigger" "$last_good_ssid"
    return 0
    fi
  fi
  if [ "$debug_passive" = "true" ] && [ "$trigger" = "gateway-and-internet-unreachable" ]; then
    log_event "minimal-ap-safety-bypass-debug-passive" "trigger=$trigger gateway=$gateway gateway_ping=$gateway_ping_status internet_ping=$internet_ping_status elapsed_grace=$effective_grace_seconds"
  fi
  log_event "recovery-enter" "trigger=$trigger last_good_ssid=${last_good_ssid:-unknown} health_reason=$health_reason runtime_reason=$runtime_reason grace_seconds=$effective_grace_seconds"
  log_event "starting-ap-recovery" "trigger=$trigger action=start-ap-recovery last_good_ssid=${last_good_ssid:-unknown} health_reason=$health_reason unstable_count=${unstable_count:-0} threshold=$threshold"
  write_state "starting-ap-recovery" "$trigger" "$last_good_ssid"
  set +e
  WIFI_KIT_AP_START_RETURN_CHECK_LOOP=1 WIFI_KIT_RUNTIME_CONFIG="$runtime_config" sh "$action_wrapper" start-ap-mode >> "$log_file" 2>&1
  ap_start_rc=$?
  set -e
  if [ "$ap_start_rc" -eq 0 ]; then
    log_event "ap-start-result" "trigger=$trigger result=success exit_code=$ap_start_rc"
    return 0
  fi
  log_event "ap-start-failed" "trigger=$trigger result=failure exit_code=$ap_start_rc"
  write_state "ap-start-failed" "$trigger" "$last_good_ssid"
  return "$ap_start_rc"
}

cmd_audit() {
  config_values
  section "runtime-watchdog-audit"
  kv "mode" "audit"
  kv "network_writes" "false"
  kv "runtime_config" "$runtime_config"
  kv "runtime_config_readable" "$([ -r "$runtime_config" ] && printf yes || printf no)"
  kv "runtime_recovery_enabled" "$enabled"
  kv "runtime_recovery_enabled_raw" "$enabled_raw"
  kv "runtime_recovery_debug_passive" "$debug_passive"
  kv "runtime_recovery_debug_passive_raw" "$debug_passive_raw"
  kv "runtime_recovery_grace_seconds" "$grace_seconds"
  kv "runtime_recovery_effective_grace_seconds" "$effective_grace_seconds"
  kv "runtime_recovery_minimal_ap_safety_seconds" "$minimal_ap_safety_seconds"
  kv "runtime_recovery_critical_link_loss_seconds" "$critical_link_loss_seconds"
  kv "runtime_recovery_critical_link_loss_active" "$critical_link_loss_active"
  if minimal_ap_safety_active; then
    kv "runtime_recovery_minimal_ap_safety_active" "yes"
  else
    kv "runtime_recovery_minimal_ap_safety_active" "no"
  fi
  kv "runtime_recovery_min_unavailable_seconds" "$min_unavailable_seconds"
  kv "runtime_recovery_internet_required" "$internet_required"
  kv "runtime_recovery_internet_required_raw" "$internet_required_raw"
  kv "runtime_recovery_internet_probe" "$internet_probe"
  kv "runtime_recovery_instability_window_minutes" "$window_minutes"
  kv "runtime_recovery_instability_threshold" "$threshold"
  kv "runtime_recovery_instability_policy" "diagnostic-only"
  kv "runtime_config_readable" "$runtime_config_readable"
  kv "last_good_configured" "$last_good_configured"
  kv "last_good_ssid" "$last_good_ssid"
  kv "last_good_connection" "$last_good_connection"
  kv "return_connection" "$return_connection"
  kv "current_ssid" "$current_ssid"
  kv "current_connection" "$current_connection"
  kv "ip" "$iface_ipv4"
  kv "default_route" "$default_route_present"
  kv "gateway" "$gateway"
  kv "gateway_ping" "$gateway_ping_status"
  kv "internet_ping" "$internet_ping_status"
  kv "bootstrap_state" "$bootstrap_state"
  kv "bootstrap_source" "$bootstrap_source"
  kv "baseline_quality" "$baseline_quality"
  kv "runtime_match" "$runtime_match"
  kv "runtime_reason" "$runtime_reason"
  kv "health_status" "$health_status"
  kv "health_reason" "$health_reason"
  if ap_recovery_ui_healthy; then
    kv "ap_recovery_ui_healthy" "yes"
  else
    kv "ap_recovery_ui_healthy" "no"
  fi
  kv "unstable_triggered" "$unstable_triggered"
  kv "unstable_count" "$unstable_count"
  kv "unstable_threshold" "$threshold"
  kv "recovery_decision" "$recovery_decision"
  kv "ap_recovery_active" "$(ap_recovery_active && printf yes || printf no)"
  kv "watchdog_state_file" "$state_file"
  kv "watchdog_persistent_state_file" "$persistent_state_file"
  kv "watchdog_persistent_log_file" "$persistent_log_file"
  kv "watchdog_instability_file" "$instability_file"
  kv "normal_ui_healthy" "$(normal_ui_healthy && printf yes || printf no)"
  kv "watchdog_status" "${watchdog_status:-unknown}"
  kv "unstable_ssid" "${unstable_ssid:-}"
  kv "status" "$status"
  if [ -n "$reason" ]; then
    kv "reason" "$reason"
  fi
}

cmd_plan() {
  cmd_audit
  section "runtime-watchdog-plan"
  kv "network_writes" "false"
  kv "runtime_scope" "watch last_good only; never try return_connection"
  kv "01.detect" "when last_good was active and wlan0 leaves it, record runtime-disconnect detected"
  kv "02.grace" "wait until runtime is unavailable continuously for effective grace"
  kv "02b.timeout" "runtime_recovery_grace_seconds defaults to 30; 0 disables AP recovery for internet-only failures"
  kv "02c.instability" "short repeated failures are logged as diagnostic-only; they do not force AP by themselves"
  kv "02c.internet" "if runtime_recovery_internet_required=true, internet probe failure can trigger AP after grace"
  kv "02d.bootstrap" "if last_good is absent and current Wi-Fi is healthy, write the initial baseline to runtime.conf only"
  kv "02e.critical" "critical link loss bypasses debug_passive after runtime_recovery_critical_link_loss_seconds"
  kv "03.cancel" "if last_good returns during grace, log recovery-cancelled link-restored"
  kv "04.recover" "if still disconnected from last_good, or gateway+internet stay unreachable past safety grace, call wrapper start-ap-mode"
  kv "05.ap" "AP return-check loop handles periodic last_good retry from AP recovery"
  kv "debug_passive" "if runtime_recovery_debug_passive=true, suppress start-ap-mode except the prolonged gateway+internet safety net"
  kv "non_actions" "no reboot, no profile deletion, no AP+STA permanent mode, no return_connection runtime retry"
}

cmd_run() {
  require_root
  config_values
  if [ "$last_good_configured" != "yes" ]; then
    if current_wifi_baseline_eligible; then
      auto_baseline_current_wifi || log_event "bootstrap-baseline-failed" "current_connection=${current_connection:-unknown} current_ssid=${current_ssid:-unknown}"
      config_values
    else
      log_event "bootstrap-onboarding-required" "reason=no-current-healthy-wifi current_connection=${current_connection:-unknown} current_ssid=${current_ssid:-unknown} ip=${iface_ipv4:-none} default_route=$default_route_present gateway=${gateway:-none} gateway_ping=$gateway_ping_status"
    fi
  fi
  if ! is_positive_integer "$ui_repair_min_seconds"; then
    ui_repair_min_seconds=60
  fi
  section "runtime-watchdog-run"
  kv "mode" "run"
  kv "log_file" "$log_file"
  kv "state_file" "$state_file"
  kv "persistent_log_file" "$persistent_log_file"
  kv "persistent_state_file" "$persistent_state_file"
  kv "poll_seconds" "$poll_seconds"
  if [ "$enabled" != "true" ]; then
    kv "status" "refused"
    kv "reason" "runtime-recovery-disabled"
    log_event "refused" "runtime-recovery-disabled"
    write_state "disabled" "runtime-recovery-disabled" ""
    exit 0
  fi
  if [ "$status" != "ok" ] && [ "$reason" != "last-good-missing" ]; then
    kv "status" "refused"
    kv "reason" "$reason"
    log_event "refused" "${reason:-runtime-recovery-disabled}"
    write_state "disabled" "$reason" ""
    exit 0
  fi
  kv "status" "started"
  log_event "started" "grace_seconds=$grace_seconds effective_grace_seconds=$effective_grace_seconds"
  write_state "watching" "started" "$last_good_ssid"

  grace_active=0
  grace_start=0
  last_ui_repair_attempt=0
  last_normal_ui_repair_attempt=0
  while :; do
    config_values
    if [ "$last_good_configured" != "yes" ] && current_wifi_baseline_eligible; then
      auto_baseline_current_wifi || log_event "bootstrap-baseline-failed" "current_connection=${current_connection:-unknown} current_ssid=${current_ssid:-unknown}"
      config_values
    fi
    if [ "$enabled" != "true" ]; then
      log_event "stopping" "runtime-recovery-disabled"
      write_state "disabled" "runtime-recovery-disabled" ""
      exit 0
    fi
    if [ "$status" != "ok" ] && [ "$reason" != "last-good-missing" ]; then
      log_event "stopping" "$reason"
      write_state "disabled" "$reason" ""
      exit 0
    fi
    if ap_recovery_active; then
      grace_active=0
      if ! ap_recovery_ui_healthy; then
        now=$(epoch_seconds)
        if [ "$last_ui_repair_attempt" -eq 0 ] || [ $((now - last_ui_repair_attempt)) -ge 30 ]; then
          last_ui_repair_attempt=$now
          ensure_ap_recovery_ui || true
        else
          log_event "recovery-ui-missing" "ap_recovery_active=yes action=retry-wait"
        fi
      else
        last_ui_repair_attempt=0
      fi
      write_state "ap-recovery-active" "watchdog-idle" "$last_good_ssid"
      sleep "$poll_seconds"
      continue
    fi
    if ! normal_ui_healthy; then
      now=$(epoch_seconds)
      if [ "$last_normal_ui_repair_attempt" -eq 0 ] || [ $((now - last_normal_ui_repair_attempt)) -ge "$ui_repair_min_seconds" ]; then
        last_normal_ui_repair_attempt=$now
        ensure_normal_ui || true
      fi
    else
      last_normal_ui_repair_attempt=0
    fi
    if is_runtime_healthy; then
      if [ "$grace_active" = "1" ]; then
        log_event "recovery-cancelled link-restored" "ssid=${current_ssid:-unknown} health_reason=$health_reason unstable_count=${unstable_count:-0} instability_policy=diagnostic-only"
      fi
      grace_active=0
      write_state "watching" "$health_reason" "${current_ssid:-$last_good_ssid}"
      sleep "$poll_seconds"
      continue
    fi
    if [ "$grace_active" != "1" ]; then
      grace_active=1
      grace_start=$(epoch_seconds)
      log_event "runtime-unavailable detected" "health_reason=$health_reason runtime_reason=$runtime_reason last_good_ssid=${last_good_ssid:-unknown} current_ssid=${current_ssid:-unknown} current_connection=${current_connection:-unknown}"
      log_event "grace-period started" "seconds=$effective_grace_seconds configured_seconds=$grace_seconds"
      if [ "$critical_link_loss_active" = "yes" ]; then
        log_event "critical-link-loss-detected" "health_reason=$health_reason runtime_reason=$runtime_reason current_connection=${current_connection:-unknown} current_ssid=${current_ssid:-unknown} ip=${iface_ipv4:-none} default_route=$default_route_present gateway=${gateway:-none} gateway_ping=$gateway_ping_status"
        log_event "critical-link-loss-grace-started" "seconds=$effective_grace_seconds configured_seconds=$critical_link_loss_seconds"
      fi
      write_state "grace-period" "$health_reason" "$last_good_ssid"
      if [ -n "$last_good_ssid" ]; then
        record_instability_event "$last_good_ssid"
      fi
    fi
    now=$(epoch_seconds)
    elapsed=$((now - grace_start))
    if [ "$critical_link_loss_active" = "yes" ]; then
      log_event "critical-link-loss-elapsed" "critical-link-loss-elapsed-seconds=$elapsed threshold=$critical_link_loss_seconds health_reason=$health_reason runtime_reason=$runtime_reason recovery_decision=$recovery_decision"
    fi
    if [ "$effective_grace_seconds" = "0" ] && [ "$health_reason" = "internet-unreachable" ]; then
      log_event "internet-check-timeout-zero" "health_reason=$health_reason recovery_decision=$recovery_decision"
      grace_active=0
      write_state "watching" "$health_reason" "${current_ssid:-$last_good_ssid}"
      sleep "$poll_seconds"
      continue
    fi
    if [ "$elapsed" -lt "$effective_grace_seconds" ]; then
      sleep "$poll_seconds"
      continue
    fi
    if ap_recovery_active; then
      grace_active=0
      sleep "$poll_seconds"
      continue
    fi
    if [ "$debug_passive" = "true" ]; then
      trigger=$health_reason
      if [ "$critical_link_loss_active" = "yes" ]; then
        trigger="critical-link-loss"
      fi
      start_ap_recovery "$trigger"
      grace_active=0
      sleep "$poll_seconds"
      continue
    fi
    trigger=$health_reason
    if [ "$critical_link_loss_active" = "yes" ]; then
      trigger="critical-link-loss"
    fi
    start_ap_recovery "$trigger" || true
    grace_active=0
    sleep "$poll_seconds"
  done
}

if [ "$#" -ne 1 ]; then
  usage
  exit 2
fi

case "$1" in
  audit) cmd_audit ;;
  plan) cmd_plan ;;
  run) cmd_run ;;
  -h|--help|help) usage ;;
  *) usage; exit 2 ;;
esac
