#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RUNTIME_OS="$ROOT_DIR/lib/os.sh"

if [ -z "${NO_COLOR:-}" ] && [ -t 1 ] && [ "${TERM:-}" != "dumb" ]; then
  COLOR_RESET=$(printf '\033[0m')
  COLOR_LABEL=$(printf '\033[1m')
  COLOR_DIM=$(printf '\033[2m')
  COLOR_SECTION=$(printf '\033[36m')
  COLOR_GOOD=$(printf '\033[32m')
  COLOR_WARN=$(printf '\033[33m')
  COLOR_BAD=$(printf '\033[31m')
  COLOR_MUTED=$(printf '\033[37m')
else
  COLOR_RESET=""
  COLOR_LABEL=""
  COLOR_DIM=""
  COLOR_SECTION=""
  COLOR_GOOD=""
  COLOR_WARN=""
  COLOR_BAD=""
  COLOR_MUTED=""
fi

ui_line() { printf '%s\n' "$*"; }
ui_header() {
  printf '\n%s%s%s\n' "$COLOR_SECTION" "$1" "$COLOR_RESET"
  if [ -n "${2:-}" ]; then
    printf '%s%s%s\n' "$COLOR_DIM" "$2" "$COLOR_RESET"
  fi
}
ui_section() { printf '\n%s%s%s\n' "$COLOR_SECTION" "$1" "$COLOR_RESET"; }
ui_separator() { ui_line "$1"; }
ui_kv() { printf '  %-12s %s\n' "$1:" "$2"; }
ui_status() { printf '  %-12s %s\n' "$1:" "$2"; }
ui_whisper() { printf '%s%s%s\n' "$COLOR_MUTED" "$*" "$COLOR_RESET"; }
ui_success() { printf '%s%s%s\n' "$COLOR_GOOD" "$*" "$COLOR_RESET"; }
ui_warning() { printf '%s%s%s\n' "$COLOR_WARN" "$*" "$COLOR_RESET"; }
ui_failure() { printf '%s%s%s\n' "$COLOR_BAD" "$*" "$COLOR_RESET"; }
ui_prompt() { printf '%s ' "$1"; }
ui_masthead() { ui_header "$1" "$2"; }
ui_focus() { ui_kv "$1" "$2"; [ -n "${3:-}" ] && printf '%s\n' "$3"; }
ui_split_focus() { ui_kv "$1" "$2"; ui_kv "$3" "$4"; ui_line "$5"; ui_line "$6"; ui_line "$7"; }
ui_card_pair() { ui_kv "$1" "$2"; ui_kv "$3" "$4"; ui_kv "$5" "$6"; }
ui_choice_bar() { ui_line "1 plan  2 detect  3 modules  q quit"; }
ui_pause() { :; }

bootstrap_init_runtime() {
  mkdir -p "$ROOT_DIR/lib" "$ROOT_DIR/modules" "$ROOT_DIR/backends"

  if [ ! -f "$RUNTIME_OS" ]; then
    cat > "$RUNTIME_OS" <<'EOF'
#!/bin/sh
set -eu

seed_detect_os() {
  SEED_RUNTIME_MODE="bootstrap"
  SEED_OS_ID="generic"
  SEED_OS_NAME="bootstrap local runtime"
  SEED_OS_LIKE=" "

  if [ -r /etc/os-release ]; then
    . /etc/os-release
    if [ -n "${ID+x}" ] && [ -n "$ID" ]; then
      SEED_OS_ID="$ID"
    fi
    if [ -n "${NAME+x}" ] && [ -n "$NAME" ]; then
      SEED_OS_NAME="$NAME"
    fi
    if [ -n "${ID_LIKE+x}" ] && [ -n "$ID_LIKE" ]; then
      SEED_OS_LIKE="$ID_LIKE"
    fi
  fi
}
EOF
  fi

  if [ ! -f "$ROOT_DIR/backends/generic.sh" ]; then
    cat > "$ROOT_DIR/backends/generic.sh" <<'EOF'
#!/bin/sh
backend_name() { echo "generic"; }
backend_plan() { echo "- local bootstrap runtime"; echo "- install and apply are limited"; }
EOF
  fi

  if [ ! -f "$ROOT_DIR/backends/debian.sh" ]; then
    cat > "$ROOT_DIR/backends/debian.sh" <<'EOF'
#!/bin/sh
backend_name() { echo "debian"; }
backend_plan() { echo "- local bootstrap runtime"; echo "- apt flow is not available in placeholder mode"; }
EOF
  fi

  if [ ! -f "$ROOT_DIR/backends/raspberrypi.sh" ]; then
    cat > "$ROOT_DIR/backends/raspberrypi.sh" <<'EOF'
#!/bin/sh
backend_name() { echo "raspberrypi"; }
backend_plan() { echo "- local bootstrap runtime"; echo "- apt flow is not available in placeholder mode"; }
EOF
  fi

  if [ ! -f "$ROOT_DIR/backends/openwrt.sh" ]; then
    cat > "$ROOT_DIR/backends/openwrt.sh" <<'EOF'
#!/bin/sh
backend_name() { echo "openwrt"; }
backend_plan() { echo "- local bootstrap runtime"; echo "- apply modules are not available in placeholder mode"; }
EOF
  fi

  if [ ! -f "$ROOT_DIR/modules/git.sh" ]; then
    cat > "$ROOT_DIR/modules/git.sh" <<'EOF'
#!/bin/sh
module_git_plan() {
  echo "- runtime bootstrap placeholder"
  echo "- full git plan requires repository runtime"
}
EOF
  fi

  if [ ! -f "$ROOT_DIR/modules/docker.sh" ]; then
    cat > "$ROOT_DIR/modules/docker.sh" <<'EOF'
#!/bin/sh
module_docker_plan() {
  echo "- runtime bootstrap placeholder"
  echo "- full docker plan requires repository runtime"
}
EOF
  fi

  if [ ! -f "$ROOT_DIR/modules/tailscale.sh" ]; then
    cat > "$ROOT_DIR/modules/tailscale.sh" <<'EOF'
#!/bin/sh
module_tailscale_plan() {
  echo "- runtime bootstrap placeholder"
  echo "- full tailscale plan requires repository runtime"
}
EOF
  fi

  if [ ! -f "$ROOT_DIR/modules/wifi-stability.sh" ]; then
    cat > "$ROOT_DIR/modules/wifi-stability.sh" <<'EOF'
#!/bin/sh
module_wifi_stability_plan() {
  echo "- runtime bootstrap placeholder"
  echo "- Raspberry Pi Wi-Fi power save stability check"
  echo "- apply can disable wlan0 power_save for the current boot"
  echo "- persistence after reboot is TODO"
}
EOF
  fi

  if [ ! -f "$ROOT_DIR/modules/cloudflared.sh" ]; then
    cat > "$ROOT_DIR/modules/cloudflared.sh" <<'EOF'
#!/bin/sh
module_cloudflared_plan() {
  echo "- runtime bootstrap placeholder"
  echo "- full cloudflared install plan requires repository runtime"
  echo "- install-only: no tunnel login, no tunnel create, no credentials"
}
EOF
  fi

  if [ ! -f "$ROOT_DIR/modules/caddy.sh" ]; then
    cat > "$ROOT_DIR/modules/caddy.sh" <<'EOF'
#!/bin/sh
module_caddy_plan() {
  echo "- runtime bootstrap placeholder"
  echo "- full caddy install plan requires repository runtime"
  echo "- install-only: no site config, no DNS, no certificate automation"
}
EOF
  fi

  if [ ! -f "$ROOT_DIR/modules/homepage.sh" ]; then
    cat > "$ROOT_DIR/modules/homepage.sh" <<'EOF'
#!/bin/sh
module_homepage_plan() {
  echo "- runtime bootstrap placeholder"
  echo "- full homepage plan requires repository runtime"
}
EOF
  fi

  if [ ! -f "$ROOT_DIR/modules/homer.sh" ]; then
    cat > "$ROOT_DIR/modules/homer.sh" <<'EOF'
#!/bin/sh
module_homer_plan() {
  echo "- runtime bootstrap placeholder"
  echo "- full homer plan requires repository runtime"
  echo "- static placeholder path: /srv/seed-kit/homer"
  echo "- no Caddy config, no DNS, no certificates, no Docker"
}
EOF
  fi
}

bootstrap_runtime_ready() {
  command -v seed_detect_os >/dev/null 2>&1
}

is_full_repo_mode() {
  [ -f "$ROOT_DIR/docs/ARCHITECTURE.md" ]
}

seed_detect_os_builtin() {
  if is_full_repo_mode; then
    SEED_RUNTIME_MODE="full repo"
  else
    SEED_RUNTIME_MODE="single-file"
  fi
  SEED_OS_ID="generic"
  SEED_OS_NAME="local system"
  SEED_OS_LIKE=" "

  if [ -r /etc/os-release ]; then
    . /etc/os-release
    if [ -n "${ID+x}" ] && [ -n "$ID" ]; then
      SEED_OS_ID="$ID"
    fi
    if [ -n "${NAME+x}" ] && [ -n "$NAME" ]; then
      SEED_OS_NAME="$NAME"
    fi
    if [ -n "${ID_LIKE+x}" ] && [ -n "$ID_LIKE" ]; then
      SEED_OS_LIKE="$ID_LIKE"
    fi
  fi
}

if [ ! -f "$RUNTIME_OS" ] && ! is_full_repo_mode; then
  echo "Seed-Kit"
  echo "Small shell bootstrap toolkit"
  echo ""
  echo "System: runtime missing"

  printf "initialize local runtime structure? [y/N]: "
  if ! IFS= read -r bootstrap_answer; then
    bootstrap_answer=
  fi

  case "$bootstrap_answer" in
    y|Y)
      bootstrap_init_runtime
      echo "runtime initialized in: $(pwd)"
      echo "runtime files ready (OS/backend/modules)"
      echo "rerun seed-kit.sh for normal mode"
      exit 0
      ;;
    *)
      exit 0
      ;;
  esac
fi

if [ -f "$RUNTIME_OS" ]; then
  . "$RUNTIME_OS"
fi

if ! bootstrap_runtime_ready; then
  if is_full_repo_mode; then
    seed_detect_os() { seed_detect_os_builtin; }
  else
    bootstrap_init_runtime
    . "$RUNTIME_OS"
  fi
fi

MODULES="git docker tailscale wifi-stability cloudflared caddy homer homepage wifi-kit"

load_backend_file() {
  backend_file=$1
  backend_label=$2

  if [ -f "$backend_file" ]; then
    . "$backend_file"
  else
    backend_name() { echo "$backend_label"; }
    backend_plan() { echo "- backend file not present in this checkout"; echo "- using built-in minimal backend fallback"; }
  fi
}

load_backend() {
  case "$SEED_OS_ID" in
    raspberrypi)
      load_backend_file "$ROOT_DIR/backends/raspberrypi.sh" "raspberrypi"
      ;;
    debian)
      load_backend_file "$ROOT_DIR/backends/debian.sh" "debian"
      ;;
    ubuntu)
      load_backend_file "$ROOT_DIR/backends/debian.sh" "debian"
      ;;
    openwrt)
      load_backend_file "$ROOT_DIR/backends/openwrt.sh" "openwrt"
      ;;
    *)
      case " $SEED_OS_LIKE " in
        *" debian "*)
          load_backend_file "$ROOT_DIR/backends/debian.sh" "debian"
          ;;
        *)
          backend_name() { echo "generic"; }
          backend_plan() { echo "- use generic POSIX shell checks only"; }
          ;;
      esac
      ;;
  esac
}

run_module_plan() {
  module=$1
  module_file="$ROOT_DIR/modules/$module.sh"
  module_plan_base="$(printf '%s' "$module" | tr '-' '_')"
  module_plan_fn="module_${module_plan_base}_plan"

  if [ ! -f "$module_file" ]; then
    ui_line "Missing module: $module"
    return 1
  fi

  # shellcheck source=/dev/null
  . "$module_file"

  if ! command -v "$module_plan_fn" >/dev/null 2>&1; then
    ui_line "Missing module plan function: $module_plan_fn"
    return 1
  fi

  "$module_plan_fn"
}

run_module_apply() {
  module=$1
  module_file="$ROOT_DIR/modules/$module.sh"
  module_apply_base="$(printf '%s' "$module" | tr '-' '_')"
  module_apply_fn="module_${module_apply_base}_apply"

  if [ ! -f "$module_file" ]; then
    ui_line "Missing module: $module"
    return 1
  fi

  # shellcheck source=/dev/null
  . "$module_file"

  if ! command -v "$module_apply_fn" >/dev/null 2>&1; then
    ui_line "Missing module apply function: $module_apply_fn"
    return 1
  fi

  "$module_apply_fn"
}

show_bootstrap_plan_summary() {
  ui_section "bootstrap runtime"
  ui_line "bootstrap runtime active"
  ui_line "OS detected: $SEED_OS_NAME"
  ui_line "backend detected: $(backend_name)"
  ui_line "modules known: $MODULES"
  ui_line "runtime minimal active"
  ui_line "full repo runtime adds advanced module plans and stronger apply support"
}

machine_hostname() {
  hostname 2>/dev/null || echo "unknown"
}

machine_arch() {
  uname -m 2>/dev/null || echo "unknown"
}

machine_model() {
  if [ -r /proc/device-tree/model ]; then
    tr -d '\000' < /proc/device-tree/model 2>/dev/null || echo "unknown machine"
  else
    machine_hostname
  fi
}

machine_ram() {
  if [ -r /proc/meminfo ]; then
    while read -r key value unit; do
      case "$key" in
        MemTotal:)
          mb=$((value / 1024))
          if [ "$mb" -ge 1024 ]; then
            gb=$((mb / 1024))
            rem=$((mb % 1024))
            if [ "$rem" -gt 512 ]; then
              gb=$((gb + 1))
            fi
            echo "${gb} GB RAM"
          else
            echo "${mb} MB RAM"
          fi
          return
          ;;
      esac
    done < /proc/meminfo
  fi

  echo "RAM unknown"
}

command_status() {
  command -v "$1" >/dev/null 2>&1 && echo "present" || echo "missing"
}

module_is_installed() {
  command -v "$1" >/dev/null 2>&1
}

docker_status() {
  if module_is_installed docker; then
    echo "present"
  else
    echo "heavy"
  fi
}

status_word() {
  case "$1" in
    present|ok|ready)
      echo "ready"
      ;;
    heavy)
      echo "optional"
      ;;
    *)
      echo "$1"
      ;;
    esac
}

is_debian_like() {
  case "$SEED_OS_ID" in
    debian|ubuntu|raspberrypi)
      return 0
      ;;
  esac

  case " $SEED_OS_LIKE " in
    *" debian "*) return 0 ;;
    *) return 1 ;;
  esac
}

apply_step() {
  ui_line "[apply] $*"
}

apply_skip() {
  ui_warning "[skip] $*"
}

require_network_for_apply() {
  label=${1:-apply}

  if ! command -v ping >/dev/null 2>&1; then
    echo "network check required for $label, but ping is not available." >&2
    return 3
  fi

  if ! ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
    echo "network access is required for $label." >&2
    echo "Check connectivity, then rerun the selected apply command." >&2
    return 4
  fi

  return 0
}

apply_safe_confirm() {
  if [ "$APPLY_AUTO" -eq 1 ]; then
    return 0
  fi

  ui_prompt "confirm safe action: continue [y/N]:"
  IFS= read -r answer || return 1
  case "$answer" in
    y|Y)
      return 0
      ;;
    *)
      echo "[apply] aborted by user"
      return 2
      ;;
  esac
}

require_sudo_for_system_action() {
  label=${1:-this action}

  if [ "$(id -u)" -eq 0 ]; then
    ui_line "running as root; no sudo needed for $label"
    return 0
  fi

  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required for $label but is not installed." >&2
    return 3
  fi

  if [ -t 0 ] && [ -t 1 ]; then
    if ! sudo -v; then
      echo "sudo access is required for $label." >&2
      return 4
    fi
    return 0
  fi

  if ! sudo -n true >/dev/null 2>&1; then
    echo "sudo access is required for $label."
    echo "Run this command from an interactive terminal."
    return 4
  fi

  return 0
}

apply_module_git() {
  apply_step "git: checking installation"
  if module_is_installed git; then
    apply_skip "git already installed"
    return 0
  fi

  if ! is_debian_like; then
    echo "[git] unsupported OS for apply: $SEED_OS_NAME" >&2
    return 2
  fi

  if ! apply_safe_confirm; then
    return 2
  fi

  if ! require_network_for_apply "git package install"; then
    return 2
  fi

  if ! require_sudo_for_system_action "git package install" "sh seed-kit.sh --apply --modules=git"; then
    return 2
  fi

  apply_step "git: install via apt"
  if [ "$(id -u)" -eq 0 ]; then
    SUDO=
  else
    SUDO=sudo
  fi

  apply_step "git: running apt-get update"
  if ! $SUDO apt-get update; then
    echo "[git] apt-get update failed" >&2
    return 4
  fi

  apply_step "git: running apt-get install"
  if ! $SUDO apt-get install -y git; then
    echo "[git] apt-get install failed" >&2
    return 5
  fi

  apply_step "git: verifying installation"
  if module_is_installed git; then
    apply_step "git: installed"
    return 0
  fi

  echo "[git] post-install check failed: binary not found" >&2
  return 6
}

is_raspberry_pi() {
  case "$SEED_OS_ID" in
    raspberrypi)
      return 0
      ;;
  esac

  if [ -r /proc/device-tree/model ]; then
    model=$(tr -d '\000' < /proc/device-tree/model 2>/dev/null || true)
    case "$model" in
      *"Raspberry Pi"*) return 0 ;;
    esac
  fi

  return 1
}

wifi_stability_iw_cmd() {
  if command -v iw >/dev/null 2>&1; then
    command -v iw
    return 0
  fi

  if [ -x /usr/sbin/iw ]; then
    echo "/usr/sbin/iw"
    return 0
  fi

  return 1
}

wifi_stability_power_save_state() {
  iw_cmd=$(wifi_stability_iw_cmd) || return 1
  "$iw_cmd" dev wlan0 get power_save 2>/dev/null || return 1
}

wifi_stability_service_enabled() {
  command -v systemctl >/dev/null 2>&1 &&
    systemctl is-enabled seed-kit-wifi-stability.service >/dev/null 2>&1
}

apply_module_wifi_stability() {
  apply_step "wifi-stability: checking Raspberry Pi"
  if ! is_raspberry_pi; then
    apply_skip "not a Raspberry Pi target"
    return 0
  fi

  apply_step "wifi-stability: checking wlan0"
  if [ ! -d /sys/class/net/wlan0 ]; then
    apply_skip "wlan0 not present"
    return 0
  fi

  iw_cmd=$(wifi_stability_iw_cmd || true)
  if [ -z "$iw_cmd" ]; then
    echo "[wifi-stability] iw is required to inspect or change Wi-Fi power save." >&2
    return 2
  fi

  current_state=$(wifi_stability_power_save_state || true)
  if [ -z "$current_state" ]; then
    echo "[wifi-stability] unable to read wlan0 power_save state" >&2
    return 2
  fi

  ui_line "[wifi-stability] current: $current_state"
  case "$current_state" in
    *": off"|*" off")
      apply_skip "wlan0 power_save already off for current boot"
      ;;
    *": on"|*" on")
      needs_current_boot_change=1
      ;;
    *)
      echo "[wifi-stability] unknown power_save state: $current_state" >&2
      return 2
      ;;
  esac

  if [ "${needs_current_boot_change:-0}" -eq 0 ] && wifi_stability_service_enabled; then
    apply_skip "wifi-stability systemd service already enabled"
    return 0
  fi

  if ! command -v systemctl >/dev/null 2>&1; then
    echo "[wifi-stability] systemctl is required for persistent V1 service." >&2
    return 2
  fi

  ui_line "Wi-Fi power save may make idle Raspberry Pi nodes unreachable."
  ui_line "This action disables wlan0 power_save now when needed."
  ui_line "It also installs a small systemd oneshot for persistence after reboot."
  ui_line "No reboot or network restart will be performed."

  if ! apply_safe_confirm; then
    return 2
  fi

  if ! require_sudo_for_system_action "wifi power save disable"; then
    return 2
  fi

  if [ "$(id -u)" -eq 0 ]; then
    SUDO=
  else
    SUDO=sudo
  fi

  if [ "${needs_current_boot_change:-0}" -eq 1 ]; then
    apply_step "wifi-stability: disable wlan0 power_save for current boot"
    if ! $SUDO "$iw_cmd" dev wlan0 set power_save off; then
      echo "[wifi-stability] failed to disable wlan0 power_save" >&2
      return 3
    fi
  fi

  verify_state=$(wifi_stability_power_save_state || true)
  ui_line "[wifi-stability] after: ${verify_state:-unknown}"
  case "$verify_state" in
    *": off"|*" off")
      apply_step "wifi-stability: wlan0 power_save off"
      ;;
    *)
      echo "[wifi-stability] verification failed: wlan0 power_save is not off" >&2
      return 4
      ;;
  esac

  service_tmp="${TMPDIR:-/tmp}/seed-kit-wifi-stability.service.$$"
  cat > "$service_tmp" <<'EOF'
[Unit]
Description=Seed-Kit Wi-Fi stability guard
Wants=sys-subsystem-net-devices-wlan0.device
After=sys-subsystem-net-devices-wlan0.device
ConditionPathExists=/sys/class/net/wlan0

[Service]
Type=oneshot
ExecStart=/usr/sbin/iw dev wlan0 set power_save off
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  apply_step "wifi-stability: install systemd oneshot service"
  if ! $SUDO cp "$service_tmp" /etc/systemd/system/seed-kit-wifi-stability.service; then
    rm -f "$service_tmp"
    echo "[wifi-stability] failed to install systemd service" >&2
    return 5
  fi
  rm -f "$service_tmp"

  apply_step "wifi-stability: reload systemd"
  if ! $SUDO systemctl daemon-reload; then
    echo "[wifi-stability] systemctl daemon-reload failed" >&2
    return 6
  fi

  apply_step "wifi-stability: enable service for next boot"
  if ! $SUDO systemctl enable seed-kit-wifi-stability.service; then
    echo "[wifi-stability] failed to enable systemd service" >&2
    return 7
  fi

  if wifi_stability_service_enabled; then
    apply_step "wifi-stability: persistent service enabled"
    ui_line "Rollback:"
    ui_line "  sudo systemctl disable seed-kit-wifi-stability.service"
    ui_line "  sudo rm /etc/systemd/system/seed-kit-wifi-stability.service"
    ui_line "  sudo systemctl daemon-reload"
    return 0
  fi

  echo "[wifi-stability] service enable verification failed" >&2
  return 8
}

tailscale_repo_distro() {
  case "$SEED_OS_ID" in
    raspberrypi)
      echo "raspbian"
      ;;
    debian|ubuntu)
      echo "$SEED_OS_ID"
      ;;
    *)
      if is_debian_like; then
        echo "debian"
      else
        return 1
      fi
      ;;
  esac
}

tailscale_repo_codename() {
  if [ -r /etc/os-release ]; then
    (
      . /etc/os-release
      printf '%s\n' "${VERSION_CODENAME:-}"
    )
  fi
}

apply_module_tailscale() {
  apply_step "tailscale: checking installation"
  if module_is_installed tailscale; then
    apply_skip "tailscale already installed"
    ui_line "Next manual step: sudo tailscale up"
    return 0
  fi

  if ! is_debian_like; then
    echo "[tailscale] unsupported OS for apply: $SEED_OS_NAME" >&2
    return 2
  fi

  if ! apply_safe_confirm; then
    return 2
  fi

  if ! require_network_for_apply "tailscale package install"; then
    return 2
  fi

  if ! require_sudo_for_system_action "tailscale package install" "sh seed-kit.sh --apply --modules=tailscale"; then
    return 2
  fi

  tailscale_distro=$(tailscale_repo_distro)
  tailscale_codename=$(tailscale_repo_codename)
  if [ -z "$tailscale_codename" ]; then
    echo "[tailscale] unable to detect VERSION_CODENAME from /etc/os-release" >&2
    return 2
  fi

  if [ "$(id -u)" -eq 0 ]; then
    SUDO=
  else
    SUDO=sudo
  fi

  apply_step "tailscale: install apt prerequisites"
  if ! $SUDO apt-get update; then
    echo "[tailscale] apt-get update failed" >&2
    return 4
  fi
  if ! $SUDO apt-get install -y ca-certificates curl; then
    echo "[tailscale] prerequisite install failed" >&2
    return 5
  fi

  tailscale_base_url="https://pkgs.tailscale.com/stable/$tailscale_distro/$tailscale_codename"
  tailscale_key_tmp="${TMPDIR:-/tmp}/seed-kit-tailscale-keyring.$$"
  tailscale_list_tmp="${TMPDIR:-/tmp}/seed-kit-tailscale-list.$$"

  apply_step "tailscale: download official apt key"
  if ! curl -fsSL "$tailscale_base_url.noarmor.gpg" -o "$tailscale_key_tmp"; then
    rm -f "$tailscale_key_tmp" "$tailscale_list_tmp"
    echo "[tailscale] failed to download apt key: $tailscale_base_url.noarmor.gpg" >&2
    return 6
  fi

  apply_step "tailscale: download official apt source"
  if ! curl -fsSL "$tailscale_base_url.tailscale-keyring.list" -o "$tailscale_list_tmp"; then
    rm -f "$tailscale_key_tmp" "$tailscale_list_tmp"
    echo "[tailscale] failed to download apt source: $tailscale_base_url.tailscale-keyring.list" >&2
    return 7
  fi

  apply_step "tailscale: configure apt source"
  if ! $SUDO mkdir -p /usr/share/keyrings; then
    rm -f "$tailscale_key_tmp" "$tailscale_list_tmp"
    echo "[tailscale] failed to create keyring directory" >&2
    return 8
  fi
  if ! $SUDO cp "$tailscale_key_tmp" /usr/share/keyrings/tailscale-archive-keyring.gpg; then
    rm -f "$tailscale_key_tmp" "$tailscale_list_tmp"
    echo "[tailscale] failed to install apt key" >&2
    return 9
  fi
  if ! $SUDO cp "$tailscale_list_tmp" /etc/apt/sources.list.d/tailscale.list; then
    rm -f "$tailscale_key_tmp" "$tailscale_list_tmp"
    echo "[tailscale] failed to install apt source" >&2
    return 10
  fi
  rm -f "$tailscale_key_tmp" "$tailscale_list_tmp"

  apply_step "tailscale: install package"
  if ! $SUDO apt-get update; then
    echo "[tailscale] apt-get update failed after adding repository" >&2
    return 11
  fi
  if ! $SUDO apt-get install -y tailscale; then
    echo "[tailscale] apt-get install tailscale failed" >&2
    return 12
  fi

  apply_step "tailscale: verifying installation"
  if module_is_installed tailscale; then
    apply_step "tailscale: installed"
    ui_line "Next manual step: sudo tailscale up"
    return 0
  fi

  echo "[tailscale] post-install check failed: binary not found" >&2
  return 13
}

apply_module_cloudflared() {
  apply_step "cloudflared: checking installation"
  if module_is_installed cloudflared; then
    apply_skip "cloudflared already installed"
    ui_line "Next manual step: cloudflared tunnel login/create/configure outside Seed-Kit"
    return 0
  fi

  if ! is_debian_like; then
    echo "[cloudflared] unsupported OS for apply: $SEED_OS_NAME" >&2
    return 2
  fi

  if ! apply_safe_confirm; then
    return 2
  fi

  if ! require_network_for_apply "cloudflared package install"; then
    return 2
  fi

  if ! require_sudo_for_system_action "cloudflared package install" "sh seed-kit.sh --apply --modules=cloudflared"; then
    return 2
  fi

  if [ "$(id -u)" -eq 0 ]; then
    SUDO=
  else
    SUDO=sudo
  fi

  apply_step "cloudflared: install apt prerequisites"
  if ! $SUDO apt-get update; then
    echo "[cloudflared] apt-get update failed" >&2
    return 4
  fi
  if ! $SUDO apt-get install -y ca-certificates curl; then
    echo "[cloudflared] prerequisite install failed" >&2
    return 5
  fi

  cloudflared_key_tmp="${TMPDIR:-/tmp}/seed-kit-cloudflare-keyring.$$"
  cloudflared_list_tmp="${TMPDIR:-/tmp}/seed-kit-cloudflared-list.$$"

  apply_step "cloudflared: download official apt key"
  if ! curl -fsSL "https://pkg.cloudflare.com/cloudflare-main.gpg" -o "$cloudflared_key_tmp"; then
    rm -f "$cloudflared_key_tmp" "$cloudflared_list_tmp"
    echo "[cloudflared] failed to download apt key: https://pkg.cloudflare.com/cloudflare-main.gpg" >&2
    return 6
  fi

  apply_step "cloudflared: prepare official apt source"
  if ! printf '%s\n' "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" > "$cloudflared_list_tmp"; then
    rm -f "$cloudflared_key_tmp" "$cloudflared_list_tmp"
    echo "[cloudflared] failed to prepare apt source" >&2
    return 7
  fi

  apply_step "cloudflared: configure apt source"
  if ! $SUDO mkdir -p /usr/share/keyrings; then
    rm -f "$cloudflared_key_tmp" "$cloudflared_list_tmp"
    echo "[cloudflared] failed to create keyring directory" >&2
    return 8
  fi
  if ! $SUDO cp "$cloudflared_key_tmp" /usr/share/keyrings/cloudflare-main.gpg; then
    rm -f "$cloudflared_key_tmp" "$cloudflared_list_tmp"
    echo "[cloudflared] failed to install apt key" >&2
    return 9
  fi
  if ! $SUDO cp "$cloudflared_list_tmp" /etc/apt/sources.list.d/cloudflared.list; then
    rm -f "$cloudflared_key_tmp" "$cloudflared_list_tmp"
    echo "[cloudflared] failed to install apt source" >&2
    return 10
  fi
  rm -f "$cloudflared_key_tmp" "$cloudflared_list_tmp"

  apply_step "cloudflared: install package"
  if ! $SUDO apt-get update; then
    echo "[cloudflared] apt-get update failed after adding repository" >&2
    return 11
  fi
  if ! $SUDO apt-get install -y cloudflared; then
    echo "[cloudflared] apt-get install cloudflared failed" >&2
    return 12
  fi

  apply_step "cloudflared: verifying installation"
  if module_is_installed cloudflared; then
    apply_step "cloudflared: installed"
    ui_line "Next manual step: cloudflared tunnel login/create/configure outside Seed-Kit"
    return 0
  fi

  echo "[cloudflared] post-install check failed: binary not found" >&2
  return 13
}

apply_module_caddy() {
  apply_step "caddy: checking installation"
  if module_is_installed caddy; then
    apply_skip "caddy already installed"
    ui_line "Next manual step: configure Caddy sites/services outside Seed-Kit"
    return 0
  fi

  if ! is_debian_like; then
    echo "[caddy] unsupported OS for apply: $SEED_OS_NAME" >&2
    return 2
  fi

  if ! apply_safe_confirm; then
    return 2
  fi

  if ! require_network_for_apply "caddy package install"; then
    return 2
  fi

  if ! require_sudo_for_system_action "caddy package install" "sh seed-kit.sh --apply --modules=caddy"; then
    return 2
  fi

  if [ "$(id -u)" -eq 0 ]; then
    SUDO=
  else
    SUDO=sudo
  fi

  apply_step "caddy: install apt prerequisites"
  if ! $SUDO apt-get update; then
    echo "[caddy] apt-get update failed" >&2
    return 4
  fi
  if ! $SUDO apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg; then
    echo "[caddy] prerequisite install failed" >&2
    return 5
  fi

  caddy_key_tmp="${TMPDIR:-/tmp}/seed-kit-caddy-key.$$"
  caddy_keyring_tmp="${TMPDIR:-/tmp}/seed-kit-caddy-keyring.$$"
  caddy_list_tmp="${TMPDIR:-/tmp}/seed-kit-caddy-list.$$"

  apply_step "caddy: download official apt key"
  if ! curl -1sLf "https://dl.cloudsmith.io/public/caddy/stable/gpg.key" -o "$caddy_key_tmp"; then
    rm -f "$caddy_key_tmp" "$caddy_keyring_tmp" "$caddy_list_tmp"
    echo "[caddy] failed to download apt key: https://dl.cloudsmith.io/public/caddy/stable/gpg.key" >&2
    return 6
  fi

  apply_step "caddy: prepare apt keyring"
  if ! gpg --dearmor < "$caddy_key_tmp" > "$caddy_keyring_tmp"; then
    rm -f "$caddy_key_tmp" "$caddy_keyring_tmp" "$caddy_list_tmp"
    echo "[caddy] failed to prepare apt keyring" >&2
    return 7
  fi

  apply_step "caddy: download official apt source"
  if ! curl -1sLf "https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt" -o "$caddy_list_tmp"; then
    rm -f "$caddy_key_tmp" "$caddy_keyring_tmp" "$caddy_list_tmp"
    echo "[caddy] failed to download apt source: https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt" >&2
    return 8
  fi

  apply_step "caddy: configure apt source"
  if ! $SUDO mkdir -p /usr/share/keyrings; then
    rm -f "$caddy_key_tmp" "$caddy_keyring_tmp" "$caddy_list_tmp"
    echo "[caddy] failed to create keyring directory" >&2
    return 9
  fi
  if ! $SUDO cp "$caddy_keyring_tmp" /usr/share/keyrings/caddy-stable-archive-keyring.gpg; then
    rm -f "$caddy_key_tmp" "$caddy_keyring_tmp" "$caddy_list_tmp"
    echo "[caddy] failed to install apt keyring" >&2
    return 10
  fi
  if ! $SUDO cp "$caddy_list_tmp" /etc/apt/sources.list.d/caddy-stable.list; then
    rm -f "$caddy_key_tmp" "$caddy_keyring_tmp" "$caddy_list_tmp"
    echo "[caddy] failed to install apt source" >&2
    return 11
  fi
  if ! $SUDO chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg /etc/apt/sources.list.d/caddy-stable.list; then
    rm -f "$caddy_key_tmp" "$caddy_keyring_tmp" "$caddy_list_tmp"
    echo "[caddy] failed to set apt source permissions" >&2
    return 12
  fi
  rm -f "$caddy_key_tmp" "$caddy_keyring_tmp" "$caddy_list_tmp"

  apply_step "caddy: install package"
  if ! $SUDO apt-get update; then
    echo "[caddy] apt-get update failed after adding repository" >&2
    return 13
  fi
  if ! $SUDO apt-get install -y caddy; then
    echo "[caddy] apt-get install caddy failed" >&2
    return 14
  fi

  apply_step "caddy: verifying installation"
  if module_is_installed caddy; then
    apply_step "caddy: installed"
    ui_line "Next manual step: configure Caddy sites/services outside Seed-Kit"
    return 0
  fi

  echo "[caddy] post-install check failed: binary not found" >&2
  return 15
}

suggested_next_step() {
  if ! command -v git >/dev/null 2>&1; then
    echo "install git"
  elif ! command -v tailscale >/dev/null 2>&1; then
    echo "decide if tailscale is needed"
  else
    echo "review module plan"
  fi
}

show_dashboard() {
  ui_header "Seed-Kit" "small shell bootstrap toolkit"
  ui_section "System"
  ui_kv "OS" "$SEED_OS_NAME"
  ui_kv "Backend" "$(backend_name)"
  ui_kv "Runtime" "${SEED_RUNTIME_MODE:-full}"
  ui_kv "Next" "--plan"

  ui_section "Status"
  ui_kv "Git" "$(command_status git)"
  ui_kv "Docker" "$(docker_status)"
  ui_kv "Tailscale" "$(command_status tailscale)"

  ui_section "Commands"
  ui_line "  --plan       show install plan"
  ui_line "  --modules    list available modules"
  ui_line "  --apply      apply selected modules"
}

show_modules_list() {
  for module in $MODULES; do
    ui_line "$module"
  done
}

seed_kit_usage() {
  echo "Usage: sh seed-kit.sh [--plan|--detect|--ui-demo|--modules|--apply]"
  echo ""
  echo "Planned CLI shape:"
  echo "  --plan           show the full execution plan"
  echo "  --profile=<name> --plan  show recommended modules for one profile"
  echo "  --profile=<name> --apply  preview profile apply order without running modules"
  echo "  --modules        list available modules"
  echo "  --apply [--modules=git,docker] [--yes|-y]  minimal safe apply for supported modules"
  echo "  --apply-module=<module> [--yes|-y]  apply one module only"
  echo "  --fetch-module=wifi-kit [--yes|-y]  fetch one repo-backed module with git sparse checkout"
  echo "  --install-module=wifi-kit [--yes|-y]  prepare git if needed, then fetch one repo-backed module"
  echo "  --self-check     compare local Seed-Kit with public repository HEAD when git is available"
  echo "  --detect         show OS detection details"
  echo "  --uninstall-runtime [--yes|-y]  remove local Seed-Kit runtime directories (lib/modules/backends)"
}

show_self_check() {
  repo_url="https://github.com/warzou/seed-kit.git"

  ui_header "Seed-Kit self check"

  if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local_mode="git repository"
    local_head=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
  else
    local_mode="${SEED_RUNTIME_MODE:-single-file}"
    local_head="unknown"
  fi

  ui_kv "Local mode" "$local_mode"
  ui_kv "Local commit" "$local_head"
  ui_kv "Remote repo" "$repo_url"

  if ! command -v git >/dev/null 2>&1; then
    ui_line "Remote HEAD: unavailable"
    ui_line "Update status: git is required for network self-check"
    ui_line "Try:"
    ui_line "  sh seed-kit.sh --apply --modules=git"
    return 0
  fi

  if ! remote_line=$(git ls-remote "$repo_url" HEAD 2>/dev/null); then
    ui_line "Remote HEAD: unavailable"
    ui_line "Update status: cannot reach public Seed-Kit repository"
    return 2
  fi

  remote_head=$(printf '%s\n' "$remote_line" | awk '{print $1}')
  if [ -z "$remote_head" ]; then
    ui_line "Remote HEAD: unavailable"
    ui_line "Update status: remote HEAD not found"
    return 2
  fi

  ui_kv "Remote HEAD" "$remote_head"

  if [ "$local_head" = "unknown" ]; then
    ui_line "Update status: cannot compare local single-file yet"
  elif [ "$local_head" = "$remote_head" ]; then
    ui_line "Update status: up to date"
  else
    ui_line "Update status: newer remote available or local commit differs"
  fi
}

profile_modules() {
  case "$1" in
    rpi0-pocket)
      echo "wifi-stability homer"
      ;;
    rpi0-pocket-node)
      echo "wifi-stability tailscale homer"
      ;;
    rpi3-edge)
      echo "wifi-stability cloudflared caddy homer"
      ;;
    rpi3-edge-node|minimal-resilient-node)
      echo "wifi-stability tailscale cloudflared caddy homer"
      ;;
    edge-services-node)
      echo "wifi-stability tailscale cloudflared caddy homer docker homepage"
      ;;
    *)
      return 1
      ;;
  esac
}

show_profile_plan() {
  profile=$1

  if ! modules=$(profile_modules "$profile"); then
    echo "unknown profile: $profile" >&2
    echo "known profiles: rpi0-pocket rpi0-pocket-node rpi3-edge rpi3-edge-node minimal-resilient-node edge-services-node" >&2
    return 2
  fi

  ui_header "profile plan" "$profile"
  ui_line "recommended modules:"
  for module in $modules; do
    ui_line "  $module"
  done
  ui_line ""
  ui_line "profile apply V1 is available for minimal-resilient-node only"
}

show_profile_apply_preview() {
  profile=$1

  if ! modules=$(profile_modules "$profile"); then
    echo "unknown profile: $profile" >&2
    echo "known profiles: rpi0-pocket rpi0-pocket-node rpi3-edge rpi3-edge-node minimal-resilient-node edge-services-node" >&2
    return 2
  fi

  ui_header "profile apply preview" "$profile"
  ui_line "would apply:"
  for module in $modules; do
    ui_line "  $module"
  done
  ui_line ""
  ui_line "profile apply automation is not implemented yet"
}

run_profile_apply() {
  profile=$1

  if ! modules=$(profile_modules "$profile"); then
    echo "unknown profile: $profile" >&2
    echo "known profiles: rpi0-pocket rpi0-pocket-node rpi3-edge rpi3-edge-node minimal-resilient-node edge-services-node" >&2
    return 2
  fi

  case "$profile" in
    minimal-resilient-node)
      ;;
    *)
      show_profile_apply_preview "$profile"
      ui_line "real profile apply V1 is limited to minimal-resilient-node"
      return 0
      ;;
  esac

  ui_header "profile apply" "$profile"
  ui_line "modules in order:"
  for module in $modules; do
    ui_line "  $module"
  done
  ui_line ""
  ui_line "Preflight:"
  ui_line "  some modules may require sudo"
  ui_line "  some modules may require network access"
  ui_line "  package installs should run from an interactive SSH/local terminal"
  ui_line "  profile apply stops on first failure"
  ui_line "  no rollback automation is implemented"
  ui_line ""
  ui_line "This applies modules sequentially and stops on first failure."
  ui_line "No rollback automation is implemented."

  APPLY_AUTO=0
  if ! apply_safe_confirm; then
    return 2
  fi

  APPLY_AUTO=1
  set -- $modules
  total=$#
  index=1
  completed_modules=""

  for module do
    ui_line "[profile $index/$total] $module"
    APPLY_MODULES=$module
    if ! run_apply_modules; then
      ui_line ""
      ui_line "profile apply failed"
      if [ -n "$completed_modules" ]; then
        ui_line ""
        for completed_module in $completed_modules; do
          ui_success "[OK] $completed_module"
        done
      fi
      ui_failure "[FAIL] $module"
      return 1
    fi
    completed_modules="$completed_modules $module"
    index=$((index + 1))
  done

  ui_line ""
  ui_line "profile apply completed"
  ui_line ""
  for completed_module in $completed_modules; do
    ui_success "[OK] $completed_module"
  done
  ui_line ""
  ui_warning "manual steps remaining:"
  ui_line ""
  ui_line "* sudo tailscale up"
  ui_line "* configure cloudflared tunnel"
  ui_line "* configure caddy sites"
}

parse_fetch_options() {
  FETCH_AUTO=0
  for arg in "$@"; do
    case "$arg" in
      -y|--yes)
        FETCH_AUTO=1
        ;;
      *)
        echo "unknown option: $arg" >&2
        return 2
        ;;
    esac
  done
}

fetch_module_safe_confirm() {
  if [ "$FETCH_AUTO" -eq 1 ]; then
    return 0
  fi

  ui_prompt "fetch repo-backed module? [y/N]:"
  IFS= read -r answer || answer=
  case "$answer" in
    y|Y)
      return 0
      ;;
    *)
      echo "[fetch] aborted by user"
      return 2
      ;;
  esac
}

fetch_repo_module() {
  module=$1
  repo_url="https://github.com/warzou/seed-kit.git"

  case "$module" in
    wifi-kit)
      target_dir="${HOME:-}/seed-kit-wifi-kit"
      ;;
    *)
      echo "unsupported repo-backed module fetch: $module" >&2
      echo "supported: wifi-kit" >&2
      return 2
      ;;
  esac

  if [ -z "${HOME:-}" ]; then
    echo "HOME is not set; cannot choose a safe fetch directory." >&2
    return 2
  fi

  if ! command -v git >/dev/null 2>&1; then
    echo "git is required to fetch repo-backed modules."
    echo "Try:"
    echo "  sh seed-kit.sh --apply --modules=git"
    return 2
  fi

  if [ -e "$target_dir" ]; then
    echo "target already exists: $target_dir"
    echo "No changes made."
    echo "Try:"
    echo "  cd $target_dir"
    echo "  git status"
    return 0
  fi

  ui_header "fetch module" "$module"
  ui_line "Repository: $repo_url"
  ui_line "Target: $target_dir"
  ui_line "Mode: git sparse checkout"
  ui_line "No git pull, no token, no overwrite."

  if ! fetch_module_safe_confirm; then
    return 2
  fi

  if [ "$FETCH_AUTO" -eq 1 ]; then
    ui_whisper "auto-confirm mode requested"
  fi

  ui_line "[fetch] check repository access"
  if ! git ls-remote "$repo_url" HEAD >/dev/null 2>&1; then
    echo "Cannot reach warzou/seed-kit repository." >&2
    echo "Check network access and GitHub connectivity." >&2
    return 3
  fi

  ui_line "[fetch] clone sparse repository"
  if ! git clone --filter=blob:none --sparse "$repo_url" "$target_dir"; then
    echo "[fetch] clone failed" >&2
    return 4
  fi

  ui_line "[fetch] select wifi-kit paths"
  if ! (
    cd "$target_dir" &&
    git sparse-checkout set --no-cone \
      /seed-kit.sh \
      /modules/wifi-kit \
      /modules/wifi-kit.sh \
      /docs/ARCHITECTURE.md \
      /docs/MODULES.md \
      /docs/FRESH-NODE-FLOW.md
  ); then
    echo "[fetch] sparse-checkout failed in $target_dir" >&2
    return 5
  fi

  ui_line "Module fetched: wifi-kit"
  ui_line "Next:"
  ui_line "  cd $target_dir"
  ui_line "  sh seed-kit.sh --modules"
  ui_line "  sh seed-kit.sh --plan"
  ui_line "  sh seed-kit.sh --apply --modules=wifi-kit"
}

parse_install_options() {
  INSTALL_AUTO=0
  for arg in "$@"; do
    case "$arg" in
      -y|--yes)
        INSTALL_AUTO=1
        ;;
      *)
        echo "unknown option: $arg" >&2
        return 2
        ;;
    esac
  done
}

install_repo_module() {
  module=$1

  case "$module" in
    wifi-kit)
      ;;
    *)
      echo "unsupported repo-backed module install: $module" >&2
      echo "supported: wifi-kit" >&2
      return 2
      ;;
  esac

  ui_header "install module" "$module"
  ui_line "This prepares a sparse repo-backed module checkout."
  ui_line "It does not run wifi-kit, update Seed-Kit, or overwrite existing directories."

  if ! command -v git >/dev/null 2>&1; then
    ui_line "Git is required for repo-backed modules."
    ui_line "Manual option:"
    ui_line "  sh seed-kit.sh --apply --modules=git"
    ui_line "Seed-Kit can run that SAFE git install path now."

    APPLY_AUTO=$INSTALL_AUTO
    if ! apply_module_git; then
      echo "[install] git install path did not complete" >&2
      return 3
    fi

    if ! command -v git >/dev/null 2>&1; then
      echo "[install] git is still missing after install attempt" >&2
      return 4
    fi
  fi

  FETCH_AUTO=$INSTALL_AUTO
  fetch_repo_module "$module"
}

parse_apply_modules() {
  requested_modules="$1"
  old_ifs=$IFS
  IFS=,
  if [ -z "$requested_modules" ]; then
    APPLY_MODULES=""
    IFS=$old_ifs
    return 0
  fi

  APPLY_MODULES=""

  for module in $requested_modules; do
    case " $MODULES " in
      *" $module "*) ;;
      *)
        IFS=$old_ifs
        echo "unknown module: $module" >&2
        return 1
        ;;
    esac

    if [ -z "$APPLY_MODULES" ]; then
      APPLY_MODULES="$module"
    else
      APPLY_MODULES="$APPLY_MODULES $module"
    fi
  done
  IFS=$old_ifs
}

parse_apply_options() {
  APPLY_AUTO=0
  APPLY_MODULES_FILTER=""
  for arg in "$@"; do
    case "$arg" in
      -y|--yes)
        APPLY_AUTO=1
        ;;
      --modules=*)
        APPLY_MODULES_FILTER="${arg#--modules=}"
        ;;
      --modules)
        echo "unknown option: --modules (use --modules=<comma-separated> instead)" >&2
        return 2
        ;;
      *)
        echo "unknown option: $arg" >&2
        return 2
        ;;
    esac
  done

  parse_apply_modules "$APPLY_MODULES_FILTER"
}

parse_apply_module_options() {
  APPLY_AUTO=0
  for arg in "$@"; do
    case "$arg" in
      -y|--yes)
        APPLY_AUTO=1
        ;;
      *)
        echo "unknown option: $arg" >&2
        return 2
        ;;
    esac
  done
}

run_single_module_apply() {
  module=$1

  if ! parse_apply_modules "$module"; then
    return 2
  fi

  ui_header "apply module" "$module"
  APPLY_MODULES=$module
  if run_apply_modules; then
    ui_line ""
    ui_line "apply module completed"
    ui_line ""
    ui_success "[OK] $module"
    case "$module" in
      tailscale)
        ui_line ""
        ui_warning "manual steps remaining:"
        ui_line "- sudo tailscale up"
        ;;
      cloudflared)
        ui_line ""
        ui_warning "manual steps remaining:"
        ui_line "- configure cloudflared tunnel"
        ;;
      caddy)
        ui_line ""
        ui_warning "manual steps remaining:"
        ui_line "- configure caddy sites"
        ;;
    esac
    return 0
  fi

  ui_line ""
  ui_line "apply module failed"
  ui_line ""
  ui_failure "[FAIL] $module"
  return 1
}

parse_uninstall_runtime_options() {
  UNINSTALL_AUTO=0
  for arg in "$@"; do
    case "$arg" in
      -y|--yes)
        UNINSTALL_AUTO=1
        ;;
      *)
        echo "unknown option: $arg" >&2
        return 2
        ;;
    esac
  done
}

uninstall_runtime_path() {
  item=$1
  target="$ROOT_DIR/$item"

  case "$target" in
    "$ROOT_DIR/lib" | "$ROOT_DIR/modules" | "$ROOT_DIR/backends")
      ;;
    *)
      echo "unsafe target rejected: $item" >&2
      return 2
      ;;
  esac

  if [ ! -e "$target" ]; then
    ui_line "$item: not present"
    return 0
  fi

  if [ ! -d "$target" ]; then
    echo "unsafe target type for $item: expected directory" >&2
    return 2
  fi

  rm -rf "$target"
  ui_line "removed $item"
}

uninstall_seed_runtime() {
  if is_full_repo_mode; then
    echo "This looks like a full repo or sparse repo-backed checkout." >&2
    echo "Refusing to remove modules/." >&2
    echo "Use --uninstall-runtime only from a generated bootstrap runtime." >&2
    return 2
  fi

  if [ "$UNINSTALL_AUTO" -eq 0 ]; then
    ui_line "This only removes Seed-Kit local runtime files."
    ui_line "It does not uninstall system packages or remove seed-kit.sh."
    ui_line "Targets:"
    ui_line "  lib/"
    ui_line "  modules/"
    ui_line "  backends/"
    ui_prompt "Remove Seed-Kit local runtime? [y/N]:"
    IFS= read -r uninstall_answer || uninstall_answer=

    case "$uninstall_answer" in
      y|Y)
        ;;
      *)
        ui_line "aborted."
        return 0
        ;;
    esac
  else
    ui_line "auto-confirm mode requested"
  fi

  for item in lib modules backends; do
    if ! uninstall_runtime_path "$item"; then
      exit 1
    fi
  done
}

show_apply_preview() {
  ui_header "apply mode preview"
  ui_whisper "minimal actions in V0"
  ui_line "selected modules: $1"
  ui_separator "progress"
  ui_line "[1/4] detect system"
  ui_line "[2/4] prepare plan"
  ui_line "[3/4] confirm safe steps"
  ui_line "[4/4] apply"
}

run_apply_modules() {
  for module in $APPLY_MODULES; do
    case "$module" in
      git)
        apply_module_git
        ;;
      docker)
        ui_line "[docker] not implemented in V0"
        ;;
      tailscale)
        apply_module_tailscale
        ;;
      wifi-stability)
        apply_module_wifi_stability
        ;;
      cloudflared)
        apply_module_cloudflared
        ;;
      caddy)
        apply_module_caddy
        ;;
      homer)
        run_module_apply "$module"
        ;;
      homepage)
        ui_line "[homepage] not implemented in V0"
        ;;
      wifi-kit)
        run_module_apply "$module"
        ;;
      *)
        ui_line "unknown module: $module"
        ;;
    esac
  done
}

show_ui_demo() {
  show_dashboard
}

show_plan() {
  show_dashboard

  if [ "${SEED_RUNTIME_MODE:-}" = "bootstrap" ]; then
    show_bootstrap_plan_summary
    echo
  fi

  ui_section "backend plan"
  backend_plan
  echo

  ui_section "modules"
  for module in $MODULES; do
    ui_line "[$module]"
    run_module_plan "$module" | sed 's/^/  /'
    echo
  done
}

show_menu() {
  while :; do
    show_dashboard
    ui_separator "actions"
    ui_choice_bar
    ui_prompt "choice:"
    IFS= read -r choice || exit 0

    case "$choice" in
      1)
        show_plan
        ui_pause
        ;;
      2)
        ui_header "os detection"
        ui_kv "id" "$SEED_OS_ID"
        ui_kv "name" "$SEED_OS_NAME"
        ui_kv "like" "$SEED_OS_LIKE"
        ui_pause
        ;;
      3)
        ui_header "modules"
        for module in $MODULES; do
          ui_line "$module"
        done
        ui_pause
        ;;
      q|Q)
        exit 0
        ;;
      *)
        ui_line "Unknown choice"
        ui_pause
        ;;
    esac
  done
}

seed_detect_os
load_backend

case "${1:-}" in
  --plan)
    show_plan
    ;;
  --apply)
    shift
    if ! parse_apply_options "$@"; then
      exit 2
    fi
    if [ "$APPLY_AUTO" -eq 1 ]; then
      ui_whisper "auto-confirm mode requested"
    fi
    show_apply_preview "$APPLY_MODULES"
    if [ -z "$APPLY_MODULES" ]; then
      ui_line "no modules selected for apply: use --modules=git"
      exit 0
    fi
    run_apply_modules
    ;;
  --apply-module=*)
    apply_module="${1#--apply-module=}"
    shift
    if ! parse_apply_module_options "$@"; then
      exit 2
    fi
    if [ "$APPLY_AUTO" -eq 1 ]; then
      ui_whisper "auto-confirm mode requested"
    fi
    run_single_module_apply "$apply_module"
    ;;
  --profile=*)
    profile="${1#--profile=}"
    shift
    case "${1:-}" in
      --plan)
        show_profile_plan "$profile"
        ;;
      --apply)
        run_profile_apply "$profile"
        ;;
      *)
        echo "profiles support --plan and limited --apply V1" >&2
        echo "usage: sh seed-kit.sh --profile=<name> --plan" >&2
        echo "       sh seed-kit.sh --profile=<name> --apply" >&2
        exit 2
        ;;
    esac
    ;;
  --fetch-module=*)
    fetch_module="${1#--fetch-module=}"
    shift
    if ! parse_fetch_options "$@"; then
      exit 2
    fi
    fetch_repo_module "$fetch_module"
    ;;
  --install-module=*)
    install_module="${1#--install-module=}"
    shift
    if ! parse_install_options "$@"; then
      exit 2
    fi
    install_repo_module "$install_module"
    ;;
  --self-check)
    show_self_check
    ;;
  --detect)
    ui_header "os detection"
    ui_kv "id" "$SEED_OS_ID"
    ui_kv "name" "$SEED_OS_NAME"
    ui_kv "like" "$SEED_OS_LIKE"
    ;;
  --modules)
    ui_header "modules"
    show_modules_list
    ;;
  --ui-demo)
    show_ui_demo
    ;;
  --uninstall-runtime)
    shift
    if ! parse_uninstall_runtime_options "$@"; then
      exit 2
    fi
    uninstall_seed_runtime
    ;;
  -h|--help)
    seed_kit_usage
    ;;
  "")
    show_menu
    ;;
  *)
    echo "Unknown option: $1" >&2
    seed_kit_usage >&2
    exit 2
    ;;
esac
