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
  target_rel_path="${4:-$rel_path}"

  source_path="$source_root/$rel_path"
  target_path="$staging_dir/$target_rel_path"

  if [ ! -e "$source_path" ]; then
    echo "missing: $rel_path"
    return 0
  fi

  if [ -d "$source_path" ]; then
    (
      cd "$source_path"
      find . \
        \( -name log -o -name logs -o -name cache -o -name caches \) -prune \
        -o -type f ! -name .env ! -name '*.log' -print | while IFS= read -r item; do
          clean_item="${item#./}"
          mkdir -p "$(dirname "$target_path/$clean_item")"
          cp "$clean_item" "$target_path/$clean_item"
        done
    )
  else
    case "$source_path" in
      *.log)
        echo "skipped runtime: $rel_path"
        return 0
        ;;
    esac
    mkdir -p "$(dirname "$target_path")"
    cp "$source_path" "$target_path"
  fi
  echo "copied: $rel_path -> $target_rel_path"
}

write_manifest() {
  manifest="$1"
  service="$2"
  source_dir="$3"

  {
    echo "service-name: $service"
    echo "package-id: rpi-edge-service"
    echo "profile-id: rpi-edge"
    echo "format-version: 1"
    echo "generated-by: seed-kit"
    echo "generated-at: $(timestamp_utc)"
    echo "reconstruction-mode: manual"
    echo "mode: dry-run"
    echo "source: $source_dir"
    echo "restore-supported: no"
    echo "cloud-upload: no"
    echo "secrets-included: no"
    echo "human-steps:"
    echo "  - review-secrets"
    echo "  - reconnect-identities"
    echo "  - review-hostname"
    echo "  - validate-ssh-trust"
    echo "  - dns-cutover"
    echo "manual-secrets:"
    echo "  - .env"
    echo "  - machine-id"
    echo "  - ssh-host-keys"
    echo "  - tailscale-state"
    echo "  - cloudflare-credentials"
    echo "  - tokens-api-keys"
    echo "  - service-credentials"
    echo
    echo "included-paths:"
    echo "  - seed-kit-package.sh"
    echo "  - profiles/rpi-edge.profile"
    echo "  - services/docker-compose.yml"
    echo "  - configs/caddy"
    echo "  - configs/homepage"
    echo "  - docs/reconstruction.txt"
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

write_package_descriptor() {
  descriptor="$1"

  {
    echo 'PACKAGE_ID="rpi-edge-service"'
    echo 'PROFILE_ID="rpi-edge"'
    echo 'SYSTEM="docker tailscale cloudflared"'
    echo 'MODULES=""'
    echo 'SERVICES="caddy homepage"'
    echo 'MANUAL_IDENTITIES="tailscale cloudflared"'
    echo 'HUMAN_STEPS="review-secrets reconnect-identities review-hostname validate-ssh-trust dns-cutover"'
    echo 'MANUAL_SECRETS="env machine-id ssh-host-keys tailscale-state cloudflare-credentials tokens-api-keys service-credentials"'
    echo 'SECRETS_POLICY="manual-reconnect"'
  } > "$descriptor"
}

write_profile() {
  profile="$1"

  {
    echo 'PROFILE_ID="rpi-edge"'
    echo 'NODE_ROLE="edge-service"'
    echo 'SYSTEM="docker tailscale cloudflared"'
    echo 'MODULES=""'
    echo 'SERVICES="caddy homepage"'
    echo 'MANUAL_IDENTITIES="tailscale cloudflared"'
    echo 'RECONSTRUCTION_MODE="manual"'
  } > "$profile"
}

transform_compose_for_deploy() {
  src_file=$1
  dst_file=$2

  if [ ! -f "$src_file" ]; then
    echo "transform compose: source missing: $src_file" >&2
    return 2
  fi

  tmp_file="${dst_file}.seed-kit-compose-tmp.$$"

  sed -e 's#\./\./config/caddy/Caddyfile#./Caddyfile#g' \
    -e 's#\.\./config/caddy/Caddyfile#./Caddyfile#g' \
    -e 's#\./\./config/homepage#./homepage#g' \
    -e 's#\.\./config/homepage#./homepage#g' \
    -e 's#${TAILSCALE_IP:-100\.110\.92\.41}#${TAILSCALE_IP:-127.0.0.1}#g' \
    -e 's#100\.110\.92\.41#127.0.0.1#g' \
    "$src_file" > "$tmp_file"

  mv "$tmp_file" "$dst_file"
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
  staging_name="rpi-edge-service"
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

  mkdir -p "$staging_dir/services" "$staging_dir/configs" "$staging_dir/docs" "$staging_dir/profiles"

  write_manifest "$staging_dir/MANIFEST.txt" "rpi-edge-vps" "$source_dir"
  write_package_descriptor "$staging_dir/seed-kit-package.sh"
  write_profile "$staging_dir/profiles/rpi-edge.profile"

  if copy_allowed_path "$source_dir" "$staging_dir" "compose/docker-compose.yml" "services/docker-compose.yml"; then
    transform_compose_for_deploy "$staging_dir/services/docker-compose.yml" "$staging_dir/services/docker-compose.yml"
  fi
  copy_allowed_path "$source_dir" "$staging_dir" "config/caddy" "configs/caddy"
  copy_allowed_path "$source_dir" "$staging_dir" "config/homepage" "configs/homepage"

  {
    echo "rpi-edge-vps reconstruction notes"
    echo
    echo "- restore compose/config manually"
    echo "- review .env outside this package"
    echo "- reconnect Tailscale manually"
    echo "- reconnect Cloudflare manually"
    echo "- validate services before production cutover"
  } > "$staging_dir/docs/reconstruction.txt"

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
  echo "  seed-kit-package.sh"
  echo "  profiles/"
  echo "  services/"
  echo "  configs/"
  echo "  docs/"
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
