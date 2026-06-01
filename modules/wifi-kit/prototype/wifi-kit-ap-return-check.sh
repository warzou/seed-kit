#!/bin/sh
set -eu

runtime_config="${WIFI_KIT_RUNTIME_CONFIG:-${HOME:-/tmp}/.config/wifi-kit/runtime.conf}"

usage() {
  cat <<'EOF'
wifi-kit AP return check prototype

Usage:
  sh modules/wifi-kit/prototype/wifi-kit-ap-return-check.sh audit
  sh modules/wifi-kit/prototype/wifi-kit-ap-return-check.sh plan
  sudo sh modules/wifi-kit/prototype/wifi-kit-ap-return-check.sh run-once
  sudo sh modules/wifi-kit/prototype/wifi-kit-ap-return-check.sh run-loop
  sudo sh modules/wifi-kit/prototype/wifi-kit-ap-return-check.sh stop-loop

Modes:
  audit  Read runtime config and resolve the future AP return-check target.
  plan   Print the future AP recovery return-check flow. No network writes.
  run-once
         If AP recovery is active and return_check_enabled=true, stop AP
         recovery, try the configured target once with bounded timeouts, and
         restart AP recovery if the return attempt fails.
  run-loop
         From AP recovery only, sleep return_check_interval_seconds between
         run-once attempts. 0 disables automatic return checks.
  stop-loop
         Stop the background AP return-check loop, if it is running.

This helper never stores or logs client Wi-Fi passwords. The run-once mode is
for controlled AP recovery testing only.
EOF
}

iface="${WIFI_KIT_RETURN_CHECK_IFACE:-wlan0}"
connect_wait_seconds="${WIFI_KIT_RETURN_CHECK_CONNECT_WAIT:-30}"
ping_wait_seconds="${WIFI_KIT_RETURN_CHECK_PING_WAIT:-3}"
default_internet_probe="${WIFI_KIT_RETURN_CHECK_PROBE:-1.1.1.1}"
ap_restart_wait_seconds="${WIFI_KIT_RETURN_CHECK_AP_RESTART_WAIT:-30}"
ap_min_stable_seconds="${WIFI_KIT_RETURN_CHECK_AP_MIN_STABLE_SECONDS:-120}"
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ap_setup_script="$script_dir/ap-setup-test.sh"
action_wrapper="$script_dir/wifi-kit-action-wrapper.sh"
log_file="${WIFI_KIT_RETURN_CHECK_LOG:-/tmp/wifi-kit-actions/ap-return-check-$(id -u).log}"
loop_pid_file="${WIFI_KIT_RETURN_CHECK_LOOP_PID:-/tmp/wifi-kit-ap-return-check-loop.pid}"
run_once_pid_file="${WIFI_KIT_RETURN_CHECK_RUN_ONCE_PID:-/tmp/wifi-kit-ap-return-check-run-once.pid}"

kv() {
  printf '%s=%s\n' "$1" "$2"
}

section() {
  printf '\n[%s]\n' "$1"
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

is_positive_integer() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    0) return 1 ;;
    *) return 0 ;;
  esac
}

is_non_negative_integer() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

log_event() {
  event_status=$1
  detail=${2:-}
  mkdir -p /tmp/wifi-kit-actions 2>/dev/null || true
  chmod 1777 /tmp/wifi-kit-actions 2>/dev/null || true
  {
    printf 'timestamp=%s action=ap-return-check status=%s' "$(timestamp)" "$event_status"
    if [ -n "$detail" ]; then
      printf ' detail=%s' "$detail"
    fi
    printf '\n'
  } >>"$log_file" 2>/dev/null || true
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

return_check_enabled() {
  runtime_value return_check_enabled false
}

normalize_bool() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes|on) printf 'true' ;;
    false|0|no|off|'') printf 'false' ;;
    *) printf 'invalid' ;;
  esac
}

return_check_interval_minutes() {
  runtime_value return_check_interval_minutes 1
}

return_check_interval_seconds() {
  seconds=$(runtime_value return_check_interval_seconds "")
  if [ -n "$seconds" ]; then
    printf '%s\n' "$seconds"
    return 0
  fi
  minutes=$(return_check_interval_minutes)
  if is_non_negative_integer "$minutes"; then
    printf '%s\n' "$((minutes * 60))"
    return 0
  fi
  printf '300\n'
}

internet_required() {
  normalize_bool "$(runtime_value runtime_recovery_internet_required true)"
}

internet_probe() {
  runtime_value runtime_recovery_internet_probe "$default_internet_probe"
}

return_check_target() {
  runtime_value return_check_target last_good_ssid
}

return_check_mode() {
  runtime_value return_check_mode periodic-from-ap
}

target_ssid_for() {
  target=$1
  case "$target" in
    last_good_ssid|last_good_connection)
      runtime_value last_good_ssid ""
      ;;
    *)
      printf ''
      ;;
  esac
}

target_connection_for() {
  target=$1
  case "$target" in
    last_good_ssid|last_good_connection)
      runtime_value last_good_connection ""
      ;;
    *)
      printf ''
      ;;
  esac
}

connection_ssid() {
  connection=$1
  nmcli_bin=$(find_tool nmcli 2>/dev/null || true)
  [ -n "$nmcli_bin" ] || return 0
  "$nmcli_bin" -g 802-11-wireless.ssid connection show "$connection" 2>/dev/null | sed -n '1p'
}

connection_for_ssid() {
  ssid=$1
  nmcli_bin=$(find_tool nmcli 2>/dev/null || true)
  [ -n "$nmcli_bin" ] || return 0
  "$nmcli_bin" -t --escape no -f NAME,TYPE connection show 2>/dev/null |
    awk -F: '$2 == "802-11-wireless" || $2 == "wifi" { print $1 }' |
    while IFS= read -r connection; do
      [ -n "$connection" ] || continue
      candidate_ssid=$("$nmcli_bin" -g 802-11-wireless.ssid connection show "$connection" 2>/dev/null | sed -n '1p')
      if [ "$candidate_ssid" = "$ssid" ]; then
        printf '%s\n' "$connection"
        return 0
      fi
    done |
    sed -n '1p'
}

connection_exists() {
  connection=$1
  nmcli_bin=$(find_tool nmcli 2>/dev/null || true)
  [ -n "$nmcli_bin" ] || return 1
  [ -n "$connection" ] || return 1
  "$nmcli_bin" connection show "$connection" >/dev/null 2>&1
}

resolve_primary_return_target() {
  preferred_connection=$(runtime_value preferred_connection "")
  preferred_ssid=$(runtime_value preferred_ssid "")
  return_connection=$(runtime_value return_connection "")
  return_ssid=$(runtime_value return_ssid "")
  last_good_connection=$(runtime_value last_good_connection "")
  last_good_ssid=$(runtime_value last_good_ssid "")

  if connection_exists "$preferred_connection"; then
    printf 'preferred_connection|%s|%s\n' "$preferred_connection" "$preferred_ssid"
    return 0
  fi
  resolved=$(connection_for_ssid "$preferred_ssid")
  if [ -n "$resolved" ]; then
    printf 'preferred_ssid|%s|%s\n' "$resolved" "$preferred_ssid"
    return 0
  fi
  if connection_exists "$return_connection"; then
    printf 'return_connection|%s|%s\n' "$return_connection" "$return_ssid"
    return 0
  fi
  resolved=$(connection_for_ssid "$return_ssid")
  if [ -n "$resolved" ]; then
    printf 'return_ssid|%s|%s\n' "$resolved" "$return_ssid"
    return 0
  fi
  if connection_exists "$last_good_connection"; then
    printf 'last_good_connection|%s|%s\n' "$last_good_connection" "$last_good_ssid"
    return 0
  fi
  resolved=$(connection_for_ssid "$last_good_ssid")
  if [ -n "$resolved" ]; then
    printf 'last_good_ssid|%s|%s\n' "$resolved" "$last_good_ssid"
    return 0
  fi
  printf 'missing||\n'
}

ap_recovery_active() {
  [ -f "$ap_setup_script" ] || return 1
  sh "$ap_setup_script" status 2>/dev/null | grep -q '^test_hostapd_running=yes$'
}

wait_ap_recovery_active() {
  timeout=$1
  elapsed=0
  while [ "$elapsed" -le "$timeout" ]; do
    if ap_recovery_active; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

loop_pid() {
  [ -r "$loop_pid_file" ] || return 0
  sed -n '1p' "$loop_pid_file" 2>/dev/null || true
}

is_return_check_pid() {
  pid=$1
  mode=$2
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  ps -p "$pid" -o args= 2>/dev/null | grep -q "wifi-kit-ap-return-check.sh $mode"
}

is_loop_pid() {
  is_return_check_pid "$1" "run-loop"
}

run_once_pid() {
  [ -r "$run_once_pid_file" ] || return 0
  sed -n '1p' "$run_once_pid_file" 2>/dev/null || true
}

stop_loop_best_effort() {
  child_pid=$(run_once_pid)
  if [ -n "$child_pid" ] && is_return_check_pid "$child_pid" "run-once"; then
    log_event "stopping loop" "run_once_pid=$child_pid"
    kill "$child_pid" 2>/dev/null || true
  fi
  rm -f "$run_once_pid_file" 2>/dev/null || true
  pid=$(loop_pid)
  if [ -n "$pid" ] && [ "$pid" != "$$" ] && is_loop_pid "$pid"; then
    log_event "stopping loop" "pid=$pid"
    kill "$pid" 2>/dev/null || true
  fi
  rm -f "$loop_pid_file" 2>/dev/null || true
}

local_network_ok() {
  ip_bin=$(find_tool ip 2>/dev/null || true)
  [ -n "$ip_bin" ] || return 1
  "$ip_bin" -o -4 addr show dev "$iface" scope global 2>/dev/null | grep -q . || return 1
  "$ip_bin" route show default 2>/dev/null | grep -q . || return 1
}

internet_ok() {
  required=$(internet_required)
  [ "$required" = "true" ] || return 0
  ping_bin=$(find_tool ping 2>/dev/null || true)
  [ -n "$ping_bin" ] || return 1
  internet_probe_value=$(internet_probe)
  [ -n "$internet_probe_value" ] || return 1
  "$ping_bin" -c 1 -W "$ping_wait_seconds" "$internet_probe_value" >/dev/null 2>&1
}

require_number() {
  name=$1
  value=$2
  max=$3
  case "$value" in
    ''|*[!0-9]*) kv "status" "refused"; kv "reason" "$name-number-required"; exit 2 ;;
  esac
  [ "$value" -le "$max" ] || { kv "status" "refused"; kv "reason" "$name-too-large"; exit 2; }
}

require_root() {
  if [ "$(id -u)" != "0" ]; then
    kv "status" "refused"
    kv "mode" "run-once"
    kv "reason" "root-required"
    exit 1
  fi
}

audit_values() {
  enabled_raw=$(return_check_enabled)
  enabled=$(normalize_bool "$enabled_raw")
  interval=$(return_check_interval_minutes)
  interval_seconds=$(return_check_interval_seconds)
  internet_required_value=$(internet_required)
  internet_probe_value=$(internet_probe)
  target=$(return_check_target)
  mode=$(return_check_mode)
  preferred_ssid=$(runtime_value preferred_ssid "")
  preferred_connection=$(runtime_value preferred_connection "")
  last_good_ssid=$(runtime_value last_good_ssid "")
  last_good_connection=$(runtime_value last_good_connection "")
  return_ssid=$(runtime_value return_ssid "")
  return_connection=$(runtime_value return_connection "")
  ap_ssid=$(runtime_value ap_ssid "")
  primary_target=$(resolve_primary_return_target)
  target_source=${primary_target%%|*}
  primary_tail=${primary_target#*|}
  target_connection=${primary_tail%%|*}
  target_ssid=${primary_tail#*|}
  status="ok"
  reason=""

  case "$enabled" in
    true|false) ;;
    *) status="refused"; reason="return-check-enabled-invalid" ;;
  esac
  if ! is_non_negative_integer "$interval_seconds"; then
    status="refused"
    reason="${reason:-return-check-interval-seconds-invalid}"
  fi
  if [ "$interval_seconds" = "0" ] && [ "$enabled" = "true" ]; then
    enabled="false"
    reason="${reason:-return-check-disabled-by-interval-zero}"
  fi
  if [ "$internet_required_value" = "invalid" ]; then
    status="refused"
    reason="${reason:-internet-required-invalid}"
  fi
  if [ -z "$internet_probe_value" ]; then
    status="refused"
    reason="${reason:-internet-probe-missing}"
  fi
  if [ "$mode" != "periodic-from-ap" ]; then
    status="refused"
    reason="${reason:-return-check-mode-unsupported}"
  fi
  case "$target" in
    last_good_ssid|last_good_connection|primary|primary_network) ;;
    *) status="refused"; reason="${reason:-return-check-target-unsupported}" ;;
  esac
  if [ "$enabled" = "true" ] && [ -z "$target_ssid" ] && [ -z "$target_connection" ]; then
    status="refused"
    reason="${reason:-target-missing}"
  fi
  if [ "$enabled" = "false" ] && [ -z "$reason" ]; then
    reason="return-check-disabled"
  fi
}

cmd_audit() {
  audit_values
  kv "status" "$status"
  kv "mode" "audit"
  kv "mutations" "false"
  kv "runtime_config" "$runtime_config"
  kv "runtime_config_readable" "$([ -r "$runtime_config" ] && printf yes || printf no)"
  kv "return_check_enabled" "$enabled"
  kv "return_check_enabled_raw" "$enabled_raw"
  kv "return_check_interval_minutes" "$interval"
  kv "return_check_interval_seconds" "$interval_seconds"
  kv "runtime_recovery_internet_required" "$internet_required_value"
  kv "runtime_recovery_internet_probe" "$internet_probe_value"
  kv "return_check_target" "$target"
  kv "return_check_mode" "$mode"
  kv "target_source" "${target_source:-}"
  kv "target_ssid" "${target_ssid:-}"
  kv "target_connection" "${target_connection:-}"
  kv "preferred_ssid" "${preferred_ssid:-}"
  kv "preferred_connection" "${preferred_connection:-}"
  kv "last_good_ssid" "${last_good_ssid:-}"
  kv "last_good_connection" "${last_good_connection:-}"
  kv "return_ssid" "${return_ssid:-}"
  kv "return_connection" "${return_connection:-}"
  kv "ap_ssid" "${ap_ssid:-}"
  loop_pid_value=$(loop_pid)
  if [ -n "$loop_pid_value" ] && is_loop_pid "$loop_pid_value"; then
    kv "loop_running" "yes"
    kv "loop_pid" "$loop_pid_value"
  else
    kv "loop_running" "no"
    kv "loop_pid" "${loop_pid_value:-missing}"
  fi
  kv "secret_policy" "no client Wi-Fi password is read, logged, or stored"
  if [ -n "$reason" ]; then
    kv "reason" "$reason"
  fi
}

cmd_plan() {
  cmd_audit
  section "ap-return-check-plan"
  kv "network_writes" "false"
  kv "ap_stop_start" "false"
  kv "wifi_connect" "false"
  kv "hostapd" "not-started"
  kv "dnsmasq" "not-started"
  kv "sudo" "not-used"
  kv "reboot" "not-used"
  kv "future_01_scope" "only from AP recovery"
  kv "future_02_wait" "sleep at least 120 seconds, or return_check_interval_seconds if longer, before attempts; 0 disables automatic return"
  kv "future_03_leave_ap" "temporarily leave AP recovery; do not use permanent AP+STA"
  kv "future_04_try_target" "try preferred_connection, preferred_ssid, return_connection, return_ssid, last_good_connection, then last_good_ssid with bounded timeout"
  kv "future_05_success" "stay normal and leave AP recovery stopped"
  kv "future_06_failure" "relaunch or remain in AP recovery"
  kv "future_07_secrets" "no Wi-Fi client password read, logged, or returned"
}

cmd_stop_loop() {
  section "ap-return-check-stop-loop"
  kv "mode" "stop-loop"
  kv "pidfile" "$loop_pid_file"
  stop_loop_best_effort
  kv "status" "done"
}

cmd_run_loop() {
  audit_values
  section "ap-return-check-run-loop"
  kv "mode" "run-loop"
  kv "log_file" "$log_file"
  kv "pidfile" "$loop_pid_file"
  kv "run_once_pidfile" "$run_once_pid_file"
  kv "runtime_config" "$runtime_config"
  kv "return_check_enabled" "$enabled"
  kv "return_check_interval_seconds" "$interval_seconds"
  kv "return_check_target" "$target"
  kv "target_source" "${target_source:-}"
  kv "return_check_mode" "$mode"
  kv "target_connection" "${target_connection:-}"
  kv "target_ssid" "${target_ssid:-}"
  kv "ap_restart_wait_seconds" "$ap_restart_wait_seconds"
  kv "ap_min_stable_seconds" "$ap_min_stable_seconds"
  kv "secret_policy" "no client Wi-Fi password is read, logged, or stored"
  require_root
  if [ "$status" != "ok" ] || [ "$enabled" != "true" ]; then
    kv "status" "refused"
    kv "reason" "${reason:-return-check-disabled}"
    log_event "refused" "${reason:-return-check-disabled}"
    exit 2
  fi
  require_number "return-check-interval-seconds" "$interval_seconds" "86400"
  require_number "ap-restart-wait-seconds" "$ap_restart_wait_seconds" "120"
  require_number "ap-min-stable-seconds" "$ap_min_stable_seconds" "3600"
  if [ -n "${WIFI_KIT_RETURN_CHECK_INTERVAL_SECONDS:-}" ]; then
    require_number "return-check-interval-seconds" "$WIFI_KIT_RETURN_CHECK_INTERVAL_SECONDS" "86400"
    interval_seconds=$WIFI_KIT_RETURN_CHECK_INTERVAL_SECONDS
  fi
  existing_pid=$(loop_pid)
  if [ -n "$existing_pid" ] && is_loop_pid "$existing_pid"; then
    kv "status" "refused"
    kv "reason" "loop-already-running"
    kv "loop_pid" "$existing_pid"
    exit 2
  fi
  printf '%s\n' "$$" >"$loop_pid_file"
  cleanup_loop() {
    current_pid=$(loop_pid)
    if [ "$current_pid" = "$$" ]; then
      rm -f "$loop_pid_file" 2>/dev/null || true
    fi
    rm -f "$run_once_pid_file" 2>/dev/null || true
    log_event "stopping loop" "pid=$$"
  }
  trap cleanup_loop EXIT INT TERM HUP
  kv "status" "started"
  kv "interval_seconds" "$interval_seconds"
  kv "min_stable_seconds" "$ap_min_stable_seconds"
  log_event "ap-return-check-loop started" "interval_seconds=$interval_seconds"
  while ap_recovery_active; do
    sleep_seconds=$interval_seconds
    if [ "$sleep_seconds" -lt "$ap_min_stable_seconds" ]; then
      sleep_seconds=$ap_min_stable_seconds
    fi
    log_event "sleeping interval" "seconds=$sleep_seconds min_stable_seconds=$ap_min_stable_seconds"
    sleep "$sleep_seconds"
    audit_values
    if [ "$enabled" != "true" ]; then
      kv "status" "stopping"
      kv "reason" "return-check-disabled"
      log_event "stopping loop" "return-check-disabled"
      exit 0
    fi
    if ! ap_recovery_active; then
      kv "status" "stopping"
      kv "reason" "ap-recovery-not-active"
      log_event "stopping loop" "ap-recovery-not-active"
      exit 0
    fi
    log_event "run-once started" "target_connection=${target_connection:-unknown}"
    WIFI_KIT_AP_RETURN_CHECK_INTERNAL=1 WIFI_KIT_RUNTIME_CONFIG="$runtime_config" sh "$0" run-once &
    run_once_pid=$!
    printf '%s\n' "$run_once_pid" >"$run_once_pid_file"
    if wait "$run_once_pid"; then
      rm -f "$run_once_pid_file" 2>/dev/null || true
      kv "status" "done"
      kv "decision" "normal"
      log_event "success" "loop-exit-normal"
      exit 0
    fi
    rm -f "$run_once_pid_file" 2>/dev/null || true
    log_event "failure" "run-once-failed"
    log_event "waiting" "ap-recovery-restart timeout_seconds=$ap_restart_wait_seconds"
    if wait_ap_recovery_active "$ap_restart_wait_seconds"; then
      log_event "ap-recovery-active" "loop-continues"
      continue
    else
      kv "status" "stopping"
      kv "reason" "ap-recovery-not-active-after-failure"
      log_event "stopping loop" "ap-recovery-not-active-after-failure"
      exit 1
    fi
  done
  kv "status" "done"
  kv "reason" "ap-recovery-not-active"
  log_event "stopping loop" "ap-recovery-not-active"
}

cmd_run_once() {
  audit_values
  section "ap-return-check-run-once"
  kv "mode" "run-once"
  kv "log_file" "$log_file"
  kv "runtime_config" "$runtime_config"
  kv "runtime_config_readable" "$([ -r "$runtime_config" ] && printf yes || printf no)"
  kv "return_check_enabled" "$enabled"
  kv "return_check_enabled_raw" "$enabled_raw"
  kv "return_check_target" "$target"
  kv "target_source" "${target_source:-}"
  kv "target_connection" "${target_connection:-}"
  kv "target_ssid" "${target_ssid:-}"
  kv "iface" "$iface"
  kv "connect_wait_seconds" "$connect_wait_seconds"
  kv "runtime_recovery_internet_required" "$internet_required_value"
  kv "runtime_recovery_internet_probe" "$internet_probe_value"
  kv "secret_policy" "no client Wi-Fi password is read, logged, or stored"
  log_event "started" "mode=run-once"
  require_root
  require_number "connect-wait-seconds" "$connect_wait_seconds" "120"
  require_number "ping-wait-seconds" "$ping_wait_seconds" "10"
  if [ "$status" != "ok" ] || [ "$enabled" != "true" ]; then
    kv "status" "refused"
    kv "reason" "${reason:-return-check-disabled}"
    log_event "refused" "${reason:-return-check-disabled}"
    exit 2
  fi
  if [ "$mode" != "periodic-from-ap" ]; then
    kv "status" "refused"
    kv "reason" "return-check-mode-unsupported"
    log_event "refused" "return-check-mode-unsupported"
    exit 2
  fi
  if ! ap_recovery_active; then
    kv "status" "refused"
    kv "reason" "ap-recovery-not-active"
    log_event "refused" "ap-recovery-not-active"
    exit 2
  fi
  nmcli_bin=$(find_tool nmcli 2>/dev/null || true)
  [ -n "$nmcli_bin" ] || { kv "status" "failed"; kv "reason" "nmcli-missing"; log_event "failed" "nmcli-missing"; exit 1; }
  if [ -z "$target_connection" ] && [ -n "$target_ssid" ]; then
    target_connection=$(connection_for_ssid "$target_ssid")
  fi
  [ -n "$target_connection" ] || { kv "status" "refused"; kv "reason" "target-connection-missing"; log_event "refused" "target-connection-missing"; exit 2; }
  resolved_ssid=$(connection_ssid "$target_connection")
  kv "target_connection" "$target_connection"
  kv "target_ssid" "${target_ssid:-$resolved_ssid}"
  kv "ap_stop" "starting"
  log_event "ap-stop-starting" "target_connection=$target_connection"
  WIFI_KIT_AP_SKIP_NM_RESTORE=1 sh "$ap_setup_script" stop >/dev/null 2>&1 || true
  "$nmcli_bin" device set "$iface" managed yes >/dev/null 2>&1 || true
  log_event "return-check-attempt-primary" "target_source=$target_source target_connection=$target_connection target_ssid=${target_ssid:-$resolved_ssid}"
  kv "connect" "starting"
  log_event "connect-starting" "target_connection=$target_connection"
  if "$nmcli_bin" --wait "$connect_wait_seconds" connection up "$target_connection" ifname "$iface" >/dev/null 2>&1 &&
    local_network_ok &&
    internet_ok; then
    kv "status" "done"
    kv "decision" "normal"
    kv "network" "ok"
    kv "internet" "$([ "$internet_required_value" = "true" ] && printf ok || printf not-required)"
    log_event "recovery-exit-success" "target_connection=$target_connection"
    exit 0
  fi
  kv "connect" "failed"
  kv "internet" "failed"
  kv "ap_restart" "starting"
  log_event "failure" "restarting-ap-recovery"
  "$nmcli_bin" device disconnect "$iface" >/dev/null 2>&1 || true
  "$nmcli_bin" device set "$iface" managed no >/dev/null 2>&1 || true
  log_event "return-check-failed-keep-ap" "target_connection=$target_connection nm_managed=no"
  if [ -f "$action_wrapper" ]; then
    if sh "$action_wrapper" start-ap-mode; then
      kv "status" "failed"
      kv "reason" "target-connect-failed-ap-restarted"
      log_event "failure" "ap-recovery-restarted"
      exit 1
    fi
    kv "status" "failed"
    kv "reason" "ap-recovery-restart-failed"
    log_event "failed" "ap-recovery-restart-failed"
    exit 1
  else
    kv "status" "failed"
    kv "reason" "action-wrapper-missing"
    log_event "failed" "action-wrapper-missing"
    exit 1
  fi
}

if [ "$#" -ne 1 ]; then
  usage
  exit 2
fi

case "$1" in
  audit) cmd_audit ;;
  plan) cmd_plan ;;
  run-once) cmd_run_once ;;
  run-loop) cmd_run_loop ;;
  stop-loop) cmd_stop_loop ;;
  -h|--help|help) usage ;;
  *) usage; exit 2 ;;
esac
