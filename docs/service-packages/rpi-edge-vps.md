# rpi-edge-vps service package

## Goal

- reconstruct the edge VPS service
- avoid cloning the complete node

The package should preserve the service knowledge needed for PRA, not machine
identity or the full runtime environment.

## Current detected structure

- `compose/docker-compose.yml`
- `config/caddy`
- `config/homepage`
- Docker volumes detected:
  - `rpi-edge-vps_caddy_data`
  - `rpi-edge-vps_caddy_config`

## Candidate package contents

- compose files
- caddy config
- homepage config
- reconstruction notes
- manifests/checksums
- optional selected small runtime state

## Explicitly excluded

- machine-id
- ssh host keys
- tailscale state
- cloudflare credentials
- docker runtime complet
- logs
- cache
- images docker
- full SD image

## Reconstruction flow

1. fresh OS
2. git clone Seed-Kit
3. self-update
4. doctor
5. inspect
6. verify service package
7. restore compose/config manually
8. reconnect tailscale
9. reconnect cloudflare
10. validate services
11. production cutover

## Manual decisions still required

- hostname
- tailscale login
- cloudflare authentication
- DNS validation
- exposed services validation

## Future possibilities

Seed-Kit could later:

- produce the package
- verify the package
- help reconstruct from the package

This should still avoid automatic restore. The package can document and verify
the service shape, while the operator keeps control of identities, secrets,
network exposure, and cutover.
