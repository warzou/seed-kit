#!/bin/sh

link_watch_script_path() {
  printf '%s/scripts/link-watch/link-watch.sh\n' "$ROOT_DIR"
}

link_watch_unit_path() {
  printf '/etc/systemd/system/seed-kit-link-watch.service\n'
}

link_watch_log_dir() {
  printf '/var/log/seed-kit/link-watch\n'
}

module_link_watch_plan() {
  echo "- module: link-watch"
  echo "- purpose: monitor Internet availability without changing network config"
  echo "- default target: 1.1.1.1"
  echo "- default interval: 5 seconds"
  echo "- logs state changes only: monitor-started, internet-ok, internet-down, internet-restored"
  echo "- log: /var/log/seed-kit/link-watch/link-watch.log"
  echo "- state: /var/log/seed-kit/link-watch/link-watch.state"
  echo "- service: seed-kit-link-watch.service"
  echo "- safety: no route change, no DNS change, no NetworkManager restart, no reboot"
  echo "- commands: sh seed-kit.sh link-watch start|stop|status|logs|follow"
}

link_watch_install_service() {
  script=$(link_watch_script_path)
  unit=$(link_watch_unit_path)
  log_dir=$(link_watch_log_dir)

  if [ ! -f "$script" ]; then
    echo "[link-watch] missing script: $script" >&2
    return 1
  fi
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "[link-watch] systemctl is required for service management" >&2
    return 1
  fi
  if ! require_sudo_for_system_action "link-watch service install"; then
    return 2
  fi
  if [ "$(id -u)" -eq 0 ]; then
    SUDO=
  else
    SUDO=sudo
  fi

  tmp="${TMPDIR:-/tmp}/seed-kit-link-watch.service.$$"
  cat > "$tmp" <<EOF
[Unit]
Description=Seed-Kit link availability watcher
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=LINK_WATCH_TARGETS=1.1.1.1
Environment=LINK_WATCH_INTERVAL_SECONDS=5
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

module_link_watch_apply() {
  echo "[link-watch] install service definition only"
  echo "[link-watch] no reboot, no NetworkManager restart, no route/DNS changes"
  if ! apply_safe_confirm; then
    return 2
  fi
  link_watch_install_service
  echo "[link-watch] installed: $(link_watch_unit_path)"
  echo "[link-watch] start with: sh seed-kit.sh link-watch start"
}

module_link_watch_command() {
  command=${1:-}
  script=$(link_watch_script_path)
  unit=seed-kit-link-watch.service
  log_dir=$(link_watch_log_dir)

  case "$command" in
    start)
      echo "[link-watch] start requested"
      echo "[link-watch] target: 1.1.1.1; interval: 5 seconds"
      echo "[link-watch] no network configuration will be changed"
      if ! apply_safe_confirm; then
        return 2
      fi
      link_watch_install_service || return $?
      if [ "$(id -u)" -eq 0 ]; then SUDO=; else SUDO=sudo; fi
      $SUDO systemctl enable --now "$unit"
      ;;
    stop)
      echo "[link-watch] stop requested"
      if ! command -v systemctl >/dev/null 2>&1; then
        echo "[link-watch] systemctl unavailable" >&2
        return 1
      fi
      if ! require_sudo_for_system_action "link-watch stop"; then
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
        echo "[link-watch] missing script: $script" >&2
        return 1
      fi
      ;;
    logs)
      if [ -f "$script" ]; then
        sh "$script" logs
      else
        echo "[link-watch] missing script: $script" >&2
        return 1
      fi
      ;;
    follow)
      if [ -f "$script" ]; then
        sh "$script" follow
      else
        echo "[link-watch] missing script: $script" >&2
        return 1
      fi
      ;;
    uninstall)
      echo "[link-watch] uninstall requested"
      echo "[link-watch] this stops/disables the service and removes only the unit file"
      if ! apply_safe_confirm; then
        return 2
      fi
      if ! require_sudo_for_system_action "link-watch uninstall"; then
        return 2
      fi
      if [ "$(id -u)" -eq 0 ]; then SUDO=; else SUDO=sudo; fi
      $SUDO systemctl disable --now "$unit" >/dev/null 2>&1 || true
      $SUDO rm -f "$(link_watch_unit_path)"
      $SUDO systemctl daemon-reload
      ;;
    *)
      echo "usage: sh seed-kit.sh link-watch start|stop|status|logs|follow|uninstall" >&2
      return 2
      ;;
  esac
}
