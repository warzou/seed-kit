#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

. "$ROOT_DIR/lib/os.sh"
. "$ROOT_DIR/lib/ui.sh"

MODULES="git docker tailscale homepage"

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

  if [ ! -f "$module_file" ]; then
    ui_line "Missing module: $module"
    return 1
  fi

  # shellcheck source=/dev/null
  . "$module_file"
  "module_${module}_plan"
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

docker_status() {
  if command -v docker >/dev/null 2>&1; then
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

apply_module_git() {
  ui_line "[git] checking installation"
  if command -v git >/dev/null 2>&1; then
    ui_line "[git] already installed"
    return 0
  fi

  if ! is_debian_like; then
    echo "[git] unsupported OS for apply: $SEED_OS_NAME" >&2
    return 2
  fi

  if ! apply_safe_confirm; then
    return 2
  fi

  ui_line "[git] install via apt"
  if [ "$(id -u)" -ne 0 ]; then
    if ! command -v sudo >/dev/null 2>&1; then
      echo "[git] sudo required for apt install (not running as root)" >&2
      return 3
    fi
    SUDO=sudo
  else
    SUDO=
  fi

  ui_line "[git] running apt-get update"
  if ! $SUDO apt-get update; then
    echo "[git] apt-get update failed" >&2
    return 4
  fi

  ui_line "[git] running apt-get install"
  if ! $SUDO apt-get install -y git; then
    echo "[git] apt-get install failed" >&2
    return 5
  fi

  ui_line "[git] verifying installation"
  if command -v git >/dev/null 2>&1; then
    ui_line "[git] installed"
    return 0
  fi

  echo "[git] post-install check failed: binary not found" >&2
  return 6
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

show_dashboard_cockpit() {
  ui_header "Seed-Kit" "machine-aware terminal companion"
  ui_card_pair \
    "machine" \
    "$SEED_OS_NAME" \
    "$(machine_model)" \
    "$(machine_ram) / $(machine_arch)" \
    "context" \
    "backend: $(backend_name)" \
    "mode: plan only" \
    "host: $(machine_hostname)"

  ui_separator "recommended setup"
  ui_status "Git" "$(command_status git)" "base tool"
  ui_status "Tailscale" "$(command_status tailscale)" "recommended"
  ui_status "Docker" "$(docker_status)" "optional on small machines"
  ui_status "Homepage" "later" "placeholder"

  ui_separator "suggested next step"
  ui_line "$(suggested_next_step)"
}

show_dashboard_focus() {
  ui_masthead "Seed-Kit" "calm machine setup" "$(machine_hostname) / $(backend_name) / plan only"

  ui_focus "suggested next step" "$(suggested_next_step)" "$SEED_OS_NAME / $(machine_ram)"

  ui_separator "machine"
  ui_kv "system" "$SEED_OS_NAME"
  ui_kv "model" "$(machine_model)"
  ui_kv "memory" "$(machine_ram)"

  ui_separator "readiness"
  ui_status "Git" "$(command_status git)" "base tool"
  ui_status "Tailscale" "$(command_status tailscale)" "recommended"
  ui_status "Docker" "$(docker_status)" "optional"
}

show_dashboard_split() {
  ui_masthead "Seed-Kit" "ambient terminal cockpit" ""
  ui_split_focus \
    "machine" \
    "$SEED_OS_NAME" \
    "$(machine_model) / $(machine_ram)" \
    "readiness" \
    "Git: $(status_word "$(command_status git)")" \
    "Tailscale: $(status_word "$(command_status tailscale)")" \
    "Docker: $(status_word "$(docker_status)")"

  ui_separator "next"
  ui_line "$(suggested_next_step)"
  ui_whisper "plan-only mode / no system changes"
}

show_dashboard() {
  case "${SEED_UI_STYLE:-split}" in
    focus)
      show_dashboard_focus
      ;;
    split)
      show_dashboard_split
      ;;
    cockpit|*)
      show_dashboard_cockpit
      ;;
  esac
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
  echo "  --detect         show OS detection details"
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
        ui_line "[tailscale] not implemented in V0"
        ;;
      homepage)
        ui_line "[homepage] not implemented in V0"
        ;;
      *)
        ui_line "unknown module: $module"
        ;;
    esac
  done
}

show_ui_demo() {
  old_style=${SEED_UI_STYLE:-cockpit}

  SEED_UI_STYLE=cockpit
  ui_separator "variant / cockpit"
  show_dashboard

  SEED_UI_STYLE=focus
  ui_separator "variant / focus"
  show_dashboard

  SEED_UI_STYLE=split
  ui_separator "variant / split"
  show_dashboard

  SEED_UI_STYLE=$old_style
}

show_plan() {
  show_dashboard

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
      ui_line "no modules selected for apply"
      exit 0
    fi
    run_apply_modules
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
