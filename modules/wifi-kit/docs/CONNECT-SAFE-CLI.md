# connect-safe CLI prototype

This document defines the first CLI-only shape for a future real
`connect-safe` workflow.

The current implementation is plan-only:

```sh
sh modules/wifi-kit/prototype/connect-safe-plan.sh \
  --dry-run --iface wlan0 --from <current-ssid> --to <target-ssid>
```

It does not connect to Wi-Fi, write `wpa_supplicant`, call `save_config`,
restart networking, run `hostapd`, run `dnsmasq`, or persist anything.

## Why a separate script

`prototype/wifi-kit.sh` already contains broad read-only diagnostics and
simulation commands.

The future real `connect-safe` path is higher risk, so the first CLI prototype
lives in:

```text
modules/wifi-kit/prototype/connect-safe-plan.sh
```

That keeps the future transaction flow isolated from the phone UI and from the
general diagnostic prototype.

## Target field scenario

The first real test should be a known-network switch:

- start on Wi-Fi A,
- switch temporarily to already-known Wi-Fi B,
- validate IP, route, gateway or reachability, and SSH safety,
- rollback automatically to Wi-Fi A if validation fails,
- avoid persistence until a later phase.

No PSK should be handled by `wifi-kit` in this phase. Both networks should
already exist in the system Wi-Fi backend.

## DHCP and IP prerequisites

Before any future apply test:

- reserve or know the expected IP on Wi-Fi A,
- reserve or know the expected IP on Wi-Fi B,
- know the expected gateway for each network when possible,
- confirm SSH can tolerate a short Wi-Fi transition,
- prefer having physical or alternate access for the first real test.

Static reservations on the DHCP servers are preferred over writing static IP
configuration from `wifi-kit`.

## Proposed transaction flow

1. Preflight tools, Wi-Fi interface, SSH route, rollback path, and known
   network entries.
2. Snapshot the current state: interface, SSID metadata, IP, default route,
   power-save, backend, and timestamp.
3. Build a target plan for the known Wi-Fi B profile without reading or
   storing secrets.
4. In a future apply phase, perform a bounded temporary switch.
5. Wait for IP with a short timeout.
6. Validate default route, gateway or reachability, and SSH safety.
7. If validation succeeds, report success but do not persist by default.
8. If validation fails, switch back to Wi-Fi A and validate rollback.
9. If rollback cannot be proven, report `recovery-required`.

## Future command families

The plan-only script prints the command families that a later implementation
would need, including:

- `ip addr show dev <iface>` for IP validation,
- `ip route show default` for route validation,
- `iw dev <iface> get power_save` for stability context,
- `wpa_cli -i <iface> status` for read-only backend state,
- `wpa_cli -i <iface> list_networks` to find known profile IDs,
- a future bounded profile switch using `wpa_cli`.

The plan-only prototype must not execute any switching command.

## Guardrails before real apply

Real apply remains forbidden until these conditions are designed and tested:

- strong operator confirmation,
- bounded timeout for IP, validation, and rollback,
- automatic rollback to the previous known SSID,
- proof that SSH still has a safe route,
- no PSK logging,
- no `save_config` in the first real test,
- no UI integration,
- no retry loop that can keep the node isolated.

## Current limits

- No real Wi-Fi switch is implemented.
- No profile ID lookup is executed.
- No runtime journal is written.
- No rollback command is executed.
- No phone UI integration exists.
- No persistence boundary is implemented.

The next safe step is to review the dry-run output on the target node before
designing an apply gate.
