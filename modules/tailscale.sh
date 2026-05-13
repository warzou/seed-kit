#!/bin/sh

module_tailscale_plan() {
  echo "- check whether tailscale is installed"
  echo "- install Tailscale from the official apt repository on Debian/Raspberry Pi OS"
  echo "- install-only: no tailscale up, no auth key, no tailnet join"
  echo "- after install, run manually: sudo tailscale up"
}
