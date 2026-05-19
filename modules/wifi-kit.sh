#!/bin/sh

module_wifi_kit_plan() {
  case "${SEED_KIT_LANG:-en}" in
    fr)
      echo "Seed-Kit > plan - wifi-kit"
      echo ""
      echo "Mode : SAFE lecture seule"
      echo ""
      echo "Dépendances système :"
      echo "- network-manager"
      echo "- wpasupplicant / wpa_cli"
      echo "- hostapd"
      echo "- dnsmasq"
      echo "- python3"
      echo "- iw"
      echo "- iproute2"
      echo "- rfkill optionnel"
      echo ""
      echo "Persistant futur :"
      echo "- paquets système installés"
      echo "- fichiers module sous /opt/seed-kit/wifi-kit/"
      echo "- configuration sous /etc/seed-kit/wifi-kit/"
      echo "- logs sous /var/log/seed-kit/wifi-kit/"
      echo ""
      echo "Temporaire :"
      echo "- vérifications"
      echo "- staging éventuel"
      echo ""
      echo "Ne fera pas :"
      echo "- démarrer un AP"
      echo "- modifier le réseau courant"
      echo "- appliquer sudoers"
      echo "- installer service systemd"
      echo "- lancer l'UI normale"
      echo "- écrire de secret"
      echo "- reboot/restart réseau"
      echo ""
      echo "Runtime futur :"
      echo "- UI normale : port 54321"
      echo "- recovery captive : port 80 seulement en mode AP explicite"
      ;;
    *)
      echo "Seed-Kit > plan - wifi-kit"
      echo ""
      echo "Mode: SAFE read-only"
      echo ""
      echo "System dependencies:"
      echo "- network-manager"
      echo "- wpasupplicant / wpa_cli"
      echo "- hostapd"
      echo "- dnsmasq"
      echo "- python3"
      echo "- iw"
      echo "- iproute2"
      echo "- rfkill optional"
      echo ""
      echo "Future persistent state:"
      echo "- system packages installed"
      echo "- module files under /opt/seed-kit/wifi-kit/"
      echo "- configuration under /etc/seed-kit/wifi-kit/"
      echo "- logs under /var/log/seed-kit/wifi-kit/"
      echo ""
      echo "Temporary:"
      echo "- checks"
      echo "- optional staging"
      echo ""
      echo "Will not:"
      echo "- start an AP"
      echo "- change the current network"
      echo "- apply sudoers"
      echo "- install a systemd service"
      echo "- launch the normal UI"
      echo "- write secrets"
      echo "- reboot/restart networking"
      echo ""
      echo "Future runtime:"
      echo "- normal UI: port 54321"
      echo "- recovery captive portal: port 80 only in explicit AP mode"
      ;;
  esac
}

module_wifi_kit_dependencies() {
  echo "Wifi-Kit dependencies"
  echo ""
  echo "System packages:"
  echo "- network-manager"
  echo "- wpasupplicant / wpa_cli"
  echo "- hostapd"
  echo "- dnsmasq"
  echo "- python3"
  echo "- iw"
  echo "- iproute2"
  echo "- rfkill (optional)"
  echo ""
  echo "Future runtime:"
  echo "- normal UI port: 54321"
  echo "- recovery captive portal: 80"
  echo "- AP mode: explicit only"
  echo ""
  echo "Safety:"
  echo "- no AP at boot"
  echo "- no sudoers applied"
  echo "- no network changes"
  echo "- no services installed"
  echo "- no secrets"
}

module_wifi_kit_apply() {
  echo "- SAFE apply simulation (dry-run only)"
  echo "- no real network action: no hostapd, no dnsmasq, no NetworkManager"
  echo "- no Wi-Fi secrets are read, written, or logged"
  echo "- check docs: modules/wifi-kit/README.md"
  echo "- check prototype: modules/wifi-kit/prototype/wifi-kit.sh"

  if ! command -v sh >/dev/null 2>&1; then
    echo "- simulation blocked: sh unavailable"
    return 1
  fi

  if [ -f modules/wifi-kit/prototype/wifi-kit.sh ]; then
    echo "- status simulation"
    sh modules/wifi-kit/prototype/wifi-kit.sh status
    echo "- scan simulation"
    sh modules/wifi-kit/prototype/wifi-kit.sh scan
    echo "- reconnect-plan simulation"
    sh modules/wifi-kit/prototype/wifi-kit.sh reconnect-plan
    echo "- recovery-plan simulation"
    sh modules/wifi-kit/prototype/wifi-kit.sh recovery-plan
    return 0
  fi

  echo "- prototype script is missing (non-blocking for core integration testing)"
  return 1
}
