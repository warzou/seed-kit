#!/bin/sh

seed_detect_os() {
  SEED_OS_ID="unknown"
  SEED_OS_NAME="Unknown OS"
  SEED_OS_LIKE=""

  if [ -r /etc/os-release ]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    SEED_OS_ID=${ID:-unknown}
    SEED_OS_NAME=${PRETTY_NAME:-${NAME:-Unknown OS}}
    SEED_OS_LIKE=${ID_LIKE:-}
  fi

  if [ "$SEED_OS_ID" = "raspbian" ] || [ -r /etc/rpi-issue ]; then
    SEED_OS_ID="raspberrypi"
    SEED_OS_NAME=${SEED_OS_NAME:-Raspberry Pi OS}
  fi

  export SEED_OS_ID SEED_OS_NAME SEED_OS_LIKE
}
