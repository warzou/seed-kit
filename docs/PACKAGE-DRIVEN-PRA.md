# Package-driven PRA

## Goal

Package-driven PRA makes the service package the source of truth.

The package must include its own profile so the operator cannot accidentally use
a valid package with the wrong external profile.

Target commands:

```sh
sh seed-kit.sh --plan --package <file.tar.gz>
sh seed-kit.sh --apply --package <file.tar.gz>
sh seed-kit.sh package apply-guided <file.tar.gz> --step install-modules
sh seed-kit.sh package apply-guided <file.tar.gz> --step review-configs
```

## Model

- package: source of truth for one reconstruction candidate
- profile: included in the package, not passed separately
- system: host packages/installations such as docker, tailscale, cloudflared, caddy, or git
- modules: internal Seed-Kit modules such as wifi-stability or wifi-kit
- services: application services carried by the package, such as homepage or a compose stack
- manual identities: trust/login steps that must be reconnected by the operator
- Seed-Kit: SAFE engine that verifies, plans, stages, and guides partial apply

Older packages may still expose `COMPONENTS`. Seed-Kit treats that as a
temporary compatibility fallback while V1 packages move to `SYSTEM`, `MODULES`,
`SERVICES`, and `MANUAL_IDENTITIES`.

## Possible package layout

```text
MANIFEST.txt
SHA256SUMS
seed-kit-package.sh
profiles/<profile>.profile
services/
configs/
docs/
```

## Package Declaration

`seed-kit-package.sh` is declarative shell data. Seed-Kit reads it without
`source` or `eval`.

```text
SYSTEM="docker tailscale cloudflared"
MODULES=""
SERVICES="caddy homepage"
MANUAL_IDENTITIES="tailscale cloudflared"
```

System entries can be used by guided install-only steps. Services are never
treated as installable Seed-Kit modules. Module entries are reserved for
internal Seed-Kit modules.

## Secrets

Secrets are never restored automatically.

Packages may document where identity, DNS, tunnel, token, or service credentials
must be reconnected manually. The operator remains responsible for reviewing and
reconnecting trust.

## SAFE modes

- verify: check archive presence, manifest, checksums, and declared shape
- stage: extract only into a reviewable staging directory
- apply-guided: perform explicit selected steps after SAFE confirmation

## Non-goals

- no full machine clone
- no automatic secret restore
- no automatic DNS cutover
- no automatic cloud sync
- no automatic app stack restore in V1
