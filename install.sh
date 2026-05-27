#!/bin/sh
set -eu

repo_url="${SEED_KIT_REPO_URL:-https://github.com/warzou/seed-kit.git}"
branch="${SEED_KIT_BRANCH:-wifi-kit-work}"
target_dir="${SEED_KIT_DIR:-$HOME/seed-kit}"

usage() {
  cat <<'EOF'
Seed-Kit bootstrap installer

Usage:
  sh install.sh

Environment:
  SEED_KIT_REPO_URL   Git repository URL. Default: https://github.com/warzou/seed-kit.git
  SEED_KIT_BRANCH     Git branch to checkout. Default: wifi-kit-work
  SEED_KIT_DIR        Target directory. Default: ~/seed-kit

This script prepares the Seed-Kit checkout, then asks before running:
  sh seed-kit.sh install wifi-kit

It does not reboot, shut down, restart NetworkManager, start AP recovery,
or change Wi-Fi settings by itself.
EOF
}

prompt_yes() {
  prompt=$1
  printf '%s [y/N] ' "$prompt"
  IFS= read -r answer || answer=
  case "$answer" in
    y|Y) return 0 ;;
    *) return 1 ;;
  esac
}

find_git() {
  if command -v git >/dev/null 2>&1; then
    command -v git
    return 0
  fi
  return 1
}

install_git_prompt() {
  if find_git >/dev/null 2>&1; then
    return 0
  fi

  echo "[seed-kit] git is required to clone or update Seed-Kit."
  if [ ! -r /etc/os-release ]; then
    echo "[seed-kit] cannot detect OS package manager. Install git manually, then rerun this script." >&2
    return 1
  fi
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "[seed-kit] apt-get not found. Install git manually, then rerun this script." >&2
    return 1
  fi
  if ! prompt_yes "Install git with apt now?"; then
    echo "[seed-kit] aborted: git missing"
    return 1
  fi
  if ! command -v sudo >/dev/null 2>&1; then
    echo "[seed-kit] sudo is required to install git." >&2
    return 1
  fi
  sudo apt-get update
  sudo apt-get install -y git
}

prepare_checkout() {
  git_bin=$(find_git)
  if [ -d "$target_dir/.git" ]; then
    echo "[seed-kit] updating existing checkout: $target_dir"
    "$git_bin" -C "$target_dir" fetch origin "$branch"
    "$git_bin" -C "$target_dir" checkout "$branch"
    "$git_bin" -C "$target_dir" pull --ff-only origin "$branch"
    return 0
  fi
  if [ -e "$target_dir" ]; then
    echo "[seed-kit] target exists but is not a Git checkout: $target_dir" >&2
    echo "[seed-kit] choose another SEED_KIT_DIR or move the existing path." >&2
    return 1
  fi
  echo "[seed-kit] cloning $repo_url branch $branch into $target_dir"
  "$git_bin" clone --branch "$branch" "$repo_url" "$target_dir"
}

show_next_steps() {
  echo
  echo "[seed-kit] ready"
  echo "  directory: $target_dir"
  echo "  branch:    $branch"
  echo
  echo "Next command:"
  echo "  cd $target_dir"
  echo "  sh seed-kit.sh install wifi-kit"
  echo
  echo "Safety notes:"
  echo "  - Wifi-Kit install applies wifi-stability first on Raspberry Pi targets."
  echo "  - No reboot or NetworkManager restart is expected."
  echo "  - Do not start AP/recovery tests until the normal UI is validated."
}

case "${1:-}" in
  -h|--help|help)
    usage
    exit 0
    ;;
  "")
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

install_git_prompt
prepare_checkout
show_next_steps

if prompt_yes "Run Wifi-Kit install now?"; then
  cd "$target_dir"
  sh seed-kit.sh install wifi-kit
else
  echo "[seed-kit] install not started"
fi
