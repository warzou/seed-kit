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

Forbidden:
  --apply
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
      fail "apply locked"
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
  *) fail "explicit --dry-run or --preflight-readonly is required" ;;
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
