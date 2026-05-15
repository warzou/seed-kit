#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage:
  ap-reconnect-plan.sh --dry-run [--iface IFACE] [--fallback SSID] [--ap-ssid SSID]

Print a plan-only Wifi-Kit boot reconnect and temporary AP fallback flow.

This script does not modify networking. It does not start hostapd, dnsmasq,
NetworkManager, systemd-networkd, or wpa_supplicant. It does not read or log
Wi-Fi secrets.
EOF
}

iface="wlan0"
fallback="Flint"
ap_ssid="Wifi-Kit-Setup"
mode=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --plan|--dry-run)
      mode="plan"
      shift
      ;;
    --iface)
      iface="${2:-}"
      [ -n "$iface" ] || {
        echo "error=missing-iface" >&2
        exit 2
      }
      shift 2
      ;;
    --fallback)
      fallback="${2:-}"
      [ -n "$fallback" ] || {
        echo "error=missing-fallback" >&2
        exit 2
      }
      shift 2
      ;;
    --ap-ssid)
      ap_ssid="${2:-}"
      [ -n "$ap_ssid" ] || {
        echo "error=missing-ap-ssid" >&2
        exit 2
      }
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error=unknown-argument arg=$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ "$mode" != "plan" ]; then
  echo "error=dry-run-required"
  echo "real_apply_allowed=false"
  echo "network_writes=false"
  exit 2
fi

cat <<EOF
wifi_kit_ap_reconnect_plan=true
mode=plan-only
interface=$iface
fallback_network=$fallback
temporary_ap_ssid=$ap_ssid
real_apply_allowed=false
network_writes=false
secrets_read=false
secrets_logged=false

state=boot
action=preflight
check=wifi-stability
check=backend-detect
check=ssh-safety

state=load-known-networks
source=/etc/seed-kit/wifi-kit/validated-networks.json
note=metadata-only-no-secrets

state=try-known-networks
order=priority-then-last-success-then-fallback
candidate=validated-networks
candidate=fallback-network

state=validate-candidate
validate=ip-address
validate=default-route
validate=gateway-reachability
validate=dns-if-safe
validate=ssh-safety

state=success
action=stay-on-known-wifi
metadata_update=last_success_retry_count

state=known-networks-failed
action=rollback-or-next-candidate
fallback=$fallback

state=no-known-network-works
action=temporary-ap-plan
ap_apply_allowed=false
would_require_future=hostapd
would_require_future=dnsmasq
would_require_future=explicit-review

state=phone-ui
action=scan-select-plan
connect_safe_real_apply=false

state=new-wifi-validation
action=future-connect-safe-transaction
promote_to_known_only_after=validation-success

state=failure
action=rollback-or-return-ap
EOF
