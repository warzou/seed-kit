# V1 stabilization

Seed-Kit V1 PRA is intentionally minimal.

The goal is not to automate a full rebuild. The goal is to make small-machine
reconstruction understandable, testable, and safe enough to repeat manually.

## Validated

- self-update
- doctor/inspect
- profile-state
- service-package dry-run
- rpi-edge-vps package
- transfer and verification on rpi3-edge-audit

## Out of scope

- automatic restore
- cloud sync
- incremental backup
- scheduler
- secret vault
- orchestration
- full machine clone

## Stability rule

Every new feature must come from a real field test.

Do not add features just in case. Prefer documentation, tests, and readability.
When the field reveals friction, fix the smallest real problem first.

## Allowed next steps

- fix simple bugs
- document field friction
- test manually
- improve messages when needed

## Not allowed without explicit decision

- automatic Docker install
- Cloudflare automation
- Tailscale automation
- restore
- cloud backup
- complex package engine

## Philosophy

Keep V1 small enough to trust.

The operator remains in control of identity, secrets, network exposure, service
startup, and production cutover.
