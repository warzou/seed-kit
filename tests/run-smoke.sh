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

run_test "seed-kit syntax" "cd '$repo_dir' && sh -n seed-kit.sh"
run_test "install-seed-kit syntax" "cd '$repo_dir' && sh -n install-seed-kit.sh"
run_test "seed-kit fresh-node help" "cd '$repo_dir' && sh seed-kit.sh --help | grep -q 'Fresh-node bootstrap'"
run_test "seed-kit self-update help" "cd '$repo_dir' && sh seed-kit.sh --help | grep -q 'self-update --plan'"
run_test "seed-kit self-update usage" "cd '$repo_dir' && out=\$(sh seed-kit.sh self-update 2>&1) && exit 1 || printf '%s\n' \"\$out\" | grep -q 'usage: sh seed-kit.sh self-update --plan'"
run_test "seed-kit modules list" "cd '$repo_dir' && sh seed-kit.sh modules list | grep -q 'Available modules'"
run_test "seed-kit docker plan" "cd '$repo_dir' && out=\$(sh seed-kit.sh --plan --modules=docker) && printf '%s\n' \"\$out\" | grep -q 'install Docker Engine from the official Docker apt repository'"
run_test "seed-kit package plan preview" "cd '$repo_dir' && pkg=\$(mktemp -t seed-kit-package-plan.XXXXXX) && out=\$(sh seed-kit.sh --plan --package \"\$pkg\") && rm -f \"\$pkg\" && printf '%s\n' \"\$out\" | grep -q 'package-driven PRA'"
run_fail_test "seed-kit package apply preview refused" "cd '$repo_dir' && pkg=\$(mktemp -t seed-kit-package-apply.XXXXXX) && sh seed-kit.sh --apply --package \"\$pkg\" --components docker >/tmp/seed-kit-package-apply.out 2>&1; rc=\$?; rm -f \"\$pkg\" /tmp/seed-kit-package-apply.out; exit \$rc"
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
