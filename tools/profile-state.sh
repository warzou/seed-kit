#!/bin/sh

set -eu

candidate_paths="/etc/caddy
/etc/cloudflared
/srv/seed-kit/homer
/srv/seed-kit/homepage
/opt/seed-kit"

sensitive_candidate_paths="$HOME/.config/rclone"

usage() {
  echo "Usage:"
  echo "  sh tools/profile-state.sh plan"
  echo "  sh tools/profile-state.sh inventory"
  echo "  sh tools/profile-state.sh backup --dry-run"
}

show_plan() {
  echo "profile-state V0"
  echo
  echo "Purpose:"
  echo "  prepare a local-only private state backup flow for Seed-Kit nodes"
  echo
  echo "V0 behavior:"
  echo "  plan: explain intended future backup/restore boundaries"
  echo "  inventory: list candidate paths read-only"
  echo "  backup --dry-run: show what would be included"
  echo
  echo "Not implemented in V0:"
  echo "  no archive creation"
  echo "  no restore"
  echo "  no encryption yet"
  echo "  no secret content reads"
  echo "  no cloud upload"
  echo
  echo "Encryption is required before any real backup containing private state leaves the node."
}

list_inventory() {
  echo "profile-state inventory"
  echo
  echo "candidate paths:"
  printf '%s\n' "$candidate_paths" | while IFS= read -r path; do
    if [ -e "$path" ]; then
      echo "  present: $path"
    else
      echo "  missing: $path"
    fi
  done
  echo
  echo "sensitive candidates, not included by default:"
  printf '%s\n' "$sensitive_candidate_paths" | while IFS= read -r path; do
    if [ -e "$path" ]; then
      echo "  present: $path"
    else
      echo "  missing: $path"
    fi
  done
}

backup_dry_run() {
  echo "profile-state backup dry-run"
  echo
  echo "would include existing candidate paths:"
  printf '%s\n' "$candidate_paths" | while IFS= read -r path; do
    if [ -e "$path" ]; then
      echo "  include: $path"
    fi
  done
  echo
  echo "would not include by default:"
  printf '%s\n' "$sensitive_candidate_paths" | while IFS= read -r path; do
    echo "  sensitive candidate: $path"
  done
  echo
  echo "no archive created"
  echo "no secret content read"
  echo "encryption required before real backup"
}

case "${1:-}" in
  plan)
    show_plan
    ;;
  inventory)
    list_inventory
    ;;
  backup)
    case "${2:-}" in
      --dry-run)
        backup_dry_run
        ;;
      *)
        usage >&2
        exit 2
        ;;
    esac
    ;;
  -h|--help|"")
    usage
    ;;
  *)
    echo "unknown command: $1" >&2
    usage >&2
    exit 2
    ;;
esac
