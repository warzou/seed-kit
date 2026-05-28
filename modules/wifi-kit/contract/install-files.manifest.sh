#!/bin/sh
set -eu

# Wifi-Kit install-files manifest (sourceable shell declaration)
# Purpose:
# - describe files and directories for Seed-Kit core install-files-preview
# - keep copy/chmod/chown orchestration outside Wifi-Kit
# - avoid real system mutation from this artifact

WIFI_KIT_INSTALL_MANIFEST_ID="wifi-kit-install-files"
WIFI_KIT_INSTALL_MANIFEST_MODULE_ID="wifi-kit"
WIFI_KIT_INSTALL_MANIFEST_VERSION="1"

WIFI_KIT_INSTALL_APP_DIR="/opt/seed-kit/wifi-kit"
WIFI_KIT_INSTALL_UI_DIR="/opt/seed-kit/wifi-kit/ui"
WIFI_KIT_INSTALL_CONFIG_DIR="/etc/seed-kit/wifi-kit"
WIFI_KIT_INSTALL_RUNTIME_DIR="/run/seed-kit/wifi-kit"
WIFI_KIT_INSTALL_LOG_DIR="/var/log/seed-kit/wifi-kit"

WIFI_KIT_INSTALL_DIRS='
/opt/seed-kit/wifi-kit|root:root|0755|app-dir
/opt/seed-kit/wifi-kit/ui|root:root|0755|ui-dir
/etc/seed-kit/wifi-kit|root:root|0750|config-dir
/run/seed-kit/wifi-kit|root:root|0750|runtime-dir
/var/log/seed-kit/wifi-kit|root:root|0750|log-dir
'

WIFI_KIT_INSTALL_FILES='
prototype/ui/serve-readonly.py|/opt/seed-kit/wifi-kit/ui/serve-readonly.py|root:root|0644|normal-ui-backend
prototype/ui/index.html|/opt/seed-kit/wifi-kit/ui/index.html|root:root|0644|normal-ui-static
prototype/ap-setup-test.sh|/opt/seed-kit/wifi-kit/ap-setup-test.sh|root:root|0755|recovery-ap-helper
prototype/wifi-kit-connect-recovery.sh|/opt/seed-kit/wifi-kit/wifi-kit-connect-recovery.sh|root:root|0755|recovery-connect-helper
prototype/wifi-kit-connect-transaction.sh|/opt/seed-kit/wifi-kit/wifi-kit-connect-transaction.sh|root:root|0755|connect-transaction-helper
prototype/wifi-kit-recovery-guard.sh|/opt/seed-kit/wifi-kit/wifi-kit-recovery-guard.sh|root:root|0755|recovery-cleanup-guard
prototype/wifi-kit-action-wrapper.sh|/opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh|root:root|0755|privileged-action-wrapper
prototype/wifi-kit-ap-return-check.sh|/opt/seed-kit/wifi-kit/wifi-kit-ap-return-check.sh|root:root|0755|ap-return-check-helper
prototype/wifi-kit-node-ip-transaction.sh|/opt/seed-kit/wifi-kit/wifi-kit-node-ip-transaction.sh|root:root|0755|static-ip-transaction-helper
prototype/wifi-kit-runtime-watchdog.sh|/opt/seed-kit/wifi-kit/wifi-kit-runtime-watchdog.sh|root:root|0755|runtime-recovery-watchdog
prototype/wifi-kit-nm-ap-lab.sh|/opt/seed-kit/wifi-kit/wifi-kit-nm-ap-lab.sh|root:root|0755|networkmanager-ap-lab-helper
'

WIFI_KIT_INSTALL_CONFIG_POLICY='
future-config-files|/etc/seed-kit/wifi-kit|root:root|0600-or-0640|secrets-outside-git
'

WIFI_KIT_INSTALL_SECURITY_NOTES='
wrapper must be root-owned
wrapper must not be writable by the UI user
normal UI may run as a dedicated service user later
secret config files must use strict permissions
Wi-Fi passwords remain runtime-only
'

WIFI_KIT_INSTALL_NON_ACTIONS='
no-copy
no-chmod
no-chown
no-sudoers
no-systemd
no-runtime-start
no-ap
no-network-change
no-secret
no-reboot
'

_wifi_kit_install_print_pipe_list() {
  _name="$1"
  _list="$2"
  printf '%s\n' "$_list" | sed '/^$/d' | while IFS= read -r _entry; do
    [ -n "$_entry" ] && printf '%s=%s\n' "$_name" "$_entry"
  done
}

module_wifi_kit_install_files_manifest() {
  printf 'WIFI_KIT_INSTALL_MANIFEST_ID=%s\n' "$WIFI_KIT_INSTALL_MANIFEST_ID"
  printf 'WIFI_KIT_INSTALL_MANIFEST_MODULE_ID=%s\n' "$WIFI_KIT_INSTALL_MANIFEST_MODULE_ID"
  printf 'WIFI_KIT_INSTALL_MANIFEST_VERSION=%s\n' "$WIFI_KIT_INSTALL_MANIFEST_VERSION"
  printf 'WIFI_KIT_INSTALL_APP_DIR=%s\n' "$WIFI_KIT_INSTALL_APP_DIR"
  printf 'WIFI_KIT_INSTALL_UI_DIR=%s\n' "$WIFI_KIT_INSTALL_UI_DIR"
  printf 'WIFI_KIT_INSTALL_CONFIG_DIR=%s\n' "$WIFI_KIT_INSTALL_CONFIG_DIR"
  printf 'WIFI_KIT_INSTALL_RUNTIME_DIR=%s\n' "$WIFI_KIT_INSTALL_RUNTIME_DIR"
  printf 'WIFI_KIT_INSTALL_LOG_DIR=%s\n' "$WIFI_KIT_INSTALL_LOG_DIR"
  _wifi_kit_install_print_pipe_list WIFI_KIT_INSTALL_DIR "$WIFI_KIT_INSTALL_DIRS"
  _wifi_kit_install_print_pipe_list WIFI_KIT_INSTALL_FILE "$WIFI_KIT_INSTALL_FILES"
  _wifi_kit_install_print_pipe_list WIFI_KIT_INSTALL_CONFIG_POLICY "$WIFI_KIT_INSTALL_CONFIG_POLICY"
  _wifi_kit_install_print_pipe_list WIFI_KIT_INSTALL_SECURITY_NOTE "$WIFI_KIT_INSTALL_SECURITY_NOTES"
  _wifi_kit_install_print_pipe_list WIFI_KIT_INSTALL_NON_ACTION "$WIFI_KIT_INSTALL_NON_ACTIONS"
}

if [ "${1-}" = "print" ]; then
  module_wifi_kit_install_files_manifest
  exit 0
fi
