#!/bin/sh

set -eu

project_dir="${PROFILE_STATE_PROJECT_DIR:-$HOME/git/rpi-edge-vps}"

public_project_paths="$project_dir"

manual_restore_paths="$project_dir/docker-compose.yml
$project_dir/compose.yml
$project_dir/compose/docker-compose.yml
$project_dir/compose/docker-compose.example.yml
$project_dir/config/caddy
$project_dir/config/homepage
/etc/caddy
/etc/cloudflared
/srv/seed-kit/homer
/srv/seed-kit/homepage
/opt/seed-kit"

sensitive_candidate_paths="$project_dir/.env
$HOME/.config/rclone"

docker_volume_names="rpi-edge-vps_caddy_data
rpi-edge-vps_caddy_config"

do_not_clone_paths="/etc/machine-id
/etc/ssh/ssh_host_rsa_key
/etc/ssh/ssh_host_ecdsa_key
/etc/ssh/ssh_host_ed25519_key
/var/lib/tailscale/tailscaled.state"

usage() {
  echo "Usage:"
  echo "  sh tools/profile-state.sh plan"
  echo "  sh tools/profile-state.sh inventory"
  echo "  sh tools/profile-state.sh backup --dry-run"
  echo "  sh tools/profile-state.sh backup --local --dry-run"
}

show_plan() {
  echo "profile-state V0"
  echo
  echo "Purpose:"
  echo "  prepare a local-only private state backup flow for Seed-Kit nodes"
  echo
  echo "V0 behavior:"
  echo "  plan: explain intended future backup/restore boundaries"
  echo "  inventory: list categorized candidate paths read-only"
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

path_size() {
  path="$1"
  du -sh "$path" 2>/dev/null | awk '{print $1}' || echo "unknown"
}

path_size_kb() {
  path="$1"
  du -sk "$path" 2>/dev/null | awk '{print $1}' || echo 0
}

print_archive_path() {
  category="$1"
  path="$2"
  note="$3"
  include_policy="$4"

  if [ -e "$path" ]; then
    status="present"
    size="$(path_size "$path")"
  else
    status="missing"
    size="0"
  fi

  echo "  - path: $path"
  echo "    category: $category"
  echo "    status: $status"
  echo "    size: $size"
  echo "    note: $note"
  echo "    policy: $include_policy"
}

print_archive_paths() {
  category="$1"
  paths="$2"
  note="$3"
  include_policy="$4"

  printf '%s\n' "$paths" | while IFS= read -r path; do
    [ -n "$path" ] || continue
    print_archive_path "$category" "$path" "$note" "$include_policy"
  done
}

sum_existing_kb() {
  paths="$1"
  printf '%s\n' "$paths" | while IFS= read -r path; do
    [ -n "$path" ] || continue
    if [ -e "$path" ]; then
      path_size_kb "$path"
    fi
  done | awk '{total += $1} END {print total + 0}'
}

show_path() {
  category="$1"
  path="$2"
  note="$3"

  if [ -e "$path" ]; then
    echo "  present [$category]: $path"
    echo "    size: $(path_size "$path")"
    echo "    note: $note"
  else
    echo "  missing [$category]: $path"
    echo "    note: $note"
  fi
}

show_paths() {
  category="$1"
  paths="$2"
  note="$3"

  printf '%s\n' "$paths" | while IFS= read -r path; do
    [ -n "$path" ] || continue
    show_path "$category" "$path" "$note"
  done
}

show_docker_volumes() {
  if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    printf '%s\n' "$docker_volume_names" | while IFS= read -r volume; do
      [ -n "$volume" ] || continue
      echo "  unknown [docker-volume]: $volume"
      echo "    note: docker unavailable to current user"
    done
    return 0
  fi

  printf '%s\n' "$docker_volume_names" | while IFS= read -r volume; do
    [ -n "$volume" ] || continue
    if mountpoint="$(docker volume inspect "$volume" --format '{{ .Mountpoint }}' 2>/dev/null)" && [ -n "$mountpoint" ]; then
      echo "  present [docker-volume]: $volume"
      echo "    mountpoint: $mountpoint"
      if [ -e "$mountpoint" ]; then
        echo "    size: $(path_size "$mountpoint")"
      fi
      echo "    note: encrypted backup candidate; may contain runtime service state"
    else
      echo "  missing [docker-volume]: $volume"
      echo "    note: docker volume not found or not readable by current user"
    fi
  done
}

list_inventory() {
  echo "profile-state inventory"
  echo
  echo "public-project:"
  show_paths "public-project" "$public_project_paths" "repo-backed project files; review before backup"
  echo
  echo "manual-restore:"
  show_paths "manual-restore" "$manual_restore_paths" "restore manually and validate before production cutover"
  echo
  echo "sensitive:"
  show_paths "sensitive" "$sensitive_candidate_paths" "encrypted backup candidate only; do not print contents"
  echo
  echo "docker-volume:"
  show_docker_volumes
  echo
  echo "do-not-clone:"
  show_paths "do-not-clone" "$do_not_clone_paths" "unique node identity; do not duplicate blindly"
}

backup_dry_run() {
  echo "profile-state backup local dry-run"
  echo
  echo "archive plan only"
  echo "no archive created"
  echo "no secret content read"
  echo
  echo "would include:"
  echo
  echo "public-project:"
  print_archive_paths "public-project" "$public_project_paths" "repo-backed project files; review before backup" "include if present"
  echo
  echo "manual-restore:"
  print_archive_paths "manual-restore" "$manual_restore_paths" "restore inputs only; not auto-applied" "include if present"
  echo
  echo "sensitive:"
  print_archive_paths "sensitive" "$sensitive_candidate_paths" "private state; do not print contents" "include only in encrypted archive"
  echo
  echo "docker-volume:"
  show_docker_volumes
  echo
  echo "would NOT be included:"
  print_archive_paths "do-not-clone" "$do_not_clone_paths" "unique per-node identity; regenerate or reconnect manually" "exclude always"
  echo
  public_kb="$(sum_existing_kb "$public_project_paths")"
  manual_kb="$(sum_existing_kb "$manual_restore_paths")"
  sensitive_kb="$(sum_existing_kb "$sensitive_candidate_paths")"
  total_kb=$((public_kb + manual_kb + sensitive_kb))
  echo "summary:"
  echo "  estimated local file size: ${total_kb}K"
  echo "  would require encryption: yes"
  echo "  archive created: no"
  echo "  restore performed: no"
  echo "  cloud upload: no"
  echo "  rclone used: no"
}

case "${1:-}" in
  plan)
    show_plan
    ;;
  inventory)
    list_inventory
    ;;
  backup)
    case "${2:-} ${3:-}" in
      "--local --dry-run")
        backup_dry_run
        ;;
      "--dry-run ")
        backup_dry_run
        ;;
      *)
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
