# Service package format

## Goal

A service package preserves the capacity to reconstruct a service.

It does not save the whole machine. It keeps only the small, explicit files and
notes that an operator can review, verify, and use during manual PRA
reconstruction.

## Minimal structure

Example:

```text
rpi-edge-vps-service/
  MANIFEST.txt
  SHA256SUMS
  compose/
  config/
  notes/
```

Archive form:

```text
rpi-edge-vps-service.tar.gz
```

## Expected contents

- compose files
- service configs
- reconstruction notes
- manifests/checksums
- optional selected small runtime state

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
format-version: 1
generated-by: seed-kit
reconstruction-mode: manual
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
