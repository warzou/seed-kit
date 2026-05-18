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
ui_report_ok() { printf '%s[OK]%s %s\n' "$COLOR_GOOD" "$COLOR_RESET" "$*"; }
ui_report_warn() { printf '%s[WARN]%s %s\n' "$COLOR_WARN" "$COLOR_RESET" "$*"; }
ui_report_info() { printf '%s[INFO]%s %s\n' "$COLOR_SECTION" "$COLOR_RESET" "$*"; }
ui_report_active() { printf '%s->%s %s\n' "$COLOR_SECTION" "$COLOR_RESET" "$*"; }
ui_prompt() { printf '%s ' "$1"; }
ui_masthead() { ui_header "$1" "$2"; }
ui_focus() { ui_kv "$1" "$2"; [ -n "${3:-}" ] && printf '%s\n' "$3"; }
ui_split_focus() { ui_kv "$1" "$2"; ui_kv "$3" "$4"; ui_line "$5"; ui_line "$6"; ui_line "$7"; }
ui_card_pair() { ui_kv "$1" "$2"; ui_kv "$3" "$4"; ui_kv "$5" "$6"; }
ui_choice_bar() { ui_line "1 plan  2 detect  3 modules  q quit"; }
ui_pause() { :; }

seed_lang() {
  case "${SEED_KIT_LANG:-en}" in
    fr)
      printf '%s\n' "fr"
      ;;
    *)
      printf '%s\n' "en"
      ;;
  esac
}

seed_verbose() {
  case "${SEED_KIT_VERBOSE:-0}" in
    1|yes|true|on)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

seed_msg() {
  key=$1

  if [ "$(seed_lang)" = "fr" ]; then
    case "$key" in
      mode_safe_read_only) printf '%s\n' "SAFE lecture seule" ;;
      mode_safe_install_only) printf '%s\n' "SAFE installation seule" ;;
      mode_safe_guided_copy) printf '%s\n' "SAFE copie guidée" ;;
      apply_guided_title) printf '%s\n' "RAPPORT APPLY-GUIDED" ;;
      step_label) printf '%s\n' "Étape" ;;
      package_label) printf '%s\n' "Package" ;;
      profile_label) printf '%s\n' "Profil" ;;
      mode_label) printf '%s\n' "Mode" ;;
      progress) printf '%s\n' "Progression" ;;
      readiness) printf '%s\n' "État de préparation" ;;
      next_actions) printf '%s\n' "Actions suivantes" ;;
      todo) printf '%s\n' "À faire" ;;
      nothing_changed) printf '%s\n' "Aucun changement effectué" ;;
      details) printf '%s\n' "Détails" ;;
      proposed_future_actions) printf '%s\n' "Actions futures proposées" ;;
      ready) printf '%s\n' "prêt" ;;
      installed_not_ready) printf '%s\n' "installé, pas prêt" ;;
      not_installed) printf '%s\n' "non installé" ;;
      not_ready) printf '%s\n' "pas prêt" ;;
      to_connect) printf '%s\n' "à connecter" ;;
      to_configure) printf '%s\n' "à configurer" ;;
      ready_plural) printf '%s\n' "prêts" ;;
      connected) printf '%s\n' "connecté" ;;
      installed_not_connected) printf '%s\n' "installé, non connecté" ;;
      configured) printf '%s\n' "configuré" ;;
      installed_not_configured) printf '%s\n' "installé, non configuré" ;;
      deployed_validated) printf '%s\n' "déployés et validés" ;;
      deployed_validation_needed) printf '%s\n' "déployés, validation requise" ;;
      not_deployed) printf '%s\n' "non déployés" ;;
      none) printf '%s\n' "aucune" ;;
      no_change_summary) printf '%s\n' "Aucun tailscale up, login cloudflared, compose up/pull, démarrage service, reload/restart Caddy, secret, DNS/cutover, reboot, restart réseau ou copie fichier n'a été tenté." ;;
      no_restore) printf '%s\n' "Aucun restore n'a été tenté." ;;
      no_service_start) printf '%s\n' "Aucun service n'a été démarré." ;;
      no_secret_copy) printf '%s\n' "Aucun secret n'a été copié." ;;
      no_dns_cutover) printf '%s\n' "Aucun DNS/cutover n'a été tenté." ;;
      no_reboot_network) printf '%s\n' "Aucun reboot ou restart réseau n'a été tenté." ;;
      package_apply_disabled) printf '%s\n' "Package apply reste désactivé en V1." ;;
      future_install_system) printf '%s\n' "- installer les paquets système manquants" ;;
      future_review_configs) printf '%s\n' "- relire services/configs" ;;
      future_reconnect_identity) printf '%s\n' "- reconnecter %s manuellement" ;;
      future_reconnect_identities) printf '%s\n' "- reconnecter les identités manuellement" ;;
      future_validate_services) printf '%s\n' "- valider les services déclarés" ;;
      future_validate_configs) printf '%s\n' "- valider compose/configs" ;;
      future_optional_start) printf '%s\n' "- démarrage manuel optionnel des services" ;;
      details_docker_service_active) printf '%s\n' "  service actif: %s" ;;
      details_ready) printf '%s\n' "  prêt: %s" ;;
      details_tailscale_not_connected) printf '%s\n' "  Ce noeud n'est pas encore connecté à votre tailnet." ;;
      details_tailscale_auth) printf '%s\n' "  La prochaine étape ouvrira une URL d'authentification dans le navigateur." ;;
      details_tailscale_expected) printf '%s\n' "  Résultat attendu: le noeud apparaît dans votre tailnet et tailscale ip retourne une IP." ;;
      details_cloudflared_missing) printf '%s\n' "  Credentials/tunnel ne sont pas encore configurés." ;;
      details_cloudflared_expected) printf '%s\n' "  Résultat attendu: credentials de tunnel et configuration sont détectés." ;;
      details_deploy_root) printf '%s\n' "  racine deploy: %s" ;;
      details_deployed) printf '%s\n' "  déployé: %s" ;;
      details_validated) printf '%s\n' "  validé: %s" ;;
      *)
        printf '%s\n' "$key"
        ;;
    esac
    return 0
  fi

  case "$key" in
    mode_safe_read_only) printf '%s\n' "SAFE read-only" ;;
    mode_safe_install_only) printf '%s\n' "SAFE install-only" ;;
    mode_safe_guided_copy) printf '%s\n' "SAFE guided copy" ;;
    apply_guided_title) printf '%s\n' "PACKAGE APPLY GUIDED" ;;
    step_label) printf '%s\n' "Step" ;;
    package_label) printf '%s\n' "Package" ;;
    profile_label) printf '%s\n' "Profile" ;;
    mode_label) printf '%s\n' "Mode" ;;
    progress) printf '%s\n' "Progress" ;;
    readiness) printf '%s\n' "Readiness" ;;
    next_actions) printf '%s\n' "Next actions" ;;
    todo) printf '%s\n' "To do" ;;
    nothing_changed) printf '%s\n' "Nothing was changed" ;;
    details) printf '%s\n' "Details" ;;
    proposed_future_actions) printf '%s\n' "Proposed future actions" ;;
    ready) printf '%s\n' "ready" ;;
    installed_not_ready) printf '%s\n' "installed, not ready" ;;
    not_installed) printf '%s\n' "not installed" ;;
    not_ready) printf '%s\n' "not ready" ;;
    to_connect) printf '%s\n' "connect" ;;
    to_configure) printf '%s\n' "configure" ;;
    ready_plural) printf '%s\n' "ready" ;;
    connected) printf '%s\n' "connected" ;;
    installed_not_connected) printf '%s\n' "installed, not connected" ;;
    configured) printf '%s\n' "configured" ;;
    installed_not_configured) printf '%s\n' "installed, not configured" ;;
    deployed_validated) printf '%s\n' "deployed + validated" ;;
    deployed_validation_needed) printf '%s\n' "deployed, validation needed" ;;
    not_deployed) printf '%s\n' "not deployed" ;;
    none) printf '%s\n' "none" ;;
    no_change_summary) printf '%s\n' "No tailscale up, cloudflared login, compose up/pull, service start, Caddy reload/restart, secrets, DNS/cutover, reboot, network restart, or file copy was attempted." ;;
    no_restore) printf '%s\n' "No restore was attempted." ;;
    no_service_start) printf '%s\n' "No service was started." ;;
    no_secret_copy) printf '%s\n' "No secret was copied." ;;
    no_dns_cutover) printf '%s\n' "No DNS/cutover was attempted." ;;
    no_reboot_network) printf '%s\n' "No reboot or network restart was attempted." ;;
    package_apply_disabled) printf '%s\n' "Package apply remains disabled in V1." ;;
    future_install_system) printf '%s\n' "- install missing system packages" ;;
    future_review_configs) printf '%s\n' "- review services/configs" ;;
    future_reconnect_identity) printf '%s\n' "- reconnect %s manually" ;;
    future_reconnect_identities) printf '%s\n' "- reconnect identities manually" ;;
    future_validate_services) printf '%s\n' "- validate declared services" ;;
    future_validate_configs) printf '%s\n' "- validate compose/configs" ;;
    future_optional_start) printf '%s\n' "- optional manual service start" ;;
    details_docker_service_active) printf '%s\n' "  service active: %s" ;;
    details_ready) printf '%s\n' "  ready: %s" ;;
    details_tailscale_not_connected) printf '%s\n' "  This node is not connected to your tailnet yet." ;;
    details_tailscale_auth) printf '%s\n' "  The next step will open a browser authentication URL." ;;
    details_tailscale_expected) printf '%s\n' "  Expected result: node appears in your tailnet and tailscale ip returns an IP." ;;
    details_cloudflared_missing) printf '%s\n' "  Credentials/tunnel are not configured yet." ;;
    details_cloudflared_expected) printf '%s\n' "  Expected result: tunnel credentials and configuration are detected." ;;
    details_deploy_root) printf '%s\n' "  deploy root: %s" ;;
    details_deployed) printf '%s\n' "  deployed: %s" ;;
    details_validated) printf '%s\n' "  validated: %s" ;;
    *)
      printf '%s\n' "$key"
      ;;
  esac
}

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

fresh_bootstrap_usage() {
  echo "Seed-Kit fresh-node bootstrap"
  echo
  echo "Fresh-node:"
  echo "  wget https://raw.githubusercontent.com/warzou/seed-kit/main/seed-kit.sh"
  echo "  sh seed-kit.sh [--yes] [--target <dir>]"
  echo
  echo "Usage:"
  echo "  sh seed-kit.sh [--yes] [--target <dir>]"
  echo "  sh seed-kit.sh --help"
  echo
  echo "What it does:"
  echo "  - installs git with apt if git is missing"
  echo "  - clones Seed-Kit to ~/seed-kit if absent"
  echo "  - updates Seed-Kit with git fetch + git pull --ff-only if present"
  echo
  echo "Scope:"
  echo "  - Raspberry Pi OS / Debian apt only for V1"
  echo "  - no Docker"
  echo "  - no Tailscale"
  echo "  - no Cloudflare"
  echo "  - no restore"
  echo "  - no secrets"
  echo "  - no cloud sync"
  echo "  - no orchestration"
}

fresh_bootstrap_confirm_git_install() {
  if [ "$FRESH_BOOTSTRAP_YES" = "yes" ]; then
    return 0
  fi

  echo "git is missing."
  echo "Seed-Kit can install git with:"
  echo "  sudo apt update"
  echo "  sudo apt install -y git"
  printf "Continue? [y/N] "
  IFS= read -r answer || answer=
  case "$answer" in
    y|Y|yes|YES)
      return 0
      ;;
    *)
      echo "aborted: git is required"
      return 1
      ;;
  esac
}

fresh_bootstrap_install_git_if_missing() {
  if command -v git >/dev/null 2>&1; then
    echo "git: present"
    return 0
  fi

  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required to install git" >&2
    return 2
  fi

  if ! command -v apt >/dev/null 2>&1; then
    echo "apt is required to install git in Seed-Kit V1 bootstrap" >&2
    return 2
  fi

  fresh_bootstrap_confirm_git_install
  echo "running: sudo apt update"
  sudo apt update
  echo "running: sudo apt install -y git"
  sudo apt install -y git
}

fresh_bootstrap_clone_or_update() {
  if [ -d "$FRESH_BOOTSTRAP_TARGET/.git" ]; then
    echo "Seed-Kit repo: $FRESH_BOOTSTRAP_TARGET"
    (
      cd "$FRESH_BOOTSTRAP_TARGET"
      git fetch origin
      git pull --ff-only
    )
    return 0
  fi

  if [ -e "$FRESH_BOOTSTRAP_TARGET" ]; then
    echo "target exists but is not a git checkout: $FRESH_BOOTSTRAP_TARGET" >&2
    return 2
  fi

  echo "cloning Seed-Kit to: $FRESH_BOOTSTRAP_TARGET"
  git clone "https://github.com/warzou/seed-kit.git" "$FRESH_BOOTSTRAP_TARGET"
}

fresh_bootstrap_main() {
  FRESH_BOOTSTRAP_TARGET="$HOME/seed-kit"
  FRESH_BOOTSTRAP_YES="no"

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --yes|-y)
        FRESH_BOOTSTRAP_YES="yes"
        shift
        ;;
      --target)
        FRESH_BOOTSTRAP_TARGET="${2:-}"
        if [ -z "$FRESH_BOOTSTRAP_TARGET" ]; then
          echo "missing value for --target" >&2
          exit 2
        fi
        shift 2
        ;;
      --help|-h|help)
        fresh_bootstrap_usage
        exit 0
        ;;
      *)
        echo "unknown option: $1" >&2
        fresh_bootstrap_usage >&2
        exit 2
        ;;
    esac
  done

  fresh_bootstrap_install_git_if_missing
  fresh_bootstrap_clone_or_update

  echo
  echo "Seed-Kit is ready."
  echo "Next commands:"
  echo "  cd $FRESH_BOOTSTRAP_TARGET"
  echo "  sh seed-kit.sh doctor"
  echo "  sh seed-kit.sh inspect"
  echo "  sh seed-kit.sh --modules"
}

if [ ! -f "$RUNTIME_OS" ] && ! is_full_repo_mode; then
  fresh_bootstrap_main "$@"
  exit $?
fi

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
    debian|ubuntu|raspberrypi|raspbian)
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

ui_rule() {
  ui_line "========================================"
}

ui_phase() {
  ui_rule
  ui_line "$1"
  ui_rule
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
  if [ "${APPLY_CONFIRMED:-0}" -eq 1 ] || [ "${APPLY_AUTO:-0}" -eq 1 ]; then
    return 0
  fi

  ui_rule
  ui_line "SAFE APPLY CONFIRMATION"
  ui_line "Target: ${APPLY_CONFIRM_TARGET:-modules=$APPLY_MODULES}"
  ui_line "Will:"
  ui_line "  - run only explicitly selected Seed-Kit apply steps"
  ui_line "  - show package manager and system command output"
  ui_line "Will NOT:"
  ui_line "  - start application containers"
  ui_line "  - write secrets"
  ui_line "  - restore a full machine"
  ui_line "  - reboot or restart networking"
  ui_rule
  ui_prompt "Continue? [y/N]:"
  IFS= read -r answer || return 1
  case "$answer" in
    y|Y)
      APPLY_CONFIRMED=1
      return 0
      ;;
    *)
      echo "[apply] aborted by user"
      return 2
      ;;
  esac
}

apply_note_module() {
  module=$1
  case " ${APPLY_DONE_MODULES:-} " in
    *" $module "*) return 0 ;;
  esac
  if [ -z "${APPLY_DONE_MODULES:-}" ]; then
    APPLY_DONE_MODULES="$module"
  else
    APPLY_DONE_MODULES="$APPLY_DONE_MODULES $module"
  fi
}

apply_note_manual_step() {
  step=$1
  case "${APPLY_MANUAL_STEPS:-}" in
    *"$step"*) return 0 ;;
  esac
  APPLY_MANUAL_STEPS="${APPLY_MANUAL_STEPS:-}${step}
"
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
  ui_phase "MODULE START: git"
  apply_step "git: checking installation"
  if module_is_installed git; then
    apply_skip "git already installed"
    apply_note_module git
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

  ui_phase "VERIFY: git"
  apply_step "git: verifying installation"
  if module_is_installed git; then
    apply_step "git: installed"
    apply_note_module git
    return 0
  fi

  echo "[git] post-install check failed: binary not found" >&2
  return 6
}

docker_repo_family() {
  docker_arch=$1
  docker_codename=$2

  case "$SEED_OS_ID" in
    raspberrypi|raspbian)
      case "$docker_arch" in
        arm64)
          echo "debian"
          ;;
        armhf)
          case "$docker_codename" in
            bookworm|bullseye)
              echo "raspbian"
              ;;
            *)
              echo ""
              ;;
          esac
          ;;
        *)
          echo "debian"
          ;;
      esac
      return 0
      ;;
  esac

  echo "debian"
}

docker_repo_codename() {
  if [ -r /etc/os-release ]; then
    (
      . /etc/os-release
      printf '%s\n' "${VERSION_CODENAME:-}"
    )
    return 0
  fi

  echo ""
}

apply_module_docker() {
  ui_phase "MODULE START: docker"
  apply_step "docker: checking installation"
  if module_is_installed docker; then
    apply_skip "docker already installed"
    docker --version || true
    if docker compose version >/dev/null 2>&1; then
      docker compose version
    else
      ui_line "docker compose plugin: unavailable"
    fi
    if command -v systemctl >/dev/null 2>&1; then
      systemctl is-active docker || true
    fi
    ui_line "Optional manual step: add your user to the docker group only if you choose passwordless docker."
    apply_note_module docker
    apply_note_manual_step "  - add your user to the docker group only if you choose passwordless docker"
    return 0
  fi

  if ! is_debian_like; then
    echo "[docker] unsupported OS for apply: $SEED_OS_NAME" >&2
    return 2
  fi

  if ! apply_safe_confirm; then
    return 2
  fi

  if ! require_network_for_apply "docker package install"; then
    return 2
  fi

  if ! require_sudo_for_system_action "docker package install" "sh seed-kit.sh --apply --modules=docker"; then
    return 2
  fi

  docker_codename=$(docker_repo_codename)
  if [ -z "$docker_codename" ]; then
    echo "[docker] unable to detect VERSION_CODENAME from /etc/os-release" >&2
    return 2
  fi
  docker_arch=$(dpkg --print-architecture)
  docker_family=$(docker_repo_family "$docker_arch" "$docker_codename")
  if [ -z "$docker_family" ]; then
    echo "[docker] unsupported Raspberry Pi OS Docker apt repository for $docker_arch/$docker_codename" >&2
    echo "[docker] official Docker docs support Raspberry Pi OS 32-bit for bookworm/bullseye; use Raspberry Pi OS 64-bit arm64 with the Debian repository for trixie." >&2
    return 2
  fi

  if [ "$(id -u)" -eq 0 ]; then
    SUDO=
  else
    SUDO=sudo
  fi

  docker_repo_url="https://download.docker.com/linux/$docker_family"
  docker_key_tmp="${TMPDIR:-/tmp}/seed-kit-docker-keyring.$$"
  docker_list_tmp="${TMPDIR:-/tmp}/seed-kit-docker-list.$$"

  apply_step "docker: install apt prerequisites"
  if ! $SUDO apt-get update; then
    echo "[docker] apt-get update failed" >&2
    return 4
  fi
  if ! $SUDO apt-get install -y ca-certificates curl; then
    echo "[docker] prerequisite install failed" >&2
    return 5
  fi

  apply_step "docker: download official apt key"
  if ! curl -fsSL "$docker_repo_url/gpg" -o "$docker_key_tmp"; then
    rm -f "$docker_key_tmp" "$docker_list_tmp"
    echo "[docker] failed to download apt key: $docker_repo_url/gpg" >&2
    return 6
  fi
  if ! chmod 0644 "$docker_key_tmp"; then
    rm -f "$docker_key_tmp" "$docker_list_tmp"
    echo "[docker] failed to prepare apt key permissions" >&2
    return 7
  fi

  apply_step "docker: prepare official apt source"
  {
    printf '%s\n' "Types: deb"
    printf '%s\n' "URIs: $docker_repo_url"
    printf '%s\n' "Suites: $docker_codename"
    printf '%s\n' "Components: stable"
    printf '%s\n' "Architectures: $docker_arch"
    printf '%s\n' "Signed-By: /etc/apt/keyrings/docker.asc"
  } > "$docker_list_tmp"

  apply_step "docker: configure apt source"
  if ! $SUDO install -m 0755 -d /etc/apt/keyrings; then
    rm -f "$docker_key_tmp" "$docker_list_tmp"
    echo "[docker] failed to create keyring directory" >&2
    return 8
  fi
  if ! $SUDO cp "$docker_key_tmp" /etc/apt/keyrings/docker.asc; then
    rm -f "$docker_key_tmp" "$docker_list_tmp"
    echo "[docker] failed to install apt key" >&2
    return 9
  fi
  if ! $SUDO cp "$docker_list_tmp" /etc/apt/sources.list.d/docker.sources; then
    rm -f "$docker_key_tmp" "$docker_list_tmp"
    echo "[docker] failed to install apt source" >&2
    return 10
  fi
  rm -f "$docker_key_tmp" "$docker_list_tmp"

  apply_step "docker: install packages"
  if ! $SUDO apt-get update; then
    echo "[docker] apt-get update failed after adding repository" >&2
    return 11
  fi
  if ! $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
    echo "[docker] apt-get install docker packages failed" >&2
    return 12
  fi

  ui_phase "VERIFY: docker"
  apply_step "docker: verifying installation"
  if ! module_is_installed docker; then
    echo "[docker] post-install check failed: binary not found" >&2
    return 13
  fi

  docker --version || true
  if docker compose version >/dev/null 2>&1; then
    docker compose version
  else
    ui_line "docker compose plugin: unavailable"
  fi
  if command -v systemctl >/dev/null 2>&1; then
    systemctl is-active docker || true
  fi
  ui_line "No containers or compose stacks were started."
  ui_line "Optional manual step: add your user to the docker group only if you choose passwordless docker."
  apply_note_module docker
  apply_note_manual_step "  - add your user to the docker group only if you choose passwordless docker"
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
  ui_phase "MODULE START: tailscale"
  apply_step "tailscale: checking installation"
  if module_is_installed tailscale; then
    apply_skip "tailscale already installed"
    ui_line "Next manual step: sudo tailscale up"
    apply_note_module tailscale
    apply_note_manual_step "  - sudo tailscale up"
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

  ui_phase "VERIFY: tailscale"
  apply_step "tailscale: verifying installation"
  if module_is_installed tailscale; then
    apply_step "tailscale: installed"
    ui_line "Next manual step: sudo tailscale up"
    apply_note_module tailscale
    apply_note_manual_step "  - sudo tailscale up"
    return 0
  fi

  echo "[tailscale] post-install check failed: binary not found" >&2
  return 13
}

apply_module_cloudflared() {
  ui_phase "MODULE START: cloudflared"
  apply_step "cloudflared: checking installation"
  if module_is_installed cloudflared; then
    apply_skip "cloudflared already installed"
    ui_line "Next manual step: cloudflared tunnel login/create/configure outside Seed-Kit"
    apply_note_module cloudflared
    apply_note_manual_step "  - cloudflared tunnel login/create/configure outside Seed-Kit"
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

  ui_phase "VERIFY: cloudflared"
  apply_step "cloudflared: verifying installation"
  if module_is_installed cloudflared; then
    apply_step "cloudflared: installed"
    ui_line "Next manual step: cloudflared tunnel login/create/configure outside Seed-Kit"
    apply_note_module cloudflared
    apply_note_manual_step "  - cloudflared tunnel login/create/configure outside Seed-Kit"
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

show_modules_dir_list() {
  ui_line "Available modules:"
  found=0

  for module_file in "$ROOT_DIR"/modules/*.sh; do
    [ -f "$module_file" ] || continue
    module_name=${module_file##*/}
    module_name=${module_name%.sh}
    case "$module_name" in
      wifi-kit)
        continue
        ;;
    esac
    ui_line "  $module_name"
    found=1
  done

  if [ "$found" -eq 0 ]; then
    ui_line "  none"
  fi
}

show_module_dependencies() {
  module=$1
  module_file="$ROOT_DIR/modules/$module.sh"
  dependency_base="$(printf '%s' "$module" | tr '-' '_')"
  dependency_fn="module_${dependency_base}_dependencies"

  case " $MODULES " in
    *" $module "*) ;;
    *)
      echo "unknown module: $module" >&2
      return 2
      ;;
  esac

  if [ ! -f "$module_file" ]; then
    echo "missing module file: $module_file" >&2
    return 2
  fi

  . "$module_file"

  ui_header "module dependencies" "$module"
  if command -v "$dependency_fn" >/dev/null 2>&1; then
    "$dependency_fn"
  else
    ui_line "no dependency declaration"
  fi
}

seed_kit_usage() {
  echo "Usage: sh seed-kit.sh [--plan|--detect|--ui-demo|--modules|--apply]"
  echo ""
  echo "Fresh-node bootstrap:"
  echo "  wget https://raw.githubusercontent.com/warzou/seed-kit/main/seed-kit.sh"
  echo "  sh seed-kit.sh [--yes] [--target <dir>]"
  echo "  installs git when needed, then clones/updates Seed-Kit"
  echo ""
  echo "Commands:"
  echo "  --plan [--modules=git,docker]  show the execution plan"
  echo "  --plan --package <file>  preview package-driven PRA design only"
  echo "  --profile=<name> --plan  show recommended modules for one profile"
  echo "  --profile=<name> --apply  preview profile apply order without running modules"
  echo "  --modules        list available modules"
  echo "  modules list     list module scripts available in modules/"
  echo "  modules deps <module>  show read-only module dependency declaration"
  echo "  package verify <file>  verify package archive, manifest, checksums, and exclusions"
  echo "  package stage <file>   verify and extract package to /tmp for manual inspection"
  echo "  package inspect-stage <dir>  inspect staged package without applying it"
  echo "  package apply-guided <file> [--step install-modules|review-configs|validate-services|deploy-configs|validate-deployed|suggest-start|readiness]  guided SAFE package assistant"
  echo "  --apply [--modules=git,docker] [--yes|-y]  minimal safe apply for supported modules"
  echo "  --apply --package <file> [--components=a,b]  preview package apply only"
  echo "  --apply-module=<module> [--yes|-y]  apply one module only"
  echo "  --fetch-module=wifi-kit [--yes|-y]  fetch one repo-backed module with git sparse checkout"
  echo "  --install-module=wifi-kit [--yes|-y]  prepare git if needed, then fetch one repo-backed module"
  echo "  --self-check     compare local Seed-Kit with public repository HEAD when git is available"
  echo "  doctor           show a short read-only Seed-Kit diagnostic"
  echo "  inspect          show a short read-only reconstruction-oriented report"
  echo "  self-update --plan   inspect origin/main update status without changing files"
  echo "  self-update --apply  update current branch with git pull --ff-only"
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

show_doctor() {
  echo "Seed-Kit doctor"
  echo "mode: read-only"
  echo
  echo "shell: OK"
  echo "git: $(command_status git)"
  echo "tar: $(command_status tar)"
  echo "sha256sum: $(command_status sha256sum)"

  if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "repo: git checkout"
    if workspace_state=$(git status --porcelain 2>/dev/null); then
      if [ -z "$workspace_state" ]; then
        echo "workspace: clean"
      else
        echo "workspace: dirty"
      fi
    else
      echo "workspace: unknown"
    fi
  else
    echo "repo: not git checkout"
    echo "workspace: unknown"
  fi

  echo "self-update: available"
  if [ -f "$ROOT_DIR/tools/profile-state.sh" ]; then
    echo "profile-state: available"
  else
    echo "profile-state: missing"
  fi
  echo
  echo "No changes were made."
}

show_inspect() {
  echo "Seed-Kit inspect"
  echo "mode: read-only"
  echo
  echo "system:"
  echo "  hostname: $(machine_hostname)"
  echo "  os: ${SEED_OS_ID:-unknown}"
  echo "  arch: $(machine_arch)"
  echo
  echo "runtime:"
  echo "  git: $(command_status git)"
  echo "  docker: $(command_status docker)"
  echo "  tailscale: $(command_status tailscale)"
  echo "  cloudflared: $(command_status cloudflared)"
  echo "  caddy: $(command_status caddy)"
  echo
  echo "seed-kit:"
  if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "  repo: git checkout"
    if workspace_state=$(git status --porcelain 2>/dev/null); then
      if [ -z "$workspace_state" ]; then
        echo "  workspace: clean"
      else
        echo "  workspace: dirty"
      fi
    else
      echo "  workspace: unknown"
    fi
  else
    echo "  repo: not git checkout"
    echo "  workspace: unknown"
  fi
  if [ -f "$ROOT_DIR/tools/profile-state.sh" ]; then
    echo "  profile-state: available"
  else
    echo "  profile-state: missing"
  fi
  echo
  echo "manual reconstruction required:"
  echo "  - tailscale login/state"
  echo "  - cloudflare authentication"
  echo "  - ssh trust validation"
  echo "  - hostname review"
  echo
  echo "not copied automatically:"
  echo "  - machine-id"
  echo "  - ssh host keys"
  echo "  - tailscale state"
  echo "  - cloudflare credentials"
  echo "  - tokens/api keys"
  echo
  echo "No changes were made."
}

self_update_require_git_repo() {
  if ! command -v git >/dev/null 2>&1; then
    echo "git is required for self-update." >&2
    return 2
  fi

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "self-update requires a git checkout." >&2
    return 2
  fi

  if ! git remote get-url origin >/dev/null 2>&1; then
    echo "self-update requires remote origin." >&2
    return 2
  fi

  return 0
}

self_update_branch() {
  git symbolic-ref --quiet --short HEAD 2>/dev/null || return 1
}

self_update_fetch_origin() {
  ui_line "[self-update] fetch origin"
  git fetch origin
}

self_update_state() {
  branch=$1
  remote_ref="origin/$branch"

  if ! git rev-parse --verify "$remote_ref" >/dev/null 2>&1; then
    echo "unknown"
    return 0
  fi

  counts=$(git rev-list --left-right --count "HEAD...$remote_ref" 2>/dev/null || echo "unknown")
  case "$counts" in
    "0	0"|"0 0")
      echo "up-to-date"
      ;;
    0*)
      echo "behind"
      ;;
    *"	0"|*" 0")
      echo "ahead"
      ;;
    *)
      echo "diverged"
      ;;
  esac
}

show_self_update_plan() {
  if ! self_update_require_git_repo; then
    return 2
  fi

  branch=$(self_update_branch || true)
  if [ -z "$branch" ]; then
    echo "self-update requires a named branch." >&2
    return 2
  fi

  local_short=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

  ui_header "Seed-Kit self-update plan"
  ui_kv "Branch" "$branch"
  ui_kv "Local" "$local_short"
  ui_kv "Remote" "origin/$branch"

  if ! self_update_fetch_origin; then
    echo "self-update fetch failed." >&2
    return 3
  fi

  if remote_short=$(git rev-parse --short "origin/$branch" 2>/dev/null); then
    ui_kv "Remote commit" "$remote_short"
  else
    ui_kv "Remote commit" "unavailable"
  fi

  ui_kv "State" "$(self_update_state "$branch")"
  ui_line "Plan mode only: no pull, checkout, stash, reset, or clean."
}

apply_self_update() {
  if ! self_update_require_git_repo; then
    return 2
  fi

  branch=$(self_update_branch || true)
  if [ -z "$branch" ]; then
    echo "self-update requires a named branch." >&2
    return 2
  fi

  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    echo "self-update refused: workspace has local changes." >&2
    return 2
  fi

  if ! self_update_fetch_origin; then
    echo "self-update fetch failed." >&2
    return 3
  fi

  state=$(self_update_state "$branch")
  case "$state" in
    up-to-date)
      ui_line "already up-to-date"
      return 0
      ;;
    behind)
      if git pull --ff-only; then
        ui_line "update applied"
        return 0
      fi
      echo "self-update failed: git pull --ff-only failed." >&2
      return 4
      ;;
    ahead)
      echo "self-update refused: local branch is ahead of origin/$branch." >&2
      return 2
      ;;
    diverged)
      echo "self-update refused: branch has diverged from origin/$branch." >&2
      return 2
      ;;
    *)
      echo "self-update refused: unable to compare with origin/$branch." >&2
      return 2
      ;;
  esac
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
    rpi3-edge-node|minimal-resilient-node|rpi-edge-replacement)
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
    echo "known profiles: rpi0-pocket rpi0-pocket-node rpi3-edge rpi3-edge-node minimal-resilient-node edge-services-node rpi-edge-replacement" >&2
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
    echo "known profiles: rpi0-pocket rpi0-pocket-node rpi3-edge rpi3-edge-node minimal-resilient-node edge-services-node rpi-edge-replacement" >&2
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
  APPLY_PACKAGE_FILE=""
  APPLY_COMPONENTS_FILTER=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -y|--yes)
        APPLY_AUTO=1
        shift
        ;;
      --modules=*)
        APPLY_MODULES_FILTER="${1#--modules=}"
        shift
        ;;
      --package=*)
        APPLY_PACKAGE_FILE="${1#--package=}"
        shift
        ;;
      --components=*)
        APPLY_COMPONENTS_FILTER="${1#--components=}"
        shift
        ;;
      --modules)
        echo "unknown option: --modules (use --modules=<comma-separated> instead)" >&2
        return 2
        ;;
      --package)
        APPLY_PACKAGE_FILE="${2:-}"
        if [ -z "$APPLY_PACKAGE_FILE" ]; then
          echo "missing value for --package" >&2
          return 2
        fi
        shift 2
        ;;
      --components)
        APPLY_COMPONENTS_FILTER="${2:-}"
        if [ -z "$APPLY_COMPONENTS_FILTER" ]; then
          echo "missing value for --components" >&2
          return 2
        fi
        shift 2
        ;;
      *)
        echo "unknown option: $1" >&2
        return 2
        ;;
    esac
  done

  if [ -n "$APPLY_PACKAGE_FILE" ] && [ -n "$APPLY_MODULES_FILTER" ]; then
    echo "use either --package or --modules, not both" >&2
    return 2
  fi

  if [ -n "$APPLY_COMPONENTS_FILTER" ] && [ -z "$APPLY_PACKAGE_FILE" ]; then
    echo "--components requires --package=<file>" >&2
    return 2
  fi

  parse_apply_modules "$APPLY_MODULES_FILTER"
}

parse_plan_options() {
  PLAN_MODULES_FILTER=""
  PLAN_PACKAGE_FILE=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --modules=*)
        PLAN_MODULES_FILTER="${1#--modules=}"
        shift
        ;;
      --package=*)
        PLAN_PACKAGE_FILE="${1#--package=}"
        shift
        ;;
      --modules)
        echo "unknown option: --modules (use --modules=<comma-separated> instead)" >&2
        return 2
        ;;
      --package)
        PLAN_PACKAGE_FILE="${2:-}"
        if [ -z "$PLAN_PACKAGE_FILE" ]; then
          echo "missing value for --package" >&2
          return 2
        fi
        shift 2
        ;;
      *)
        echo "unknown option: $1" >&2
        return 2
        ;;
    esac
  done

  if [ -n "$PLAN_PACKAGE_FILE" ] && [ -n "$PLAN_MODULES_FILTER" ]; then
    echo "use either --package or --modules, not both" >&2
    return 2
  fi

  if [ -n "$PLAN_PACKAGE_FILE" ]; then
    PLAN_MODULES=""
    return 0
  fi

  if [ -z "$PLAN_MODULES_FILTER" ]; then
    PLAN_MODULES="$MODULES"
    return 0
  fi

  if ! parse_apply_modules "$PLAN_MODULES_FILTER"; then
    return 2
  fi
  PLAN_MODULES="$APPLY_MODULES"
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

find_package_entry() {
  entries=$1
  wanted=$2

  old_ifs=$IFS
  IFS='
'

  for entry in $entries; do
    case "$entry" in
      "$wanted"|*/"$wanted")
        printf '%s\n' "$entry"
        IFS=$old_ifs
        return 0
        ;;
    esac
  done

  IFS=$old_ifs
  return 1
}

strip_package_value_quotes() {
  value=$1

  case "$value" in
    \"*\")
      value=${value#\"}
      value=${value%\"}
      ;;
    \'*\')
      value=${value#\'}
      value=${value%\'}
      ;;
  esac

  printf '%s\n' "$value"
}

package_descriptor_value() {
  content=$1
  key=$2

  line=$(printf '%s\n' "$content" | sed -n "s/^$key=//p" | sed -n '1p')
  [ -n "$line" ] || return 0
  strip_package_value_quotes "$line"
}

package_descriptor_list_value() {
  content=$1
  key=$2

  value=$(package_descriptor_value "$content" "$key")
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
    return 0
  fi

  printf '%s\n' "$content" | awk -v key="$key" '
    $0 == key "=\"" { in_block = 1; next }
    in_block && $0 == "\"" { exit }
    in_block { print }
  ' | sed '/^[[:space:]]*$/d'
}

package_print_list() {
  label=$1
  values=$2

  if [ -n "$values" ]; then
    ui_line "$label"
    for value in $values; do
      ui_line "  - $value"
    done
  else
    ui_line "$label none"
  fi
}

read_package_metadata() {
  package_file=$1
  package_entries=$2

  PACKAGE_METADATA_STATUS="unavailable"
  PACKAGE_METADATA_PACKAGE_ID=""
  PACKAGE_METADATA_PROFILE_ID=""
  PACKAGE_METADATA_COMPONENTS=""
  PACKAGE_METADATA_SYSTEM=""
  PACKAGE_METADATA_MODULES=""
  PACKAGE_METADATA_SERVICES=""
  PACKAGE_METADATA_MANUAL_IDENTITIES=""
  PACKAGE_METADATA_SECRETS_POLICY=""

  [ -n "$package_entries" ] || return 0
  command -v tar >/dev/null 2>&1 || return 0

  descriptor_path=$(find_package_entry "$package_entries" "seed-kit-package.sh" || true)
  if [ -z "$descriptor_path" ]; then
    PACKAGE_METADATA_STATUS="missing"
    return 0
  fi

  if ! descriptor_content=$(tar -xOzf "$package_file" "$descriptor_path" 2>/dev/null); then
    PACKAGE_METADATA_STATUS="unreadable"
    return 0
  fi

  PACKAGE_METADATA_PACKAGE_ID=$(package_descriptor_value "$descriptor_content" "PACKAGE_ID")
  PACKAGE_METADATA_PROFILE_ID=$(package_descriptor_value "$descriptor_content" "PROFILE_ID")
  PACKAGE_METADATA_COMPONENTS=$(package_descriptor_list_value "$descriptor_content" "COMPONENTS")
  PACKAGE_METADATA_SYSTEM=$(package_descriptor_list_value "$descriptor_content" "SYSTEM")
  PACKAGE_METADATA_MODULES=$(package_descriptor_list_value "$descriptor_content" "MODULES")
  PACKAGE_METADATA_SERVICES=$(package_descriptor_list_value "$descriptor_content" "SERVICES")
  PACKAGE_METADATA_MANUAL_IDENTITIES=$(package_descriptor_list_value "$descriptor_content" "MANUAL_IDENTITIES")
  if [ -z "$PACKAGE_METADATA_SYSTEM" ] && [ -n "$PACKAGE_METADATA_COMPONENTS" ]; then
    PACKAGE_METADATA_SYSTEM="$PACKAGE_METADATA_COMPONENTS"
  fi
  PACKAGE_METADATA_SECRETS_POLICY=$(package_descriptor_value "$descriptor_content" "SECRETS_POLICY")
  PACKAGE_METADATA_STATUS="present"
}

PACKAGE_VERIFY_TMP=""

cleanup_package_verify() {
  case "$PACKAGE_VERIFY_TMP" in
    /tmp/seed-kit-package-verify.*)
      if [ -d "$PACKAGE_VERIFY_TMP" ]; then
        rm -rf "$PACKAGE_VERIFY_TMP"
      fi
      ;;
  esac
  PACKAGE_VERIFY_TMP=""
}

package_verify_ok() {
  if [ "${PACKAGE_OUTPUT_COMPACT:-0}" = "1" ]; then
    return 0
  fi
  ui_line "OK: $*"
}

package_verify_fail() {
  PACKAGE_VERIFY_FAILED=1
  ui_line "FAIL: $*"
}

package_entries_have_safe_paths() {
  entries=$1
  old_ifs=$IFS
  IFS='
'

  for entry in $entries; do
    [ -n "$entry" ] || continue
    case "$entry" in
      /*|../*|*/../*|*/..|..)
        IFS=$old_ifs
        return 1
        ;;
    esac
  done

  IFS=$old_ifs
  return 0
}

package_entries_have_forbidden_paths() {
  entries=$1
  old_ifs=$IFS
  IFS='
'

  for entry in $entries; do
    [ -n "$entry" ] || continue
    case "$entry" in
      .env|*/.env|*.log|logs|*/logs|logs/*|*/logs/*|log|*/log|log/*|*/log/*|cache|*/cache|cache/*|*/cache/*|caches|*/caches|caches/*|*/caches/*|id_rsa|*/id_rsa|id_ed25519|*/id_ed25519|*.pem|*.key|ssh_host_*|*/ssh_host_*|machine-id|*/machine-id|*tailscale*state*|*cloudflare*credential*|*cloudflared*credential*|*cloudflare*token*|*cloudflared*token*|*cloudflare*cert*|*cloudflared*cert*|*cloudflare*key*|*cloudflared*key*)
        IFS=$old_ifs
        return 0
        ;;
    esac
  done

  IFS=$old_ifs
  return 1
}

package_archive_has_links() {
  package_file=$1

  if ! verbose_entries=$(tar -tvzf "$package_file" 2>/dev/null); then
    return 1
  fi

  old_ifs=$IFS
  IFS='
'

  for line in $verbose_entries; do
    case "$line" in
      l*|h*)
        IFS=$old_ifs
        return 0
        ;;
    esac
  done

  IFS=$old_ifs
  return 1
}

verify_package_archive() {
  package_file=$1

  PACKAGE_VERIFY_FAILED=0

  if [ "${PACKAGE_OUTPUT_COMPACT:-0}" != "1" ]; then
    ui_section "Package verification"
    ui_line "Mode: read-only"
    ui_line "Package: $package_file"
  fi

  if [ ! -f "$package_file" ]; then
    package_verify_fail "package file not found"
    return 2
  fi

  if command -v gzip >/dev/null 2>&1; then
    if gzip -t "$package_file" 2>/dev/null; then
      package_verify_ok "gzip"
    else
      package_verify_fail "gzip"
    fi
  else
    package_verify_fail "gzip unavailable"
  fi

  package_entries=""
  if command -v tar >/dev/null 2>&1; then
    if package_entries=$(tar -tzf "$package_file" 2>/dev/null); then
      package_verify_ok "tar listing"
    else
      package_verify_fail "tar listing"
    fi
  else
    package_verify_fail "tar unavailable"
  fi

  if [ -n "$package_entries" ]; then
    if package_entries_have_safe_paths "$package_entries"; then
      package_verify_ok "tar paths safe"
    else
      package_verify_fail "tar contains unsafe absolute or parent paths"
    fi

    if package_archive_has_links "$package_file"; then
      package_verify_fail "tar contains link entries"
    else
      package_verify_ok "no tar links detected"
    fi

    for required in \
      "MANIFEST.txt" \
      "SHA256SUMS" \
      "seed-kit-package.sh" \
      "profiles/" \
      "services/" \
      "configs/" \
      "docs/"
    do
      if find_package_entry "$package_entries" "$required" >/dev/null; then
        package_verify_ok "$required present"
      else
        package_verify_fail "$required missing"
      fi
    done

    if package_entries_have_forbidden_paths "$package_entries"; then
      package_verify_fail "forbidden secret/runtime paths detected"
    else
      package_verify_ok "secret/runtime path scan"
    fi
  fi

  if [ "$PACKAGE_VERIFY_FAILED" -eq 0 ]; then
    if ! command -v mktemp >/dev/null 2>&1; then
      package_verify_fail "mktemp unavailable"
    elif ! command -v sha256sum >/dev/null 2>&1; then
      package_verify_fail "sha256sum unavailable"
    else
      PACKAGE_VERIFY_TMP=$(mktemp -d -t seed-kit-package-verify.XXXXXX)
      case "$PACKAGE_VERIFY_TMP" in
        /tmp/seed-kit-package-verify.*)
          trap 'cleanup_package_verify' EXIT HUP INT TERM
          if tar -xzf "$package_file" -C "$PACKAGE_VERIFY_TMP" 2>/dev/null; then
            sums_entry=$(find_package_entry "$package_entries" "SHA256SUMS")
            sums_root=${sums_entry%/SHA256SUMS}
            if [ "$sums_root" = "$sums_entry" ]; then
              sums_root="."
            fi
            verify_dir="$PACKAGE_VERIFY_TMP/$sums_root"
            if [ -d "$verify_dir" ] && [ -f "$verify_dir/SHA256SUMS" ]; then
              if (cd "$verify_dir" && sha256sum -c SHA256SUMS >/dev/null 2>&1); then
                package_verify_ok "SHA256SUMS"
              else
                package_verify_fail "SHA256SUMS"
              fi
            else
              package_verify_fail "SHA256SUMS verification path"
            fi
          else
            package_verify_fail "temporary extraction"
          fi
          cleanup_package_verify
          trap - EXIT HUP INT TERM
          ;;
        *)
          package_verify_fail "unsafe temporary verification directory"
          ;;
      esac
    fi
  fi

  if [ "$PACKAGE_VERIFY_FAILED" -eq 0 ]; then
    if [ "${PACKAGE_OUTPUT_COMPACT:-0}" != "1" ]; then
      ui_line "Result: OK"
    fi
    return 0
  fi

  ui_line "Result: FAILED"
  return 2
}

stage_package_archive() {
  package_file=$1

  if [ "${PACKAGE_OUTPUT_COMPACT:-0}" != "1" ]; then
    ui_header "Package stage" "inspection only"
  fi
  if ! verify_package_archive "$package_file"; then
    ui_line "Stage: skipped because verification failed"
    return 2
  fi

  if ! command -v mktemp >/dev/null 2>&1; then
    ui_line "Stage: mktemp unavailable"
    return 2
  fi

  stage_dir=$(mktemp -d -t seed-kit-package-stage.XXXXXX)
  case "$stage_dir" in
    /tmp/seed-kit-package-stage.*)
      ;;
    *)
      ui_line "Stage: unsafe temporary directory"
      return 2
      ;;
  esac

  if ! tar -xzf "$package_file" -C "$stage_dir" 2>/dev/null; then
    ui_line "Stage: extraction failed"
    case "$stage_dir" in
      /tmp/seed-kit-package-stage.*)
        rm -rf "$stage_dir"
        ;;
    esac
    return 2
  fi

  if [ "${PACKAGE_OUTPUT_COMPACT:-0}" = "1" ]; then
    ui_line "Stage dir: $stage_dir"
    return 0
  fi

  ui_line "Package staged"
  ui_line "Stage dir: $stage_dir"
  ui_line "No system changes were made."
  ui_line "No restore, compose up, secrets, DNS/cutover, reboot, or network restart was attempted."
  ui_line "Contents:"
  stage_entries=$(tar -tzf "$package_file" 2>/dev/null || true)
  for item in \
    "seed-kit-package.sh" \
    "profiles/" \
    "services/" \
    "configs/" \
    "docs/"
  do
    if find_package_entry "$stage_entries" "$item" >/dev/null; then
      ui_line "  - $item"
    else
      ui_line "  - $item missing/unknown"
    fi
  done
  ui_line "Inspect:"
  ui_line "  find $stage_dir -maxdepth 3 -type f"
  ui_line "Cleanup:"
  ui_line "  rm -rf $stage_dir"
}

package_stage_safe_dir() {
  stage_dir=$1

  case "$stage_dir" in
    /tmp/seed-kit-package-stage.*/*)
      return 1
      ;;
    /tmp/seed-kit-package-stage.?*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

find_stage_package_root() {
  stage_dir=$1

  if [ -f "$stage_dir/seed-kit-package.sh" ]; then
    printf '%s\n' "$stage_dir"
    return 0
  fi

  find "$stage_dir" -mindepth 2 -maxdepth 2 -type f -name seed-kit-package.sh 2>/dev/null | sed 's#/seed-kit-package\.sh$##' | sed -n '1p'
}

stage_subdir_status() {
  package_root=$1
  subdir=$2

  if [ -d "$package_root/$subdir" ]; then
    count=$(find "$package_root/$subdir" -type f 2>/dev/null | wc -l | sed 's/[[:space:]]//g')
    ui_line "$subdir detected: ${count:-0} file(s)"
  else
    ui_line "$subdir detected: no"
  fi
}

inspect_stage_package() {
  stage_dir=$1

  if [ "${PACKAGE_OUTPUT_COMPACT:-0}" != "1" ]; then
    ui_header "Package stage inspect" "read-only"
    ui_line "Stage dir: $stage_dir"
  fi

  if ! package_stage_safe_dir "$stage_dir"; then
    ui_line "Refusing path outside /tmp/seed-kit-package-stage.*"
    return 2
  fi

  if [ ! -d "$stage_dir" ]; then
    ui_line "Stage dir: not found"
    return 2
  fi

  package_root=$(find_stage_package_root "$stage_dir")
  if [ -z "$package_root" ] || [ ! -d "$package_root" ]; then
    ui_line "Package root: not found"
    return 2
  fi

  if [ "${PACKAGE_OUTPUT_COMPACT:-0}" = "1" ]; then
    ui_line "Package root: $package_root"
    return 0
  fi

  descriptor="$package_root/seed-kit-package.sh"
  descriptor_content=""
  if [ -r "$descriptor" ]; then
    descriptor_content=$(sed -n '1,80p' "$descriptor")
  fi

  profile_file=$(find "$package_root/profiles" -maxdepth 1 -type f -name '*.profile' 2>/dev/null | sed -n '1p')
  profile_content=""
  if [ -n "$profile_file" ] && [ -r "$profile_file" ]; then
    profile_content=$(sed -n '1,80p' "$profile_file")
  fi

  package_id=$(package_descriptor_value "$descriptor_content" "PACKAGE_ID")
  profile_id=$(package_descriptor_value "$descriptor_content" "PROFILE_ID")
  components=$(package_descriptor_list_value "$descriptor_content" "COMPONENTS")
  system_items=$(package_descriptor_list_value "$descriptor_content" "SYSTEM")
  module_items=$(package_descriptor_list_value "$descriptor_content" "MODULES")
  service_items=$(package_descriptor_list_value "$descriptor_content" "SERVICES")
  manual_identities=$(package_descriptor_list_value "$descriptor_content" "MANUAL_IDENTITIES")
  if [ -z "$system_items" ] && [ -n "$components" ]; then
    system_items="$components"
  fi
  secrets_policy=$(package_descriptor_value "$descriptor_content" "SECRETS_POLICY")
  node_role=$(package_descriptor_value "$profile_content" "NODE_ROLE")
  reconstruction_mode=$(package_descriptor_value "$profile_content" "RECONSTRUCTION_MODE")

  ui_line "Package root: $package_root"
  ui_line "Package ID: ${package_id:-unknown}"
  ui_line "Profile ID: ${profile_id:-unknown}"
  package_print_list "System:" "$system_items"
  package_print_list "Modules:" "$module_items"
  package_print_list "Services:" "$service_items"
  package_print_list "Manual identities:" "$manual_identities"
  ui_line "Secrets policy: ${secrets_policy:-unknown}"
  ui_line "Node role: ${node_role:-unknown}"
  ui_line "Reconstruction mode: ${reconstruction_mode:-unknown}"

  ui_section "Detected content"
  stage_subdir_status "$package_root" "services"
  stage_subdir_status "$package_root" "configs"
  stage_subdir_status "$package_root" "docs"
  stage_subdir_status "$package_root" "profiles"

  ui_section "Next manual steps"
  ui_line "- verify identity"
  ui_line "- tailscale up manual"
  ui_line "- cloudflared login/tunnel manual"
  ui_line "- review compose/configs"

  ui_line "No restore, compose up, secrets, DNS/cutover, reboot, or network restart was attempted."
}

apply_guided_install_modules() {
  system_items=$1

  ui_section "install-modules step"
  installable_modules=""
  installed_modules=""
  missing_modules=""
  manual_modules=""

  for system_item in $system_items; do
    case "$system_item" in
      git|docker|tailscale|cloudflared|caddy)
        if module_is_installed "$system_item"; then
          installed_modules="${installed_modules}${system_item} "
        else
          missing_modules="${missing_modules}${system_item} "
          installable_modules="${installable_modules}${system_item} "
        fi
        ;;
      *)
        manual_modules="${manual_modules}${system_item} "
        ;;
    esac
  done

  ui_line "Declared system:"
  if [ -n "$system_items" ]; then
    for system_item in $system_items; do
      ui_line "  - $system_item"
    done
  else
    ui_line "  none"
  fi
  ui_line "Already present: ${installed_modules:-none}"
  ui_line "Missing: ${missing_modules:-none}"
  ui_line "Install-only candidates: ${installable_modules:-none}"
  ui_line "Manual/future: ${manual_modules:-none}"

  if [ -z "$installable_modules" ]; then
    ui_line "No install-only modules selected for apply."
    return 0
  fi

  ui_line "SAFE boundary:"
  ui_line "  - no staged configs copied to /etc"
  ui_line "  - no restore"
  ui_line "  - no compose pull/up"
  ui_line "  - no secrets"
  ui_line "  - no tailscale up"
  ui_line "  - no cloudflared login"
  ui_line "  - no DNS/cutover"
  ui_line "  - no reboot or network restart"

  APPLY_AUTO=0
  APPLY_CONFIRMED=0
  APPLY_MODULES=$(printf '%s\n' "$installable_modules" | sed 's/[[:space:]]*$//')
  APPLY_CONFIRM_TARGET="package apply-guided step=install-modules modules=$APPLY_MODULES"
  APPLY_DONE_MODULES=""
  APPLY_MANUAL_STEPS=""

  if ! apply_safe_confirm; then
    return 2
  fi

  run_apply_modules
}

review_text_file_preview() {
  file=$1
  label=$2

  if [ -f "$file" ]; then
    ui_line ""
    ui_line "$label:"
    sed -n '1,40p' "$file" | sed 's/^/  /'
  fi
}

apply_guided_review_configs() {
  package_root=$1

  ui_section "CONFIG REVIEW"
  ui_line "Staged root: $package_root"
  ui_line "Detected:"
  if [ -f "$package_root/services/docker-compose.yml" ]; then
    ui_line "  - services/docker-compose.yml"
  fi
  if [ -f "$package_root/configs/caddy/Caddyfile" ]; then
    ui_line "  - configs/caddy/Caddyfile"
  fi
  if [ -d "$package_root/configs/homepage" ]; then
    ui_line "  - configs/homepage/..."
  fi
  if [ -f "$package_root/docs/reconstruction.txt" ]; then
    ui_line "  - docs/reconstruction.txt"
  fi

  ui_line "Future destinations:"
  ui_line "  - Caddyfile -> manual review before /etc/caddy/Caddyfile or Docker Caddy config"
  ui_line "  - homepage config -> manual review before compose volume/config path"
  ui_line "  - docker-compose.yml -> manual review before service directory"

  review_text_file_preview "$package_root/configs/caddy/Caddyfile" "Preview configs/caddy/Caddyfile"
  review_text_file_preview "$package_root/services/docker-compose.yml" "Preview services/docker-compose.yml"
  review_text_file_preview "$package_root/docs/reconstruction.txt" "Preview docs/reconstruction.txt"

  ui_line ""
  ui_line "No files were copied."
  ui_line "No restore, compose up/pull, Caddy reload, secrets, DNS/cutover, reboot, or network restart was attempted."
}

apply_guided_validate_services() {
  package_root=$1
  compose_file="$package_root/services/docker-compose.yml"
  caddy_file="$package_root/configs/caddy/Caddyfile"
  homepage_dir="$package_root/configs/homepage"

  ui_section "SERVICE VALIDATION"
  ui_line "Staged root: $package_root"

  ui_line ""
  ui_line "docker compose:"
  if [ ! -f "$compose_file" ]; then
    ui_line "  missing: services/docker-compose.yml"
  elif docker compose version >/dev/null 2>&1; then
    if docker compose -f "$compose_file" config >/dev/null 2>&1; then
      ui_line "  OK"
    else
      ui_line "  warning: docker compose config failed"
    fi
  else
    ui_line "  warning: docker compose unavailable, skipped"
  fi

  ui_line ""
  ui_line "caddy config:"
  if [ ! -f "$caddy_file" ]; then
    ui_line "  missing: configs/caddy/Caddyfile"
  elif command -v caddy >/dev/null 2>&1; then
    if caddy validate --config "$caddy_file" >/dev/null 2>&1; then
      ui_line "  OK"
    else
      ui_line "  warning: caddy validate failed"
    fi
  else
    ui_line "  warning: caddy unavailable, skipped"
  fi

  ui_line ""
  ui_line "homepage configs:"
  if [ -d "$homepage_dir" ]; then
    ui_line "  detected"
  else
    ui_line "  missing: configs/homepage"
  fi

  ui_line ""
  ui_line "No services were started."
  ui_line "No configs were copied."
  ui_line "No compose up/pull, Caddy reload, secrets, DNS/cutover, reboot, or network restart was attempted."
}

deploy_config_confirm() {
  prompt=$1

  ui_prompt "$prompt [y/N]:"
  IFS= read -r answer || return 1
  case "$answer" in
    y|Y)
      return 0
      ;;
    *)
      ui_line "  skipped"
      return 1
      ;;
  esac
}

deploy_config_copy_file() {
  label=$1
  src=$2
  dest_dir=$3
  dest=$4

  [ -f "$src" ] || return 0
  if ! deploy_config_confirm "Copy $label to $dest?"; then
    return 0
  fi
  if [ -e "$dest" ]; then
    ui_line "  skipped existing: $dest"
    return 0
  fi
  if ! mkdir -p "$dest_dir"; then
    ui_line "  failed: unable to create $dest_dir"
    return 2
  fi
  if ! cp "$src" "$dest"; then
    ui_line "  failed: unable to copy $label"
    return 2
  fi
  DEPLOY_COPIED_COUNT=$((DEPLOY_COPIED_COUNT + 1))
  ui_line "  - $dest"
}

deploy_config_copy_dir() {
  label=$1
  src=$2
  dest_parent=$3
  dest=$4

  [ -d "$src" ] || return 0
  if ! deploy_config_confirm "Copy $label to $dest?"; then
    return 0
  fi
  if [ -e "$dest" ]; then
    ui_line "  skipped existing: $dest"
    return 0
  fi
  if ! mkdir -p "$dest_parent"; then
    ui_line "  failed: unable to create $dest_parent"
    return 2
  fi
  if ! cp -R "$src" "$dest"; then
    ui_line "  failed: unable to copy $label"
    return 2
  fi
  DEPLOY_COPIED_COUNT=$((DEPLOY_COPIED_COUNT + 1))
  ui_line "  - $dest"
}

deploy_id_from_descriptor() {
  descriptor_content=$1

  deploy_id=$(package_descriptor_value "$descriptor_content" "PROFILE_ID")
  if [ -z "$deploy_id" ]; then
    deploy_id=$(package_descriptor_value "$descriptor_content" "PACKAGE_ID")
  fi
  case "$deploy_id" in
    ""|"."|".."|/*|*/*|*[!A-Za-z0-9._-]*)
      deploy_id="package"
      ;;
  esac

  printf '%s\n' "$deploy_id"
}

apply_guided_deploy_configs() {
  package_root=$1
  descriptor_content=""
  if [ -r "$package_root/seed-kit-package.sh" ]; then
    descriptor_content=$(sed -n '1,80p' "$package_root/seed-kit-package.sh")
  fi
  deploy_id=$(deploy_id_from_descriptor "$descriptor_content")

  if [ -z "${HOME:-}" ]; then
    ui_line "Deploy configs: HOME is not set"
    return 2
  fi

  compose_file="$package_root/services/docker-compose.yml"
  caddy_file="$package_root/configs/caddy/Caddyfile"
  homepage_dir="$package_root/configs/homepage"
  deploy_root="$HOME/seed-kit-deploy/$deploy_id"

  ui_section "GUIDED CONFIG DEPLOYMENT"
  ui_line "Detected:"
  detected=0
  if [ -f "$compose_file" ]; then
    ui_line "  - services/docker-compose.yml"
    detected=$((detected + 1))
  fi
  if [ -f "$caddy_file" ]; then
    ui_line "  - configs/caddy/Caddyfile"
    detected=$((detected + 1))
  fi
  if [ -d "$homepage_dir" ]; then
    ui_line "  - configs/homepage/"
    detected=$((detected + 1))
  fi

  if [ "$detected" -eq 0 ]; then
    ui_line "  none"
    ui_line "No files were copied."
    return 0
  fi

  ui_line ""
  ui_line "Suggested destinations:"
  ui_line "  - $deploy_root/docker-compose.yml"
  ui_line "  - $deploy_root/Caddyfile"
  ui_line "  - $deploy_root/homepage/"
  ui_line ""
  ui_line "SAFE boundary:"
  ui_line "  - user directory only"
  ui_line "  - no /etc writes"
  ui_line "  - no compose up/pull"
  ui_line "  - no Caddy reload/restart"
  ui_line "  - no secrets, DNS/cutover, reboot, or network restart"

  if ! deploy_config_confirm "Continue with guided config deployment?"; then
    ui_line "No files were copied."
    return 2
  fi

  ui_line ""
  ui_line "Copied:"
  DEPLOY_COPIED_COUNT=0
  deploy_config_copy_file "services/docker-compose.yml" "$compose_file" "$deploy_root" "$deploy_root/docker-compose.yml" || return 2
  deploy_config_copy_file "configs/caddy/Caddyfile" "$caddy_file" "$deploy_root" "$deploy_root/Caddyfile" || return 2
  deploy_config_copy_dir "configs/homepage/" "$homepage_dir" "$deploy_root" "$deploy_root/homepage" || return 2
  if [ "$DEPLOY_COPIED_COUNT" -eq 0 ]; then
    ui_line "  none"
  fi

  ui_line ""
  ui_line "Not done:"
  ui_line "  - compose up/pull"
  ui_line "  - Caddy reload/restart"
  ui_line "  - service start"
  ui_line "  - secrets"
  ui_line "  - DNS/cutover"
  ui_line "  - reboot or network restart"
  ui_line "Staging kept for inspection."
}

apply_guided_validate_deployed() {
  package_root=$1
  descriptor_content=""
  if [ -r "$package_root/seed-kit-package.sh" ]; then
    descriptor_content=$(sed -n '1,80p' "$package_root/seed-kit-package.sh")
  fi
  deploy_id=$(deploy_id_from_descriptor "$descriptor_content")

  if [ -z "${HOME:-}" ]; then
    ui_line "Validate deployed: HOME is not set"
    return 2
  fi

  deploy_root="$HOME/seed-kit-deploy/$deploy_id"
  compose_file="$deploy_root/docker-compose.yml"
  caddy_file="$deploy_root/Caddyfile"
  homepage_dir="$deploy_root/homepage"

  ui_section "DEPLOYED CONFIG VALIDATION"
  ui_line "Deploy root:"
  ui_line "  ~/seed-kit-deploy/$deploy_id/"
  ui_line "  $deploy_root"

  ui_line ""
  ui_line "docker compose:"
  if [ ! -f "$compose_file" ]; then
    ui_line "  missing: docker-compose.yml"
  elif docker compose version >/dev/null 2>&1; then
    if docker compose -f "$compose_file" config >/dev/null 2>&1; then
      ui_line "  OK"
    else
      ui_line "  warning: docker compose config failed"
    fi
  else
    ui_line "  warning: docker compose unavailable, skipped"
  fi

  ui_line ""
  ui_line "caddy config:"
  if [ ! -f "$caddy_file" ]; then
    ui_line "  missing: Caddyfile"
  elif command -v caddy >/dev/null 2>&1; then
    if caddy validate --config "$caddy_file" >/dev/null 2>&1; then
      ui_line "  OK"
    else
      ui_line "  warning: caddy validate failed"
    fi
  else
    ui_line "  warning: caddy unavailable, skipped"
  fi

  ui_line ""
  ui_line "homepage configs:"
  if [ -d "$homepage_dir" ]; then
    ui_line "  detected"
  else
    ui_line "  missing: homepage/"
  fi

  ui_line ""
  ui_line "Suggested next manual steps:"
  ui_line "  - docker compose up"
  ui_line "  - caddy reload"
  ui_line "  - tailscale up"
  ui_line "  - cloudflared login"
  ui_line ""
  ui_line "No services were started."
  ui_line "No configs were copied."
  ui_line "No compose up/pull, Caddy reload/restart, secrets, DNS/cutover, reboot, or network restart was attempted."
}

apply_guided_suggest_start() {
  package_root=$1
  package_file=$2
  descriptor_content=""
  if [ -r "$package_root/seed-kit-package.sh" ]; then
    descriptor_content=$(sed -n '1,80p' "$package_root/seed-kit-package.sh")
  fi
  deploy_id=$(deploy_id_from_descriptor "$descriptor_content")

  if [ -z "${HOME:-}" ]; then
    ui_line "Suggest start: HOME is not set"
    return 2
  fi

  deploy_root="$HOME/seed-kit-deploy/$deploy_id"
  compose_file="$deploy_root/docker-compose.yml"
  caddy_file="$deploy_root/Caddyfile"
  homepage_dir="$deploy_root/homepage"

  ui_section "SUGGESTED MANUAL START"
  ui_line "Deploy root:"
  ui_line "  ~/seed-kit-deploy/$deploy_id"
  ui_line "  $deploy_root"

  ui_line ""
  ui_line "Expected deployed files:"
  if [ -f "$compose_file" ]; then
    ui_line "  - docker-compose.yml: present"
  else
    ui_line "  - docker-compose.yml: missing"
  fi
  if [ -f "$caddy_file" ]; then
    ui_line "  - Caddyfile: present"
  else
    ui_line "  - Caddyfile: missing"
  fi
  if [ -d "$homepage_dir" ]; then
    ui_line "  - homepage/: present"
  else
    ui_line "  - homepage/: missing"
  fi

  ui_line ""
  ui_line "Review first:"
  ui_line "  sh seed-kit.sh package apply-guided $package_file --step validate-deployed"

  ui_line ""
  ui_line "Manual commands:"
  ui_line "  cd ~/seed-kit-deploy/$deploy_id"
  ui_line "  docker compose up -d"
  ui_line "  docker compose ps"
  ui_line "  curl http://127.0.0.1:8080"

  ui_line ""
  ui_line "Identity/manual steps:"
  ui_line "  Review readiness first:"
  ui_line "    sh seed-kit.sh package apply-guided $package_file --step readiness"
  ui_line ""
  ui_line "  Tailscale will open a browser authentication URL:"
  ui_line "  sudo tailscale up"
  ui_line ""
  ui_line "  Cloudflare tunnel setup remains manual:"
  ui_line "  cloudflared tunnel login/create/configure"

  ui_line ""
  ui_line "Seed-Kit did not start services."
  ui_line "No compose up/pull, service start, Caddy reload/restart, tailscale up, cloudflared login, secrets, DNS/cutover, reboot, or network restart was attempted."
}

readiness_bool() {
  if [ "$1" = "yes" ]; then
    printf '%s\n' "yes"
  else
    printf '%s\n' "no"
  fi
}

readiness_line() {
  name=$1
  state=$2
  summary=$3

  if ! seed_verbose; then
    if [ "$state" = "ok" ]; then
      printf '%s%-6s%s %-12s %s\n' "$COLOR_GOOD" "OK" "$COLOR_RESET" "$name" "$summary"
    else
      printf '%s%-6s%s %-12s %s\n' "$COLOR_WARN" "WARN" "$COLOR_RESET" "$name" "$summary"
    fi
    return 0
  fi

  if [ "$state" = "ok" ]; then
    printf '%s[OK]%s %-12s %s\n' "$COLOR_GOOD" "$COLOR_RESET" "$name" "$summary"
  else
    printf '%s[WARN]%s %-12s %s\n' "$COLOR_WARN" "$COLOR_RESET" "$name" "$summary"
  fi
}

cloudflared_configured() {
  for path in \
    "$HOME/.cloudflared/config.yml" \
    "$HOME/.cloudflared/config.yaml" \
    "$HOME/.cloudflared/cert.pem" \
    /etc/cloudflared/config.yml \
    /etc/cloudflared/config.yaml
  do
    if [ -e "$path" ]; then
      return 0
    fi
  done
  return 1
}

apply_guided_readiness() {
  package_root=$1
  descriptor_content=""
  if [ -r "$package_root/seed-kit-package.sh" ]; then
    descriptor_content=$(sed -n '1,80p' "$package_root/seed-kit-package.sh")
  fi
  deploy_id=$(deploy_id_from_descriptor "$descriptor_content")

  if [ -z "${HOME:-}" ]; then
    ui_line "Readiness: HOME is not set"
    return 2
  fi

  deploy_root="$HOME/seed-kit-deploy/$deploy_id"
  compose_file="$deploy_root/docker-compose.yml"
  caddy_file="$deploy_root/Caddyfile"
  homepage_dir="$deploy_root/homepage"

  if seed_verbose; then
    ui_section "$(seed_msg readiness)"
  else
    if [ "$(seed_lang)" = "fr" ]; then
      ui_line "Seed-Kit > readiness — $deploy_id"
    else
      ui_line "Seed-Kit > readiness - $deploy_id"
    fi
    ui_line ""
  fi

  docker_installed=no
  docker_service_active=no
  docker_compose_available=no
  docker_ready=no
  if module_is_installed docker; then
    docker_installed=yes
  fi
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active docker >/dev/null 2>&1; then
    docker_service_active=yes
  fi
  if docker compose version >/dev/null 2>&1; then
    docker_compose_available=yes
  fi
  if [ "$docker_installed" = "yes" ] && [ "$docker_service_active" = "yes" ] && [ "$docker_compose_available" = "yes" ]; then
    docker_ready=yes
  fi
  docker_summary=$(seed_msg ready)
  docker_state=ok
  if [ "$docker_ready" != "yes" ]; then
    docker_state=warn
    if [ "$docker_installed" = "yes" ]; then
      if seed_verbose; then
        docker_summary=$(seed_msg installed_not_ready)
      else
        docker_summary=$(seed_msg not_ready)
      fi
    else
      docker_summary=$(seed_msg not_installed)
    fi
  fi

  tailscale_installed=no
  tailscale_connected=no
  if module_is_installed tailscale; then
    tailscale_installed=yes
    if tailscale ip >/dev/null 2>&1 || tailscale status >/dev/null 2>&1; then
      tailscale_connected=yes
    fi
  fi
  tailscale_state=ok
  tailscale_summary=$(seed_msg connected)
  if [ "$tailscale_connected" != "yes" ]; then
    tailscale_state=warn
    if [ "$tailscale_installed" = "yes" ]; then
      if seed_verbose; then
        tailscale_summary=$(seed_msg installed_not_connected)
      else
        tailscale_summary=$(seed_msg to_connect)
      fi
    else
      tailscale_summary=$(seed_msg not_installed)
    fi
  fi

  cloudflared_installed=no
  cloudflared_configured_status=no
  if module_is_installed cloudflared; then
    cloudflared_installed=yes
    if cloudflared_configured; then
      cloudflared_configured_status=yes
    else
      cloudflared_configured_status="no/unknown"
    fi
  fi
  cloudflared_state=ok
  cloudflared_summary=$(seed_msg configured)
  if [ "$cloudflared_configured_status" != "yes" ]; then
    cloudflared_state=warn
    if [ "$cloudflared_installed" = "yes" ]; then
      if seed_verbose; then
        cloudflared_summary=$(seed_msg installed_not_configured)
      else
        cloudflared_summary=$(seed_msg to_configure)
      fi
    else
      cloudflared_summary=$(seed_msg not_installed)
    fi
  fi

  services_deployed=no
  services_validated=no
  if [ -f "$compose_file" ] && [ -f "$caddy_file" ] && [ -d "$homepage_dir" ]; then
    services_deployed=yes
  fi
  compose_ok=no
  caddy_ok=no
  if [ -f "$compose_file" ]; then
    if docker compose version >/dev/null 2>&1; then
      if docker compose -f "$compose_file" config >/dev/null 2>&1; then
        compose_ok=yes
      fi
    else
      compose_ok=unknown
    fi
  fi
  if [ -f "$caddy_file" ]; then
    if command -v caddy >/dev/null 2>&1; then
      if caddy validate --config "$caddy_file" >/dev/null 2>&1; then
        caddy_ok=yes
      fi
    else
      caddy_ok=unknown
    fi
  fi
  if [ "$services_deployed" = "yes" ]; then
    case "$compose_ok:$caddy_ok" in
      yes:yes|yes:unknown|unknown:yes|unknown:unknown)
        services_validated=yes
        ;;
    esac
  fi
  services_state=ok
  if seed_verbose; then
    services_summary=$(seed_msg deployed_validated)
  else
    services_summary=$(seed_msg ready_plural)
  fi
  if [ "$services_validated" != "yes" ]; then
    services_state=warn
    if [ "$services_deployed" = "yes" ]; then
      if seed_verbose; then
        services_summary=$(seed_msg deployed_validation_needed)
      else
        services_summary=$(seed_msg to_configure)
      fi
    else
      services_summary=$(seed_msg not_deployed)
    fi
  fi

  readiness_line "docker" "$docker_state" "$docker_summary"
  readiness_line "tailscale" "$tailscale_state" "$tailscale_summary"
  readiness_line "cloudflared" "$cloudflared_state" "$cloudflared_summary"
  readiness_line "services" "$services_state" "$services_summary"

  ui_line ""
  if seed_verbose; then
    ui_section "$(seed_msg next_actions)"
  else
    ui_line "$(seed_msg todo)"
  fi
  next_index=1
  if [ "$docker_ready" != "yes" ]; then
    ui_line "$next_index. sh seed-kit.sh package apply-guided <package> --step install-modules"
    next_index=$((next_index + 1))
  fi
  if [ "$tailscale_connected" != "yes" ]; then
    ui_line "$next_index. sudo tailscale up"
    next_index=$((next_index + 1))
  fi
  if [ "$cloudflared_configured_status" != "yes" ]; then
    ui_line "$next_index. cloudflared tunnel login/create/configure"
    next_index=$((next_index + 1))
  fi
  if [ "$services_validated" != "yes" ]; then
    ui_line "$next_index. sh seed-kit.sh package apply-guided <package> --step deploy-configs"
  fi
  if [ "$next_index" -eq 1 ]; then
    ui_line "$(seed_msg none)"
  fi

  ui_line ""
  if seed_verbose; then
    ui_section "$(seed_msg nothing_changed)"
  else
    ui_line "$(seed_msg nothing_changed)."
  fi
  if seed_verbose; then
    ui_line "$(seed_msg no_change_summary)"
  fi

  if ! seed_verbose; then
    return 0
  fi

  ui_line ""
  ui_section "$(seed_msg details)"
  ui_line "docker:"
  ui_line "  installed: $docker_installed"
  printf "$(seed_msg details_docker_service_active)\\n" "$docker_service_active"
  ui_line "  compose: $docker_compose_available"
  printf "$(seed_msg details_ready)\\n" "$docker_ready"
  if [ "$tailscale_connected" != "yes" ]; then
    ui_line ""
    ui_line "tailscale:"
    ui_line "$(seed_msg details_tailscale_not_connected)"
    ui_line "$(seed_msg details_tailscale_auth)"
    ui_line "$(seed_msg details_tailscale_expected)"
  fi
  if [ "$cloudflared_configured_status" != "yes" ]; then
    ui_line ""
    ui_line "cloudflared:"
    ui_line "$(seed_msg details_cloudflared_missing)"
    ui_line "$(seed_msg details_cloudflared_expected)"
  fi
  ui_line ""
  ui_line "services:"
  printf "$(seed_msg details_deploy_root)\\n" "~/seed-kit-deploy/$deploy_id"
  printf "$(seed_msg details_deployed)\\n" "$services_deployed"
  ui_line "  docker compose config: $compose_ok"
  ui_line "  caddy validate: $caddy_ok"
  printf "$(seed_msg details_validated)\\n" "$services_validated"
}

apply_guided_mode_label() {
  case "$1" in
    install-modules)
      seed_msg mode_safe_install_only
      ;;
    deploy-configs)
      seed_msg mode_safe_guided_copy
      ;;
    *)
      seed_msg mode_safe_read_only
      ;;
  esac
}

apply_guided_print_header() {
  guided_step=$1
  package_file=$2
  package_id=$3
  profile_id=$4

  package_label=${package_id:-${package_file##*/}}
  profile_label=${profile_id:-unknown}
  mode_label=$(apply_guided_mode_label "$guided_step")

  ui_separator "========================================"
  ui_line "$(seed_msg apply_guided_title)"
  ui_line "Seed-Kit > package apply-guided > $guided_step"
  if [ "$(seed_lang)" = "fr" ]; then
    ui_line "$(seed_msg step_label) : $guided_step"
    ui_line "$(seed_msg package_label) : $package_label"
    ui_line "$(seed_msg profile_label) : $profile_label"
    ui_line "$(seed_msg mode_label) : $mode_label"
  else
    ui_line "$(seed_msg step_label): $guided_step"
    ui_line "$(seed_msg package_label): $package_label"
    ui_line "$(seed_msg profile_label): $profile_label"
    ui_line "$(seed_msg mode_label): $mode_label"
  fi
  ui_separator "========================================"
}

apply_guided_package() {
  package_file=$1
  guided_step=${2:-preview}

  case "$guided_step" in
    preview|install-modules|review-configs|validate-services|deploy-configs|validate-deployed|suggest-start|readiness)
      ;;
    *)
      echo "unknown apply-guided step: $guided_step" >&2
      return 2
      ;;
  esac

  package_entries=""
  if [ -f "$package_file" ] && command -v tar >/dev/null 2>&1; then
    package_entries=$(tar -tzf "$package_file" 2>/dev/null || true)
  fi
  read_package_metadata "$package_file" "$package_entries"
  guided_compact_readiness=0
  if [ "$guided_step" = "readiness" ] && ! seed_verbose; then
    guided_compact_readiness=1
  fi

  if [ "$guided_compact_readiness" -eq 0 ]; then
    apply_guided_print_header "$guided_step" "$package_file" "$PACKAGE_METADATA_PACKAGE_ID" "$PACKAGE_METADATA_PROFILE_ID"
    ui_section "$(seed_msg progress)"
  fi
  PACKAGE_OUTPUT_COMPACT=1
  if ! verify_package_archive "$package_file"; then
    PACKAGE_OUTPUT_COMPACT=0
    ui_line "Apply guided: stopped because verification failed"
    return 2
  fi
  if [ "$guided_compact_readiness" -eq 0 ]; then
    ui_report_ok "verify"
  fi

  stage_output=$(stage_package_archive "$package_file") || {
    PACKAGE_OUTPUT_COMPACT=0
    printf '%s\n' "$stage_output"
    ui_line "Apply guided: stopped because staging failed"
    return 2
  }
  stage_dir=$(printf '%s\n' "$stage_output" | sed -n 's/^Stage dir: //p' | sed -n '1p')
  if [ -z "$stage_dir" ]; then
    PACKAGE_OUTPUT_COMPACT=0
    ui_line "Apply guided: unable to find stage directory"
    return 2
  fi
  if [ "$guided_compact_readiness" -eq 0 ]; then
    ui_report_ok "stage"
    ui_line "Stage dir: $stage_dir"
  fi
  package_root=$(find_stage_package_root "$stage_dir")
  descriptor_content=""
  if [ -n "$package_root" ] && [ -r "$package_root/seed-kit-package.sh" ]; then
    descriptor_content=$(sed -n '1,80p' "$package_root/seed-kit-package.sh")
  fi
  guided_system=$(package_descriptor_list_value "$descriptor_content" "SYSTEM")
  if [ -z "$guided_system" ]; then
    guided_system=$(package_descriptor_list_value "$descriptor_content" "COMPONENTS")
  fi
  guided_modules=$(package_descriptor_list_value "$descriptor_content" "MODULES")
  guided_services=$(package_descriptor_list_value "$descriptor_content" "SERVICES")
  guided_manual_identities=$(package_descriptor_list_value "$descriptor_content" "MANUAL_IDENTITIES")

  inspect_output=$(inspect_stage_package "$stage_dir") || {
    PACKAGE_OUTPUT_COMPACT=0
    printf '%s\n' "$inspect_output"
    ui_line "Apply guided: stopped because staged package inspection failed"
    return 2
  }
  PACKAGE_OUTPUT_COMPACT=0
  if [ "$guided_compact_readiness" -eq 0 ]; then
    ui_report_ok "inspect"
    printf '%s\n' "$inspect_output" | sed 's/^/  /'
    ui_report_active "$guided_step"
  fi

  if [ "$guided_step" = "preview" ]; then
    ui_section "$(seed_msg proposed_future_actions)"
    ui_line "$(seed_msg future_install_system)"
    ui_line "$(seed_msg future_review_configs)"
    if [ -n "$guided_manual_identities" ]; then
      for identity in $guided_manual_identities; do
        if [ "$(seed_lang)" = "fr" ]; then
          ui_line "- reconnecter $identity manuellement"
        else
          ui_line "- reconnect $identity manually"
        fi
      done
    else
      ui_line "$(seed_msg future_reconnect_identities)"
    fi
    if [ -n "$guided_services" ]; then
      ui_line "$(seed_msg future_validate_services)"
    else
      ui_line "$(seed_msg future_validate_configs)"
    fi
    ui_line "$(seed_msg future_optional_start)"

    ui_section "$(seed_msg nothing_changed)"
    ui_line "$(seed_msg no_restore)"
    ui_line "$(seed_msg no_service_start)"
    ui_line "$(seed_msg no_secret_copy)"
    ui_line "$(seed_msg no_dns_cutover)"
    ui_line "$(seed_msg no_reboot_network)"
    ui_line "$(seed_msg package_apply_disabled)"
  fi

  if [ "$guided_step" = "install-modules" ]; then
    apply_guided_install_modules "$guided_system"
  fi
  if [ "$guided_step" = "review-configs" ]; then
    if [ -z "$package_root" ]; then
      ui_line "Review configs: package root not found"
      return 2
    fi
    apply_guided_review_configs "$package_root"
  fi
  if [ "$guided_step" = "validate-services" ]; then
    if [ -z "$package_root" ]; then
      ui_line "Validate services: package root not found"
      return 2
    fi
    apply_guided_validate_services "$package_root"
  fi
  if [ "$guided_step" = "deploy-configs" ]; then
    if [ -z "$package_root" ]; then
      ui_line "Deploy configs: package root not found"
      return 2
    fi
    apply_guided_review_configs "$package_root"
    apply_guided_validate_services "$package_root"
    apply_guided_deploy_configs "$package_root"
  fi
  if [ "$guided_step" = "validate-deployed" ]; then
    if [ -z "$package_root" ]; then
      ui_line "Validate deployed: package root not found"
      return 2
    fi
    apply_guided_validate_deployed "$package_root"
  fi
  if [ "$guided_step" = "suggest-start" ]; then
    if [ -z "$package_root" ]; then
      ui_line "Suggest start: package root not found"
      return 2
    fi
    apply_guided_suggest_start "$package_root" "$package_file"
  fi
  if [ "$guided_step" = "readiness" ]; then
    if [ -z "$package_root" ]; then
      ui_line "Readiness: package root not found"
      return 2
    fi
    apply_guided_readiness "$package_root"
    readiness_rc=$?
    if [ "$guided_compact_readiness" -eq 1 ]; then
      case "$stage_dir" in
        /tmp/seed-kit-package-stage.*)
          rm -rf "$stage_dir"
          ;;
      esac
    fi
    return "$readiness_rc"
  fi
}

show_package_plan() {
  package_file=$1

  ui_header "Package-driven PRA preview" "design/preview only"
  ui_line "Package: $package_file"
  if [ ! -f "$package_file" ]; then
    echo "package not found: $package_file" >&2
    echo "Next: copy package to this node, then rerun --plan --package $package_file" >&2
    return 2
  fi

  ui_line "Status: present"
  if command -v wc >/dev/null 2>&1; then
    size_bytes=$(wc -c < "$package_file" 2>/dev/null || echo "unknown")
    ui_line "Size: $size_bytes bytes"
  fi

  if command -v gzip >/dev/null 2>&1; then
    if gzip -t "$package_file" 2>/dev/null; then
      ui_line "Gzip: OK"
    else
      ui_line "Gzip: unable to verify"
    fi
  else
    ui_line "Gzip: unavailable"
  fi

  package_entries=""
  if command -v tar >/dev/null 2>&1; then
    if package_entries=$(tar -tzf "$package_file" 2>/dev/null); then
      ui_line "Tar listing: OK"
    else
      ui_line "Tar listing: unavailable"
    fi
  else
    ui_line "Tar listing: tar unavailable"
  fi

  ui_section "Key files"
  if [ -n "$package_entries" ]; then
    for pattern in \
      "MANIFEST.txt" \
      "SHA256SUMS" \
      "seed-kit-package." \
      "profiles/" \
      "services/" \
      "configs/" \
      "docs/"
    do
      if printf '%s\n' "$package_entries" | grep -q "$pattern"; then
        ui_line "- $pattern present"
      else
        ui_line "- $pattern missing/unknown"
      fi
    done
  else
    ui_line "- unknown: archive contents not listed"
  fi

  read_package_metadata "$package_file" "$package_entries"

  ui_section "Package metadata"
  case "$PACKAGE_METADATA_STATUS" in
    present)
      ui_line "Package ID: ${PACKAGE_METADATA_PACKAGE_ID:-unknown}"
      ui_line "Profile: ${PACKAGE_METADATA_PROFILE_ID:-unknown}"
      package_print_list "System:" "$PACKAGE_METADATA_SYSTEM"
      package_print_list "Modules:" "$PACKAGE_METADATA_MODULES"
      package_print_list "Services:" "$PACKAGE_METADATA_SERVICES"
      package_print_list "Manual identities:" "$PACKAGE_METADATA_MANUAL_IDENTITIES"
      ui_line "Secrets policy: ${PACKAGE_METADATA_SECRETS_POLICY:-unknown}"
      ;;
    missing)
      ui_line "Package metadata: seed-kit-package.sh missing"
      ;;
    unreadable)
      ui_line "Package metadata: unable to read seed-kit-package.sh"
      ;;
    *)
      ui_line "Package metadata: unavailable"
      ;;
  esac

  verify_package_archive "$package_file" || true

  ui_section "Preview"
  ui_line "Profile: ${PACKAGE_METADATA_PROFILE_ID:-embedded / unknown}"
  if [ -n "$PACKAGE_METADATA_SYSTEM$PACKAGE_METADATA_MODULES$PACKAGE_METADATA_SERVICES" ]; then
    ui_line "System/modules/services: detected"
  else
    ui_line "System/modules/services: detected / unknown"
  fi
  ui_line "Would verify manifest/checksums later"
  ui_line "Would install required system packages later"
  ui_line "Would stage safe files later"
  ui_line "Would require manual identity reconnection"

  ui_section "Replacement preparation"
  ui_line "- hostname review"
  ui_line "- tailscale login/state manual"
  ui_line "- cloudflare tunnel credentials manual"
  ui_line "- SSH trust validation"
  ui_line "- DNS/cutover manual"

  ui_line "Apply package: disabled"
  ui_line "No extraction, staging, restore, service start, secret write, reboot, DNS, or cutover."
  ui_line "Docs: docs/PACKAGE-DRIVEN-PRA.md"
}

show_package_apply_preview_only() {
  package_file=$1
  components=${2:-all}

  ui_header "package-driven PRA apply" "preview only"
  ui_line "Package: $package_file"
  ui_line "Selection: $components"
  ui_line "Package apply is disabled in V1."
  if [ ! -f "$package_file" ]; then
    ui_line "Status: package not found"
  else
    ui_line "Status: package present"
  fi
  ui_line "No extraction was attempted."
  ui_line "No restore was attempted."
  ui_line "No secrets, DNS/cutover, or compose up were attempted."
  return 2
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
  ui_phase "PREVIEW"
  ui_header "apply mode preview"
  ui_whisper "minimal actions in V0"
  ui_line "selected modules: $1"
  ui_separator "progress"
  ui_line "[1/4] detect system"
  ui_line "[2/4] prepare plan"
  ui_line "[3/4] confirm safe steps"
  ui_line "[4/4] apply"
}

show_apply_summary() {
  ui_phase "APPLY COMPLETE"
  ui_line "Modules: ${APPLY_DONE_MODULES:-$APPLY_MODULES}"
  ui_line "Changed: install-only packages/services"
  ui_line "Not done: containers, secrets, reboot, network restart"
  ui_line "Next manual steps:"
  if [ -n "$APPLY_MANUAL_STEPS" ]; then
    printf '%s' "$APPLY_MANUAL_STEPS"
  else
    ui_line "  - none"
  fi
  ui_rule
}

run_apply_modules() {
  for module in $APPLY_MODULES; do
    case "$module" in
      git)
        apply_module_git
        ;;
      docker)
        apply_module_docker
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
    apply_note_module "$module"
  done
  show_apply_summary
}

show_ui_demo() {
  show_dashboard
}

show_plan() {
  plan_modules=${1:-$MODULES}

  show_dashboard

  if [ "${SEED_RUNTIME_MODE:-}" = "bootstrap" ]; then
    show_bootstrap_plan_summary
    echo
  fi

  ui_section "backend plan"
  backend_plan
  echo

  ui_section "modules"
  for module in $plan_modules; do
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
    shift
    if ! parse_plan_options "$@"; then
      exit 2
    fi
    if [ -n "$PLAN_PACKAGE_FILE" ]; then
      show_package_plan "$PLAN_PACKAGE_FILE"
      exit $?
    fi
    show_plan "$PLAN_MODULES"
    ;;
  --apply)
    shift
    if ! parse_apply_options "$@"; then
      exit 2
    fi
    if [ "$APPLY_AUTO" -eq 1 ]; then
      ui_whisper "auto-confirm mode requested"
    fi
    if [ -n "$APPLY_PACKAGE_FILE" ]; then
      show_package_apply_preview_only "$APPLY_PACKAGE_FILE" "${APPLY_COMPONENTS_FILTER:-all}"
      exit $?
    fi
    show_apply_preview "$APPLY_MODULES"
    if [ -z "$APPLY_MODULES" ]; then
      ui_line "no modules selected for apply: use --modules=git"
      exit 0
    fi
    APPLY_CONFIRM_TARGET="modules=$APPLY_MODULES"
    APPLY_CONFIRMED=0
    APPLY_DONE_MODULES=""
    APPLY_MANUAL_STEPS=""
    if ! apply_safe_confirm; then
      exit 2
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
  doctor)
    show_doctor
    ;;
  inspect)
    show_inspect
    ;;
  self-update)
    shift
    case "${1:-}" in
      --plan)
        show_self_update_plan
        ;;
      --apply)
        apply_self_update
        ;;
      *)
        echo "usage: sh seed-kit.sh self-update --plan" >&2
        echo "       sh seed-kit.sh self-update --apply" >&2
        exit 2
        ;;
    esac
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
  modules)
    shift
    case "${1:-}" in
      list)
        show_modules_dir_list
        ;;
      deps)
        shift
        if [ -z "${1:-}" ]; then
          echo "usage: sh seed-kit.sh modules deps <module>" >&2
          exit 2
        fi
        show_module_dependencies "$1"
        ;;
      *)
        echo "usage: sh seed-kit.sh modules list" >&2
        echo "       sh seed-kit.sh modules deps <module>" >&2
        exit 2
        ;;
    esac
    ;;
  package)
    shift
    case "${1:-}" in
      verify)
        shift
        if [ -z "${1:-}" ]; then
          echo "usage: sh seed-kit.sh package verify <file>" >&2
          exit 2
        fi
        verify_package_archive "$1"
        ;;
      stage)
        shift
        if [ -z "${1:-}" ]; then
          echo "usage: sh seed-kit.sh package stage <file>" >&2
          exit 2
        fi
        stage_package_archive "$1"
        ;;
      inspect-stage)
        shift
        if [ -z "${1:-}" ]; then
          echo "usage: sh seed-kit.sh package inspect-stage <dir>" >&2
          exit 2
        fi
        inspect_stage_package "$1"
        ;;
      apply-guided)
        shift
        if [ -z "${1:-}" ]; then
          echo "usage: sh seed-kit.sh package apply-guided <file>" >&2
          exit 2
        fi
        package_file=$1
        guided_step=preview
        shift
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --step)
              if [ -z "${2:-}" ]; then
                echo "missing value for --step" >&2
                exit 2
              fi
              guided_step="${2:-}"
              shift 2
              ;;
            --step=*)
              guided_step="${1#--step=}"
              shift
              ;;
            --verbose)
              SEED_KIT_VERBOSE=1
              export SEED_KIT_VERBOSE
              shift
              ;;
            *)
              echo "unknown option for package apply-guided: $1" >&2
              exit 2
              ;;
          esac
        done
        apply_guided_package "$package_file" "$guided_step"
        ;;
      *)
        echo "usage: sh seed-kit.sh package verify <file>" >&2
        echo "       sh seed-kit.sh package stage <file>" >&2
        echo "       sh seed-kit.sh package inspect-stage <dir>" >&2
        echo "       sh seed-kit.sh package apply-guided <file>" >&2
        exit 2
        ;;
    esac
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
