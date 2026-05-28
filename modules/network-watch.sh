#!/bin/sh

network_watch_script_path() {
  printf '%s/scripts/network-watch/network-watch.sh\n' "$ROOT_DIR"
}

network_watch_unit_path() {
  printf '/etc/systemd/system/seed-kit-network-watch.service\n'
}

network_watch_log_dir() {
  printf '/var/log/seed-kit/network-watch\n'
}

module_network_watch_plan() {
  echo "- module: network-watch"
  echo "- purpose: monitor Internet availability without changing network config"
  echo "- default target: 1.1.1.1"
  echo "- default interval: 5 seconds"
  echo "- logs state changes only: monitor-started, internet-ok, internet-down, internet-restored"
  echo "- log: /var/log/seed-kit/network-watch/network-watch.log"
  echo "- state: /var/log/seed-kit/network-watch/network-watch.state"
  echo "- service: seed-kit-network-watch.service"
  echo "- safety: no route change, no DNS change, no NetworkManager restart, no reboot"
  echo "- commands: sh seed-kit.sh network-watch start|stop|status|logs|follow"
}

network_watch_install_service() {
  script=$(network_watch_script_path)
  unit=$(network_watch_unit_path)
  log_dir=$(network_watch_log_dir)

  if [ ! -f "$script" ]; then
    echo "[network-watch] missing script: $script" >&2
    return 1
  fi
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "[network-watch] systemctl is required for service management" >&2
    return 1
  fi
  if ! require_sudo_for_system_action "network-watch service install"; then
    return 2
  fi
  if [ "$(id -u)" -eq 0 ]; then
    SUDO=
  else
    SUDO=sudo
  fi

  tmp="${TMPDIR:-/tmp}/seed-kit-network-watch.service.$$"
  cat > "$tmp" <<EOF
[Unit]
Description=Seed-Kit Internet availability watcher
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=NETWORK_WATCH_TARGETS=1.1.1.1
Environment=NETWORK_WATCH_INTERVAL_SECONDS=5
ExecStart=/bin/sh $script monitor
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  $SUDO mkdir -p "$log_dir"
  $SUDO chmod 0755 "$log_dir"
  $SUDO cp "$tmp" "$unit"
  rm -f "$tmp"
  $SUDO chmod 0644 "$unit"
  $SUDO systemctl daemon-reload
}

module_network_watch_apply() {
  echo "[network-watch] install service definition only"
  echo "[network-watch] no reboot, no NetworkManager restart, no route/DNS changes"
  if ! apply_safe_confirm; then
    return 2
  fi
  network_watch_install_service
  echo "[network-watch] installed: $(network_watch_unit_path)"
  echo "[network-watch] start with: sh seed-kit.sh network-watch start"
}

module_network_watch_command() {
  command=${1:-}
  script=$(network_watch_script_path)
  unit=seed-kit-network-watch.service
  log_dir=$(network_watch_log_dir)

  case "$command" in
    start)
      echo "[network-watch] start requested"
      echo "[network-watch] target: 1.1.1.1; interval: 5 seconds"
      echo "[network-watch] no network configuration will be changed"
      if ! apply_safe_confirm; then
        return 2
      fi
      network_watch_install_service || return $?
      if [ "$(id -u)" -eq 0 ]; then SUDO=; else SUDO=sudo; fi
      $SUDO systemctl enable --now "$unit"
      ;;
    stop)
      echo "[network-watch] stop requested"
      if ! command -v systemctl >/dev/null 2>&1; then
        echo "[network-watch] systemctl unavailable" >&2
        return 1
      fi
      if ! require_sudo_for_system_action "network-watch stop"; then
        return 2
      fi
      if [ "$(id -u)" -eq 0 ]; then SUDO=; else SUDO=sudo; fi
      $SUDO systemctl stop "$unit"
      ;;
    status)
      if command -v systemctl >/dev/null 2>&1; then
        systemctl status "$unit" --no-pager || true
      fi
      if [ -f "$script" ]; then
        sh "$script" status
      else
        echo "[network-watch] missing script: $script" >&2
        return 1
      fi
      ;;
    logs)
      if [ -f "$script" ]; then
        sh "$script" logs
      else
        echo "[network-watch] missing script: $script" >&2
        return 1
      fi
      ;;
    follow)
      if [ -f "$script" ]; then
        sh "$script" follow
      else
        echo "[network-watch] missing script: $script" >&2
        return 1
      fi
      ;;
    uninstall)
      echo "[network-watch] uninstall requested"
      echo "[network-watch] this stops/disables the service and removes only the unit file"
      if ! apply_safe_confirm; then
        return 2
      fi
      if ! require_sudo_for_system_action "network-watch uninstall"; then
        return 2
      fi
      if [ "$(id -u)" -eq 0 ]; then SUDO=; else SUDO=sudo; fi
      $SUDO systemctl disable --now "$unit" >/dev/null 2>&1 || true
      $SUDO rm -f "$(network_watch_unit_path)"
      $SUDO systemctl daemon-reload
      ;;
    *)
      echo "usage: sh seed-kit.sh network-watch start|stop|status|logs|follow|uninstall" >&2
      return 2
      ;;
  esac
}
