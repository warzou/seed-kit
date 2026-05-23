#!/bin/sh

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
  echo "- safety: explicit confirmation required before real install"
  echo "- safety: no AP start, no Wi-Fi change, no profile deletion, no reboot"
  echo "- safety: no client Wi-Fi password storage"
  if [ -f modules/wifi-kit/prototype/install-wifi-kit-runtime.sh ]; then
    echo "- installer plan:"
    sh modules/wifi-kit/prototype/install-wifi-kit-runtime.sh plan | sed 's/^/  /'
  fi
}

module_wifi_kit_apply() {
  installer="modules/wifi-kit/prototype/install-wifi-kit-runtime.sh"
  confirm_phrase="INSTALL WIFI-KIT RUNTIME"

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

  echo "[wifi-kit] installer audit"
  sh "$installer" audit
  echo "[wifi-kit] installer plan"
  sh "$installer" plan

  echo ""
  echo "[wifi-kit] To continue, type exactly:"
  echo "$confirm_phrase"
  printf "confirm wifi-kit runtime install: "
  IFS= read -r answer || answer=
  if [ "$answer" != "$confirm_phrase" ]; then
    echo "[wifi-kit] aborted"
    return 2
  fi

  if ! require_sudo_for_system_action "wifi-kit runtime install"; then
    return 2
  fi

  if [ "$(id -u)" -eq 0 ]; then
    SUDO=
  else
    SUDO=sudo
  fi

  $SUDO sh "$installer" install --confirm "$confirm_phrase"
}
