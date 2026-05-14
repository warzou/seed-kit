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
  echo "  sh tools/profile-state.sh snapshot --local --dry-run --output <dir>"
  echo "  sh tools/profile-state.sh package --local --dry-run --output <dir>"
  echo "  sh tools/profile-state.sh package --verify --input <tar>"
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

timestamp_utc() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
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

write_snapshot_paths() {
  file="$1"
  category="$2"
  paths="$3"
  note="$4"
  policy="$5"

  printf '%s\n' "$paths" | while IFS= read -r path; do
    [ -n "$path" ] || continue
    if [ -e "$path" ]; then
      status="present"
      size="$(path_size "$path")"
    else
      status="missing"
      size="0"
    fi
    {
      echo "path=$path"
      echo "category=$category"
      echo "status=$status"
      echo "size=$size"
      echo "note=$note"
      echo "policy=$policy"
      echo
    } >> "$file"
  done
}

safe_snapshot_output_dir() {
  output_dir="$1"

  [ -n "$output_dir" ] || return 1

  case "$output_dir" in
    /|/home|/home/|"$HOME"|"$HOME/"|/etc|/etc/|/var|/var/|/usr|/usr/|/opt|/opt/)
      return 1
      ;;
  esac

  return 0
}

snapshot_local_dry_run() {
  output_dir="$1"

  if ! safe_snapshot_output_dir "$output_dir"; then
    echo "unsafe or missing --output: $output_dir" >&2
    echo "choose an explicit test directory, for example /tmp/seed-kit-profile-state-snapshot" >&2
    return 2
  fi

  mkdir -p "$output_dir"
  mkdir -p "$output_dir/inventory" \
    "$output_dir/projects" \
    "$output_dir/configs" \
    "$output_dir/docker-volumes" \
    "$output_dir/manual" \
    "$output_dir/excluded"

  manifest="$output_dir/MANIFEST.txt"
  inventory_file="$output_dir/inventory/classification.txt"
  manual_file="$output_dir/manual/restore-notes.txt"
  excluded_file="$output_dir/excluded/do-not-clone.txt"
  sums_file="$output_dir/SHA256SUMS"

  {
    echo "profile-state snapshot dry-run"
    echo "PROFILE_STATE_FORMAT_VERSION=1"
    echo "GENERATED_AT=$(timestamp_utc)"
    echo "TOOL=profile-state.sh"
    echo "MODE=safe-dry-run"
    echo "ARCHIVE=unencrypted-tar"
    echo "RESTORE_SUPPORTED=no"
    echo "CLOUD_SUPPORTED=no"
    echo "SECRETS_INCLUDED=no"
    echo "mode=local"
    echo "dry_run=true"
    echo "archive_created=false"
    echo "encryption_performed=false"
    echo "restore_performed=false"
    echo "secret_content_read=false"
    echo "cloud_upload=false"
    echo
    echo "This directory is a preview manifest only."
    echo "No project files, .env files, host identity files, Tailscale state, or Docker volumes are copied."
  } > "$manifest"

  {
    echo "profile-state classification"
    echo
  } > "$inventory_file"
  write_snapshot_paths "$inventory_file" "public-project" "$public_project_paths" "repo-backed project files; review before backup" "manifest only; no copy"
  write_snapshot_paths "$inventory_file" "manual-restore" "$manual_restore_paths" "restore inputs only; not auto-applied" "manifest only; no copy"
  write_snapshot_paths "$inventory_file" "sensitive" "$sensitive_candidate_paths" "private state; do not print contents" "encrypted archive required; no copy"

  {
    echo "manual restore notes"
    echo
    echo "- review rpi-edge-vps project files before restore"
    echo "- restore .env only from an encrypted archive"
    echo "- reconnect Tailscale manually"
    echo "- authenticate Cloudflare manually"
    echo "- validate Caddy and Homepage before production cutover"
    echo "- do not run docker compose up from this dry-run"
  } > "$manual_file"

  {
    echo "do-not-clone"
    echo
  } > "$excluded_file"
  write_snapshot_paths "$excluded_file" "do-not-clone" "$do_not_clone_paths" "unique node identity; regenerate or reconnect manually" "exclude always"

  if command -v sha256sum >/dev/null 2>&1; then
    (
      cd "$output_dir"
      sha256sum MANIFEST.txt inventory/classification.txt manual/restore-notes.txt excluded/do-not-clone.txt
    ) > "$sums_file"
  else
    {
      echo "sha256sum unavailable"
      echo "checksums not generated"
    } > "$sums_file"
  fi

  echo "profile-state snapshot local dry-run"
  echo "output: $output_dir"
  echo "created:"
  echo "  MANIFEST.txt"
  echo "  SHA256SUMS"
  echo "  inventory/"
  echo "  projects/"
  echo "  configs/"
  echo "  docker-volumes/"
  echo "  manual/"
  echo "  excluded/"
  echo
  echo "summary:"
  echo "  archive created: no"
  echo "  encryption performed: no"
  echo "  restore performed: no"
  echo "  secret content read: no"
  echo "  sensitive files copied: no"
  echo "  do-not-clone files copied: no"
}

package_local_dry_run() {
  output_dir="$1"

  if ! safe_snapshot_output_dir "$output_dir"; then
    echo "unsafe or missing --output: $output_dir" >&2
    echo "choose an explicit test directory, for example /tmp/seed-kit-profile-state-package" >&2
    return 2
  fi

  snapshot_local_dry_run "$output_dir"

  tar_file="$output_dir/profile-state-snapshot.tar"
  if [ -e "$tar_file" ]; then
    echo "refusing to overwrite existing package: $tar_file" >&2
    return 2
  fi

  (
    cd "$output_dir"
    tar -cf "profile-state-snapshot.tar" \
      MANIFEST.txt \
      SHA256SUMS \
      inventory \
      projects \
      configs \
      docker-volumes \
      manual \
      excluded
  )

  echo
  echo "profile-state package local dry-run"
  echo "mode: SAFE / DRY-RUN / UNENCRYPTED"
  echo "package: $tar_file"
  echo "size: $(path_size "$tar_file")"
  echo
  echo "summary:"
  echo "  archive created: yes, local tar preview only"
  echo "  compression: none"
  echo "  encryption performed: no"
  echo "  restore performed: no"
  echo "  secret content read: no"
  echo "  sensitive files copied: no"
  echo "  do-not-clone files copied: no"
  echo "  cloud upload: no"
}

tar_contains_entry() {
  tar_file="$1"
  entry="$2"
  tar -tf "$tar_file" | while IFS= read -r item; do
    case "$item" in
      "$entry"|"$entry"/)
        echo yes
        break
        ;;
    esac
  done | grep -q yes
}

verify_tar_paths_safe() {
  tar_file="$1"
  tar -tf "$tar_file" | while IFS= read -r item; do
    case "$item" in
      /*|*../*|../*|*.env|*/.env|*ssh_host_*|*machine-id*|*tailscaled.state*)
        echo "unsafe tar entry: $item" >&2
        return 1
        ;;
    esac
  done
}

package_verify() {
  input_tar="$1"
  errors=0
  verify_tmp_dir=""

  if [ -z "$input_tar" ]; then
    echo "missing --input <tar>" >&2
    return 2
  fi

  if [ ! -f "$input_tar" ]; then
    echo "input tar not found: $input_tar" >&2
    return 2
  fi

  echo "profile-state package verify"
  echo "input: $input_tar"
  echo
  echo "contents:"
  tar -tf "$input_tar"
  echo

  path_errors=0
  if ! verify_tar_paths_safe "$input_tar"; then
    path_errors=1
    errors=$((errors + 1))
  fi

  for entry in MANIFEST.txt SHA256SUMS inventory manual excluded; do
    if tar_contains_entry "$input_tar" "$entry"; then
      echo "present: $entry"
    else
      echo "missing: $entry"
      errors=$((errors + 1))
    fi
  done

  if [ "$path_errors" -eq 0 ]; then
    echo "path safety: OK"
  else
    echo "path safety: ERROR"
  fi

  if ! command -v mktemp >/dev/null 2>&1; then
    echo "temporary verify directory unavailable: mktemp missing" >&2
    errors=$((errors + 1))
  elif [ "$errors" -eq 0 ]; then
    verify_tmp_dir="$(TMPDIR=/tmp mktemp -d -t profile-state-verify.XXXXXX)"
    case "$verify_tmp_dir" in
      /tmp/*)
        ;;
      *)
        echo "temporary verify directory unsafe: $verify_tmp_dir" >&2
        errors=$((errors + 1))
        ;;
    esac

    if [ -z "$verify_tmp_dir" ] || [ ! -d "$verify_tmp_dir" ]; then
      echo "temporary verify directory unavailable" >&2
      errors=$((errors + 1))
    fi

    trap 'rm -rf "$verify_tmp_dir"' EXIT HUP INT TERM

    if [ "$errors" -eq 0 ] && (
      cd "$verify_tmp_dir"
      tar -xf "$input_tar"
    ); then
      echo "extraction: OK"
    elif [ "$errors" -eq 0 ]; then
      echo "extraction: ERROR"
      errors=$((errors + 1))
    fi

    if [ "$errors" -eq 0 ]; then
      if grep -q '^PROFILE_STATE_FORMAT_VERSION=1$' "$verify_tmp_dir/MANIFEST.txt"; then
        echo "format version: 1"
      elif grep -q '^PROFILE_STATE_FORMAT_VERSION=' "$verify_tmp_dir/MANIFEST.txt"; then
        echo "format version: ERROR unsupported"
        errors=$((errors + 1))
      else
        echo "format version: ERROR missing"
        errors=$((errors + 1))
      fi
    fi

    if [ "$errors" -eq 0 ]; then
      if [ ! -f "$verify_tmp_dir/SHA256SUMS" ]; then
        echo "checksum: ERROR missing SHA256SUMS"
        errors=$((errors + 1))
      elif command -v sha256sum >/dev/null 2>&1; then
        if (
          cd "$verify_tmp_dir"
          sha256sum -c SHA256SUMS
        ); then
          echo "checksum: OK"
        else
          echo "checksum: ERROR"
          errors=$((errors + 1))
        fi
      else
        echo "checksum: WARNING sha256sum unavailable, skipped"
      fi
    fi
  fi

  echo
  if [ "$errors" -eq 0 ]; then
    echo "SAFE VERIFY OK"
    return 0
  fi

  echo "SAFE VERIFY ERROR"
  return 1
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
  snapshot)
    case "${2:-} ${3:-}" in
      "--local --dry-run")
        output_dir=""
        shift 3
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --output)
              output_dir="${2:-}"
              shift 2
              ;;
            *)
              usage >&2
              exit 2
              ;;
          esac
        done
        snapshot_local_dry_run "$output_dir"
        ;;
      *)
        usage >&2
        exit 2
        ;;
    esac
    ;;
  package)
    case "${2:-} ${3:-}" in
      "--local --dry-run")
        output_dir=""
        shift 3
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --output)
              output_dir="${2:-}"
              shift 2
              ;;
            *)
              usage >&2
              exit 2
              ;;
          esac
        done
        package_local_dry_run "$output_dir"
        ;;
      "--verify --input")
        package_verify "${4:-}"
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
