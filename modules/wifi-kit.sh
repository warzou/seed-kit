#!/bin/sh

wifi_kit_audit_value() {
  key=$1
  awk -F= -v key="$key" '$1 == key { print substr($0, length(key) + 2); exit }'
}

wifi_kit_apply_summary() {
  audit_output=$1
  install_user=$(printf '%s\n' "$audit_output" | wifi_kit_audit_value install_user)
  app_dir=$(printf '%s\n' "$audit_output" | wifi_kit_audit_value app_dir)
  runtime_config=$(printf '%s\n' "$audit_output" | wifi_kit_audit_value runtime_config)
  ui_port=$(printf '%s\n' "$audit_output" | wifi_kit_audit_value ui_port)
  sudoers_exists=$(printf '%s\n' "$audit_output" | wifi_kit_audit_value sudoers_target_exists)
  ui_unit_exists=$(printf '%s\n' "$audit_output" | wifi_kit_audit_value ui_unit_target_exists)
  boot_guard_unit_exists=$(printf '%s\n' "$audit_output" | wifi_kit_audit_value boot_guard_unit_target_exists)
  runtime_config_exists=no

  if [ -n "$runtime_config" ] && [ -f "$runtime_config" ]; then
    runtime_config_exists=yes
  fi

  echo "[wifi-kit] summary"
  echo "  install user: ${install_user:-unknown}"
  echo "  target: ${app_dir:-unknown}"
  echo "  UI port: ${ui_port:-54321}"
  echo "  sudoers: ${sudoers_exists:-unknown}"
  echo "  systemd units: ui=${ui_unit_exists:-unknown} boot-guard=${boot_guard_unit_exists:-unknown}"
  echo "  runtime config: $runtime_config_exists"
}

module_wifi_kit_plan() {
  echo "- module: wifi-kit"
  echo "- mode: runtime installer prototype"
  echo "- docs: modules/wifi-kit/README.md"
  echo "- docs: modules/wifi-kit/docs/ARCHITECTURE.md"
  echo "- docs: modules/wifi-kit/docs/RECOVERY.md"
  echo "- docs: modules/wifi-kit/docs/SECURITY.md"
  echo "- docs: modules/wifi-kit/docs/ROADMAP.md"
  echo "- docs: modules/wifi-kit/docs/RUNTIME-VALIDATION.md"
  echo "- prototype: modules/wifi-kit/prototype/wifi-kit.sh"
  echo "- installer: modules/wifi-kit/prototype/install-wifi-kit-runtime.sh"
  echo "- command: sh seed-kit.sh install wifi-kit"
  echo "- alternate: sh seed-kit.sh --apply --modules=wifi-kit"
  echo "- installs: /opt runtime, strict sudoers, normal UI service, boot guard service"
  echo "- safety: install/reinstall prompt before real install"
  echo "- safety: no AP start, no Wi-Fi change, no profile deletion, no reboot"
  echo "- safety: no client Wi-Fi password storage"
  if [ -f modules/wifi-kit/prototype/install-wifi-kit-runtime.sh ]; then
    echo "- installer plan:"
    sh modules/wifi-kit/prototype/install-wifi-kit-runtime.sh plan | sed 's/^/  /'
  fi
}

module_wifi_kit_apply() {
  installer="modules/wifi-kit/prototype/install-wifi-kit-runtime.sh"
  installed=0

  echo "[wifi-kit] runtime install"
  echo "[wifi-kit] installs /opt runtime, sudoers, wifi-kit-ui.service, and wifi-kit-boot-guard.service"
  echo "[wifi-kit] does not start AP mode, change Wi-Fi, delete Wi-Fi profiles, store client Wi-Fi passwords, or reboot"

  if ! command -v sh >/dev/null 2>&1; then
    echo "[wifi-kit] blocked: sh unavailable" >&2
    return 1
  fi

  if [ ! -f "$installer" ]; then
    echo "[wifi-kit] installer missing: $installer" >&2
    return 1
  fi

  audit_output=$(sh "$installer" audit)
  if [ "${WIFI_KIT_VERBOSE:-0}" = "1" ]; then
    echo "[wifi-kit] installer audit"
    printf '%s\n' "$audit_output"
    echo "[wifi-kit] installer plan"
    sh "$installer" plan
  else
    wifi_kit_apply_summary "$audit_output"
    echo "[wifi-kit] set WIFI_KIT_VERBOSE=1 to show full audit, plan, sudoers, and systemd previews"
  fi

  echo ""
  if [ -d /opt/seed-kit/wifi-kit ] || [ -e /etc/sudoers.d/wifi-kit ] || [ -e /etc/systemd/system/wifi-kit-ui.service ] || [ -e /etc/systemd/system/wifi-kit-boot-guard.service ]; then
    installed=1
    echo "[wifi-kit] already installed"
    printf "reinstall? [y/N] "
  else
    printf "install wifi-kit runtime? [y/N] "
  fi
  IFS= read -r answer || answer=
  case "$answer" in
    y|Y)
      ;;
    *)
    echo "[wifi-kit] aborted"
    return 2
      ;;
  esac

  if ! require_sudo_for_system_action "wifi-kit runtime install"; then
    return 2
  fi

  if [ "$(id -u)" -eq 0 ]; then
    SUDO=
  else
    SUDO=sudo
  fi

  if [ "$installed" -eq 1 ]; then
    $SUDO sh "$installer" install --reinstall
  else
    $SUDO sh "$installer" install
  fi
}
