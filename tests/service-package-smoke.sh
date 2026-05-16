#!/bin/sh

set -eu

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
service_package="$repo_dir/tools/service-package.sh"
tmp_root=""

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "OK: $*"
}

cleanup() {
  if [ -n "$tmp_root" ] && [ -d "$tmp_root" ]; then
    rm -rf "$tmp_root"
  fi
}

trap cleanup EXIT HUP INT TERM

if ! command -v mktemp >/dev/null 2>&1; then
  fail "mktemp is required"
fi

tmp_root="$(mktemp -d -t seed-kit-service-package-smoke.XXXXXX)"
case "$tmp_root" in
  /tmp/*)
    ;;
  *)
    fail "unsafe temporary directory: $tmp_root"
    ;;
esac

source_dir="$tmp_root/source"
output_dir="$tmp_root/output"
staging_dir="$output_dir/rpi-edge-vps-service"

mkdir -p "$source_dir/compose" "$source_dir/config/caddy" "$source_dir/config/homepage/logs" "$source_dir/config/homepage/cache" "$output_dir"
printf '%s\n' "services: {}" > "$source_dir/compose/docker-compose.yml"
printf '%s\n' ":80" > "$source_dir/config/caddy/Caddyfile"
printf '%s\n' "title: rpi-edge" > "$source_dir/config/homepage/settings.yaml"
printf '%s\n' "runtime log" > "$source_dir/config/homepage/logs/homepage.log"
printf '%s\n' "runtime cache" > "$source_dir/config/homepage/cache/data.txt"
printf '%s\n' "SECRET=refused" > "$source_dir/.env"

echo "service-package smoke"

sh -n "$service_package"
pass "service-package syntax"

if sh "$service_package" create --service rpi-edge-vps --output "$tmp_root/no-dry-run" --source "$source_dir" >/dev/null 2>&1; then
  fail "create without --dry-run should be refused"
fi
pass "dry-run required"

if sh "$service_package" create --service unknown --dry-run --output "$tmp_root/unknown" --source "$source_dir" >/dev/null 2>&1; then
  fail "unknown service should be refused"
fi
pass "unknown service refused"

create_output="$tmp_root/create-output.txt"
sh "$service_package" create --service rpi-edge-vps --dry-run --output "$output_dir" --source "$source_dir" > "$create_output"
grep -q '^service-package create$' "$create_output" || fail "missing create title"
grep -q '^service: rpi-edge-vps$' "$create_output" || fail "missing service name"
grep -q '^mode: dry-run$' "$create_output" || fail "missing dry-run mode"
pass "create dry-run"

[ -f "$staging_dir/MANIFEST.txt" ] || fail "missing MANIFEST.txt"
[ -f "$staging_dir/SHA256SUMS" ] || fail "missing SHA256SUMS"
[ -f "$staging_dir/compose/docker-compose.yml" ] || fail "missing compose file"
[ -f "$staging_dir/config/caddy/Caddyfile" ] || fail "missing caddy config"
[ -f "$staging_dir/config/homepage/settings.yaml" ] || fail "missing homepage config"
[ ! -e "$staging_dir/config/homepage/logs/homepage.log" ] || fail "homepage log was included"
[ ! -e "$staging_dir/config/homepage/cache/data.txt" ] || fail "homepage cache was included"
[ -f "$staging_dir/notes/reconstruction.txt" ] || fail "missing reconstruction notes"
pass "expected files generated"

grep -q '^service-name: rpi-edge-vps$' "$staging_dir/MANIFEST.txt" || fail "missing manifest service name"
grep -q '^format-version: 1$' "$staging_dir/MANIFEST.txt" || fail "missing manifest format version"
grep -q '^reconstruction-mode: manual$' "$staging_dir/MANIFEST.txt" || fail "missing manifest reconstruction mode"
pass "manifest content"

grep -q 'MANIFEST.txt' "$staging_dir/SHA256SUMS" || fail "missing manifest checksum"
grep -q 'compose/docker-compose.yml' "$staging_dir/SHA256SUMS" || fail "missing compose checksum"
pass "checksums content"

if find "$staging_dir" -name .env -type f | grep -q .; then
  fail ".env was included"
fi
pass ".env excluded"

bad_output="$tmp_root/output-residual-forbidden"
mkdir -p "$bad_output/rpi-edge-vps-service/logs"
printf '%s\n' "leftover" > "$bad_output/rpi-edge-vps-service/logs/homepage.log"
if sh "$service_package" create --service rpi-edge-vps --dry-run --output "$bad_output" --source "$source_dir" >/dev/null 2>&1; then
  fail "residual forbidden path should be refused"
fi
pass "residual forbidden paths refused"

if [ -f "$output_dir/rpi-edge-vps-service.tar.gz" ]; then
  tar -tzf "$output_dir/rpi-edge-vps-service.tar.gz" | grep -q 'rpi-edge-vps-service/MANIFEST.txt' || fail "archive missing manifest"
  if tar -tzf "$output_dir/rpi-edge-vps-service.tar.gz" | grep -q '\.env$'; then
    fail ".env was included in archive"
  fi
  if tar -tzf "$output_dir/rpi-edge-vps-service.tar.gz" | grep -q 'logs/homepage\.log$'; then
    fail "homepage log was included in archive"
  fi
  pass "archive content"
else
  pass "archive skipped"
fi

echo "service-package smoke OK"
