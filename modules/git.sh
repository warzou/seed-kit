#!/bin/sh

module_git_plan() {
  if command -v git >/dev/null 2>&1; then
    echo "- status: ready"
  else
    echo "- status: missing"
    echo "- plan: install git later through the detected backend"
  fi

  echo "- no repository changes in V0"
}
