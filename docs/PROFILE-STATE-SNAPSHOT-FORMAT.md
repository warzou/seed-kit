# Profile-state snapshot format

This document sketches the future local snapshot format for `profile-state`.

It is design only. No archive creation, encryption, restore, cloud upload, or
system mutation is implemented by this document.

## Purpose

A profile-state snapshot should help prepare a SAFE reconstruction of a node.

It should make private reconstruction state visible, classifiable, and
reviewable before any real backup or restore exists.

The first goal is not automation. The first goal is a trustworthy manifest.

## What it is not

A profile-state snapshot is not:

- an OS clone,
- an automatic restore mechanism,
- a secret vault,
- a cloud backup,
- a production cutover tool,
- a replacement for human validation.

## Proposed future structure

```text
profile-state-snapshot/
  MANIFEST.txt
  SHA256SUMS
  inventory/
  projects/
  configs/
  docker-volumes/
  manual/
  excluded/
```

Suggested roles:

- `MANIFEST.txt`: human-readable source, target, timestamp, warnings, and
  classification summary.
- `SHA256SUMS`: checksums for included files when an archive eventually exists.
- `inventory/`: read-only command outputs and path classifications with no
  secret contents.
- `projects/`: selected project trees, such as `rpi-edge-vps`, optionally
  without `.git`.
- `configs/`: explicit service config copies selected for reconstruction.
- `docker-volumes/`: optional volume exports, only when encrypted and reviewed.
- `manual/`: human checklist steps that must not be automated silently.
- `excluded/`: manifest entries for items intentionally not copied.

## Classification rules

Profile-state V1 uses these categories:

- `public-project`: repo-backed project files that can usually be reviewed or
  recloned.
- `sensitive`: private state such as `.env`; encrypted backup only.
- `docker-volume`: runtime service state; optional and encrypted only.
- `manual-restore`: files useful for reconstruction but not auto-applied.
- `do-not-clone`: unique node identity or state that must not be duplicated.

## Strict rules

- Never include `.env` in an unencrypted snapshot.
- Never include host SSH private keys.
- Never include `/etc/machine-id`.
- Never include full Tailscale identity/state automatically.
- Prefer manifest and checksums before any archive format.
- Prefer dry-run output before any write.
- Treat Docker volumes as opt-in encrypted candidates.
- Treat Cloudflare and Tailscale reconnect as manual unless explicitly designed
  otherwise.

## Current state

Current status:

- design only,
- no encryption implemented,
- no real restore,
- no cloud upload,
- no archive writer,
- no system mutation.

The current concrete command remains a dry-run plan:

```sh
sh tools/profile-state.sh backup --local --dry-run
```
