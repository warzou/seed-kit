#!/bin/sh

set -eu

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
profile_state="$repo_dir/tools/profile-state.sh"
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

tmp_root="$(mktemp -d -t seed-kit-profile-state-smoke.XXXXXX)"
case "$tmp_root" in
  /tmp/*)
    ;;
  *)
    fail "unsafe temporary directory: $tmp_root"
    ;;
esac

run_ok() {
  "$@" >/dev/null 2>&1 || fail "expected success: $*"
}

run_fail() {
  if "$@" >/dev/null 2>&1; then
    fail "expected failure: $*"
  fi
}

make_package() {
  out_dir="$1"
  run_ok sh "$profile_state" package --local --dry-run --output "$out_dir"
  [ -f "$out_dir/profile-state-snapshot.tar" ] || fail "missing package tar"
}

retara_from_dir() {
  src_dir="$1"
  out_tar="$2"
  (
    cd "$src_dir"
    tar -cf "$out_tar" \
      MANIFEST.txt \
      SHA256SUMS \
      inventory \
      projects \
      configs \
      docker-volumes \
      manual \
      excluded
  )
}

make_path_without_sha256sum() {
  bin_dir="$1"

  mkdir -p "$bin_dir"
  for tool in sh tar grep mktemp rm; do
    tool_path="$(command -v "$tool" 2>/dev/null || true)"
    [ -n "$tool_path" ] || fail "missing required tool: $tool"
    ln -s "$tool_path" "$bin_dir/$tool"
  done
}

echo "profile-state smoke"

run_ok sh -n "$profile_state"
pass "profile-state syntax"

snapshot_dir="$tmp_root/snapshot"
run_ok sh "$profile_state" snapshot --local --dry-run --output "$snapshot_dir"
[ -f "$snapshot_dir/MANIFEST.txt" ] || fail "missing MANIFEST.txt"
grep -q '^PROFILE_STATE_FORMAT_VERSION=1$' "$snapshot_dir/MANIFEST.txt" || fail "missing manifest format version"
pass "snapshot manifest version"

package_dir="$tmp_root/package"
make_package "$package_dir"
run_ok sh "$profile_state" package --verify --input "$package_dir/profile-state-snapshot.tar"
pass "package verify OK"

no_sha_bin="$tmp_root/no-sha-bin"
no_sha_output="$tmp_root/no-sha-output.txt"
make_path_without_sha256sum "$no_sha_bin"
if PATH="$no_sha_bin" sh "$profile_state" package --verify --input "$package_dir/profile-state-snapshot.tar" > "$no_sha_output" 2>&1; then
  grep -q '^checksum: WARNING sha256sum unavailable, skipped$' "$no_sha_output" || fail "missing sha256sum unavailable warning"
  if grep -q '^checksum: OK$' "$no_sha_output"; then
    fail "checksum OK reported while sha256sum is unavailable"
  fi
else
  fail "verify should stay SAFE when sha256sum is unavailable"
fi
pass "sha256sum unavailable warning"

run_fail sh "$profile_state" package --verify
pass "missing input refused"

run_fail sh "$profile_state" package --verify --input "$tmp_root/missing.tar"
pass "missing file refused"

empty_input="$tmp_root/empty-input.tar"
: > "$empty_input"
run_fail sh "$profile_state" package --verify --input "$empty_input"
pass "empty non-tar input refused"

text_input="$tmp_root/text-input.tar"
printf '%s\n' "not a tar archive" > "$text_input"
run_fail sh "$profile_state" package --verify --input "$text_input"
pass "text non-tar input refused"

directory_input="$tmp_root/directory-input"
mkdir -p "$directory_input"
run_fail sh "$profile_state" package --verify --input "$directory_input"
pass "directory input refused"

unsafe_dir="$tmp_root/unsafe-env"
mkdir -p "$unsafe_dir"
printf '%s\n' "secret-placeholder" > "$unsafe_dir/.env"
(
  cd "$unsafe_dir"
  tar -cf "$tmp_root/unsafe-env.tar" .env
)
run_fail sh "$profile_state" package --verify --input "$tmp_root/unsafe-env.tar"
pass ".env archive refused"

missing_version_dir="$tmp_root/missing-version"
mkdir -p "$missing_version_dir"
(
  cd "$missing_version_dir"
  tar -xf "$package_dir/profile-state-snapshot.tar"
  sed '/^PROFILE_STATE_FORMAT_VERSION=/d' MANIFEST.txt > MANIFEST.next
  mv MANIFEST.next MANIFEST.txt
)
retara_from_dir "$missing_version_dir" "$tmp_root/missing-version.tar"
run_fail sh "$profile_state" package --verify --input "$tmp_root/missing-version.tar"
pass "manifest without version refused"

unknown_version_dir="$tmp_root/unknown-version"
mkdir -p "$unknown_version_dir"
(
  cd "$unknown_version_dir"
  tar -xf "$package_dir/profile-state-snapshot.tar"
  sed 's/^PROFILE_STATE_FORMAT_VERSION=.*/PROFILE_STATE_FORMAT_VERSION=999/' MANIFEST.txt > MANIFEST.next
  mv MANIFEST.next MANIFEST.txt
)
retara_from_dir "$unknown_version_dir" "$tmp_root/unknown-version.tar"
run_fail sh "$profile_state" package --verify --input "$tmp_root/unknown-version.tar"
pass "unknown manifest version refused"

bad_checksum_dir="$tmp_root/bad-checksum"
mkdir -p "$bad_checksum_dir"
(
  cd "$bad_checksum_dir"
  tar -xf "$package_dir/profile-state-snapshot.tar"
  printf '%s\n' "checksum-corruption=true" >> MANIFEST.txt
)
retara_from_dir "$bad_checksum_dir" "$tmp_root/bad-checksum.tar"
run_fail sh "$profile_state" package --verify --input "$tmp_root/bad-checksum.tar"
pass "corrupted checksum refused"

echo "profile-state smoke OK"
