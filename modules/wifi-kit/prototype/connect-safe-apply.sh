#!/bin/sh
set -eu

mode=""
iface=""
from_ssid=""
to_ssid=""
gateway=""
preflight_host="pocket-node.lan"
preflight_user="warzy"
preflight_identity="$HOME/.ssh/id_ed25519_pocket_node_codex"
reachability_probe="1.1.1.1"
ip_timeout="30"
validation_timeout="20"
rollback_timeout="30"
dangerous_real_apply=0
apply_confirm=""
target_ssid="SFR_7B28"
rollback_ssid="GL-MT6000-d53"

usage() {
  cat <<'EOF'
wifi-kit connect-safe apply prototype

Dry-run only. This script structures the future A -> B -> rollback
transaction, but apply is locked. It never reads secrets, never prints
secrets, never calls wpa_cli, and never mutates networking.

Usage:
  sh modules/wifi-kit/prototype/connect-safe-apply.sh \
    --dry-run

  sh modules/wifi-kit/prototype/connect-safe-apply.sh \
    --preflight-readonly

  WIFI_KIT_TARGET_PSK=<runtime-only-secret> \
    sh modules/wifi-kit/prototype/connect-safe-apply.sh \
      --apply \
      --dangerous-real-apply \
      --confirm "WIFI-KIT TEMP APPLY ROLLBACK"

Optional:
  --iface <name>                Future interface name. Default: <interface>
  --from <current-ssid>         Future rollback profile A. Default: <profile-a>
  --to <target-ssid>            Future temporary target profile B. Default: <profile-b>
  --gateway <ip>                 Future expected gateway validation target.
  --reachability-probe <target>  Future reachability probe. Default: 1.1.1.1
  --ip-timeout <seconds>         Future DHCP/IP wait timeout. Default: 30
  --validation-timeout <seconds> Future validation timeout. Default: 20
  --rollback-timeout <seconds>   Future rollback timeout. Default: 30
  --preflight-host <host>        Read-only SSH host. Default: pocket-node.lan
  --preflight-user <user>        Read-only SSH user. Default: warzy
  --identity <path>              SSH identity for preflight.
  --dangerous-real-apply         Required for the experimental apply path.
  --confirm <text>               Must equal WIFI-KIT TEMP APPLY ROLLBACK.

Safety:
  --apply refuses unless every explicit gate is satisfied. It never calls
  save_config and always rolls back to GL-MT6000-d53 before cleanup.
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

run_preflight_readonly() {
  [ -n "$iface" ] || iface="wlan0"

  ssh -i "$preflight_identity" \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=yes \
    "$preflight_user@$preflight_host" \
    "IFACE='$iface' sh -s" <<'REMOTE'
set -u

PATH="/usr/sbin:/sbin:/usr/bin:/bin:$PATH"
IFACE=${IFACE:-wlan0}
ROLLBACK_SSID="GL-MT6000-d53"
TARGET_SSID="SFR_7B28"
readiness="OK"

kv() {
  printf '%s=%s\n' "$1" "$2"
}

mark_ko() {
  readiness="KO"
}

hostname_value=$(hostname 2>&1)
hostname_status=$?
user_value=$(whoami 2>&1)
user_status=$?
uptime_value=$(uptime 2>&1)
uptime_status=$?
ip_addr_output=$(ip addr show "$IFACE" 2>&1)
ip_addr_status=$?
ip_route_output=$(ip route 2>&1)
ip_route_status=$?
iw_info_output=$(iw dev "$IFACE" info 2>&1)
iw_info_status=$?
power_save_output=$(iw dev "$IFACE" get power_save 2>&1)
power_save_status=$?
wpa_status_output=$(wpa_cli -i "$IFACE" status 2>&1)
wpa_status_status=$?
wpa_networks_output=$(wpa_cli -i "$IFACE" list_networks 2>&1)
wpa_networks_status=$?

current_ssid=$(printf '%s\n' "$wpa_status_output" | awk -F= '$1 == "ssid" {print $2; exit}')
current_ip=$(printf '%s\n' "$wpa_status_output" | awk -F= '$1 == "ip_address" {print $2; exit}')
[ -n "$current_ip" ] || current_ip=$(printf '%s\n' "$ip_addr_output" | awk '/inet / {sub(/\/.*/, "", $2); print $2; exit}')
gateway_value=$(printf '%s\n' "$ip_route_output" | awk '$1 == "default" {print $3; exit}')
power_save_value=$(printf '%s\n' "$power_save_output" | awk -F: '/Power save/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}')
rollback_line=$(printf '%s\n' "$wpa_networks_output" | awk -F '\t' -v ssid="$ROLLBACK_SSID" '$2 == ssid {print; exit}')
rollback_id=$(printf '%s\n' "$rollback_line" | awk -F '\t' '{print $1}')
rollback_flags=$(printf '%s\n' "$rollback_line" | awk -F '\t' '{print $4}')
target_line=$(printf '%s\n' "$wpa_networks_output" | awk -F '\t' -v ssid="$TARGET_SSID" '$2 == ssid {print; exit}')

[ "$hostname_value" = "pocket-node" ] || mark_ko
[ "$user_value" = "warzy" ] || mark_ko
[ "$hostname_status" -eq 0 ] || mark_ko
[ "$user_status" -eq 0 ] || mark_ko
[ "$uptime_status" -eq 0 ] || mark_ko
[ "$ip_addr_status" -eq 0 ] || mark_ko
[ "$ip_route_status" -eq 0 ] || mark_ko
[ "$iw_info_status" -eq 0 ] || mark_ko
[ "$power_save_status" -eq 0 ] || mark_ko
[ "$wpa_status_status" -eq 0 ] || mark_ko
[ "$wpa_networks_status" -eq 0 ] || mark_ko
[ -n "$current_ssid" ] || mark_ko
[ -n "$current_ip" ] || mark_ko
[ -n "$gateway_value" ] || mark_ko
[ "$power_save_value" = "off" ] || mark_ko
[ -n "$rollback_line" ] || mark_ko
case "$rollback_flags" in
  *"[CURRENT]"*) ;;
  *) mark_ko ;;
esac

printf '[wifi-kit] connect-safe apply preflight readonly\n'
kv "mode" "preflight-readonly"
kv "network_writes" "false"
kv "secrets" "not-read-not-written-not-logged"
kv "wpa_cli_commands" "status,list_networks"
kv "hostname_status" "$hostname_status"
kv "whoami_status" "$user_status"
kv "uptime_status" "$uptime_status"
kv "ip_addr_status" "$ip_addr_status"
kv "ip_route_status" "$ip_route_status"
kv "iw_info_status" "$iw_info_status"
kv "power_save_status" "$power_save_status"
kv "wpa_status_status" "$wpa_status_status"
kv "wpa_list_networks_status" "$wpa_networks_status"
kv "hostname" "$hostname_value"
kv "user" "$user_value"
kv "uptime" "$uptime_value"
kv "interface" "$IFACE"
kv "current_ssid" "${current_ssid:-missing}"
kv "current_ip" "${current_ip:-missing}"
kv "gateway" "${gateway_value:-missing}"
kv "power_save" "${power_save_value:-missing}"
kv "rollback_ssid" "$ROLLBACK_SSID"
kv "rollback_present" "$([ -n "$rollback_line" ] && printf yes || printf no)"
kv "rollback_current" "$(printf '%s\n' "$rollback_flags" | grep -q '\[CURRENT\]' && printf yes || printf no)"
kv "rollback_id" "${rollback_id:-missing}"
kv "target_ssid" "$TARGET_SSID"
kv "target_profile_present" "$([ -n "$target_line" ] && printf yes || printf no)"
kv "readiness" "$readiness"

printf '\n[raw-ip-addr-show-%s]\n%s\n' "$IFACE" "$ip_addr_output"
printf '\n[raw-ip-route]\n%s\n' "$ip_route_output"
printf '\n[raw-iw-dev-%s-info]\n%s\n' "$IFACE" "$iw_info_output"
printf '\n[raw-iw-dev-%s-get-power_save]\n%s\n' "$IFACE" "$power_save_output"
printf '\n[raw-wpa-cli-status]\n%s\n' "$wpa_status_output"
printf '\n[raw-wpa-cli-list-networks]\n%s\n' "$wpa_networks_output"
REMOTE
}

run_apply_experimental() {
  [ "$dangerous_real_apply" -eq 1 ] || fail "apply locked: missing --dangerous-real-apply"
  [ "$apply_confirm" = "WIFI-KIT TEMP APPLY ROLLBACK" ] || fail "apply locked: confirmation mismatch"
  [ "${WIFI_KIT_TARGET_PSK+x}" = "x" ] || fail "apply locked: WIFI_KIT_TARGET_PSK is required"
  [ -n "$WIFI_KIT_TARGET_PSK" ] || fail "apply locked: WIFI_KIT_TARGET_PSK is empty"
  [ -n "$iface" ] || iface="wlan0"

  script_path=$(mktemp)
  trap 'rm -f "$script_path"' EXIT INT TERM
  cat >"$script_path" <<'REMOTE'
set -u

PATH="/usr/sbin:/sbin:/usr/bin:/bin:$PATH"
IFACE=${IFACE:-wlan0}
TARGET_SSID=${TARGET_SSID:-SFR_7B28}
ROLLBACK_SSID=${ROLLBACK_SSID:-GL-MT6000-d53}
IP_TIMEOUT=${IP_TIMEOUT:-30}
VALIDATION_TIMEOUT=${VALIDATION_TIMEOUT:-20}
ROLLBACK_TIMEOUT=${ROLLBACK_TIMEOUT:-30}
REACHABILITY_PROBE=${REACHABILITY_PROBE:-1.1.1.1}
target_id=""
rollback_id=""
rollback_attempted="no"
cleanup_attempted="no"

kv() {
  printf '%s=%s\n' "$1" "$2"
}

now_epoch() {
  date +%s
}

now_iso() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

log_step() {
  printf 'step=%s\n' "$1"
  kv "step_timestamp" "$(now_iso)"
}

status_field() {
  field=$1
  awk -F= -v field="$field" '$1 == field {print $2; exit}'
}

snapshot_status() {
  label=$1
  status_output=$(wpa_cli -i "$IFACE" status 2>&1 || true)
  route_output=$(ip route 2>&1 || true)
  kv "${label}_timestamp" "$(now_iso)"
  kv "${label}_wpa_state" "$(printf '%s\n' "$status_output" | status_field wpa_state)"
  kv "${label}_ssid" "$(printf '%s\n' "$status_output" | status_field ssid)"
  kv "${label}_bssid" "$(printf '%s\n' "$status_output" | status_field bssid)"
  kv "${label}_freq" "$(printf '%s\n' "$status_output" | status_field freq)"
  kv "${label}_ip" "$(printf '%s\n' "$status_output" | status_field ip_address)"
  kv "${label}_default_route" "$(printf '%s\n' "$route_output" | awk '$1 == "default" {print $0; exit}')"
}

snapshot_networks() {
  label=$1
  printf '\n[%s-list-networks]\n' "$label"
  wpa_cli -i "$IFACE" list_networks 2>&1 || true
}

ping_probe() {
  label=$1
  target=$2
  output=$(ping -c 1 -W "$VALIDATION_TIMEOUT" "$target" 2>&1)
  status=$?
  kv "${label}_target" "$target"
  kv "${label}_status" "$status"
  kv "${label}_output" "$(printf '%s\n' "$output" | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g')"
  return "$status"
}

rollback_and_cleanup() {
  if [ -n "$rollback_id" ]; then
    rollback_attempted="yes"
    wpa_cli -i "$IFACE" select_network "$rollback_id" >/dev/null 2>&1 || true
  fi
  if [ -n "$target_id" ]; then
    cleanup_attempted="yes"
    wpa_cli -i "$IFACE" remove_network "$target_id" >/dev/null 2>&1 || true
    target_id=""
  fi
}

fail_apply() {
  snapshot_status "failure_before_rollback_cleanup"
  rollback_and_cleanup
  snapshot_status "failure_after_rollback_cleanup"
  snapshot_networks "failure-after-cleanup"
  kv "status" "failed"
  kv "reason" "$1"
  kv "rollback_attempted" "$rollback_attempted"
  kv "cleanup_attempted" "$cleanup_attempted"
  kv "save_config" "not-called"
  exit 1
}

wait_for_ssid() {
  expected_ssid=$1
  timeout_seconds=$2
  deadline=$(( $(date +%s) + timeout_seconds ))
  seen_ssid=""

  while [ "$(date +%s)" -lt "$deadline" ]; do
    status_output=$(wpa_cli -i "$IFACE" status 2>&1 || true)
    seen_ssid=$(printf '%s\n' "$status_output" | awk -F= '$1 == "ssid" {print $2; exit}')
    [ "$seen_ssid" = "$expected_ssid" ] && return 0
    sleep 1
  done

  return 1
}

[ -n "$WIFI_KIT_TARGET_PSK" ] || fail_apply "secret-empty"

printf '[wifi-kit] connect-safe experimental apply\n'
kv "mode" "dangerous-real-apply"
kv "apply_start_timestamp" "$(now_iso)"
kv "secret" "runtime-only-not-logged"
kv "save_config" "not-called"
kv "target_ssid" "$TARGET_SSID"
kv "rollback_ssid" "$ROLLBACK_SSID"

log_step "preflight-readonly"
hostname_value=$(hostname 2>&1) || fail_apply "hostname-failed"
user_value=$(whoami 2>&1) || fail_apply "whoami-failed"
ip_route_output=$(ip route 2>&1) || fail_apply "ip-route-failed"
power_save_output=$(iw dev "$IFACE" get power_save 2>&1) || fail_apply "power-save-read-failed"
wpa_status_output=$(wpa_cli -i "$IFACE" status 2>&1) || fail_apply "wpa-status-failed"
wpa_networks_output=$(wpa_cli -i "$IFACE" list_networks 2>&1) || fail_apply "wpa-list-networks-failed"
current_ssid=$(printf '%s\n' "$wpa_status_output" | awk -F= '$1 == "ssid" {print $2; exit}')
current_ip=$(printf '%s\n' "$wpa_status_output" | awk -F= '$1 == "ip_address" {print $2; exit}')
gateway_value=$(printf '%s\n' "$ip_route_output" | awk '$1 == "default" {print $3; exit}')
power_save_value=$(printf '%s\n' "$power_save_output" | awk -F: '/Power save/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}')
rollback_line=$(printf '%s\n' "$wpa_networks_output" | awk -F '\t' -v ssid="$ROLLBACK_SSID" '$2 == ssid {print; exit}')
rollback_id=$(printf '%s\n' "$rollback_line" | awk -F '\t' '{print $1}')
rollback_flags=$(printf '%s\n' "$rollback_line" | awk -F '\t' '{print $4}')
target_line=$(printf '%s\n' "$wpa_networks_output" | awk -F '\t' -v ssid="$TARGET_SSID" '$2 == ssid {print; exit}')

[ "$hostname_value" = "pocket-node" ] || fail_apply "preflight-hostname-not-pocket-node"
[ "$user_value" = "warzy" ] || fail_apply "preflight-user-not-warzy"
[ "$current_ssid" = "$ROLLBACK_SSID" ] || fail_apply "preflight-current-ssid-not-rollback"
[ -n "$current_ip" ] || fail_apply "preflight-current-ip-missing"
[ -n "$gateway_value" ] || fail_apply "preflight-gateway-missing"
[ "$power_save_value" = "off" ] || fail_apply "preflight-power-save-not-off"
[ -n "$rollback_id" ] || fail_apply "preflight-rollback-id-missing"
case "$rollback_flags" in
  *"[CURRENT]"*) ;;
  *) fail_apply "preflight-rollback-not-current" ;;
esac
[ -z "$target_line" ] || fail_apply "preflight-target-profile-already-present"
kv "preflight_readiness" "OK"
kv "rollback_id" "$rollback_id"
kv "current_ip" "$current_ip"
kv "gateway" "$gateway_value"
snapshot_networks "before-apply"
snapshot_status "before_apply"

log_step "add-network"
target_id=$(wpa_cli -i "$IFACE" add_network) || fail_apply "add-network-failed"
[ -n "$target_id" ] || fail_apply "add-network-empty-id"
kv "temporary_target_id" "$target_id"

log_step "set-network-ssid"
wpa_cli -i "$IFACE" set_network "$target_id" ssid "\"$TARGET_SSID\"" >/dev/null || fail_apply "set-network-ssid-failed"

log_step "set-network-psk"
wpa_cli -i "$IFACE" set_network "$target_id" psk "\"$WIFI_KIT_TARGET_PSK\"" >/dev/null || fail_apply "set-network-psk-failed"
unset WIFI_KIT_TARGET_PSK

log_step "select-target"
select_start=$(now_epoch)
snapshot_status "before_select_target"
wpa_cli -i "$IFACE" select_network "$target_id" >/dev/null || fail_apply "select-target-failed"
snapshot_status "after_select_target"

log_step "wait-ip"
deadline=$(( $(date +%s) + IP_TIMEOUT ))
target_ip=""
dhcp_start=$select_start
poll_count=0
while [ "$(date +%s)" -lt "$deadline" ]; do
  target_status=$(wpa_cli -i "$IFACE" status 2>&1 || true)
  target_route=$(ip route 2>&1 || true)
  poll_count=$((poll_count + 1))
  kv "dhcp_poll_${poll_count}_timestamp" "$(now_iso)"
  kv "dhcp_poll_${poll_count}_wpa_state" "$(printf '%s\n' "$target_status" | status_field wpa_state)"
  kv "dhcp_poll_${poll_count}_ssid" "$(printf '%s\n' "$target_status" | status_field ssid)"
  kv "dhcp_poll_${poll_count}_bssid" "$(printf '%s\n' "$target_status" | status_field bssid)"
  kv "dhcp_poll_${poll_count}_freq" "$(printf '%s\n' "$target_status" | status_field freq)"
  target_ip=$(printf '%s\n' "$target_status" | awk -F= '$1 == "ip_address" {print $2; exit}')
  kv "dhcp_poll_${poll_count}_ip" "${target_ip:-missing}"
  kv "dhcp_poll_${poll_count}_default_route" "$(printf '%s\n' "$target_route" | awk '$1 == "default" {print $0; exit}')"
  [ -n "$target_ip" ] && break
  sleep 1
done
[ -n "$target_ip" ] || fail_apply "target-ip-timeout"
dhcp_end=$(now_epoch)
kv "dhcp_elapsed_seconds" "$((dhcp_end - dhcp_start))"
kv "target_ip" "$target_ip"
snapshot_status "before_validation"

log_step "validate-gateway"
target_gateway=$(ip route | awk '$1 == "default" {print $3; exit}')
[ -n "$target_gateway" ] || fail_apply "target-gateway-missing"
ping_probe "gateway_ping" "$target_gateway" || fail_apply "target-gateway-unreachable"
kv "target_gateway" "$target_gateway"

log_step "validate-reachability"
ping_probe "reachability_ping" "$REACHABILITY_PROBE" || fail_apply "target-reachability-failed"

log_step "forced-rollback"
snapshot_status "before_rollback"
rollback_start=$(now_epoch)
wpa_cli -i "$IFACE" select_network "$rollback_id" >/dev/null || fail_apply "rollback-select-failed"
rollback_attempted="yes"
wait_for_ssid "$ROLLBACK_SSID" "$ROLLBACK_TIMEOUT" || fail_apply "rollback-validation-failed"
rollback_end=$(now_epoch)
kv "select_target_to_rollback_seconds" "$((rollback_start - select_start))"
kv "rollback_elapsed_seconds" "$((rollback_end - rollback_start))"
snapshot_status "after_rollback"
kv "rollback_validated" "yes"

log_step "cleanup-temporary-profile"
wpa_cli -i "$IFACE" remove_network "$target_id" >/dev/null || fail_apply "cleanup-remove-target-failed"
target_id=""
cleanup_attempted="yes"
snapshot_networks "after-cleanup"

kv "cleanup_temporary_profile" "done"
kv "save_config" "not-called"
kv "status" "rolled-back-cleaned"
exit 0
REMOTE

  {
    printf '%s\n' "$WIFI_KIT_TARGET_PSK"
    cat "$script_path"
  } | env \
      IFACE="$iface" \
      TARGET_SSID="$target_ssid" \
      ROLLBACK_SSID="$rollback_ssid" \
      IP_TIMEOUT="$ip_timeout" \
      VALIDATION_TIMEOUT="$validation_timeout" \
      ROLLBACK_TIMEOUT="$rollback_timeout" \
      REACHABILITY_PROBE="$reachability_probe" \
      ssh -i "$preflight_identity" \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=yes \
      "$preflight_user@$preflight_host" \
      'read -r WIFI_KIT_TARGET_PSK && export WIFI_KIT_TARGET_PSK && sh -s'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      [ -z "$mode" ] || fail "choose only one mode"
      mode="dry-run"
      ;;
    --preflight-readonly)
      [ -z "$mode" ] || fail "choose only one mode"
      mode="preflight-readonly"
      ;;
    --apply)
      [ -z "$mode" ] || fail "choose only one mode"
      mode="apply"
      ;;
    --dangerous-real-apply)
      dangerous_real_apply=1
      ;;
    --confirm)
      [ "$#" -gt 1 ] || fail "--confirm requires a value"
      apply_confirm="$2"
      shift
      ;;
    --iface)
      [ "$#" -gt 1 ] || fail "--iface requires a value"
      iface="$2"
      shift
      ;;
    --from)
      [ "$#" -gt 1 ] || fail "--from requires a value"
      from_ssid="$2"
      shift
      ;;
    --to)
      [ "$#" -gt 1 ] || fail "--to requires a value"
      to_ssid="$2"
      shift
      ;;
    --gateway)
      [ "$#" -gt 1 ] || fail "--gateway requires a value"
      gateway="$2"
      shift
      ;;
    --reachability-probe)
      [ "$#" -gt 1 ] || fail "--reachability-probe requires a value"
      reachability_probe="$2"
      shift
      ;;
    --ip-timeout)
      [ "$#" -gt 1 ] || fail "--ip-timeout requires a value"
      ip_timeout="$2"
      shift
      ;;
    --validation-timeout)
      [ "$#" -gt 1 ] || fail "--validation-timeout requires a value"
      validation_timeout="$2"
      shift
      ;;
    --rollback-timeout)
      [ "$#" -gt 1 ] || fail "--rollback-timeout requires a value"
      rollback_timeout="$2"
      shift
      ;;
    --preflight-host)
      [ "$#" -gt 1 ] || fail "--preflight-host requires a value"
      preflight_host="$2"
      shift
      ;;
    --preflight-user)
      [ "$#" -gt 1 ] || fail "--preflight-user requires a value"
      preflight_user="$2"
      shift
      ;;
    --identity)
      [ "$#" -gt 1 ] || fail "--identity requires a value"
      preflight_identity="$2"
      shift
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
  dry-run) ;;
  preflight-readonly)
    run_preflight_readonly
    exit $?
    ;;
  apply)
    run_apply_experimental
    exit $?
    ;;
  *) fail "explicit --dry-run, --preflight-readonly, or --apply is required" ;;
esac
iface=${iface:-"<interface>"}
from_ssid=${from_ssid:-"<profile-a>"}
to_ssid=${to_ssid:-"<profile-b>"}

printf '[wifi-kit] connect-safe apply prototype\n'
kv "mode" "dry-run"
kv "apply" "locked"
kv "real_apply_allowed" "false"
kv "network_writes" "false"
kv "secrets" "not-read-not-written-not-logged"
kv "wpa_cli" "not-called"
kv "interface" "$iface"
kv "current_profile_a" "$from_ssid"
kv "temporary_target_profile_b" "$to_ssid"
kv "no_save_config" "true"

section "future-transaction-plan"
kv "01.preflight" "verify operator safety, interface, existing A profile, and rollback readiness"
kv "02.snapshot" "capture current A ssid, network id, ip, route, gateway, and reachability state"
kv "03.create_temporary_target_profile" "future add transient B profile without persistence"
kv "04.configure_ssid" "future set temporary B ssid only"
kv "05.configure_psk_from_runtime_only_secret" "future consume operator-provided secret without logging or storing it"
kv "06.temporary_select_target" "future temporary select target B"
kv "07.wait_ip" "future wait up to ${ip_timeout}s for target IP"
kv "08.validate_gateway" "future validate gateway ${gateway:-operator-provided-or-discovered}"
kv "09.validate_reachability" "future validate reachability to $reachability_probe within ${validation_timeout}s"
kv "10.rollback_to_a" "future select previous A profile after validation window or on any failure"
kv "11.cleanup_temporary_profile" "future remove transient B profile"
kv "12.no_save_config" "never persist during this prototype flow"

section "locked-commands"
kv "add_network" "not-executed"
kv "set_network" "not-executed"
kv "select_network" "not-executed"
kv "remove_network" "not-executed"
kv "save_config" "not-executed"
kv "restart_network" "not-executed"
kv "hostapd_dnsmasq" "not-touched"

section "rollback-contract"
kv "rollback_source" "snapshot profile A"
kv "rollback_trigger" "preflight-failed, ip-timeout, gateway-failed, reachability-failed, operator-abort"
kv "rollback_deadline" "${rollback_timeout}s"
kv "cleanup_after_rollback" "temporary profile B only"
kv "persistence_boundary" "no save_config"

section "operator-next-step"
kv "decision" "review dry-run output only"
kv "unlock_apply_requires" "separate reviewed implementation with explicit operator authorization"
