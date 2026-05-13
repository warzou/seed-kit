#!/bin/sh

module_caddy_plan() {
  echo "- check whether caddy is installed"
  echo "- install Caddy from the official Caddy apt repository"
  echo "- install-only: no site config, no reverse proxy, no DNS automation"
  echo "- after install, configure Caddy sites/services manually outside Seed-Kit"
}
