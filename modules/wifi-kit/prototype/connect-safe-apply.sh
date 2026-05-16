#!/bin/sh
set -eu

mode=""
iface=""
from_ssid=""
to_ssid=""
gateway=""
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

Optional:
  --iface <name>                Future interface name. Default: <interface>
  --from <current-ssid>         Future rollback profile A. Default: <profile-a>
  --to <target-ssid>            Future temporary target profile B. Default: <profile-b>
  --gateway <ip>                 Future expected gateway validation target.
  --reachability-probe <target>  Future reachability probe. Default: 1.1.1.1
  --ip-timeout <seconds>         Future DHCP/IP wait timeout. Default: 30
  --validation-timeout <seconds> Future validation timeout. Default: 20
  --rollback-timeout <seconds>   Future rollback timeout. Default: 30

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

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      [ -z "$mode" ] || fail "choose only one mode"
      mode="dry-run"
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

[ "$mode" = "dry-run" ] || fail "explicit --dry-run is required"
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
