# Service package format

## Goal

A service package preserves the capacity to reconstruct a service.

It does not save the whole machine. It keeps only the small, explicit files and
notes that an operator can review, verify, and use during manual PRA
reconstruction.

## Minimal structure

Example:

```text
rpi-edge-service/
  MANIFEST.txt
  SHA256SUMS
  seed-kit-package.sh
  profiles/rpi-edge.profile
  services/
  configs/
  docs/
```

Archive form:

```text
rpi-edge-service.tar.gz
```

## Expected contents

- compose files
- service configs
- reconstruction notes
- package declaration
- embedded profile
- manifests/checksums
- optional selected small runtime state

## Package declaration

`seed-kit-package.sh` uses declarative shell values:

```text
SYSTEM="docker tailscale cloudflared"
MODULES=""
SERVICES="caddy homepage"
MANUAL_IDENTITIES="tailscale cloudflared"
HUMAN_STEPS="review-secrets reconnect-identities review-hostname validate-ssh-trust dns-cutover"
MANUAL_SECRETS="env machine-id ssh-host-keys tailscale-state cloudflare-credentials tokens-api-keys service-credentials"
SECRETS_POLICY="manual-reconnect"
```

- `SYSTEM` is for host packages/installations.
- `MODULES` is only for internal Seed-Kit modules.
- `SERVICES` is for application services carried by the package.
- `MANUAL_IDENTITIES` documents logins/trust that remain manual.
- `HUMAN_STEPS` lists operator-owned reconstruction steps that Seed-Kit must
  show and guide, not automate silently.
- `MANUAL_SECRETS` lists secret, key, token, identity, or credential classes
  intentionally left outside the package.
- `SECRETS_POLICY` summarizes how secrets are handled.

Legacy `COMPONENTS` packages remain readable as a compatibility fallback.

## Explicitly excluded

- machine-id
- ssh host keys
- tailscale state
- cloudflare credentials
- logs
- caches
- docker runtime complet
- full SD image

## MANIFEST philosophy

`MANIFEST.txt` should stay:

- simple text
- human-readable
- without a database
- without a complex format

Example:

```text
service-name: rpi-edge-vps
package-id: rpi-edge-service
profile-id: rpi-edge
format-version: 1
generated-by: seed-kit
reconstruction-mode: manual
human-steps:
  - review-secrets
  - reconnect-identities
  - review-hostname
manual-secrets:
  - .env
  - machine-id
  - ssh-host-keys
```

## Verification philosophy

Verification should be small and explicit:

- `SHA256SUMS` records package file checksums
- package verify checks that files match the manifest/checksums
- operator review decides whether the package is acceptable
- no automatic restore happens during verification

## Future direction

Seed-Kit could later:

- create a package
- verify a package
- help reconstruct from a package

Always:

- without magic
- without automatic restore
- without orchestration
