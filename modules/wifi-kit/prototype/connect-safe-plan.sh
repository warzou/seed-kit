#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# shellcheck source=helpers.sh
. "$SCRIPT_DIR/helpers.sh"

dry_run=0
iface=""
from_ssid=""
to_ssid=""
gateway=""
dns_probe="1.1.1.1"
ip_timeout="30"
validation_timeout="20"
rollback_timeout="30"

usage() {
  cat <<'EOF'
wifi-kit connect-safe plan prototype

Dry-run only. This script prints a future transaction plan for moving between
two already-known Wi-Fi profiles. It does not connect, write config, save
secrets, restart networking, or change routes.

Usage:
  sh modules/wifi-kit/prototype/connect-safe-plan.sh \
    --dry-run --iface wlan0 --from <current-ssid> --to <target-ssid>

Optional:
  --gateway <ip>              Expected gateway after target connection.
  --dns-probe <ip-or-host>    Future reachability probe target. Default: 1.1.1.1
  --ip-timeout <seconds>      Future DHCP/IP wait timeout. Default: 30
  --validation-timeout <sec>  Future validation timeout. Default: 20
  --rollback-timeout <sec>    Future rollback timeout. Default: 30

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
    --dry-run|--plan)
      dry_run=1
      ;;
    --apply)
      fail "--apply is intentionally not implemented; this prototype is plan-only"
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
    --dns-probe)
      [ "$#" -gt 1 ] || fail "--dns-probe requires a value"
      dns_probe="$2"
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

[ "$dry_run" -eq 1 ] || fail "explicit --dry-run is required"
[ -n "$iface" ] || fail "--iface is required"
[ -n "$from_ssid" ] || fail "--from <current-ssid> is required"
[ -n "$to_ssid" ] || fail "--to <target-ssid> is required"

ip_tool="$(find_tool ip 2>/dev/null || true)"
iw_tool="$(find_tool iw 2>/dev/null || true)"
wpa_cli_tool="$(find_tool wpa_cli 2>/dev/null || true)"
timeout_tool="$(find_tool timeout 2>/dev/null || true)"

printf '[wifi-kit] connect-safe future CLI plan\n'
kv "mode" "dry-run"
kv "real_apply_allowed" "false"
kv "network_writes" "false"
kv "secrets" "not-read-not-written-not-logged"
kv "interface" "$iface"
kv "from_ssid" "$from_ssid"
kv "to_ssid" "$to_ssid"

section "preflight-read-only"
kv "tool.ip" "${ip_tool:-missing}"
kv "tool.iw" "${iw_tool:-missing}"
kv "tool.wpa_cli" "${wpa_cli_tool:-missing}"
kv "tool.timeout" "${timeout_tool:-missing}"
kv "check.ssh_safety" "required-before-real-apply"
kv "check.rollback_path" "required-before-real-apply"
kv "check.known_networks" "both-ssid-profiles-must-already-exist"

section "snapshot-plan"
kv "snapshot.current_ssid" "$from_ssid"
kv "snapshot.interface" "$iface"
kv "snapshot.ip" "future-read: ip addr show dev $iface"
kv "snapshot.route" "future-read: ip route show default"
kv "snapshot.power_save" "future-read: iw dev $iface get power_save"
kv "snapshot.wpa_state" "future-read: wpa_cli -i $iface status"
kv "snapshot.secret_policy" "no-psk-in-wifi-kit-state"

section "future-attempt-plan"
kv "target.ssid" "$to_ssid"
kv "timeouts.wait_ip" "${ip_timeout}s"
kv "timeouts.validation" "${validation_timeout}s"
kv "timeouts.rollback" "${rollback_timeout}s"
kv "future.lookup_target" "wpa_cli -i $iface list_networks"
kv "future.temporary_switch" "wpa_cli -i $iface select_network <target-network-id>"
kv "future.wait_ip" "ip addr show dev $iface until address appears or timeout"
kv "future.validate_route" "ip route show default"
if [ -n "$gateway" ]; then
  kv "future.validate_gateway" "ping -c 1 -W 2 $gateway"
else
  kv "future.validate_gateway" "optional; provide --gateway for stricter validation"
fi
kv "future.validate_dns_or_reachability" "probe $dns_probe with bounded timeout"
kv "future.validate_ssh" "ensure current SSH route is not lost or unsafe"

section "rollback-plan"
kv "rollback.trigger" "ip-timeout,route-missing,reachability-failed,ssh-unsafe,operator-timeout"
kv "rollback.target_ssid" "$from_ssid"
kv "future.lookup_previous" "wpa_cli -i $iface list_networks"
kv "future.rollback_switch" "wpa_cli -i $iface select_network <previous-network-id>"
kv "future.rollback_validate" "ip,route,gateway,ssh-route"
kv "recovery_required_if" "rollback-cannot-be-proven"

section "commit-boundary"
kv "persist_target" "future-phase-only"
kv "wpa_cli.save_config" "forbidden-in-this-prototype"
kv "ui_integration" "none"
kv "decision" "plan-only"

section "operator-notes"
kv "dhcp" "reserve or know stable IPs for both SSIDs before real test"
kv "ssh" "prefer alternate access path before changing the active wlan link"
kv "physical_access" "recommended for first real apply"
kv "next_step" "review this plan; do not run real apply yet"
