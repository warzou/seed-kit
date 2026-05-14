# Edge reconstruction

This note sketches a SAFE V1 path for rebuilding an `rpi-edge`-style node on a fresh SD card or on `rpi-edge-audit`.

The goal is replacement readiness, not automatic production takeover.

## Objective

Rebuild a node shaped like `rpi-edge` from a fresh machine using Seed-Kit profiles and explicit manual validation.

Private configuration, credentials, tokens, DNS ownership, tunnel credentials, and service data must stay outside Git.

## Boundaries

Public Seed-Kit profile:

- names the intended public modules
- documents the safe order
- can install or prepare generic host-level capabilities

Private manual actions:

- Tailscale login or tailnet approval
- Cloudflare tunnel login, token, or tunnel selection
- Caddy site content and private hostnames
- service-specific restore decisions

Secrets:

- never committed
- never embedded in public profiles
- handled manually or by a future private restore flow

Runtime data:

- lives on the target node
- is validated before any replacement decision
- is not inferred from the public Seed-Kit repository

## Candidate profile

Future profile name:

```text
rpi-edge-replacement
```

V1 status: plan-only. It is intended to show the recommended public modules for rebuilding an `rpi-edge`-style host, but it must not apply production replacement actions automatically.

Probable modules:

- `wifi-stability` when the replacement is a Raspberry Pi using Wi-Fi
- `tailscale`
- `cloudflared`
- `caddy`
- `homer`

Optional later, not part of the V1 plan-only profile:

- `docker` when required by edge services
- `homepage` when the heavier dashboard path is required

## V1 limits

- no automatic restore
- no secrets in Git
- no automatic DNS mutation
- no automatic Cloudflare failover
- no production replacement without human validation
- no automatic rollback
- no dependency engine beyond explicit module order

## Field Test Lessons

`rpi3-edge-audit` is a validated reconstruction candidate.

Field test notes:

- tested on a fresh sacrificial machine as normal user `codex`
- Git was absent, which is acceptable for the copied single-file flow
- `minimal-resilient-node` reconstruction completed successfully
- `wlan0` was DOWN, but `wifi-stability` still disabled Wi-Fi power save and enabled persistence

Package side effects observed:

- `tailscaled` was enabled by the Tailscale package
- `caddy` was enabled by the Caddy package

Manual steps that should remain manual:

- `tailscale up`
- Cloudflare authentication and tunnel selection
- DNS failover or production cutover
- secret placement and private restore decisions

## SAFE workflow

1. Prepare a fresh SD card or fresh test node.
2. Copy `seed-kit.sh` to the target.
3. Run the planned profile:

```sh
sh seed-kit.sh --profile=minimal-resilient-node --plan
```

4. Apply the public host-level base when ready:

```sh
sh seed-kit.sh --profile=minimal-resilient-node --apply
```

5. Complete private manual steps:

- `sudo tailscale up`
- Cloudflare tunnel login or tunnel credential placement
- Caddy site configuration
- private service restore decisions

6. Validate services from another machine.
7. Decide manually whether the rebuilt node replaces `rpi-edge`.

## Future possible

- read-only inventory of current `rpi-edge`
- exportable reconstruction checklist
- private backup and restore workflow outside the public repo
- local uncommitted profile overlay
- bootstrap from a URL after explicit user approval
