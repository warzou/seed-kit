#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RUNTIME_OS="$ROOT_DIR/lib/os.sh"

if [ -z "${NO_COLOR:-}" ] && [ -t 1 ] && [ "${TERM:-}" != "dumb" ]; then
  COLOR_RESET=$(printf '\033[0m')
  COLOR_LABEL=$(printf '\033[1m')
  COLOR_DIM=$(printf '\033[2m')
  COLOR_GOOD=$(printf '\033[32m')
  COLOR_WARN=$(printf '\033[33m')
  COLOR_MUTED=$(printf '\033[37m')
else
  COLOR_RESET=""
  COLOR_LABEL=""
  COLOR_DIM=""
  COLOR_GOOD=""
  COLOR_WARN=""
  COLOR_MUTED=""
fi

ui_line() { printf '%s\n' "$*"; }
ui_header() {
  printf '\n%s%s%s\n' "$COLOR_LABEL" "$1" "$COLOR_RESET"
  if [ -n "${2:-}" ]; then
    printf '%s%s%s\n' "$COLOR_DIM" "$2" "$COLOR_RESET"
  fi
}
ui_section() { printf '\n%s%s%s\n' "$COLOR_LABEL" "$1" "$COLOR_RESET"; }
ui_separator() { ui_line "$1"; }
ui_kv() { printf '  %-12s %s\n' "$1:" "$2"; }
ui_status() { printf '  %-12s %s\n' "$1:" "$2"; }
ui_whisper() { printf '%s%s%s\n' "$COLOR_MUTED" "$*" "$COLOR_RESET"; }
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

if [ ! -f "$RUNTIME_OS" ]; then
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

. "$RUNTIME_OS"
if ! bootstrap_runtime_ready; then
  bootstrap_init_runtime
  . "$RUNTIME_OS"
fi

MODULES="git docker tailscale cloudflared caddy homer homepage wifi-kit"

load_backend() {
  case "$SEED_OS_ID" in
    raspberrypi)
      . "$ROOT_DIR/backends/raspberrypi.sh"
      ;;
    debian)
      . "$ROOT_DIR/backends/debian.sh"
      ;;
    ubuntu)
      . "$ROOT_DIR/backends/debian.sh"
      ;;
    openwrt)
      . "$ROOT_DIR/backends/openwrt.sh"
      ;;
    *)
      case " $SEED_OS_LIKE " in
        *" debian "*)
          . "$ROOT_DIR/backends/debian.sh"
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
  ui_line "[skip] $*"
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
  echo "  --modules        list available modules"
  echo "  --apply [--modules=git,docker] [--yes|-y]  minimal safe apply for supported modules"
  echo "  --fetch-module=wifi-kit [--yes|-y]  fetch one repo-backed module with git sparse checkout"
  echo "  --install-module=wifi-kit [--yes|-y]  prepare git if needed, then fetch one repo-backed module"
  echo "  --detect         show OS detection details"
  echo "  --uninstall-runtime [--yes|-y]  remove local Seed-Kit runtime directories (lib/modules/backends)"
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
      seed-kit.sh \
      modules/wifi-kit \
      modules/wifi-kit.sh \
      docs/ARCHITECTURE.md \
      docs/MODULES.md \
      docs/FRESH-NODE-FLOW.md
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
