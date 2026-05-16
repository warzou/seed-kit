# Service packages

## Goal

A service package preserves the capacity to reconstruct a service.

It is not a machine image, a backup engine, or a full runtime snapshot. It keeps
the small, reviewable files and notes that let an operator rebuild the service
on a fresh node.

## What a package should contain

- compose files
- service configs
- reconstruction notes
- small selected runtime state if explicitly chosen
- checksums/manifests

## What should NOT be included

- machine identity
- ssh host keys
- tailscale state
- cloudflare credentials
- logs
- caches
- full Docker runtime
- full SD images

## Example: rpi-edge-vps

The `rpi-edge-vps` package would describe and preserve only the service state
needed to rebuild the edge service from a clean node:

- `compose/docker-compose.yml`
- `config/caddy`
- `config/homepage`
- possible future metadata:
  - source project path
  - expected service names
  - selected Docker volume names
  - manual validation notes
  - manifest/checksum data

Expected reconstruction order:

1. prepare a fresh node
2. install git and clone Seed-Kit
3. run Seed-Kit self-update, doctor, and inspect
4. verify the service package manifest
5. restore compose and config files manually
6. review sensitive settings outside the package
7. reconnect Tailscale and Cloudflare manually
8. start services deliberately
9. validate service behavior before production cutover

## Philosophy

- service reconstruction
- node disposable
- operator-driven
- small/verifiable artifacts
- no magic restore

The node can be replaced. The service should be understandable, portable, and
rebuildable without cloning machine identity or hidden runtime state.

## Future direction

Seed-Kit could later:

- produce a package
- verify a package
- help reconstruct from a package

That future work should still avoid automatic restore. The package can guide,
check, and document, while the operator keeps control of identities, secrets,
network exposure, and service cutover.
