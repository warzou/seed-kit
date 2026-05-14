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

echo "Seed-Kit smoke tests"
echo

run_test "seed-kit syntax" "cd '$repo_dir' && sh -n seed-kit.sh"
run_test "profile-state syntax" "cd '$repo_dir' && sh -n tools/profile-state.sh"
run_test "profile-state smoke syntax" "cd '$repo_dir' && sh -n tests/profile-state-smoke.sh"
run_test "profile-state" "cd '$repo_dir' && sh tests/profile-state-smoke.sh"

echo "summary:"
echo "  total: $total"
echo "  failed: $failures"

if [ "$failures" -eq 0 ]; then
  echo "smoke tests OK"
  exit 0
fi

echo "smoke tests FAILED" >&2
exit 1
