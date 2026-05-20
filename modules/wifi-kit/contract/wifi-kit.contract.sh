#!/bin/sh
set -eu

# Wifi-Kit module contract (sourceable shell declaration)
# Purpose:
# - provide stable metadata to Seed-Kit core
# - keep install orchestration outside the module
# - avoid heavy formats (no YAML/JSON required)

WIFI_KIT_MODULE_ID="wifi-kit"
WIFI_KIT_MODULE_TYPE="network-ui"
WIFI_KIT_BACKEND="networkmanager"
WIFI_KIT_MODE="normal-ui+ap-recovery"

WIFI_KIT_TARGET_PATH_APP_DIR="/opt/seed-kit/wifi-kit"
WIFI_KIT_TARGET_PATH_CONFIG_DIR="/etc/seed-kit/wifi-kit"
WIFI_KIT_TARGET_PATH_RUNTIME_DIR="/run/seed-kit/wifi-kit"
WIFI_KIT_TARGET_PATH_LOG_DIR="/var/log/seed-kit/wifi-kit"

WIFI_KIT_DEPENDENCIES_REQUIRED='
python3
network-manager
nmcli
wpa_cli
iw
iproute2
'

WIFI_KIT_DEPENDENCIES_RECOMMENDED='
rfkill
'

WIFI_KIT_DEPENDENCIES_CONDITIONAL='
hostapd
dnsmasq
sudoers-wrapper
systemd-service
'

WIFI_KIT_CAPABILITIES='
normal-ui
wifi-scan
wifi-connect-recovery
ap-recovery
captive-portal
recovery-cleanup
privileged-actions
'

WIFI_KIT_FILES='
prototype/ui/serve-readonly.py
prototype/ui/index.html
prototype/ap-setup-test.sh
prototype/wifi-kit-connect-recovery.sh
prototype/wifi-kit-recovery-guard.sh
prototype/wifi-kit-action-wrapper.sh
'

WIFI_KIT_RUNTIME_UI_NORMAL_PORT=54321
WIFI_KIT_RUNTIME_UI_RECOVERY_PORT=80
WIFI_KIT_RUNTIME_UI_NORMAL_COMMAND='python3 /opt/seed-kit/wifi-kit/ui/serve-readonly.py --host 0.0.0.0 --port 54321'

WIFI_KIT_WRAPPER_PATH='/opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh'
WIFI_KIT_WRAPPER_ACTIONS='
start-ap-mode
return-default-network
'

WIFI_KIT_READINESS_CHECKS='
python3 present
nmcli present
wpa_cli present
NetworkManager running
wlan0 present
port 54321 free
no active Wifi-Kit recovery leftovers
'

WIFI_KIT_HEALTH_CHECKS='
/status responds
wifi scan works
wlan0 readable
no unexpected hostapd/dnsmasq in normal mode
recovery-guard clean
'

WIFI_KIT_INSTALL_PHASES='
plan
validate
stage-files
install-files
install-config
install-normal-ui-service
install-wrapper
install-sudoers-rule
enable-boot-cleanup-guard
start-ui
health-check
'

WIFI_KIT_PHASE_ALIASES='
install-files|install-files-preview|install-files.manifest.sh
install-sudoers-rule|configure-sudoers-preview|sudoers.manifest.sh
install-normal-ui-service|install-service-preview|runtime-service.manifest.sh
recovery-config|recovery-preview|recovery.manifest.sh
ap-recovery|recovery-preview|recovery.manifest.sh
'

WIFI_KIT_ROLLBACK_PHASES='
stop-ui
stop-recovery-if-active
run-recovery-guard-cleanup
remove-sudoers-rule
remove-service
remove-installed-files
preserve-user-wifi-profiles
'

WIFI_KIT_FORBIDDEN_ACTIONS='
no-reboot
no-save-config
no-ap-start-without-explicit-action
no-sudoers-write-in-dry-run
no-secret-in-git
no-delete-user-wifi-profiles
no-permanent-ap-plus-sta
no-arbitrary-shell-command
'

WIFI_KIT_SECRETS_POLICY='
AP recovery password outside git
Wi-Fi passwords runtime-only
never log secrets
never return secrets through API
secret config files with strict permissions
'

WIFI_KIT_SUDOERS_REQUIREMENTS='
NOPASSWD only on wrapper path
no global shell
no sudo nmcli broad commands
no sudo systemctl broad commands
'

_wifi_kit_print_list() {
  _name="$1"
  _list="$2"
  printf '%s\n' "$_list" | sed '/^$/d' | while IFS= read -r _entry; do
    [ -n "$_entry" ] && printf '%s=%s\n' "$_name" "$_entry"
  done
}

module_wifi_kit_contract() {
  printf 'WIFI_KIT_MODULE_ID=%s\n' "$WIFI_KIT_MODULE_ID"
  printf 'WIFI_KIT_MODULE_TYPE=%s\n' "$WIFI_KIT_MODULE_TYPE"
  printf 'WIFI_KIT_BACKEND=%s\n' "$WIFI_KIT_BACKEND"
  printf 'WIFI_KIT_MODE=%s\n' "$WIFI_KIT_MODE"
  printf 'WIFI_KIT_APP_DIR=%s\n' "$WIFI_KIT_TARGET_PATH_APP_DIR"
  printf 'WIFI_KIT_CONFIG_DIR=%s\n' "$WIFI_KIT_TARGET_PATH_CONFIG_DIR"
  printf 'WIFI_KIT_RUNTIME_DIR=%s\n' "$WIFI_KIT_TARGET_PATH_RUNTIME_DIR"
  printf 'WIFI_KIT_LOG_DIR=%s\n' "$WIFI_KIT_TARGET_PATH_LOG_DIR"
  printf 'WIFI_KIT_RUNTIME_UI_NORMAL_PORT=%s\n' "$WIFI_KIT_RUNTIME_UI_NORMAL_PORT"
  printf 'WIFI_KIT_RUNTIME_UI_RECOVERY_PORT=%s\n' "$WIFI_KIT_RUNTIME_UI_RECOVERY_PORT"
  printf 'WIFI_KIT_RUNTIME_UI_NORMAL_COMMAND=%s\n' "$WIFI_KIT_RUNTIME_UI_NORMAL_COMMAND"
  printf 'WIFI_KIT_WRAPPER_PATH=%s\n' "$WIFI_KIT_WRAPPER_PATH"
  _wifi_kit_print_list WIFI_KIT_DEPENDENCIES_REQUIRED "$WIFI_KIT_DEPENDENCIES_REQUIRED"
  _wifi_kit_print_list WIFI_KIT_DEPENDENCIES_RECOMMENDED "$WIFI_KIT_DEPENDENCIES_RECOMMENDED"
  _wifi_kit_print_list WIFI_KIT_DEPENDENCIES_CONDITIONAL "$WIFI_KIT_DEPENDENCIES_CONDITIONAL"
  _wifi_kit_print_list WIFI_KIT_CAPABILITIES "$WIFI_KIT_CAPABILITIES"
  _wifi_kit_print_list WIFI_KIT_FILES "$WIFI_KIT_FILES"
  _wifi_kit_print_list WIFI_KIT_WRAPPER_ACTIONS "$WIFI_KIT_WRAPPER_ACTIONS"
  _wifi_kit_print_list WIFI_KIT_READINESS_CHECKS "$WIFI_KIT_READINESS_CHECKS"
  _wifi_kit_print_list WIFI_KIT_HEALTH_CHECKS "$WIFI_KIT_HEALTH_CHECKS"
  _wifi_kit_print_list WIFI_KIT_INSTALL_PHASES "$WIFI_KIT_INSTALL_PHASES"
  _wifi_kit_print_list WIFI_KIT_PHASE_ALIAS "$WIFI_KIT_PHASE_ALIASES"
  _wifi_kit_print_list WIFI_KIT_ROLLBACK_PHASES "$WIFI_KIT_ROLLBACK_PHASES"
  _wifi_kit_print_list WIFI_KIT_FORBIDDEN_ACTIONS "$WIFI_KIT_FORBIDDEN_ACTIONS"
  _wifi_kit_print_list WIFI_KIT_SECRETS_POLICY "$WIFI_KIT_SECRETS_POLICY"
  _wifi_kit_print_list WIFI_KIT_SUDOERS_REQUIREMENTS "$WIFI_KIT_SUDOERS_REQUIREMENTS"
}

if [ "${1-}" = "print" ]; then
  module_wifi_kit_contract
  exit 0
fi
