#!/bin/sh
set -eu

# Wifi-Kit sudoers manifest (sourceable shell declaration)
# Purpose:
# - describe the exact privileged wrapper commands for Seed-Kit core previews
# - keep sudoers rendering and apply orchestration outside Wifi-Kit
# - avoid real sudoers, runtime, or network mutation from this artifact

WIFI_KIT_SUDOERS_MANIFEST_ID="wifi-kit-sudoers"
WIFI_KIT_SUDOERS_MANIFEST_MODULE_ID="wifi-kit"
WIFI_KIT_SUDOERS_MANIFEST_TYPE="sudoers"
WIFI_KIT_SUDOERS_MANIFEST_VERSION="1"
WIFI_KIT_SUDOERS_APPLY_PHASE_TARGET="configure-sudoers-preview"

WIFI_KIT_SUDOERS_SERVICE_USER="seed-kit-wifi"
WIFI_KIT_SUDOERS_SERVICE_USER_POLICY="placeholder-core-may-validate-before-apply"

WIFI_KIT_SUDOERS_WRAPPER_PATH="/opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh"
WIFI_KIT_SUDOERS_WRAPPER_OWNER="root:root"
WIFI_KIT_SUDOERS_WRAPPER_MODE="0755"
WIFI_KIT_SUDOERS_WRAPPER_POLICY="root-owned-not-web-writable"

WIFI_KIT_SUDOERS_ALLOWED_ACTIONS='
start-ap-mode
return-default-network
connect-wifi
ap-return-check-once
node-ip-test
node-ip-confirm
node-ip-rollback
reboot-system
shutdown-system
reinstall-runtime
restart-ui
forensics-snapshot
'

WIFI_KIT_SUDOERS_ALLOWED_COMMANDS='
/opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh start-ap-mode
/opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh return-default-network
/opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh connect-wifi
/opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh ap-return-check-once
/opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh node-ip-test
/opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh node-ip-confirm
/opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh node-ip-rollback
/opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh reboot-system
/opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh shutdown-system
/opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh reinstall-runtime
/opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh restart-ui
/opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh forensics-snapshot
'

WIFI_KIT_SUDOERS_ALLOWED_SUDO_COMMANDS='
sudo -n /opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh start-ap-mode
sudo -n /opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh return-default-network
sudo -n /opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh connect-wifi
sudo -n /opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh ap-return-check-once
sudo -n /opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh node-ip-test
sudo -n /opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh node-ip-confirm
sudo -n /opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh node-ip-rollback
sudo -n /opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh reboot-system
sudo -n /opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh shutdown-system
sudo -n /opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh reinstall-runtime
sudo -n /opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh restart-ui
sudo -n /opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh forensics-snapshot
'

WIFI_KIT_SUDOERS_PREVIEW_RULE='seed-kit-wifi ALL=(root) NOPASSWD: /opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh start-ap-mode, /opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh return-default-network, /opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh connect-wifi, /opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh ap-return-check-once, /opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh node-ip-test, /opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh node-ip-confirm, /opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh node-ip-rollback, /opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh reboot-system, /opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh shutdown-system, /opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh reinstall-runtime, /opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh restart-ui, /opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh forensics-snapshot'

WIFI_KIT_SUDOERS_FORBIDDEN='
no-sudo-sh
no-sudo-bash
no-wildcard
no-sudo-nmcli-direct
no-sudo-systemctl-direct
no-sudo-hostapd-direct
no-sudo-dnsmasq-direct
no-web-writable-wrapper-path
no-free-argument
no-direct-reboot
no-save-config
'

WIFI_KIT_SUDOERS_NON_ACTIONS='
no-sudoers-write
no-visudo
no-runtime-outside-reinstall-runtime-wrapper
no-network-change
no-ap-start
no-secret
'

WIFI_KIT_SUDOERS_READINESS_CHECKS='
wrapper target path known
wrapper expected root-owned
wrapper expected not web-writable
sudoers rule not applied during preview
sudo -n expected to fail until apply
'

_wifi_kit_sudoers_print_list() {
  _name="$1"
  _list="$2"
  printf '%s\n' "$_list" | sed '/^$/d' | while IFS= read -r _entry; do
    [ -n "$_entry" ] && printf '%s=%s\n' "$_name" "$_entry"
  done
}

module_wifi_kit_sudoers_manifest() {
  printf 'WIFI_KIT_SUDOERS_MANIFEST_ID=%s\n' "$WIFI_KIT_SUDOERS_MANIFEST_ID"
  printf 'WIFI_KIT_SUDOERS_MANIFEST_MODULE_ID=%s\n' "$WIFI_KIT_SUDOERS_MANIFEST_MODULE_ID"
  printf 'WIFI_KIT_SUDOERS_MANIFEST_TYPE=%s\n' "$WIFI_KIT_SUDOERS_MANIFEST_TYPE"
  printf 'WIFI_KIT_SUDOERS_MANIFEST_VERSION=%s\n' "$WIFI_KIT_SUDOERS_MANIFEST_VERSION"
  printf 'WIFI_KIT_SUDOERS_APPLY_PHASE_TARGET=%s\n' "$WIFI_KIT_SUDOERS_APPLY_PHASE_TARGET"
  printf 'WIFI_KIT_SUDOERS_SERVICE_USER=%s\n' "$WIFI_KIT_SUDOERS_SERVICE_USER"
  printf 'WIFI_KIT_SUDOERS_SERVICE_USER_POLICY=%s\n' "$WIFI_KIT_SUDOERS_SERVICE_USER_POLICY"
  printf 'WIFI_KIT_SUDOERS_WRAPPER_PATH=%s\n' "$WIFI_KIT_SUDOERS_WRAPPER_PATH"
  printf 'WIFI_KIT_SUDOERS_WRAPPER_OWNER=%s\n' "$WIFI_KIT_SUDOERS_WRAPPER_OWNER"
  printf 'WIFI_KIT_SUDOERS_WRAPPER_MODE=%s\n' "$WIFI_KIT_SUDOERS_WRAPPER_MODE"
  printf 'WIFI_KIT_SUDOERS_WRAPPER_POLICY=%s\n' "$WIFI_KIT_SUDOERS_WRAPPER_POLICY"
  printf 'WIFI_KIT_SUDOERS_PREVIEW_RULE=%s\n' "$WIFI_KIT_SUDOERS_PREVIEW_RULE"
  _wifi_kit_sudoers_print_list WIFI_KIT_SUDOERS_ALLOWED_ACTION "$WIFI_KIT_SUDOERS_ALLOWED_ACTIONS"
  _wifi_kit_sudoers_print_list WIFI_KIT_SUDOERS_ALLOWED_COMMAND "$WIFI_KIT_SUDOERS_ALLOWED_COMMANDS"
  _wifi_kit_sudoers_print_list WIFI_KIT_SUDOERS_ALLOWED_SUDO_COMMAND "$WIFI_KIT_SUDOERS_ALLOWED_SUDO_COMMANDS"
  _wifi_kit_sudoers_print_list WIFI_KIT_SUDOERS_FORBIDDEN "$WIFI_KIT_SUDOERS_FORBIDDEN"
  _wifi_kit_sudoers_print_list WIFI_KIT_SUDOERS_NON_ACTION "$WIFI_KIT_SUDOERS_NON_ACTIONS"
  _wifi_kit_sudoers_print_list WIFI_KIT_SUDOERS_READINESS_CHECK "$WIFI_KIT_SUDOERS_READINESS_CHECKS"
}

if [ "${1-}" = "print" ]; then
  module_wifi_kit_sudoers_manifest
  exit 0
fi
