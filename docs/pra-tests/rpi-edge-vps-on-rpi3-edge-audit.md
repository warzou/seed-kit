# rpi-edge-vps on rpi3-edge-audit

## Goal

Document the first PRA read test of the `rpi-edge-vps` service package on a
secondary node.

This was not a production cutover, not a real replacement of `rpi-edge`, and
not an automatic restore.

## Package

- source package: `rpi-edge-vps-service.tar.gz`
- package size: 2.4K
- extraction: OK
- `MANIFEST.txt`: OK
- `SHA256SUMS`: OK
- forbidden paths absent:
  - `.env`
  - `logs`
  - `cache`

## Reconstructible content

- `compose/docker-compose.yml`
- `config/caddy`
- `config/homepage`
- `notes/reconstruction.txt`

## rpi3-edge-audit environment

- OS: Raspberry Pi OS
- arch: aarch64
- Docker: absent
- docker compose: absent
- port 80: already listening
- port 2019: already listening

## Findings

The package is valid and readable on the secondary node.

Real reconstruction cannot be launched yet because Docker and docker compose
are absent on `rpi3-edge-audit`.

The compose file also needs operator review before any future `docker compose
up`:

- historical Tailscale IP `100.110.92.41` appears in the compose and must be
  adapted to the reconstruction node
- ports are already in use on `rpi3-edge-audit`
- Cloudflare and Tailscale identity reconnection remains manual
- `.env` remains outside the package and must not be restored automatically

## Conclusion

- package valid: yes
- checksums valid: yes
- forbidden runtime/secrets absent: yes
- human reconstruction guidance: usable
- real service start: not ready

The package proves the service state can be moved and understood, but the node
is not yet prepared as a Docker reconstruction bench.

## Next SAFE steps

1. decide whether `rpi3-edge-audit` becomes a Docker bench
2. install Docker only after explicit decision
3. adapt `TAILSCALE_IP` to the reconstruction node
4. validate ports before any compose up
5. reconnect Tailscale and Cloudflare manually
