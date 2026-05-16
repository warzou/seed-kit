# rpi3-edge

## Role

- futur candidat remplacement rpi-edge
- node PRA propre
- reconstruction target

## Current state

- Raspberry Pi OS Lite 64-bit
- aarch64
- SSH enabled
- Seed-Kit bootstrap validated
- clean starting point

## Currently absent

- Docker
- docker compose
- Tailscale
- Cloudflared
- Homepage
- Caddy

## Intended reconstruction target

`rpi3-edge` is the future target for `rpi-edge-vps` reconstruction.

Expected target shape:

- Docker services expected
- Tailscale private access
- Cloudflare public exposure
- service-package driven reconstruction

## Current PRA status

- fresh install validated
- bootstrap validated
- no production services running yet
- no cutover
- safe rollback still possible

## Next expected steps

1. install Docker
2. validate compose environment
3. restore compose/config manually
4. reconnect Tailscale
5. reconnect Cloudflare
6. validate services
7. future production cutover

## Philosophy

- reconstruct service, not machine
- node disposable
- operator-driven reconstruction
