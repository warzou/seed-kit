# rollback design for connect-safe

This document defines the future rollback model for `wifi-kit connect-safe`.

It is design only. It does not implement a real Wi-Fi connection, does not write `wpa_supplicant`, does not start `hostapd` or `dnsmasq`, and does not apply system network changes.

## Why rollback is critical

`wifi-kit` targets small resilient nodes that may be headless and reachable only over Wi-Fi.

A failed Wi-Fi change can isolate the node. Critical failure cases include:

- headless node with no keyboard or display,
- SSH access lost,
- wrong PSK,
- DHCP broken,
- default route broken,
- target AP unavailable,
- wrong backend selected,
- `wlan0` stuck,
- future hotspot recovery fails.

## Rollback principles

The rollback design must be:

- rollback-first,
- short transaction only,
- timeout-driven,
- based on saved previous state,
- validated before commit,
- recovery-aware when validation is impossible.

Nothing should be considered committed until IP, route, and minimal reachability are validated.

## Minimal snapshot before attempt

Before a real connection attempt, `connect-safe` should snapshot enough state to return to the previous network path.

Minimum snapshot fields:

- current SSID,
- IP state,
- default route,
- backend in use,
- `power_save` state,
- affected network files,
- `wpa_supplicant` state,
- timestamp,
- current `wifi-kit` mode.

The snapshot must not contain PSK values in `wifi-kit` business files or logs.

## Proposed transactional states

- `readonly`: observe current state and build a plan.
- `snapshot-created`: previous state and affected files are captured.
- `connecting`: candidate Wi-Fi configuration is being tried.
- `waiting-ip`: waiting for DHCP/static IP result.
- `validating`: checking route and reachability.
- `committed`: new state is accepted.
- `rollback-started`: previous state restoration has begun.
- `rollback-complete`: previous state is restored and validated enough.
- `recovery-required`: automation should stop and require manual or future rescue flow.

## Validation before commit

Before `committed`, validation should include:

- Wi-Fi interface is up,
- IP address is present,
- default route is valid,
- minimal reachability works,
- optionally gateway ping succeeds,
- DHCP timeout has not been exceeded.

Validation must be explicit and logged. Silent success is not acceptable.

## Rollback triggers

Rollback should trigger when:

- PSK is wrong,
- IP timeout is reached,
- default route is absent,
- interface is down,
- scan is impossible when it is required for the plan,
- connectivity is lost,
- validation fails.

## Minimal V1 rollback

V1 should stay simple.

No network magic. No complex multi-backend orchestration.

Minimal rollback:

- restore previous config,
- reconnect previous SSID,
- wait for IP to return,
- validate route enough to reduce isolation risk,
- otherwise enter `recovery-required`.

If rollback cannot prove that access is safe again, automation must stop.

## Recovery-required

`recovery-required` means automation should abandon further changes.

Possible next paths:

- future hotspot recovery,
- physical intervention,
- local console,
- future watchdog.

This state is not failure hiding. It is a deliberate stop condition to avoid making isolation worse.

## Out of scope

Explicitly out of scope:

- distributed orchestration,
- high availability,
- intelligent roaming,
- multi-WAN,
- mesh networking,
- complex captive portal handling,
- opaque auto-routing.

## Next safe prototypes

Allowed next prototypes are still non-applying:

- transaction-state prototype,
- snapshot prototype,
- timeout simulation,
- rollback plan simulation.

Still forbidden:

- real Wi-Fi connection,
- writing `wpa_supplicant`,
- changing route,
- starting `hostapd`,
- starting `dnsmasq`,
- applying NetworkManager changes.
