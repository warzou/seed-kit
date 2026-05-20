# Package-driven restore

## Goal

Package-driven restore makes the package the source of truth for replaying a
node/service on a fresh machine.

The package must include its own profile so the operator cannot accidentally use
a valid package with the wrong external profile.

Current commands:

```sh
sh seed-kit.sh --plan --package <file.tar.gz>
sh seed-kit.sh restore <file.tar.gz>
sh seed-kit.sh package apply-guided <file.tar.gz> --step install-modules
sh seed-kit.sh package apply-guided <file.tar.gz> --step review-configs
```

`restore` is the main package replay entrypoint. `package apply-guided` remains
available for compatibility and for explicit human-guided sub-steps.

## Model

- package: source of truth for one reconstruction candidate
- profile: included in the package, not passed separately
- system: host packages/installations such as docker, tailscale, cloudflared, caddy, or git
- modules: internal Seed-Kit modules such as wifi-stability or wifi-kit
- services: application services carried by the package, such as homepage or a compose stack
- manual identities: trust/login steps that must be reconnected by the operator
- Seed-Kit: reads the package, stages it, restores/replays explicit steps, and
  asks the operator only for actions that require human judgment

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

## Ready model

Package-driven PRA follows the Ready model:

```text
Installed -> Configured -> Validated -> Ready
```

Installing `SYSTEM` entries is not enough to declare a replacement node ready.
Manual identities such as Tailscale and Cloudflared still require operator-owned
login, trust, and configuration steps. See `docs/READY-MODEL.md`.

## Secrets

Secrets are never restored automatically.

Packages may document where identity, DNS, tunnel, token, or service credentials
must be reconnected manually. The operator remains responsible for reviewing and
reconnecting trust.

## Restore/replay modes

- verify: check archive presence, manifest, checksums, and declared shape
- stage: extract only into a reviewable staging directory
- restore/replay step: perform one explicit package step after confirmation
- guided: human-only steps such as identity login, review, validation, or start
  decision

## Non-goals

- no full machine clone
- no automatic secret restore
- no automatic DNS cutover
- no automatic cloud sync
- no hidden app stack start in V1
