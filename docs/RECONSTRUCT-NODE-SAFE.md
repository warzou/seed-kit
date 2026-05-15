# Reconstruct node safely

This document describes the minimal SAFE flow for rebuilding a node after a
fresh SD card or OS reinstall.

Seed-Kit helps prepare and verify the work. It does not automatically restore a
machine.

## Goal

Rebuild a node cleanly, one step at a time, while keeping private state and
production cutover under human control.

## Prerequisites

- fresh OS installed,
- network access,
- `git` available,
- a profile-state package to inspect, if one exists.

## Flow

```sh
git clone https://github.com/warzou/seed-kit.git
cd seed-kit
sh seed-kit.sh self-update --plan
sh seed-kit.sh modules list
sh tools/profile-state.sh reconstruction-plan
sh tools/profile-state.sh package --verify --input <tar>
```

Then restore manually, one component at a time.

Validate the rebuilt node before any production cutover.

## Safety boundaries

- secrets are not restored,
- machine identity is not cloned,
- automatic restore is not implemented,
- cloud sync is not implemented,
- profile-state is an operator aid, not a reconstruction engine.

## Manual checks

- review private configuration before use,
- reconnect Tailscale manually,
- authenticate Cloudflare manually,
- validate Caddy and service configuration manually,
- decide production replacement only after human validation.
