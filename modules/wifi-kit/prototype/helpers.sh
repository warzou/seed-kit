#!/bin/sh

find_tool() {
  tool=$1

  if command -v "$tool" >/dev/null 2>&1; then
    command -v "$tool"
    return 0
  fi

  for dir in /usr/sbin /sbin /usr/bin /bin; do
    if [ -x "$dir/$tool" ]; then
      printf '%s\n' "$dir/$tool"
      return 0
    fi
  done

  return 1
}

has_tool() {
  find_tool "$1" >/dev/null 2>&1
}
