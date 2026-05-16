#!/bin/sh

set -eu

default_source_dir="/home/warzy/git/rpi-edge-vps"

usage() {
  echo "service-package"
  echo
  echo "Usage:"
  echo "  sh tools/service-package.sh create --service rpi-edge-vps --dry-run --output <dir> [--source <dir>]"
  echo
  echo "SAFE boundaries:"
  echo "  dry-run is required"
  echo "  no restore"
  echo "  no cloud"
  echo "  no secrets copied"
  echo "  only explicit service files are copied"
}

timestamp_utc() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

safe_output_dir() {
  output_dir="$1"

  [ -n "$output_dir" ] || return 1

  case "$output_dir" in
    /|/home|/home/|"$HOME"|"$HOME/"|/etc|/etc/|/var|/var/|/usr|/usr/|/opt|/opt/)
      return 1
      ;;
  esac

  return 0
}

copy_allowed_path() {
  source_root="$1"
  staging_dir="$2"
  rel_path="$3"

  source_path="$source_root/$rel_path"
  target_path="$staging_dir/$rel_path"

  if [ ! -e "$source_path" ]; then
    echo "missing: $rel_path"
    return 0
  fi

  mkdir -p "$(dirname "$target_path")"
  if [ -d "$source_path" ]; then
    cp -R "$source_path" "$target_path"
  else
    cp "$source_path" "$target_path"
  fi
  echo "copied: $rel_path"
}

write_manifest() {
  manifest="$1"
  service="$2"
  source_dir="$3"

  {
    echo "service-name: $service"
    echo "format-version: 1"
    echo "generated-by: seed-kit"
    echo "generated-at: $(timestamp_utc)"
    echo "reconstruction-mode: manual"
    echo "mode: dry-run"
    echo "source: $source_dir"
    echo "restore-supported: no"
    echo "cloud-upload: no"
    echo "secrets-included: no"
    echo
    echo "included-paths:"
    echo "  - compose/docker-compose.yml"
    echo "  - config/caddy"
    echo "  - config/homepage"
    echo
    echo "excluded:"
    echo "  - .env"
    echo "  - logs"
    echo "  - caches"
    echo "  - docker runtime"
    echo "  - docker images"
    echo "  - machine identity"
    echo "  - ssh host keys"
    echo "  - tailscale state"
    echo "  - cloudflare credentials"
    echo "  - tokens/api keys"
  } > "$manifest"
}

write_checksums() {
  staging_dir="$1"
  sums_file="$staging_dir/SHA256SUMS"

  if ! command -v sha256sum >/dev/null 2>&1; then
    {
      echo "sha256sum unavailable"
      echo "checksums not generated"
    } > "$sums_file"
    return 0
  fi

  (
    cd "$staging_dir"
    find . -type f ! -name SHA256SUMS | sed 's#^\./##' | sort | while IFS= read -r file; do
      sha256sum "$file"
    done
  ) > "$sums_file"
}

refuse_if_forbidden_staged() {
  staging_dir="$1"

  if find "$staging_dir" -name .env | grep -q .; then
    echo "refusing staged package containing .env" >&2
    return 1
  fi

  if find "$staging_dir" \( -name log -o -name logs -o -name cache -o -name caches -o -name '*.log' \) | grep -q .; then
    echo "refusing staged package containing logs/cache paths" >&2
    return 1
  fi

  return 0
}

create_archive_if_possible() {
  output_dir="$1"
  staging_name="$2"
  archive="$output_dir/$staging_name.tar.gz"

  if ! command -v tar >/dev/null 2>&1; then
    echo "archive: skipped, tar unavailable"
    return 0
  fi

  if [ -e "$archive" ]; then
    echo "refusing to overwrite existing archive: $archive" >&2
    return 2
  fi

  (
    cd "$output_dir"
    tar -czf "$archive" "$staging_name"
  )
  echo "archive: $archive"
}

create_rpi_edge_vps() {
  source_dir="$1"
  output_dir="$2"
  staging_name="rpi-edge-vps-service"
  staging_dir="$output_dir/$staging_name"

  if [ ! -d "$source_dir" ]; then
    echo "source directory not found: $source_dir" >&2
    return 2
  fi

  if ! safe_output_dir "$output_dir"; then
    echo "unsafe or missing --output: $output_dir" >&2
    echo "choose an explicit dry-run directory, for example /tmp/seed-kit-service-package" >&2
    return 2
  fi

  if [ -e "$staging_dir" ]; then
    echo "refusing to overwrite existing staging directory: $staging_dir" >&2
    return 2
  fi

  mkdir -p "$staging_dir/compose" "$staging_dir/config" "$staging_dir/notes"

  write_manifest "$staging_dir/MANIFEST.txt" "rpi-edge-vps" "$source_dir"

  copy_allowed_path "$source_dir" "$staging_dir" "compose/docker-compose.yml"
  copy_allowed_path "$source_dir" "$staging_dir" "config/caddy"
  copy_allowed_path "$source_dir" "$staging_dir" "config/homepage"

  {
    echo "rpi-edge-vps reconstruction notes"
    echo
    echo "- restore compose/config manually"
    echo "- review .env outside this package"
    echo "- reconnect Tailscale manually"
    echo "- reconnect Cloudflare manually"
    echo "- validate services before production cutover"
  } > "$staging_dir/notes/reconstruction.txt"

  refuse_if_forbidden_staged "$staging_dir"
  write_checksums "$staging_dir"

  echo "service-package create"
  echo "service: rpi-edge-vps"
  echo "mode: dry-run"
  echo "source: $source_dir"
  echo "staging: $staging_dir"
  echo
  echo "created:"
  echo "  MANIFEST.txt"
  echo "  SHA256SUMS"
  echo "  compose/"
  echo "  config/"
  echo "  notes/"
  echo
  echo "summary:"
  echo "  restore performed: no"
  echo "  cloud upload: no"
  echo "  secrets copied: no"
  echo "  docker runtime copied: no"

  create_archive_if_possible "$output_dir" "$staging_name"
}

cmd="${1:-}"
case "$cmd" in
  create)
    service=""
    dry_run="no"
    output_dir=""
    source_dir="${SERVICE_PACKAGE_SOURCE_DIR:-$default_source_dir}"
    shift

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --service)
          service="${2:-}"
          shift 2
          ;;
        --dry-run)
          dry_run="yes"
          shift
          ;;
        --output)
          output_dir="${2:-}"
          shift 2
          ;;
        --source)
          source_dir="${2:-}"
          shift 2
          ;;
        *)
          usage >&2
          exit 2
          ;;
      esac
    done

    if [ "$dry_run" != "yes" ]; then
      echo "refusing: --dry-run is required" >&2
      exit 2
    fi

    case "$service" in
      rpi-edge-vps)
        create_rpi_edge_vps "$source_dir" "$output_dir"
        ;;
      "")
        echo "missing --service" >&2
        usage >&2
        exit 2
        ;;
      *)
        echo "unknown service: $service" >&2
        exit 2
        ;;
    esac
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "unknown command: $cmd" >&2
    usage >&2
    exit 2
    ;;
esac
