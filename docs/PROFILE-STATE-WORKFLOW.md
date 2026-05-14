# Profile-state workflow

This document records the current validated `profile-state` workflow.

The workflow is still SAFE and local. It does not restore anything, does not
upload anything, and does not encrypt yet.

## Current workflow

```text
inventory
  -> backup local dry-run
  -> snapshot dry-run
  -> package dry-run
  -> package verify
```

## Commands

Inventory:

```sh
sh tools/profile-state.sh inventory
```

Backup plan:

```sh
sh tools/profile-state.sh backup --local --dry-run
```

Snapshot manifest directory:

```sh
sh tools/profile-state.sh snapshot --local --dry-run --output /tmp/profile-state-snapshot
```

Portable local package preview:

```sh
sh tools/profile-state.sh package --local --dry-run --output /tmp/profile-state-package
```

Package verification:

```sh
sh tools/profile-state.sh package --verify --input /tmp/profile-state-package/profile-state-snapshot.tar
```

Smoke tests:

```sh
sh tests/run-smoke.sh
sh tests/profile-state-smoke.sh
```

## SAFE guarantees

Current profile-state commands must not:

- restore files,
- upload to cloud,
- encrypt or pretend encryption happened,
- copy secret contents,
- copy `.env`,
- copy host SSH keys,
- copy `/etc/machine-id`,
- copy full Tailscale state such as `tailscaled.state`.

The current package is intentionally unencrypted and must be treated as a local
preview artifact only.

## Current status

Profile-state can now create a local portable tar preview and verify its basic
shape.

The artifact is:

- local,
- inspectable,
- uncompressed,
- unencrypted,
- manifest-oriented,
- suitable for review,
- not suitable for carrying secrets.

## Known limits

- package verification is intentionally basic,
- checksums cover generated manifest files, not future copied project data,
- Docker volumes are only represented as candidates,
- no encrypted archive exists yet,
- no restore command exists,
- no overwrite/merge behavior exists,
- no production cutover behavior exists.

## Possible next steps

- make package verification stricter,
- add fuller checksum coverage when real copied files exist,
- add local encryption later,
- keep restore as a much later step,
- keep Tailscale and Cloudflare reconnect manual until explicitly designed.
