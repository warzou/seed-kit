# Profile state

`profile-state` is a proposed private backup and restore companion for Seed-Kit profiles.

It is not part of the public profile definition. It is for the machine-specific material needed to rebuild an `rpi-edge`-style node on a new SD card or replacement host.

This document is design-only. No restore implementation exists yet.

## V0 local dry-run status

`tools/profile-state.sh` starts the local-only V0 flow:

```sh
sh tools/profile-state.sh plan
sh tools/profile-state.sh inventory
sh tools/profile-state.sh backup --dry-run
```

V0 does not create archives, read secret contents, restore files, upload to cloud storage, or require sudo. It only explains the future boundary and lists candidate paths by existence.

## Field test note: rpi-edge

`profile-state inventory` was tested against the real `rpi-edge` shape.

Observed and expected detections:

- `~/git/rpi-edge-vps` is the main public project candidate.
- `~/git/rpi-edge-vps/compose/docker-compose.yml` is the real Compose file.
- `~/git/rpi-edge-vps/.env` is detected as sensitive.
- Caddy Docker volumes are treated as encrypted backup candidates.
- `/etc/machine-id` and host SSH keys are listed as `do-not-clone`.
- no secret content is read.
- no real backup archive is created.

Tailscale remains manual: reconnect or re-authenticate deliberately on the
replacement node instead of cloning full Tailscale identity.

## 1. Objectives

- capture private reconstruction state that does not belong in public Git
- make an `rpi-edge` replacement repeatable without hiding risky steps
- keep secrets out of the Seed-Kit repository
- require an explicit plan or dry-run before any restore
- avoid automatic production cutover

## 2. Included and excluded

Potentially included:

- Caddy configuration
- cloudflared configuration
- Homepage or Homer files when they are local/private
- private `.env` files
- service inventory
- reconstruction notes
- local profile notes that are not committed

Tailscale:

- include checklist notes only
- do not copy auth keys automatically
- do not run `tailscale up` automatically

Excluded:

- plaintext Cloudflare tokens
- plaintext Tailscale auth keys
- private SSH keys unless explicitly encrypted and reviewed
- production DNS mutation instructions that run automatically
- package caches or large runtime data by default

## 3. Archive format

Future archive shape:

```text
profile-state/
  manifest.txt
  inventory/
  caddy/
  cloudflared/
  homer/
  homepage/
  env/
  notes/
```

The manifest should be readable without restoring anything. It should list paths, timestamps, source host, target profile, and restore warnings.

## 4. Encryption requirement

Any archive containing private config or secrets must be encrypted before leaving the node.

Plain archives are only acceptable for read-only inventories with no secrets.

Future implementation should refuse to export known secret-bearing paths without encryption.

## 5. Backup workflow

1. Run a read-only inventory.
2. Show the planned paths.
3. Classify sensitive paths.
4. Require explicit confirmation.
5. Build an archive in a private location.
6. Encrypt the archive before transfer.
7. Store checksum and human-readable manifest.

No backup command should silently include new secret paths.

## 6. Restore workflow SAFE

1. Prepare a fresh node with Seed-Kit.
2. Apply the public profile first.
3. Copy the encrypted profile-state archive manually.
4. Decrypt locally on the target.
5. Run restore dry-run.
6. Show every target path and whether it exists.
7. Refuse overwrite by default.
8. Apply only after explicit confirmation.
9. Recheck services manually.

Restore must not mutate DNS, Cloudflare tunnels, or Tailscale state automatically.

## 7. Replacing the rpi-edge SD card

Suggested reconstruction path:

1. Build a fresh SD card.
2. Boot as a test node, such as `rpi-edge-audit`.
3. Copy `seed-kit.sh`.
4. Run the public profile plan.
5. Apply the host-level base.
6. Restore private profile state with dry-run first.
7. Validate services locally.
8. Validate remote access.
9. Decide manually whether this node replaces `rpi-edge`.

The replacement decision remains human-controlled.

## 8. V1 limits

- no automatic restore
- no overwrite by default
- no unencrypted secret export
- no Cloudflare token handling
- no Tailscale auth key handling
- no DNS cutover
- no rollback engine
- no state database

## 9. Human final checklist

- Seed-Kit profile applied
- Wi-Fi stability verified when relevant
- Tailscale login completed manually
- Cloudflare tunnel selected or configured manually
- Caddy config reviewed
- Homepage or Homer content reviewed
- private env files checked
- services started and inspected
- external access validated
- production replacement approved by a human
