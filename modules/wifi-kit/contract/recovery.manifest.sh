#!/bin/sh
set -eu

# Wifi-Kit recovery manifest (sourceable shell declaration)
# Purpose:
# - describe future AP/captive recovery behavior for Seed-Kit core previews
# - keep recovery execution behind explicit guided apply and wrapper controls
# - avoid real AP, network, runtime, or privilege mutation from this artifact

WIFI_KIT_RECOVERY_MANIFEST_ID="wifi-kit-recovery"
WIFI_KIT_RECOVERY_MANIFEST_MODULE_ID="wifi-kit"
WIFI_KIT_RECOVERY_MANIFEST_TYPE="recovery"
WIFI_KIT_RECOVERY_MANIFEST_VERSION="1"
WIFI_KIT_RECOVERY_APPLY_PHASE_TARGET="recovery-preview"

WIFI_KIT_RECOVERY_MODE="explicit-ap-captive"
WIFI_KIT_RECOVERY_WRAPPER_ACTION="start-ap-mode"
WIFI_KIT_RECOVERY_RETURN_ACTION="return-default-network"
WIFI_KIT_RECOVERY_WRAPPER_PATH="/opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh"
WIFI_KIT_RECOVERY_GUARD_PATH="/opt/seed-kit/wifi-kit/wifi-kit-recovery-guard.sh"
WIFI_KIT_RECOVERY_AP_HELPER_PATH="/opt/seed-kit/wifi-kit/ap-setup-test.sh"

WIFI_KIT_RECOVERY_IFACE="wlan0"
WIFI_KIT_RECOVERY_AP_IFACE="wlan0_ap"
WIFI_KIT_RECOVERY_AP_SSID_TEMPLATE="Wifi-Kit-<hostname>"
WIFI_KIT_RECOVERY_AP_IP="192.168.50.1/24"
WIFI_KIT_RECOVERY_DHCP_RANGE="192.168.50.20-192.168.50.80"
WIFI_KIT_RECOVERY_DHCP_LEASE="1h"
WIFI_KIT_RECOVERY_CAPTIVE_PORT="80"
WIFI_KIT_RECOVERY_DEFAULT_TIMEOUT_SECONDS="300"

WIFI_KIT_RECOVERY_TEMPORARY_FILES='
/tmp/wifi-kit-hostapd-test.conf
/tmp/wifi-kit-hostapd-test.conf.redacted
/tmp/wifi-kit-hostapd-test.log
/tmp/wifi-kit-hostapd-test.pid
/tmp/wifi-kit-dnsmasq-recovery.conf
/tmp/wifi-kit-dnsmasq-recovery.conf.redacted
/tmp/wifi-kit-dnsmasq-recovery.log
/tmp/wifi-kit-dnsmasq-recovery.pid
/tmp/wifi-kit-ui-recovery.log
/tmp/wifi-kit-ui-recovery.pid
/tmp/wifi-kit-ap-only-nm-state
'

WIFI_KIT_RECOVERY_REQUIRED_DEPENDENCIES='
python3
network-manager
nmcli
hostapd
dnsmasq
iw
iproute2
sudoers-wrapper
'

WIFI_KIT_RECOVERY_READINESS_CHECKS='
wrapper installed
sudoers rule installed
hostapd present
dnsmasq present
recovery guard installed
normal network state readable
no active Wifi-Kit recovery leftovers
'

WIFI_KIT_RECOVERY_HEALTH_CHECKS='
captive portal responds on 192.168.50.1:80
hostapd pid belongs to Wifi-Kit config
dnsmasq pid belongs to Wifi-Kit config
guard status clean after return
NetworkManager owns wlan0 after cleanup
'

WIFI_KIT_RECOVERY_FUTURE_ACTIONS='
run wrapper start-ap-mode after explicit confirmation
start temporary hostapd
start temporary dnsmasq
start temporary captive UI on port 80
run timeout-based cleanup
run return-default-network after explicit confirmation
'

WIFI_KIT_RECOVERY_FORBIDDEN='
no-ap-at-boot
no-ap-without-explicit-action
no-permanent-ap-plus-sta-assumption
no-save-config
no-delete-user-wifi-profiles
no-arbitrary-shell
no-reboot
no-secret-log
'

WIFI_KIT_RECOVERY_NON_ACTIONS='
no-ap-start
no-hostapd
no-dnsmasq
no-network-change
no-sudoers-write
no-systemd
no-runtime-start
no-secret
no-reboot
'

WIFI_KIT_RECOVERY_RISKS='
can interrupt current Wi-Fi during explicit recovery mode
requires local fallback path before apply
must clean up only Wifi-Kit scoped processes and files
must return wlan0 to NetworkManager
'

_wifi_kit_recovery_print_list() {
  _name="$1"
  _list="$2"
  printf '%s\n' "$_list" | sed '/^$/d' | while IFS= read -r _entry; do
    [ -n "$_entry" ] && printf '%s=%s\n' "$_name" "$_entry"
  done
}

module_wifi_kit_recovery_manifest() {
  printf 'WIFI_KIT_RECOVERY_MANIFEST_ID=%s\n' "$WIFI_KIT_RECOVERY_MANIFEST_ID"
  printf 'WIFI_KIT_RECOVERY_MANIFEST_MODULE_ID=%s\n' "$WIFI_KIT_RECOVERY_MANIFEST_MODULE_ID"
  printf 'WIFI_KIT_RECOVERY_MANIFEST_TYPE=%s\n' "$WIFI_KIT_RECOVERY_MANIFEST_TYPE"
  printf 'WIFI_KIT_RECOVERY_MANIFEST_VERSION=%s\n' "$WIFI_KIT_RECOVERY_MANIFEST_VERSION"
  printf 'WIFI_KIT_RECOVERY_APPLY_PHASE_TARGET=%s\n' "$WIFI_KIT_RECOVERY_APPLY_PHASE_TARGET"
  printf 'WIFI_KIT_RECOVERY_MODE=%s\n' "$WIFI_KIT_RECOVERY_MODE"
  printf 'WIFI_KIT_RECOVERY_WRAPPER_ACTION=%s\n' "$WIFI_KIT_RECOVERY_WRAPPER_ACTION"
  printf 'WIFI_KIT_RECOVERY_RETURN_ACTION=%s\n' "$WIFI_KIT_RECOVERY_RETURN_ACTION"
  printf 'WIFI_KIT_RECOVERY_WRAPPER_PATH=%s\n' "$WIFI_KIT_RECOVERY_WRAPPER_PATH"
  printf 'WIFI_KIT_RECOVERY_GUARD_PATH=%s\n' "$WIFI_KIT_RECOVERY_GUARD_PATH"
  printf 'WIFI_KIT_RECOVERY_AP_HELPER_PATH=%s\n' "$WIFI_KIT_RECOVERY_AP_HELPER_PATH"
  printf 'WIFI_KIT_RECOVERY_IFACE=%s\n' "$WIFI_KIT_RECOVERY_IFACE"
  printf 'WIFI_KIT_RECOVERY_AP_IFACE=%s\n' "$WIFI_KIT_RECOVERY_AP_IFACE"
  printf 'WIFI_KIT_RECOVERY_AP_SSID_TEMPLATE=%s\n' "$WIFI_KIT_RECOVERY_AP_SSID_TEMPLATE"
  printf 'WIFI_KIT_RECOVERY_AP_IP=%s\n' "$WIFI_KIT_RECOVERY_AP_IP"
  printf 'WIFI_KIT_RECOVERY_DHCP_RANGE=%s\n' "$WIFI_KIT_RECOVERY_DHCP_RANGE"
  printf 'WIFI_KIT_RECOVERY_DHCP_LEASE=%s\n' "$WIFI_KIT_RECOVERY_DHCP_LEASE"
  printf 'WIFI_KIT_RECOVERY_CAPTIVE_PORT=%s\n' "$WIFI_KIT_RECOVERY_CAPTIVE_PORT"
  printf 'WIFI_KIT_RECOVERY_DEFAULT_TIMEOUT_SECONDS=%s\n' "$WIFI_KIT_RECOVERY_DEFAULT_TIMEOUT_SECONDS"
  _wifi_kit_recovery_print_list WIFI_KIT_RECOVERY_TEMPORARY_FILE "$WIFI_KIT_RECOVERY_TEMPORARY_FILES"
  _wifi_kit_recovery_print_list WIFI_KIT_RECOVERY_REQUIRED_DEPENDENCY "$WIFI_KIT_RECOVERY_REQUIRED_DEPENDENCIES"
  _wifi_kit_recovery_print_list WIFI_KIT_RECOVERY_READINESS_CHECK "$WIFI_KIT_RECOVERY_READINESS_CHECKS"
  _wifi_kit_recovery_print_list WIFI_KIT_RECOVERY_HEALTH_CHECK "$WIFI_KIT_RECOVERY_HEALTH_CHECKS"
  _wifi_kit_recovery_print_list WIFI_KIT_RECOVERY_FUTURE_ACTION "$WIFI_KIT_RECOVERY_FUTURE_ACTIONS"
  _wifi_kit_recovery_print_list WIFI_KIT_RECOVERY_FORBIDDEN "$WIFI_KIT_RECOVERY_FORBIDDEN"
  _wifi_kit_recovery_print_list WIFI_KIT_RECOVERY_NON_ACTION "$WIFI_KIT_RECOVERY_NON_ACTIONS"
  _wifi_kit_recovery_print_list WIFI_KIT_RECOVERY_RISK "$WIFI_KIT_RECOVERY_RISKS"
}

if [ "${1-}" = "print" ]; then
  module_wifi_kit_recovery_manifest
  exit 0
fi

