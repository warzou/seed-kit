# runtime-state for wifi-kit

This document defines the minimal SAFE runtime-state model for `wifi-kit`.

It is design-only and read-only.
It does not write `wpa_supplicant`, does not reconnect Wi-Fi, does not start
`hostapd` or `dnsmasq`, and does not apply system network changes.

## Objective

The goal is to expose just enough network state for future:

- `connect-safe` preflight,
- rollback planning,
- SSH safety checks,
- recovery review,
- phone UI or local API read-only views later.

The runtime-state model must stay:

- small,
- human-readable,
- shell-friendly,
- non-secret,
- testable over SSH,
- easy to serialize to stable JSON.

## Current prototype surface

Read-only prototype commands:

```sh
sh modules/wifi-kit/prototype/wifi-kit.sh runtime-state show
sh modules/wifi-kit/prototype/wifi-kit.sh state-snapshot --simulate
sh modules/wifi-kit/prototype/wifi-kit.sh state-snapshot --simulate --json
sh modules/wifi-kit/prototype/wifi-kit.sh safe-diagnose
sh modules/wifi-kit/prototype/wifi-kit.sh safe-diagnose --json
```

These commands are observability only.
They do not create a persistent state database.

`safe-diagnose` is the combined preflight surface. It groups read-only runtime
state, snapshot preview, scan readiness, and `connect-safe` simulation without
turning any of those checks into a real apply.

## Minimal fields

The runtime-state model should stay limited to metadata such as:

- detected backend,
- Wi-Fi interface,
- current SSID metadata when readable,
- current IP,
- default route,
- `power_save` state,
- SSH client metadata,
- SSH route interface metadata,
- timestamp,
- minimal runtime fingerprint.

This is enough for a first rollback-aware preview without becoming a full
machine dump.

## Explicit exclusions

The runtime-state model must not include:

- Wi-Fi passwords,
- plaintext PSK values,
- copied `wpa_supplicant` secrets,
- unrelated service dumps,
- package inventories by default,
- large logs,
- automatic state persistence,
- complex databases.

## Snapshot preview shape

The future real transaction should treat runtime-state as a manifest-like
snapshot preview first.

That means:

- easy to inspect in terminal,
- easy to emit as stable JSON,
- easy to compare during review,
- explicit about missing fields,
- safe to collect before any future apply.

## Relationship with rollback

Runtime-state is not rollback by itself.

It is only the smallest preview layer needed before rollback-aware logic can
exist safely.

Future rollback may later combine:

- runtime-state preview,
- affected config path list,
- backend-specific change plan,
- validation results,
- rollback outcome.

## V1 boundary

For now, runtime-state remains:

- read-only,
- non-secret,
- in-memory or stdout only,
- non-persistent by default,
- SAFE for SSH use.

Still forbidden:

- real Wi-Fi connection,
- `wpa_supplicant` writes,
- route changes,
- reboot,
- restart networking,
- hotspot rescue runtime.
