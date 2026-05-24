#!/bin/sh
set -eu

runtime_config="${WIFI_KIT_RUNTIME_CONFIG:-${HOME:-/tmp}/.config/wifi-kit/runtime.conf}"
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
action_wrapper="$script_dir/wifi-kit-action-wrapper.sh"
ap_setup_script="$script_dir/ap-setup-test.sh"
iface="${WIFI_KIT_RUNTIME_WATCHDOG_IFACE:-wlan0}"
poll_seconds="${WIFI_KIT_RUNTIME_WATCHDOG_POLL_SECONDS:-5}"
log_file="${WIFI_KIT_RUNTIME_WATCHDOG_LOG:-/tmp/wifi-kit-actions/runtime-watchdog-$(id -u).log}"
state_file="${WIFI_KIT_RUNTIME_WATCHDOG_STATE:-/tmp/wifi-kit-actions/runtime-watchdog-state}"
events_file="${WIFI_KIT_RUNTIME_WATCHDOG_EVENTS:-/tmp/wifi-kit-actions/runtime-watchdog-events.log}"
instability_file="${WIFI_KIT_RUNTIME_WATCHDOG_INSTABILITY:-/tmp/wifi-kit-actions/runtime-watchdog-instability}"

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

log_event() {
  status=$1
  detail=${2:-}
  ensure_action_dir
  {
    printf 'timestamp=%s action=runtime-watchdog status=%s' "$(timestamp)" "$status"
    if [ -n "$detail" ]; then
      printf ' detail=%s' "$detail"
    fi
    printf '\n'
  } >> "$log_file" 2>/dev/null || true
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
    kv "current_connection" "${current_connection:-}"
    kv "current_ssid" "${current_ssid:-}"
    kv "last_good_connection" "${last_good_connection:-}"
    kv "last_good_ssid" "${last_good_ssid:-}"
    kv "iface" "$iface"
    kv "runtime_config" "$runtime_config"
    kv "log_file" "$log_file"
  } > "$state_file" 2>/dev/null || true
  chmod 0666 "$state_file" 2>/dev/null || true
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

ap_recovery_active() {
  [ -f "$ap_setup_script" ] || return 1
  sh "$ap_setup_script" status 2>/dev/null | grep -q '^test_hostapd_running=yes$'
}

config_values() {
  enabled_raw=$(runtime_value runtime_recovery_enabled true)
  enabled=$(normalize_bool "$enabled_raw")
  debug_passive_raw=$(runtime_value runtime_recovery_debug_passive false)
  debug_passive=$(normalize_bool "$debug_passive_raw")
  grace_seconds=$(runtime_value runtime_recovery_grace_seconds 30)
  window_minutes=$(runtime_value runtime_recovery_instability_window_minutes 10)
  threshold=$(runtime_value runtime_recovery_instability_threshold 3)
  last_good_ssid=$(runtime_value last_good_ssid "")
  last_good_connection=$(runtime_value last_good_connection "")
  return_connection=$(runtime_value return_connection "")
  current_connection=$(active_connection)
  current_ssid=$(active_ssid)
  runtime_match="false"
  runtime_reason="disconnected"
  unstable_ssid=$(state_value unstable_ssid)
  if [ -z "$unstable_ssid" ] && [ -r "$instability_file" ]; then
    unstable_ssid=$(sed -n 's/^unstable_ssid=//p' "$instability_file" 2>/dev/null | sed -n '1p')
  fi
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
  if ! is_positive_integer "$grace_seconds"; then
    status="refused"
    reason="${reason:-runtime-recovery-grace-invalid}"
  fi
  if ! is_positive_integer "$window_minutes"; then
    status="refused"
    reason="${reason:-runtime-recovery-window-invalid}"
  fi
  if ! is_positive_integer "$threshold"; then
    status="refused"
    reason="${reason:-runtime-recovery-threshold-invalid}"
  fi
  if [ "$enabled" = "true" ] && [ -z "$last_good_ssid" ] && [ -z "$last_good_connection" ]; then
    status="refused"
    reason="${reason:-last-good-missing}"
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
}

is_last_good_active() {
  [ "$runtime_match" = "true" ] && return 0
  return 1
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
  if [ "$count" -ge "$threshold" ]; then
    log_event "unstable-ssid" "ssid=$ssid count=$count window_minutes=$window_minutes"
    {
      kv "unstable_ssid" "$ssid"
      kv "unstable_count" "$count"
      kv "unstable_window_minutes" "$window_minutes"
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
  kv "runtime_recovery_instability_window_minutes" "$window_minutes"
  kv "runtime_recovery_instability_threshold" "$threshold"
  kv "last_good_ssid" "$last_good_ssid"
  kv "last_good_connection" "$last_good_connection"
  kv "return_connection" "$return_connection"
  kv "current_ssid" "$current_ssid"
  kv "current_connection" "$current_connection"
  kv "runtime_match" "$runtime_match"
  kv "runtime_reason" "$runtime_reason"
  kv "ap_recovery_active" "$(ap_recovery_active && printf yes || printf no)"
  kv "watchdog_state_file" "$state_file"
  kv "watchdog_instability_file" "$instability_file"
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
  kv "02.grace" "wait runtime_recovery_grace_seconds"
  kv "03.cancel" "if last_good returns during grace, log recovery-cancelled link-restored"
  kv "04.recover" "if still disconnected from last_good, call wrapper start-ap-mode"
  kv "05.ap" "AP return-check loop handles periodic last_good retry from AP recovery"
  kv "debug_passive" "if runtime_recovery_debug_passive=true, log the decision but suppress start-ap-mode"
  kv "non_actions" "no reboot, no profile deletion, no AP+STA permanent mode, no return_connection runtime retry"
}

cmd_run() {
  require_root
  config_values
  section "runtime-watchdog-run"
  kv "mode" "run"
  kv "log_file" "$log_file"
  kv "state_file" "$state_file"
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
  log_event "started" "grace_seconds=$grace_seconds"
  write_state "watching" "started" "$last_good_ssid"

  grace_active=0
  grace_start=0
  while :; do
    config_values
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
    if [ -z "$last_good_ssid" ] && [ -z "$last_good_connection" ]; then
      write_state "waiting-last-good" "last-good-missing" ""
      sleep "$poll_seconds"
      continue
    fi
    if ap_recovery_active; then
      grace_active=0
      write_state "ap-recovery-active" "watchdog-idle" "$last_good_ssid"
      sleep "$poll_seconds"
      continue
    fi
    if is_last_good_active; then
      if [ "$grace_active" = "1" ]; then
        log_event "recovery-cancelled link-restored" "ssid=${current_ssid:-unknown}"
      fi
      grace_active=0
      write_state "watching" "last-good-active" "${current_ssid:-$last_good_ssid}"
      sleep "$poll_seconds"
      continue
    fi
    if [ "$grace_active" != "1" ]; then
      grace_active=1
      grace_start=$(epoch_seconds)
      log_event "runtime-disconnect detected" "reason=$runtime_reason last_good_ssid=$last_good_ssid current_ssid=${current_ssid:-unknown} current_connection=${current_connection:-unknown}"
      log_event "grace-period started" "seconds=$grace_seconds"
      write_state "grace-period" "$runtime_reason" "$last_good_ssid"
      record_instability_event "$last_good_ssid"
    fi
    now=$(epoch_seconds)
    elapsed=$((now - grace_start))
    if [ "$elapsed" -lt "$grace_seconds" ]; then
      sleep "$poll_seconds"
      continue
    fi
    if ap_recovery_active; then
      grace_active=0
      sleep "$poll_seconds"
      continue
    fi
    if [ "$debug_passive" = "true" ]; then
      log_event "debug-passive-suppressed-action" "would_start_ap_recovery=yes runtime_reason=$runtime_reason current_connection=${current_connection:-unknown} current_ssid=${current_ssid:-unknown} last_good_connection=${last_good_connection:-unknown} last_good_ssid=${last_good_ssid:-unknown} grace_seconds=$grace_seconds"
      write_state "debug-passive-suppressed-action" "$runtime_reason" "$last_good_ssid"
      grace_active=0
      sleep "$poll_seconds"
      continue
    fi
    log_event "starting-ap-recovery" "last_good_ssid=$last_good_ssid grace_seconds=$grace_seconds"
    write_state "starting-ap-recovery" "grace-expired" "$last_good_ssid"
    WIFI_KIT_RUNTIME_CONFIG="$runtime_config" sh "$action_wrapper" start-ap-mode >> "$log_file" 2>&1 || true
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
