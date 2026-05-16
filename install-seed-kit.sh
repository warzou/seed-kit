#!/bin/sh

set -eu

REPO_URL="https://github.com/warzou/seed-kit.git"
TARGET_DIR="${HOME:-}/seed-kit"
DRY_RUN="no"

log() {
  printf '%s\n' "$*"
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Seed-Kit installer

Usage:
  sh install-seed-kit.sh [--dry-run] [--target <dir>]

What it does:
  - installs only minimal prerequisites when missing
  - clones Seed-Kit to ~/seed-kit when absent
  - updates an existing clean checkout with git pull --ff-only
  - runs ~/seed-kit/seed-kit.sh

Scope:
  - Debian / Raspberry Pi OS with apt-get
  - no Docker install
  - no Tailscale install
  - no Cloudflare install
  - no restore
  - no secrets
  - no reboot
EOF
}

run() {
  log "+ $*"
  if [ "$DRY_RUN" = "yes" ]; then
    return 0
  fi
  "$@"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

sudo_cmd() {
  if [ "$(id -u)" -eq 0 ]; then
    printf '%s\n' ""
    return 0
  fi

  have sudo || die "sudo is required to install missing prerequisites"
  printf '%s\n' "sudo"
}

install_prerequisites() {
  missing=""

  have git || missing="$missing git"

  if ! dpkg-query -W -f='${Status}' ca-certificates 2>/dev/null | grep -q 'install ok installed'; then
    missing="$missing ca-certificates"
  fi

  if ! have wget && ! have curl; then
    missing="$missing wget"
  fi

  if [ -z "$missing" ]; then
    log "[ok] prerequisites present"
    return 0
  fi

  have apt-get || die "apt-get is required to install missing prerequisites on this installer path"

  SUDO=$(sudo_cmd)
  log "[install] missing prerequisites:$missing"
  run $SUDO apt-get update
  run $SUDO apt-get install -y $missing
}

ensure_clean_checkout() {
  repo_dir=$1

  if [ ! -d "$repo_dir/.git" ]; then
    die "target exists but is not a git checkout: $repo_dir"
  fi

  status=$(cd "$repo_dir" && git status --porcelain)
  if [ -n "$status" ]; then
    cat >&2 <<EOF
Seed-Kit checkout has local changes:
  $repo_dir

Installer stopped to avoid overwriting local work.
Review the changes, commit/stash them, or choose another target with:
  sh install-seed-kit.sh --target <dir>
EOF
    exit 1
  fi
}

clone_or_update() {
  if [ -d "$TARGET_DIR/.git" ]; then
    log "[repo] existing checkout: $TARGET_DIR"
    ensure_clean_checkout "$TARGET_DIR"
    run git -C "$TARGET_DIR" fetch origin
    run git -C "$TARGET_DIR" pull --ff-only
    return 0
  fi

  if [ -e "$TARGET_DIR" ]; then
    die "target exists but is not a Seed-Kit git checkout: $TARGET_DIR"
  fi

  log "[repo] clone Seed-Kit to: $TARGET_DIR"
  run git clone "$REPO_URL" "$TARGET_DIR"
}

run_seed_kit() {
  script="$TARGET_DIR/seed-kit.sh"

  log
  log "----------------------------------------"
  log "Seed-Kit ready"
  log "Location: $TARGET_DIR"
  log "Launching runtime..."
  log "----------------------------------------"
  log "[run] sh $script"
  if [ "$DRY_RUN" = "yes" ]; then
    return 0
  fi

  if [ ! -f "$script" ]; then
    die "Seed-Kit entrypoint not found: $script"
  fi

  sh "$script"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN="yes"
      shift
      ;;
    --target)
      TARGET_DIR="${2:-}"
      [ -n "$TARGET_DIR" ] || die "missing value for --target"
      shift 2
      ;;
    --help|-h|help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown option: $1"
      ;;
  esac
done

[ -n "${HOME:-}" ] || die "HOME is required"
[ -n "$TARGET_DIR" ] || die "target directory is required"

log "Seed-Kit installer"
log "Target: $TARGET_DIR"
log "Scope: install minimal prerequisites, clone/update repo, run seed-kit.sh"
log

install_prerequisites
clone_or_update
run_seed_kit
