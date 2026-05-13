#!/bin/sh

module_cloudflared_plan() {
  echo "- check whether cloudflared is installed"
  echo "- install cloudflared from the official Cloudflare apt repository"
  echo "- install-only: no tunnel login, no tunnel create, no credentials"
  echo "- after install, configure tunnels manually outside Seed-Kit"
}
