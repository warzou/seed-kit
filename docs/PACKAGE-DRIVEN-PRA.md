# Package-driven PRA

## Goal

Package-driven PRA makes the service package the source of truth.

The package must include its own profile so the operator cannot accidentally use
a valid package with the wrong external profile.

Target commands:

```sh
sh seed-kit.sh --plan --package <file.tar.gz>
sh seed-kit.sh --apply --package <file.tar.gz>
sh seed-kit.sh --apply --package <file.tar.gz> --components docker,homepage
```

## Model

- package: source of truth for one reconstruction candidate
- profile: included in the package, not passed separately
- components: selectable parts of the package
- Seed-Kit: SAFE engine that verifies, plans, stages, and guides partial apply

## Possible package layout

```text
MANIFEST.txt
SHA256SUMS
seed-kit-package.json
profiles/<profile>.profile
services/
configs/
docs/
```

## Components

Components allow a partial guided flow:

```sh
sh seed-kit.sh --apply --package rpi-edge-service.tar.gz --components docker,homepage
```

Component selection must not become dependency orchestration. If one component
requires another, the package profile should say so and Seed-Kit should show it
before any apply.

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
