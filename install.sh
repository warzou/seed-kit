#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

usage() {
  cat <<'EOF'
Seed-Kit installer

Usage:
  sh install.sh --plan

V0 only prints the install plan. It does not modify the system.
EOF
}

case "${1:-}" in
  --plan|"")
    echo "Seed-Kit install plan"
    echo "plan-only mode / no system changes"
    echo
    echo "project: $ROOT_DIR"
    echo "- keep scripts in place"
    echo "- run with: sh seed-kit.sh --plan"
    echo "- no packages installed"
    echo "- no system files changed"
    ;;
  -h|--help)
    usage
    ;;
  *)
    usage
    exit 2
    ;;
esac
