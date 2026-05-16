#!/bin/sh

set -eu

repo_url="https://github.com/warzou/seed-kit.git"
target_dir="$HOME/seed-kit"
assume_yes="no"

usage() {
  echo "Seed-Kit bootstrap"
  echo
  echo "Usage:"
  echo "  sh bootstrap.sh [--yes] [--target <dir>]"
  echo "  sh bootstrap.sh --help"
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
}

confirm_git_install() {
  if [ "$assume_yes" = "yes" ]; then
    return 0
  fi

  echo "git is missing."
  echo "Seed-Kit can install git with:"
  echo "  sudo apt update"
  echo "  sudo apt install -y git"
  printf "Continue? [y/N] "
  read answer
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

install_git_if_missing() {
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

  confirm_git_install
  echo "running: sudo apt update"
  sudo apt update
  echo "running: sudo apt install -y git"
  sudo apt install -y git
}

clone_or_update_seed_kit() {
  if [ -d "$target_dir/.git" ]; then
    echo "Seed-Kit repo: $target_dir"
    (
      cd "$target_dir"
      git fetch origin
      git pull --ff-only
    )
    return 0
  fi

  if [ -e "$target_dir" ]; then
    echo "target exists but is not a git checkout: $target_dir" >&2
    return 2
  fi

  echo "cloning Seed-Kit to: $target_dir"
  git clone "$repo_url" "$target_dir"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes|-y)
      assume_yes="yes"
      shift
      ;;
    --target)
      target_dir="${2:-}"
      if [ -z "$target_dir" ]; then
        echo "missing value for --target" >&2
        exit 2
      fi
      shift 2
      ;;
    --help|-h|help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

install_git_if_missing
clone_or_update_seed_kit

echo
echo "Seed-Kit is ready."
echo "Next commands:"
echo "  cd $target_dir"
echo "  sh seed-kit.sh doctor"
echo "  sh seed-kit.sh inspect"
