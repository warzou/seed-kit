#!/bin/sh

module_homer_plan() {
  echo "- lightweight static dashboard for minimal resilient nodes"
  echo "- host-level path: no Docker and no Homepage dependency"
  echo "- intended for low-RAM, rescue, nomadic, and Raspberry Pi Zero 2 W nodes"
  echo "- plan-only for now: no static files, no service, no Caddy config"
}

module_homer_apply() {
  apply_step "homer: plan-only module"
  apply_skip "no files or services are deployed yet"
  ui_line "Next manual step: decide the static dashboard directory and serving method"
}
