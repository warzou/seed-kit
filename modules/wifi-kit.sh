#!/bin/sh

module_wifi_kit_plan() {
  echo "- module: wifi-kit"
  echo "- mode: SAFE prototype / simulation"
  echo "- docs: modules/wifi-kit/README.md"
  echo "- docs: modules/wifi-kit/docs/ARCHITECTURE.md"
  echo "- docs: modules/wifi-kit/docs/RECOVERY.md"
  echo "- docs: modules/wifi-kit/docs/SECURITY.md"
  echo "- docs: modules/wifi-kit/docs/ROADMAP.md"
  echo "- prototype: modules/wifi-kit/prototype/wifi-kit.sh"
  echo "- behavior: status, scan, connect, save-known-network, reconnect-plan, recovery-plan"
  echo "- safety: no hostapd, no dnsmasq, no NetworkManager real actions"
  echo "- safety: no Wi-Fi secret handling in this flow"
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
