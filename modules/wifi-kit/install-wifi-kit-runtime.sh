#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
module_dir=$script_dir
repo_dir="${WIFI_KIT_REPO_DIR:-$(CDPATH= cd -- "$module_dir/../.." && pwd)}"

install_user_source="default"
if [ -n "${WIFI_KIT_INSTALL_USER:-}" ]; then
  install_user="$WIFI_KIT_INSTALL_USER"
  install_user_source="env"
elif [ -n "${SUDO_USER:-}" ]; then
  install_user="$SUDO_USER"
  install_user_source="sudo"
else
  install_user="${USER:-warzy}"
  install_user_source="default"
fi
app_dir="${WIFI_KIT_INSTALL_APP_DIR:-/opt/seed-kit/wifi-kit}"
ui_dir="$app_dir/ui"
sudoers_path="${WIFI_KIT_SUDOERS_PATH:-/etc/sudoers.d/wifi-kit}"
normal_unit_path="${WIFI_KIT_UI_UNIT_PATH:-/etc/systemd/system/wifi-kit-ui.service}"
boot_guard_unit_path="${WIFI_KIT_BOOT_GUARD_UNIT_PATH:-/etc/systemd/system/wifi-kit-boot-guard.service}"
runtime_watchdog_unit_path="${WIFI_KIT_RUNTIME_WATCHDOG_UNIT_PATH:-/etc/systemd/system/wifi-kit-runtime-watchdog.service}"
ui_port="${WIFI_KIT_UI_PORT:-54321}"
iface="${WIFI_KIT_BOOT_GUARD_IFACE:-wlan0}"
internet_probe="${WIFI_KIT_BOOT_GUARD_PROBE:-1.1.1.1}"
system_power_actions="${WIFI_KIT_ENABLE_SYSTEM_POWER_ACTIONS:-1}"
reboot_action="${WIFI_KIT_ENABLE_REBOOT_ACTION:-1}"
shutdown_action="${WIFI_KIT_ENABLE_SHUTDOWN_ACTION:-0}"

usage() {
  cat <<'EOF'
wifi-kit runtime installer prototype

Usage:
  sh modules/wifi-kit/install-wifi-kit-runtime.sh audit
  sh modules/wifi-kit/install-wifi-kit-runtime.sh plan
  sudo sh modules/wifi-kit/install-wifi-kit-runtime.sh install
  sudo sh modules/wifi-kit/install-wifi-kit-runtime.sh install --reinstall

Modes:
  audit    Check inputs and show resolved paths. No mutation.
  plan     Print the install actions. No mutation.
  install  Install /opt files, sudoers, systemd units, runtime config skeleton,
           enable/start normal UI, and enable boot guard. It does not reboot,
           start AP mode, or intentionally change Wi-Fi.
EOF
}

kv() {
  printf '%s=%s\n' "$1" "$2"
}

section() {
  printf '\n[%s]\n' "$1"
}

find_tool() {
  command -v "$1" 2>/dev/null || true
}

user_home() {
  getent passwd "$install_user" 2>/dev/null | awk -F: '{ print $6 }' | sed -n '1p'
}

runtime_config_path() {
  home=$(user_home)
  if [ -n "$home" ]; then
    printf '%s\n' "$home/.config/wifi-kit/runtime.conf"
  else
    printf '%s\n' "/home/$install_user/.config/wifi-kit/runtime.conf"
  fi
}

runtime_config=$(runtime_config_path)
runtime_config_dir=$(dirname -- "$runtime_config")

legacy_user_ui_unit_path() {
  home=$(user_home)
  [ -n "$home" ] || home="/home/$install_user"
  printf '%s\n' "$home/.config/systemd/user/wifi-kit-ui.service"
}

require_root() {
  if [ "$(id -u)" != "0" ]; then
    kv "status" "refused"
    kv "reason" "root-required"
    exit 1
  fi
}

parse_install_options() {
  reinstall=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --reinstall)
        reinstall=1
        ;;
      *)
        kv "status" "refused"
        kv "reason" "unknown-argument:$1"
        exit 2
        ;;
    esac
    shift
  done
}

source_file() {
  rel=$1
  printf '%s\n' "$module_dir/$rel"
}

check_source() {
  rel=$1
  path=$(source_file "$rel")
  [ -f "$path" ] && kv "source_ok" "$rel" || kv "source_missing" "$rel"
}

required_sources() {
  cat <<'EOF'
prototype/wifi-kit-action-wrapper.sh
prototype/ap-setup-test.sh
prototype/wifi-kit-connect-transaction.sh
prototype/wifi-kit-boot-guard.sh
prototype/wifi-kit-ap-return-check.sh
prototype/wifi-kit-runtime-watchdog.sh
prototype/wifi-kit-nm-ap-lab.sh
prototype/ui/serve-readonly.py
prototype/ui/index.html
EOF
}

target_state() {
  label=$1
  path=$2
  if [ -e "$path" ]; then
    kv "${label}_exists" "yes"
  else
    kv "${label}_exists" "no"
  fi
}

legacy_user_ui_unit_state() {
  legacy_unit=$(legacy_user_ui_unit_path)
  target_state "legacy_user_ui_unit" "$legacy_unit"
  if [ -f "$legacy_unit" ] && grep -Eq 'seed-kit-wifi-kit-preview|WorkingDirectory=%h/seed-kit' "$legacy_unit"; then
    kv "legacy_user_ui_unit_preview_path" "yes"
  else
    kv "legacy_user_ui_unit_preview_path" "no"
  fi
}

disable_legacy_user_ui_unit_best_effort() {
  legacy_unit=$(legacy_user_ui_unit_path)
  [ -f "$legacy_unit" ] || return 0
  grep -Eq 'seed-kit-wifi-kit-preview|WorkingDirectory=%h/seed-kit' "$legacy_unit" || return 0
  if command -v runuser >/dev/null 2>&1; then
    runuser -u "$install_user" -- systemctl --user disable --now wifi-kit-ui.service >/dev/null 2>&1 || true
  fi
  mv "$legacy_unit" "$legacy_unit.disabled-by-wifi-kit-install" 2>/dev/null || true
  kv "legacy_user_ui_unit" "disabled-preview-path"
}

require_sources() {
  missing="0"
  required_sources | while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    if [ ! -f "$(source_file "$rel")" ]; then
      kv "source_missing" "$rel"
      missing="1"
    fi
    if [ "$missing" = "1" ]; then
      exit 1
    fi
  done
}

require_install_preflight() {
  require_sources || { kv "status" "refused"; kv "reason" "missing-source"; exit 1; }
  if [ "$install_user" = "root" ] && [ "$install_user_source" != "env" ]; then
    kv "status" "refused"
    kv "reason" "implicit-root-install-user"
    kv "hint" "set WIFI_KIT_INSTALL_USER to the target non-root UI user"
    exit 2
  fi
  if ! command -v visudo >/dev/null 2>&1; then
    kv "status" "refused"
    kv "reason" "visudo-required"
    exit 1
  fi
  for target in "$sudoers_path" "$normal_unit_path" "$boot_guard_unit_path" "$runtime_watchdog_unit_path"; do
    if [ -e "$target" ]; then
      if [ "${reinstall:-0}" = "1" ]; then
        continue
      fi
      kv "status" "refused"
      kv "reason" "target-exists"
      kv "target" "$target"
      kv "hint" "rerun with --reinstall to overwrite runtime files and units"
      exit 1
    fi
  done
}

copy_file() {
  rel=$1
  target=$2
  mode=$3
  install -o root -g root -m "$mode" "$(source_file "$rel")" "$target"
}

render_sudoers() {
  cat <<EOF
# Wifi-Kit runtime sudoers.
# Managed by install-wifi-kit-runtime.sh.
# No shell, wildcard, nmcli, systemctl, hostapd, dnsmasq, or direct reboot grant.
$install_user ALL=(root) NOPASSWD: $app_dir/wifi-kit-action-wrapper.sh start-ap-mode, $app_dir/wifi-kit-action-wrapper.sh return-default-network, $app_dir/wifi-kit-action-wrapper.sh connect-wifi, $app_dir/wifi-kit-action-wrapper.sh ap-return-check-once, $app_dir/wifi-kit-action-wrapper.sh reboot-system, $app_dir/wifi-kit-action-wrapper.sh shutdown-system, $app_dir/wifi-kit-action-wrapper.sh reinstall-runtime
EOF
}

render_ui_unit() {
  cat <<EOF
[Unit]
Description=Wifi-Kit normal UI
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$install_user
Group=$install_user
WorkingDirectory=$app_dir
Environment=WIFI_KIT_ENABLE_PRIVILEGED_ACTIONS=1
Environment=WIFI_KIT_ENABLE_SYSTEM_POWER_ACTIONS=$system_power_actions
Environment=WIFI_KIT_ENABLE_REBOOT_ACTION=$reboot_action
Environment=WIFI_KIT_ENABLE_SHUTDOWN_ACTION=$shutdown_action
Environment=WIFI_KIT_RUNTIME_CONFIG=$runtime_config
Environment=WIFI_KIT_REPO_DIR=$repo_dir
Environment=WIFI_KIT_UI_PORT=$ui_port
ExecStart=/usr/bin/python3 ui/serve-readonly.py --host 0.0.0.0 --port \${WIFI_KIT_UI_PORT}
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
}

render_boot_guard_unit() {
  cat <<EOF
[Unit]
Description=Wifi-Kit minimal boot guard
After=NetworkManager.service
Wants=NetworkManager.service

[Service]
Type=oneshot
Environment=WIFI_KIT_RUNTIME_CONFIG=$runtime_config
Environment=WIFI_KIT_BOOT_GUARD_IFACE=$iface
Environment=WIFI_KIT_BOOT_GUARD_PROBE=$internet_probe
Environment=WIFI_KIT_BOOT_GUARD_CONNECT_WAIT=25
Environment=WIFI_KIT_BOOT_GUARD_PING_WAIT=3
ExecStart=$app_dir/wifi-kit-boot-guard.sh run
TimeoutStartSec=120
RemainAfterExit=no

[Install]
WantedBy=multi-user.target
EOF
}

render_runtime_watchdog_unit() {
  cat <<EOF
[Unit]
Description=Wifi-Kit runtime recovery watchdog
After=NetworkManager.service wifi-kit-ui.service
Wants=NetworkManager.service wifi-kit-ui.service

[Service]
Type=simple
Environment=WIFI_KIT_RUNTIME_CONFIG=$runtime_config
Environment=WIFI_KIT_RUNTIME_WATCHDOG_IFACE=$iface
ExecStart=$app_dir/wifi-kit-runtime-watchdog.sh run
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
}

ensure_runtime_config() {
  install -d -o "$install_user" -g "$install_user" -m 0700 "$runtime_config_dir"
  if [ ! -f "$runtime_config" ]; then
    {
      printf '# Wifi-Kit runtime config\n'
      printf '# Stores AP recovery password only; never stores client Wi-Fi passwords.\n'
      printf 'ap_ssid=Wifi-Kit-%s\n' "$(hostname 2>/dev/null || printf node)"
      printf 'ap_password=12345678\n'
      printf 'runtime_recovery_enabled=true\n'
      printf 'runtime_recovery_grace_seconds=30\n'
      printf 'runtime_recovery_instability_window_minutes=10\n'
      printf 'runtime_recovery_instability_threshold=3\n'
    } > "$runtime_config"
  fi
  chown "$install_user:$install_user" "$runtime_config"
  chmod 0600 "$runtime_config"
}

cmd_audit() {
  section "wifi-kit-install-audit"
  kv "mode" "audit"
  kv "mutations" "false"
  kv "install_user" "$install_user"
  kv "install_user_source" "$install_user_source"
  kv "install_user_home" "$(user_home)"
  kv "app_dir" "$app_dir"
  kv "ui_dir" "$ui_dir"
  kv "runtime_config" "$runtime_config"
  kv "sudoers_path" "$sudoers_path"
  kv "normal_unit_path" "$normal_unit_path"
  kv "boot_guard_unit_path" "$boot_guard_unit_path"
  kv "runtime_watchdog_unit_path" "$runtime_watchdog_unit_path"
  kv "ui_port" "$ui_port"
  kv "iface" "$iface"
  kv "internet_probe" "$internet_probe"
  kv "install" "$(find_tool install)"
  kv "systemctl" "$(find_tool systemctl)"
  kv "visudo" "$(find_tool visudo)"
  required_sources | while IFS= read -r rel; do
    [ -n "$rel" ] && check_source "$rel"
  done
  target_state "sudoers_target" "$sudoers_path"
  target_state "ui_unit_target" "$normal_unit_path"
  target_state "boot_guard_unit_target" "$boot_guard_unit_path"
  target_state "runtime_watchdog_unit_target" "$runtime_watchdog_unit_path"
  legacy_user_ui_unit_state
  if [ "$install_user" = "root" ] && [ "$install_user_source" != "env" ]; then
    kv "install_user_warning" "implicit-root-refused-by-install"
  fi
}

cmd_plan() {
  cmd_audit
  section "wifi-kit-install-plan"
  kv "01.create_dirs" "$app_dir and $ui_dir root:root 0755"
  kv "02.copy_runtime_files" "wrapper, AP helper, connect transaction, boot guard, runtime watchdog, AP return-check helper, NM AP lab helper, UI backend, UI index"
  kv "03.runtime_config" "$runtime_config_dir 0700 and $runtime_config 0600 owned by $install_user"
  kv "04.sudoers" "$sudoers_path exact wrapper actions only; validate with visudo when available"
  kv "05.systemd_units" "$normal_unit_path, $boot_guard_unit_path, and $runtime_watchdog_unit_path"
  kv "05b.legacy_user_unit" "disable old per-user wifi-kit-ui.service if it points to a preview clone"
  kv "overwrite_policy" "install refuses when sudoers or target units already exist unless --reinstall is used"
  kv "visudo_policy" "install refuses if visudo is unavailable"
  kv "06.daemon_reload" "systemctl daemon-reload"
  kv "07.enable_restart_ui" "enable and restart wifi-kit-ui.service on port $ui_port so installed backend code is reloaded"
  kv "08.enable_boot_guard" "enable wifi-kit-boot-guard.service; do not start AP"
  kv "09.enable_restart_runtime_watchdog" "enable and restart wifi-kit-runtime-watchdog.service; it starts AP only after runtime grace expires"
  kv "non_actions" "no reboot, no AP start, no Wi-Fi profile deletion, no client Wi-Fi password storage"
  section "sudoers-preview"
  render_sudoers
  section "wifi-kit-ui.service-preview"
  render_ui_unit
  section "wifi-kit-boot-guard.service-preview"
  render_boot_guard_unit
  section "wifi-kit-runtime-watchdog.service-preview"
  render_runtime_watchdog_unit
}

cmd_install() {
  require_root
  parse_install_options "$@"
  require_install_preflight

  section "wifi-kit-install"
  kv "status" "starting"
  kv "reinstall" "$reinstall"
  install -d -o root -g root -m 0755 "$app_dir" "$ui_dir"
  copy_file "prototype/wifi-kit-action-wrapper.sh" "$app_dir/wifi-kit-action-wrapper.sh" 0755
  copy_file "prototype/ap-setup-test.sh" "$app_dir/ap-setup-test.sh" 0755
  copy_file "prototype/wifi-kit-connect-transaction.sh" "$app_dir/wifi-kit-connect-transaction.sh" 0755
  copy_file "prototype/wifi-kit-boot-guard.sh" "$app_dir/wifi-kit-boot-guard.sh" 0755
  copy_file "prototype/wifi-kit-ap-return-check.sh" "$app_dir/wifi-kit-ap-return-check.sh" 0755
  copy_file "prototype/wifi-kit-runtime-watchdog.sh" "$app_dir/wifi-kit-runtime-watchdog.sh" 0755
  copy_file "prototype/wifi-kit-nm-ap-lab.sh" "$app_dir/wifi-kit-nm-ap-lab.sh" 0755
  copy_file "prototype/ui/serve-readonly.py" "$ui_dir/serve-readonly.py" 0755
  copy_file "prototype/ui/index.html" "$ui_dir/index.html" 0644
  printf '%s\n' "$repo_dir" > "$app_dir/repo-dir"
  chown root:root "$app_dir/repo-dir"
  chmod 0644 "$app_dir/repo-dir"
  kv "files" "installed"

  ensure_runtime_config
  kv "runtime_config" "prepared"

  tmp_sudoers=$(mktemp)
  render_sudoers > "$tmp_sudoers"
  if command -v visudo >/dev/null 2>&1; then
    visudo -cf "$tmp_sudoers" >/dev/null
  fi
  install -o root -g root -m 0440 "$tmp_sudoers" "$sudoers_path"
  rm -f "$tmp_sudoers"
  kv "sudoers" "installed"

  tmp_unit=$(mktemp)
  render_ui_unit > "$tmp_unit"
  install -o root -g root -m 0644 "$tmp_unit" "$normal_unit_path"
  render_boot_guard_unit > "$tmp_unit"
  install -o root -g root -m 0644 "$tmp_unit" "$boot_guard_unit_path"
  render_runtime_watchdog_unit > "$tmp_unit"
  install -o root -g root -m 0644 "$tmp_unit" "$runtime_watchdog_unit_path"
  rm -f "$tmp_unit"
  kv "systemd_units" "installed"
  disable_legacy_user_ui_unit_best_effort

  systemctl daemon-reload
  systemctl enable wifi-kit-ui.service
  systemctl restart wifi-kit-ui.service
  systemctl enable wifi-kit-boot-guard.service
  systemctl enable wifi-kit-runtime-watchdog.service
  systemctl restart wifi-kit-runtime-watchdog.service
  kv "wifi-kit-ui" "enabled-restarted"
  kv "wifi-kit-boot-guard" "enabled"
  kv "wifi-kit-runtime-watchdog" "enabled-restarted"
  kv "status" "done"
}

if [ "$#" -lt 1 ]; then
  usage
  exit 2
fi

mode=$1
shift

case "$mode" in
  audit) [ "$#" -eq 0 ] || { usage; exit 2; }; cmd_audit ;;
  plan) [ "$#" -eq 0 ] || { usage; exit 2; }; cmd_plan ;;
  install) cmd_install "$@" ;;
  -h|--help|help) usage ;;
  *) usage; exit 2 ;;
esac
