#!/bin/sh

module_wifi_stability_plan() {
  echo "- Raspberry Pi Wi-Fi stability guard"
  echo "- checks wlan0 power_save state when iw and wlan0 are available"

  if [ -r /proc/device-tree/model ]; then
    model=$(tr -d '\000' < /proc/device-tree/model 2>/dev/null || true)
    case "$model" in
      *"Raspberry Pi"*) echo "- Raspberry Pi: detected ($model)" ;;
      *) echo "- Raspberry Pi: not detected ($model)" ;;
    esac
  else
    echo "- Raspberry Pi: not detected from /proc/device-tree/model"
  fi

  if [ -d /sys/class/net/wlan0 ]; then
    echo "- wlan0: present"
    if command -v iw >/dev/null 2>&1; then
      state=$(iw dev wlan0 get power_save 2>/dev/null || true)
      if [ -n "$state" ]; then
        echo "- wlan0 power_save: $state"
      else
        echo "- wlan0 power_save: unreadable"
      fi
    else
      echo "- wlan0 power_save: iw not installed"
    fi
  else
    echo "- wlan0: missing"
  fi

  echo "- risk: Wi-Fi power save can make idle Raspberry Pi nodes unreachable"
  echo "- apply V1: sudo iw dev wlan0 set power_save off"
  echo "- persistence after reboot: TODO, no systemd unit yet"
}
