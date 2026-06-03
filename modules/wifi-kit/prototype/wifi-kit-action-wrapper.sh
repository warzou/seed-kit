#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ap_setup_script="$script_dir/ap-setup-test.sh"
connect_transaction_script="$script_dir/wifi-kit-connect-transaction.sh"
ap_return_check_script="$script_dir/wifi-kit-ap-return-check.sh"
node_ip_transaction_script="$script_dir/wifi-kit-node-ip-transaction.sh"
nm_ap_lab_script="$script_dir/wifi-kit-nm-ap-lab.sh"
repo_dir_file="$script_dir/repo-dir"
log_file="/tmp/wifi-kit-action-wrapper.log"
ui_connect_log="${WIFI_KIT_CONNECT_UI_LOG:-}"
runtime_config="${WIFI_KIT_RUNTIME_CONFIG:-}"
return_connection="netplan-wlan0-GL-MT6000-d53"
ap_test_psk="12345678"
ap_ssid=""
ap_timeout_seconds="300"
connect_timeout_seconds="180"
reboot_cmd="/sbin/reboot"
shutdown_cmd="/sbin/poweroff"
ui_service_name="wifi-kit-ui.service"

default_repo_dir() {
  if [ -r "$repo_dir_file" ]; then
    repo_value=$(sed -n '1p' "$repo_dir_file" 2>/dev/null || true)
    if [ -n "$repo_value" ]; then
      printf '%s\n' "$repo_value"
      return 0
    fi
  fi
  if [ -n "${WIFI_KIT_REPO_DIR:-}" ]; then
    printf '%s\n' "$WIFI_KIT_REPO_DIR"
    return 0
  fi
  printf '%s\n' "$script_dir"
}

repo_dir=$(default_repo_dir)
runtime_installer="$repo_dir/modules/wifi-kit/install-wifi-kit-runtime.sh"

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

safe_ui_log_path() {
  path=$1
  case "$path" in
    /tmp/wifi-kit-actions/*.log)
      base=${path##*/}
      [ "$path" = "/tmp/wifi-kit-actions/$base" ] || return 1
      [ -n "$base" ] || return 1
      ;;
    *)
      return 1
      ;;
  esac
}

prepare_ui_log() {
  path=$1
  safe_ui_log_path "$path" || return 1
  mkdir -p /tmp/wifi-kit-actions 2>/dev/null || return 1
  chmod 1777 /tmp/wifi-kit-actions 2>/dev/null || true
  ( : >> "$path" ) 2>/dev/null || return 1
  chmod 0666 "$path" 2>/dev/null || true
}

append_ui_connect_log() {
  line=$1
  [ -n "$ui_connect_log" ] || return 0
  prepare_ui_log "$ui_connect_log" || return 0
  ( printf '%s\n' "$line" >> "$ui_connect_log" ) 2>/dev/null || true
}

log_ui_connect_marker() {
  marker=$1
  detail=${2:-}
  [ -n "$ui_connect_log" ] || return 0
  log_event "connect-wifi" "$marker" "$detail"
}

log_event() {
  action=$1
  status=$2
  detail=${3:-}
  line=$(
    printf 'timestamp="%s" action=%s status="%s"' "$(timestamp)" "$action" "$status"
    if [ -n "$detail" ]; then
      printf ' detail="%s"' "$(json_escape "$detail")"
    fi
    printf '\n'
  )
  printf '%s\n' "$line" >> "$log_file" 2>/dev/null || true
  if [ "$action" = "connect-wifi" ] && [ -n "$ui_connect_log" ]; then
    append_ui_connect_log "$line"
  fi
  if [ "$action" = "connect-wifi" ]; then
    printf '%s\n' "$line"
  fi
}

runtime_config_value() {
  key=$1
  fallback=$2
  if [ -r "$runtime_config" ]; then
    value=$(sed -n "s/^$key=//p" "$runtime_config" 2>/dev/null | sed -n '1p' || true)
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return 0
    fi
  fi
  printf '%s\n' "$fallback"
}

nmcli_path() {
  command -v nmcli 2>/dev/null || printf '%s\n' "nmcli"
}

connection_exists() {
  connection=$1
  [ -n "$connection" ] || return 1
  nmcli_bin=$(nmcli_path)
  "$nmcli_bin" connection show "$connection" >/dev/null 2>&1
}

connection_for_ssid() {
  target_ssid=$1
  [ -n "$target_ssid" ] || return 0
  nmcli_bin=$(nmcli_path)
  "$nmcli_bin" -t --escape no -f NAME,TYPE connection show 2>/dev/null |
    while IFS=: read -r profile typ; do
      [ "$typ" = "802-11-wireless" ] || [ "$typ" = "wifi" ] || continue
      ssid=$("$nmcli_bin" -g 802-11-wireless.ssid connection show "$profile" 2>/dev/null | sed -n '1p')
      if [ "$ssid" = "$target_ssid" ]; then
        printf '%s\n' "$profile"
        return 0
      fi
    done |
    sed -n '1p'
}

resolve_primary_return_target() {
  preferred_connection=$(runtime_config_value preferred_connection "")
  preferred_ssid=$(runtime_config_value preferred_ssid "")
  legacy_return_connection=$(runtime_config_value return_connection "$(runtime_config_value default_connection "${WIFI_KIT_RETURN_CONNECTION:-}")")
  legacy_return_ssid=$(runtime_config_value return_ssid "$(runtime_config_value default_ssid "")")
  last_good_connection=$(runtime_config_value last_good_connection "")
  last_good_ssid=$(runtime_config_value last_good_ssid "")

  if connection_exists "$preferred_connection"; then
    printf 'preferred_connection|%s\n' "$preferred_connection"
    return 0
  fi
  resolved=$(connection_for_ssid "$preferred_ssid")
  if [ -n "$resolved" ]; then
    printf 'preferred_ssid|%s\n' "$resolved"
    return 0
  fi
  if connection_exists "$legacy_return_connection"; then
    printf 'return_connection|%s\n' "$legacy_return_connection"
    return 0
  fi
  resolved=$(connection_for_ssid "$legacy_return_ssid")
  if [ -n "$resolved" ]; then
    printf 'return_ssid|%s\n' "$resolved"
    return 0
  fi
  if connection_exists "$last_good_connection"; then
    printf 'last_good_connection|%s\n' "$last_good_connection"
    return 0
  fi
  resolved=$(connection_for_ssid "$last_good_ssid")
  if [ -n "$resolved" ]; then
    printf 'last_good_ssid|%s\n' "$resolved"
    return 0
  fi
  printf 'missing|\n'
}

default_runtime_config_path() {
  if [ -n "$runtime_config" ]; then
    printf '%s\n' "$runtime_config"
    return 0
  fi
  if [ -r "/etc/seed-kit/wifi-kit/runtime.conf" ]; then
    printf '%s\n' "/etc/seed-kit/wifi-kit/runtime.conf"
    return 0
  fi
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    sudo_home=$(getent passwd "$SUDO_USER" 2>/dev/null | awk -F: '{ print $6 }' | sed -n '1p')
    if [ -n "$sudo_home" ]; then
      printf '%s\n' "$sudo_home/.config/wifi-kit/runtime.conf"
      return 0
    fi
  fi
  if [ -r "/home/warzy/.config/wifi-kit/runtime.conf" ]; then
    printf '%s\n' "/home/warzy/.config/wifi-kit/runtime.conf"
    return 0
  fi
  printf '%s\n' "${HOME:-/tmp}/.config/wifi-kit/runtime.conf"
}

runtime_config=$(default_runtime_config_path)
export WIFI_KIT_RUNTIME_CONFIG="$runtime_config"

reply() {
  status=$1
  action=$2
  detail=${3:-}
  printf 'status=%s\n' "$status"
  printf 'action=%s\n' "$action"
  if [ -n "$detail" ]; then
    printf 'detail=%s\n' "$detail"
  fi
}

forensics_section() {
  printf '\n[%s]\n' "$1"
}

forensics_kv() {
  printf '%s=%s\n' "$1" "$2"
}

find_readonly_tool() {
  primary=$1
  shift
  for candidate in "$primary" "$@"; do
    case "$candidate" in
      */*)
        if [ -x "$candidate" ]; then
          printf '%s\n' "$candidate"
          return 0
        fi
        ;;
      *)
        resolved=$(command -v "$candidate" 2>/dev/null || true)
        if [ -n "$resolved" ]; then
          printf '%s\n' "$resolved"
          return 0
        fi
        ;;
    esac
  done
  return 1
}

redact_forensics() {
  sed -E \
    -e 's/(ap_password|password|psk|wifi-sec\.psk|802-11-wireless-security\.psk)=("[^"]*"|[^[:space:]]*)/\1=<redacted>/Ig' \
    -e 's/((password|psk)[[:space:]]*:[[:space:]]*)[^[:space:]]+/\1<redacted>/Ig'
}

forensics_run() {
  label=$1
  tool=$2
  shift 2
  forensics_section "$label"
  if [ -z "$tool" ]; then
    forensics_kv "status" "tool-missing"
    return 0
  fi
  "$tool" "$@" 2>&1 | redact_forensics || true
}

forensics_file_tail() {
  label=$1
  path=$2
  lines=$3
  tail_bin=$4
  forensics_section "$label"
  forensics_kv "path" "$path"
  if [ ! -r "$path" ]; then
    forensics_kv "status" "unreadable-or-missing"
    return 0
  fi
  if [ -z "$tail_bin" ]; then
    forensics_kv "status" "tail-missing"
    return 0
  fi
  "$tail_bin" -n "$lines" "$path" 2>&1 | redact_forensics || true
}

cmd_forensics_last() {
  tail_bin=$(find_readonly_tool tail /usr/bin/tail /bin/tail || true)
  snapshot_path="/var/log/seed-kit/wifi-kit/forensics-last.log"
  max_bytes=200000

  forensics_section "forensics-last"
  forensics_kv "path" "$snapshot_path"
  forensics_kv "max_bytes" "$max_bytes"
  if [ ! -r "$snapshot_path" ]; then
    forensics_kv "status" "unreadable-or-missing"
    return 1
  fi
  if [ -z "$tail_bin" ]; then
    forensics_kv "status" "tail-missing"
    return 1
  fi
  forensics_kv "status" "ok"
  "$tail_bin" -c "$max_bytes" "$snapshot_path" 2>&1 | redact_forensics || true
}

forensics_journal_filtered() {
  label=$1
  shift
  journalctl_bin=$1
  shift
  forensics_section "$label"
  if [ -z "$journalctl_bin" ]; then
    forensics_kv "status" "journalctl-missing"
    return 0
  fi
  "$journalctl_bin" "$@" 2>&1 |
    grep -Ei 'wifi-kit|wlan0|brcmfmac|firmware|auth|assoc|deauth|disassoc|invalid|ap|sta|NetworkManager|no-ip|no-default-route|critical-link-loss|recovery' |
    redact_forensics || true
}

cmd_forensics_snapshot() {
  date_bin=$(find_readonly_tool date /bin/date /usr/bin/date || true)
  hostname_bin=$(find_readonly_tool hostname /bin/hostname /usr/bin/hostname || true)
  uptime_bin=$(find_readonly_tool uptime /usr/bin/uptime || true)
  cat_bin=$(find_readonly_tool cat /bin/cat /usr/bin/cat || true)
  tail_bin=$(find_readonly_tool tail /usr/bin/tail /bin/tail || true)
  id_bin=$(find_readonly_tool id /usr/bin/id /bin/id || true)
  ip_bin=$(find_readonly_tool ip /usr/sbin/ip /sbin/ip /usr/bin/ip /bin/ip || true)
  iw_bin=$(find_readonly_tool iw /usr/sbin/iw /sbin/iw /usr/bin/iw /bin/iw || true)
  nmcli_bin=$(find_readonly_tool nmcli /usr/bin/nmcli /bin/nmcli || true)
  ss_bin=$(find_readonly_tool ss /usr/sbin/ss /sbin/ss /usr/bin/ss /bin/ss || true)
  systemctl_bin=$(find_readonly_tool systemctl /usr/bin/systemctl /bin/systemctl || true)
  journalctl_bin=$(find_readonly_tool journalctl /usr/bin/journalctl /bin/journalctl || true)

  forensics_section "forensics-summary"
  if [ -n "$date_bin" ]; then
    forensics_kv "timestamp_utc" "$("$date_bin" -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || true)"
    forensics_kv "timestamp_local" "$("$date_bin" +"%Y-%m-%dT%H:%M:%S%z" 2>/dev/null || true)"
  fi
  if [ -n "$hostname_bin" ]; then
    forensics_kv "hostname" "$("$hostname_bin" 2>/dev/null || true)"
  fi
  if [ -n "$uptime_bin" ]; then
    forensics_kv "uptime" "$("$uptime_bin" 2>/dev/null || true)"
  fi
  if [ -n "$id_bin" ]; then
    forensics_kv "identity" "$("$id_bin" 2>/dev/null || true)"
  fi
  forensics_kv "runtime_config_path" "$runtime_config"
  forensics_kv "runtime_version_path" "$script_dir/runtime-version"
  forensics_kv "tool_iw" "${iw_bin:-missing}"
  if [ -n "$cat_bin" ] && [ -r "$script_dir/runtime-version" ]; then
    forensics_kv "runtime_version" "$("$cat_bin" "$script_dir/runtime-version" 2>/dev/null | sed -n '1p' || true)"
  fi

  if [ -n "$systemctl_bin" ]; then
    forensics_section "services"
    for service in NetworkManager wifi-kit-ui.service wifi-kit-runtime-watchdog.service wifi-kit-boot-guard.service wifi-kit-ap-return-check.service; do
      printf '%s.active=' "$service"
      "$systemctl_bin" is-active "$service" 2>/dev/null || true
      printf '%s.enabled=' "$service"
      "$systemctl_bin" is-enabled "$service" 2>/dev/null || true
    done | redact_forensics
  else
    forensics_section "services"
    forensics_kv "status" "systemctl-missing"
  fi

  forensics_run "network-nmcli-device-status" "$nmcli_bin" -t -f DEVICE,TYPE,STATE,CONNECTION device status
  forensics_run "network-nmcli-active-connections" "$nmcli_bin" -t -f NAME,TYPE,DEVICE connection show --active
  forensics_run "network-nmcli-wlan0" "$nmcli_bin" -t -f GENERAL.DEVICE,GENERAL.TYPE,GENERAL.STATE,GENERAL.CONNECTION,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS device show wlan0
  forensics_run "network-ip-addr-wlan0" "$ip_bin" addr show wlan0
  forensics_run "network-ip-route" "$ip_bin" route
  forensics_run "network-iw-dev" "$iw_bin" dev
  forensics_run "network-iw-wlan0-info" "$iw_bin" dev wlan0 info
  forensics_run "network-listening-tcp" "$ss_bin" -ltn

  forensics_file_tail "watchdog-state-persistent" "/var/log/seed-kit/wifi-kit/runtime-watchdog-state" "80" "$tail_bin"
  forensics_file_tail "watchdog-log-persistent-tail" "/var/log/seed-kit/wifi-kit/runtime-watchdog.log" "500" "$tail_bin"
  forensics_file_tail "watchdog-state-tmp" "/tmp/wifi-kit-actions/runtime-watchdog-state" "80" "$tail_bin"
  forensics_file_tail "watchdog-log-tmp-tail" "/tmp/wifi-kit-actions/runtime-watchdog-0.log" "300" "$tail_bin"
  forensics_file_tail "ap-recovery-log-tail" "/tmp/wifi-kit-nm-ap-lab-ui.log" "300" "$tail_bin"
  forensics_file_tail "action-wrapper-log-tail" "/tmp/wifi-kit-action-wrapper.log" "200" "$tail_bin"
  forensics_file_tail "start-ap-mode-log-tail" "/tmp/wifi-kit-actions/start-ap-mode-0.log" "200" "$tail_bin"
  forensics_file_tail "return-default-network-log-tail" "/tmp/wifi-kit-actions/return-default-network-0.log" "200" "$tail_bin"
  forensics_file_tail "ap-return-check-log-tail" "/tmp/wifi-kit-actions/ap-return-check-0.log" "200" "$tail_bin"

  forensics_journal_filtered "journal-watchdog-recent-filtered" "$journalctl_bin" -u wifi-kit-runtime-watchdog.service --since "12 hours ago" -n 400 --no-pager
  forensics_journal_filtered "journal-networkmanager-recent-filtered" "$journalctl_bin" -u NetworkManager --since "12 hours ago" -n 400 --no-pager
  forensics_journal_filtered "journal-kernel-recent-filtered" "$journalctl_bin" -k --since "12 hours ago" -n 400 --no-pager
}

safe_line_value() {
  key=$1
  value=$2
  cr=$(printf '\r')
  case "$value" in
    *"$cr"*) reply "refused" "$key" "newline-not-allowed"; exit 2 ;;
  esac
}

require_number() {
  key=$1
  value=$2
  max=$3
  case "$value" in
    ''|*[!0-9]*) reply "refused" "$key" "number-required"; exit 2 ;;
  esac
  [ "$value" -le "$max" ] || { reply "refused" "$key" "number-too-large"; exit 2; }
}

read_connect_request() {
  connect_ssid=""
  connect_password=""
  connect_existing_connection=""
  connect_confirm=""
  connect_dangerous_real_apply="false"
  connect_timeout_seconds="180"
  while IFS= read -r line; do
    key=${line%%=*}
    value=${line#*=}
    [ "$key" != "$line" ] || continue
    safe_line_value "$key" "$value"
    case "$key" in
      ssid) connect_ssid=$value ;;
      password) connect_password=$value ;;
      existing_connection) connect_existing_connection=$value ;;
      confirm) connect_confirm=$value ;;
      dangerous_real_apply) connect_dangerous_real_apply=$value ;;
      timeout_seconds) connect_timeout_seconds=$value ;;
      ui_log) ui_connect_log=$value ;;
      *) ;;
    esac
  done
}

read_system_power_request() {
  system_power_confirmed="false"
  system_power_dangerous_real_apply="false"
  system_power_gate="false"
  system_power_dry_run="false"
  [ -t 0 ] && return 0
  while IFS= read -r line; do
    key=${line%%=*}
    value=${line#*=}
    [ "$key" != "$line" ] || continue
    safe_line_value "$key" "$value"
    case "$key" in
      user_confirmed) system_power_confirmed=$value ;;
      dangerous_real_apply) system_power_dangerous_real_apply=$value ;;
      system_power_gate) system_power_gate=$value ;;
      dry_run) system_power_dry_run=$value ;;
      *) ;;
    esac
  done
}

read_reinstall_runtime_request() {
  reinstall_confirmed="false"
  reinstall_dangerous_real_apply="false"
  reinstall_dry_run="false"
  [ -t 0 ] && return 0
  while IFS= read -r line; do
    key=${line%%=*}
    value=${line#*=}
    [ "$key" != "$line" ] || continue
    safe_line_value "$key" "$value"
    case "$key" in
      user_confirmed) reinstall_confirmed=$value ;;
      dangerous_real_apply) reinstall_dangerous_real_apply=$value ;;
      dry_run) reinstall_dry_run=$value ;;
      *) ;;
    esac
  done
}

read_node_ip_request() {
  node_ip_confirmed="false"
  node_ip_dangerous_real_apply="false"
  node_ip_dry_run="false"
  node_ip_validation_seconds="120"
  [ -t 0 ] && return 0
  while IFS= read -r line; do
    key=${line%%=*}
    value=${line#*=}
    [ "$key" != "$line" ] || continue
    safe_line_value "$key" "$value"
    case "$key" in
      user_confirmed) node_ip_confirmed=$value ;;
      dangerous_real_apply) node_ip_dangerous_real_apply=$value ;;
      dry_run) node_ip_dry_run=$value ;;
      validation_seconds) node_ip_validation_seconds=$value ;;
      *) ;;
    esac
  done
}

validate_runtime_installer() {
  [ -r "$repo_dir_file" ] || { log_event "$1" "refused" "repo-dir-file-missing=$repo_dir_file"; reply "refused" "$1" "repo-dir-file-missing"; exit 2; }
  case "$repo_dir" in
    /*) ;;
    *) log_event "$1" "refused" "repo-dir-not-absolute"; reply "refused" "$1" "repo-dir-not-absolute"; exit 2 ;;
  esac
  [ -d "$repo_dir" ] || { log_event "$1" "failure" "repo-dir-missing=$repo_dir"; reply "failure" "$1" "repo-dir-missing"; exit 1; }
  [ -f "$runtime_installer" ] || { log_event "$1" "failure" "runtime-installer-missing=$runtime_installer"; reply "failure" "$1" "runtime-installer-missing"; exit 1; }
  case "$runtime_installer" in
    "$repo_dir"/modules/wifi-kit/install-wifi-kit-runtime.sh) ;;
    *) log_event "$1" "refused" "runtime-installer-unsafe=$runtime_installer"; reply "refused" "$1" "runtime-installer-unsafe"; exit 2 ;;
  esac
}

require_root() {
  if [ "$(id -u)" != "0" ]; then
    log_event "$1" "refused" "root-required"
    reply "refused" "$1" "root-required"
    exit 1
  fi
}

if [ "$#" -ne 1 ]; then
  log_event "unknown" "refused" "usage"
  reply "refused" "unknown" "usage: wifi-kit-action-wrapper.sh start-ap-mode|return-default-network|connect-wifi|ap-return-check-once|node-ip-test|node-ip-confirm|node-ip-rollback|reboot-system|shutdown-system|reinstall-runtime|restart-ui|forensics-snapshot|forensics-last"
  exit 2
fi

action=$1
ap_test_psk="${WIFI_KIT_AP_PSK:-$(runtime_config_value ap_password "$ap_test_psk")}"
ap_ssid="${WIFI_KIT_AP_SSID:-$(runtime_config_value ap_ssid "")}"
ap_backend="${WIFI_KIT_AP_BACKEND:-nm-hotspot}"

case "$action" in
  start-ap-mode)
    require_root "$action"
    if [ "$ap_backend" = "nm-hotspot" ]; then
      if [ ! -f "$nm_ap_lab_script" ]; then
        log_event "$action" "failure" "backend=nm-hotspot nm_helper_path=$nm_ap_lab_script nm-ap-lab-missing"
        reply "failure" "$action" "nm-ap-lab-missing"
        exit 1
      fi
      log_event "$action" "started" "backend=nm-hotspot nm_helper_path=$nm_ap_lab_script"
      WIFI_KIT_RUNTIME_CONFIG="$runtime_config" WIFI_KIT_NM_AP_LAB_APPLY=1 exec sh "$nm_ap_lab_script" start-hotspot
    fi
    if [ "$ap_backend" != "hostapd" ]; then
      log_event "$action" "failure" "unsupported-backend=$ap_backend"
      reply "failure" "$action" "unsupported-backend=$ap_backend"
      exit 1
    fi
    if [ ! -f "$ap_setup_script" ]; then
      log_event "$action" "failure" "ap-setup-test-missing"
      reply "failure" "$action" "ap-setup-test-missing"
      exit 1
    fi
    log_event "$action" "started" "timeout=$ap_timeout_seconds"
    export WIFI_KIT_AP_PSK="$ap_test_psk"
    if [ -n "$ap_ssid" ]; then
      exec sh "$ap_setup_script" apply-ap-recovery-manual-test \
        --dangerous-real-apply \
        --confirm "WIFI-KIT AP RECOVERY MANUAL TEST" \
        --ssid "$ap_ssid" \
        --stay-up-until-stop \
        --max-seconds "$ap_timeout_seconds"
    fi
    exec sh "$ap_setup_script" apply-ap-recovery-manual-test \
      --dangerous-real-apply \
      --confirm "WIFI-KIT AP RECOVERY MANUAL TEST" \
      --stay-up-until-stop \
      --max-seconds "$ap_timeout_seconds"
    ;;
  return-default-network)
    require_root "$action"
    return_target=$(resolve_primary_return_target)
    return_target_source=${return_target%%|*}
    return_connection=${return_target#*|}
    if [ -z "$return_connection" ]; then
      log_event "$action" "failure" "target_source=$return_target_source target_connection=missing"
      reply "failure" "$action" "return-target-missing"
      exit 1
    fi
    if [ -f "$ap_return_check_script" ]; then
      WIFI_KIT_RUNTIME_CONFIG="$runtime_config" sh "$ap_return_check_script" stop-loop >/dev/null 2>&1 || true
    fi
    log_event "$action" "started" "connection=$return_connection target_source=$return_target_source"
    if [ -f "$nm_ap_lab_script" ]; then
      log_event "$action" "cleanup" "backend=nm-hotspot nm_helper_path=$nm_ap_lab_script rollback=technical-only"
      WIFI_KIT_RUNTIME_CONFIG="$runtime_config" WIFI_KIT_NM_AP_LAB_APPLY=1 sh "$nm_ap_lab_script" rollback >> "$log_file" 2>&1 || true
    fi
    if [ -f "$ap_setup_script" ]; then
      log_event "$action" "cleanup" "backend=hostapd legacy-explicit-only"
      sh "$ap_setup_script" stop >> "$log_file" 2>&1 || true
    fi
    exec nmcli connection up "$return_connection"
    ;;
  connect-wifi)
    read_connect_request
    log_ui_connect_marker "wrapper-received-ui-log" "path-accepted"
    require_root "$action"
    if [ -f "$ap_return_check_script" ]; then
      WIFI_KIT_RUNTIME_CONFIG="$runtime_config" sh "$ap_return_check_script" stop-loop >/dev/null 2>&1 || true
    fi
    [ -n "$connect_ssid" ] || { reply "refused" "$action" "missing-ssid"; exit 2; }
    ssid_bytes=$(printf '%s' "$connect_ssid" | wc -c | tr -d ' ')
    [ "$ssid_bytes" -le 32 ] || { reply "refused" "$action" "ssid-too-long"; exit 2; }
    [ "$connect_confirm" = "WIFI-KIT CONNECT SAFE TRANSACTION" ] || { reply "refused" "$action" "confirm-phrase-mismatch"; exit 2; }
    [ "$connect_dangerous_real_apply" = "true" ] || [ "$connect_dangerous_real_apply" = "1" ] ||
      { reply "refused" "$action" "dangerous-real-apply-required"; exit 2; }
    require_number "timeout_seconds" "$connect_timeout_seconds" "600"
    [ -f "$connect_transaction_script" ] || { reply "failure" "$action" "connect-transaction-missing"; exit 1; }
    log_event "$action" "started" "ssid=$connect_ssid existing_connection=${connect_existing_connection:-none}"
    export WIFI_KIT_AP_PSK="$ap_test_psk"
    if [ -n "$ap_ssid" ]; then
      export WIFI_KIT_AP_SSID="$ap_ssid"
    fi
    if [ -n "$ui_connect_log" ]; then
      export WIFI_KIT_CONNECT_UI_LOG="$ui_connect_log"
    fi
    export WIFI_KIT_CONNECT_STDOUT_LOG=1
    log_ui_connect_marker "wrapper-launching-transaction" "existing_connection=${connect_existing_connection:-none}"
    if [ -n "$connect_existing_connection" ]; then
      exec sh "$connect_transaction_script" apply \
        --ssid "$connect_ssid" \
        --existing-connection "$connect_existing_connection" \
        --dangerous-real-apply \
        --confirm "WIFI-KIT CONNECT SAFE TRANSACTION" \
        --timeout-seconds "$connect_timeout_seconds"
    fi
    [ -n "$connect_password" ] || { reply "refused" "$action" "missing-password"; exit 2; }
    [ "${#connect_password}" -ge 8 ] || { reply "refused" "$action" "password-too-short"; exit 2; }
    printf '%s\n' "$connect_password" | sh "$connect_transaction_script" apply \
      --ssid "$connect_ssid" \
      --dangerous-real-apply \
      --confirm "WIFI-KIT CONNECT SAFE TRANSACTION" \
      --timeout-seconds "$connect_timeout_seconds"
    ;;
  ap-return-check-once)
    require_root "$action"
    [ -f "$ap_return_check_script" ] || { reply "failure" "$action" "ap-return-check-missing"; exit 1; }
    WIFI_KIT_RUNTIME_CONFIG="$runtime_config" sh "$ap_return_check_script" stop-loop >/dev/null 2>&1 || true
    log_event "$action" "started" "mode=run-once"
    WIFI_KIT_RUNTIME_CONFIG="$runtime_config" exec sh "$ap_return_check_script" run-once
    ;;
  node-ip-test)
    read_node_ip_request
    require_root "$action"
    [ -f "$node_ip_transaction_script" ] || { reply "failure" "$action" "node-ip-transaction-missing"; exit 1; }
    require_number "validation_seconds" "$node_ip_validation_seconds" "600"
    if [ "$node_ip_confirmed" != "true" ] && [ "$node_ip_confirmed" != "1" ]; then
      log_event "$action" "refused" "confirmation-required"
      reply "refused" "$action" "confirmation-required"
      exit 2
    fi
    if [ "$node_ip_dangerous_real_apply" != "true" ] && [ "$node_ip_dangerous_real_apply" != "1" ]; then
      log_event "$action" "planned" "dangerous-real-apply-required"
      reply "planned" "$action" "dangerous-real-apply-required"
      exit 0
    fi
    if [ "$node_ip_dry_run" = "true" ] || [ "$node_ip_dry_run" = "1" ]; then
      log_event "$action" "planned" "dry-run validation_seconds=$node_ip_validation_seconds"
      reply "planned" "$action" "validation_seconds=$node_ip_validation_seconds"
      exit 0
    fi
    log_event "$action" "started" "validation_seconds=$node_ip_validation_seconds"
    WIFI_KIT_RUNTIME_CONFIG="$runtime_config" WIFI_KIT_NODE_IP_VALIDATION_SECONDS="$node_ip_validation_seconds" exec sh "$node_ip_transaction_script" test
    ;;
  node-ip-confirm)
    read_node_ip_request
    require_root "$action"
    [ -f "$node_ip_transaction_script" ] || { reply "failure" "$action" "node-ip-transaction-missing"; exit 1; }
    if [ "$node_ip_confirmed" != "true" ] && [ "$node_ip_confirmed" != "1" ]; then
      log_event "$action" "refused" "confirmation-required"
      reply "refused" "$action" "confirmation-required"
      exit 2
    fi
    log_event "$action" "started" "confirm-static-ip"
    WIFI_KIT_RUNTIME_CONFIG="$runtime_config" exec sh "$node_ip_transaction_script" confirm
    ;;
  node-ip-rollback)
    require_root "$action"
    [ -f "$node_ip_transaction_script" ] || { reply "failure" "$action" "node-ip-transaction-missing"; exit 1; }
    log_event "$action" "started" "manual-rollback"
    WIFI_KIT_RUNTIME_CONFIG="$runtime_config" exec sh "$node_ip_transaction_script" rollback
    ;;
  reinstall-runtime)
    read_reinstall_runtime_request
    require_root "$action"
    if [ "$reinstall_confirmed" != "true" ] && [ "$reinstall_confirmed" != "1" ]; then
      log_event "$action" "refused" "confirmation-required"
      reply "refused" "$action" "confirmation-required"
      exit 2
    fi
    if [ "$reinstall_dangerous_real_apply" != "true" ] && [ "$reinstall_dangerous_real_apply" != "1" ]; then
      log_event "$action" "planned" "dangerous-real-apply-required"
      reply "planned" "$action" "dangerous-real-apply-required"
      exit 0
    fi
    validate_runtime_installer "$action"
    if [ "$reinstall_dry_run" = "true" ] || [ "$reinstall_dry_run" = "1" ]; then
      log_event "$action" "planned" "repo_dir=$repo_dir installer=$runtime_installer"
      reply "planned" "$action" "repo_dir=$repo_dir installer=$runtime_installer"
      exit 0
    fi
    command="sh $runtime_installer install --reinstall --defer-ui-restart"
    log_event "$action" "started" "repo_dir=$repo_dir command=$command"
    set +e
    sh "$runtime_installer" install --reinstall --defer-ui-restart
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
      log_event "$action" "success" "repo_dir=$repo_dir command=$command exit_code=$rc ui_restart=deferred"
      reply "success" "$action" "runtime-reinstalled exit_code=$rc ui_restart=deferred"
      exit 0
    fi
    log_event "$action" "failure" "repo_dir=$repo_dir command=$command exit_code=$rc"
    reply "failure" "$action" "runtime-reinstall-failed exit_code=$rc"
    exit "$rc"
    ;;
  restart-ui)
    require_root "$action"
    systemctl_cmd=$(command -v systemctl 2>/dev/null || true)
    [ -n "$systemctl_cmd" ] || { log_event "$action" "failure" "systemctl-missing"; reply "failure" "$action" "systemctl-missing"; exit 1; }
    log_event "$action" "requested" "service=$ui_service_name command=$systemctl_cmd restart $ui_service_name"
    set +e
    "$systemctl_cmd" restart "$ui_service_name"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
      log_event "$action" "success" "service=$ui_service_name exit_code=$rc"
      reply "success" "$action" "ui-restart-requested service=$ui_service_name exit_code=$rc"
      exit 0
    fi
    log_event "$action" "failure" "service=$ui_service_name exit_code=$rc"
    reply "failure" "$action" "ui-restart-failed service=$ui_service_name exit_code=$rc"
    exit "$rc"
    ;;
  forensics-snapshot)
    require_root "$action"
    cmd_forensics_snapshot
    ;;
  forensics-last)
    require_root "$action"
    cmd_forensics_last
    ;;
  reboot-system)
    read_system_power_request
    require_root "$action"
    if [ "$system_power_confirmed" != "true" ] && [ "$system_power_confirmed" != "1" ]; then
      log_event "$action" "refused" "confirmation-required"
      reply "refused" "$action" "confirmation-required"
      exit 2
    fi
    if [ "$system_power_dangerous_real_apply" != "true" ] && [ "$system_power_dangerous_real_apply" != "1" ]; then
      log_event "$action" "planned" "dangerous-real-apply-required"
      reply "planned" "$action" "dangerous-real-apply-required"
      exit 0
    fi
    if [ "$system_power_gate" != "true" ] && [ "$system_power_gate" != "1" ]; then
      log_event "$action" "planned" "system-power-gate-disabled"
      reply "planned" "$action" "system-power-gate-disabled"
      exit 0
    fi
    if [ "$system_power_dry_run" = "true" ] || [ "$system_power_dry_run" = "1" ]; then
      log_event "$action" "planned" "dry-run command=$reboot_cmd"
      reply "planned" "$action" "command=$reboot_cmd"
      exit 0
    fi
    [ -x "$reboot_cmd" ] || { log_event "$action" "failure" "command-missing=$reboot_cmd"; reply "failure" "$action" "command-missing=$reboot_cmd"; exit 1; }
    log_event "$action" "requested" "command=$reboot_cmd"
    exec "$reboot_cmd"
    ;;
  shutdown-system)
    read_system_power_request
    require_root "$action"
    if [ "$system_power_confirmed" != "true" ] && [ "$system_power_confirmed" != "1" ]; then
      log_event "$action" "refused" "confirmation-required"
      reply "refused" "$action" "confirmation-required"
      exit 2
    fi
    if [ "$system_power_dangerous_real_apply" != "true" ] && [ "$system_power_dangerous_real_apply" != "1" ]; then
      log_event "$action" "planned" "dangerous-real-apply-required"
      reply "planned" "$action" "dangerous-real-apply-required"
      exit 0
    fi
    if [ "$system_power_gate" != "true" ] && [ "$system_power_gate" != "1" ]; then
      log_event "$action" "planned" "system-power-gate-disabled"
      reply "planned" "$action" "system-power-gate-disabled"
      exit 0
    fi
    if [ "$system_power_dry_run" = "true" ] || [ "$system_power_dry_run" = "1" ]; then
      log_event "$action" "planned" "dry-run command=$shutdown_cmd"
      reply "planned" "$action" "command=$shutdown_cmd"
      exit 0
    fi
    [ -x "$shutdown_cmd" ] || { log_event "$action" "failure" "command-missing=$shutdown_cmd"; reply "failure" "$action" "command-missing=$shutdown_cmd"; exit 1; }
    log_event "$action" "requested" "command=$shutdown_cmd"
    exec "$shutdown_cmd"
    ;;
  *)
    log_event "$action" "refused" "action-not-allowed"
    reply "refused" "$action" "action-not-allowed"
    exit 2
    ;;
esac
