#!/bin/sh

set -u

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
failures=0
total=0

run_test() {
  name="$1"
  command="$2"

  total=$((total + 1))
  echo "== $name =="
  if sh -c "$command"; then
    echo "OK: $name"
  else
    echo "FAIL: $name" >&2
    failures=$((failures + 1))
  fi
  echo
}

run_fail_test() {
  name="$1"
  command="$2"

  total=$((total + 1))
  echo "== $name =="
  if sh -c "$command"; then
    echo "FAIL: $name" >&2
    failures=$((failures + 1))
  else
    echo "OK: $name"
  fi
  echo
}

echo "Seed-Kit smoke tests"
echo

run_test "bootstrap syntax" "cd '$repo_dir' && sh -n bootstrap.sh"
run_test "bootstrap help" "cd '$repo_dir' && sh bootstrap.sh --help | grep -q 'Seed-Kit bootstrap'"
run_test "seed-kit syntax" "cd '$repo_dir' && sh -n seed-kit.sh"
run_test "seed-kit self-update help" "cd '$repo_dir' && sh seed-kit.sh --help | grep -q 'self-update --plan'"
run_test "seed-kit self-update usage" "cd '$repo_dir' && out=\$(sh seed-kit.sh self-update 2>&1) && exit 1 || printf '%s\n' \"\$out\" | grep -q 'usage: sh seed-kit.sh self-update --plan'"
run_test "seed-kit modules list" "cd '$repo_dir' && sh seed-kit.sh modules list | grep -q 'Available modules'"
run_test "seed-kit doctor" "cd '$repo_dir' && out=\$(sh seed-kit.sh doctor) && printf '%s\n' \"\$out\" | grep -q 'Seed-Kit doctor' && printf '%s\n' \"\$out\" | grep -q 'mode: read-only' && printf '%s\n' \"\$out\" | grep -q 'No changes were made.'"
run_test "seed-kit inspect" "cd '$repo_dir' && out=\$(sh seed-kit.sh inspect) && printf '%s\n' \"\$out\" | grep -q 'Seed-Kit inspect' && printf '%s\n' \"\$out\" | grep -q 'mode: read-only' && printf '%s\n' \"\$out\" | grep -q 'No changes were made.'"
run_test "profile-state syntax" "cd '$repo_dir' && sh -n tools/profile-state.sh"
run_test "service-package syntax" "cd '$repo_dir' && sh -n tools/service-package.sh"
run_test "profile-state smoke syntax" "cd '$repo_dir' && sh -n tests/profile-state-smoke.sh"
run_test "service-package smoke syntax" "cd '$repo_dir' && sh -n tests/service-package-smoke.sh"
run_test "profile-state" "cd '$repo_dir' && sh tests/profile-state-smoke.sh"
run_test "service-package" "cd '$repo_dir' && sh tests/service-package-smoke.sh"

echo "summary:"
echo "  total: $total"
echo "  failed: $failures"

if [ "$failures" -eq 0 ]; then
  echo "smoke tests OK"
  exit 0
fi

echo "smoke tests FAILED" >&2
exit 1
