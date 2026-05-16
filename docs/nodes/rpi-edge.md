# rpi-edge

## Role

- Raspberry Pi 3 nomade
- edge VPS leger
- acces prive via Tailscale
- exposition publique via Cloudflare Tunnel
- services Docker

## Runtime detected by Seed-Kit

- docker
- tailscale
- cloudflared
- git

## Main project

`/home/warzy/git/rpi-edge-vps`

## Reconstructible service state

- `compose/docker-compose.yml`
- `config/caddy`
- `config/homepage`
- caddy docker volumes:
  - `rpi-edge-vps_caddy_data`
  - `rpi-edge-vps_caddy_config`
- reconstruction notes

## Sensitive/manual state

- `.env`
- cloudflare authentication
- tailscale login/state
- SSH trust
- machine identity

## Do not clone

- machine-id
- ssh host keys
- tailscale state
- tokens/api keys

## Expected reconstruction order

1. fresh Raspberry Pi OS
2. network access
3. git install
4. clone Seed-Kit
5. self-update
6. doctor
7. inspect
8. modules list
9. verify profile-state package
10. restore compose/config manually
11. reconnect Tailscale
12. reconnect Cloudflare
13. validate services
14. production cutover

## Possible future service packages

- rpi-edge-vps compose/config
- homepage config
- caddy config

## Current limits

Seed-Kit does not perform automatic restore for this node. It is not a full
machine clone system, and it does not restore secrets automatically.
Reconstruction remains operator-driven: the package can guide and verify, but
the operator reconnects identities, secrets, trust, and exposed services
manually.
