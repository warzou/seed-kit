# SSH safety design for connect-safe

This document defines SSH safety rules for a future real `wifi-kit connect-safe`.

It is design only. It does not implement a real Wi-Fi connection, does not write `wpa_supplicant`, does not start `hostapd` or `dnsmasq`, and does not apply system network changes.

## Why SSH safety is critical

`wifi-kit` targets small nodes that may be headless and reachable only through SSH.

A future `connect-safe` can become dangerous when:

- the node has no screen or keyboard,
- SSH currently uses `wlan0`,
- the target operation changes SSID,
- DHCP or the default route changes,
- remote access is lost during the transaction,
- there is no easy local recovery path.

For this reason, SSH safety must be treated as a first-class connect-safe guardrail.

## Identified risks

- SSH is cut during reconnect.
- DHCP takes too long.
- PSK is wrong.
- Target AP disappeared.
- Default route is invalid.
- `wlan0` is down or stuck.
- Rollback starts too late.
- Timeout is too short and causes false rollback.
- Timeout is too long and leaves the node isolated.

## V1 principles

V1 should stay simple:

- timeout is mandatory,
- rollback-first behavior,
- validation before commit,
- short transaction window,
- `recovery-required` if validation is impossible,
- no opaque network magic.

No real `connect-safe` apply should be considered safe without explicit timeout and rollback behavior.

## Dangerous conditions

The future implementation must treat these as dangerous:

- current SSH access is routed through `wlan0`,
- no secondary interface exists,
- no alternate route exists,
- no physical access is available,
- node is remote,
- node is nomadic,
- target network is unknown.

In these cases, SAFE default behavior should prefer refusal, simulation, or an explicit unsafe confirmation mode.

## Proposed timeouts

Timeouts are design-only for now. Values should remain simple and operator-readable.

Proposed timeout types:

- `waiting-ip timeout`: maximum time waiting for IP after candidate connection.
- `validation timeout`: maximum time for route and reachability checks.
- `reconnect timeout`: maximum time trying to return to previous SSID.
- `rollback timeout`: maximum time before declaring rollback uncertain.

The exact values should be chosen later from field testing on Raspberry Pi OS Lite.

Avoid clever dynamic timeout logic in V1. A small set of explicit defaults is easier to reason about during recovery.

## Minimal validation before commit

Before a future transaction reaches `committed`, it should validate:

- IP address is present,
- default route is present,
- minimal reachability works,
- gateway may be pingable,
- SSH session may still be alive.

If these checks cannot prove the node is reachable enough, the transaction should not commit.

## SSH-awareness idea for V1

Future `connect-safe` should remain SSH-aware without becoming a framework.

Simple ideas:

- detect the current SSH client address when running under SSH,
- detect the route used to reach that address,
- detect whether that route uses `wlan0`,
- warn before changing the active SSH path,
- refuse by default when SSH is only reachable through the interface being changed,
- allow a clearly named unsafe mode only after explicit operator confirmation.

This is still design only. No detection or enforcement is implemented here.

## Recovery-required

`recovery-required` is the point where automation must stop.

It should be entered when:

- rollback cannot prove the previous route is restored,
- the previous SSID cannot be restored,
- IP does not return after rollback timeout,
- route validation fails after rollback,
- SSH safety cannot be evaluated and no safe fallback exists.

After `recovery-required`, future options may include:

- future hotspot recovery,
- local console,
- physical intervention,
- future watchdog.

Automation should not keep trying random network changes after this point.

## Out of scope

Explicitly out of scope:

- high availability orchestration,
- distributed rollback,
- multi-WAN,
- mesh networking,
- intelligent network selection,
- complex auto-healing,
- opaque routing changes.

## Next safe prototypes

Allowed next prototypes must stay non-applying:

- timeout simulation,
- SSH-awareness simulation,
- route-to-SSH planning output,
- rollback timeout demo.

Still forbidden:

- real Wi-Fi connection,
- writing `wpa_supplicant`,
- changing routes or IP addresses,
- starting `hostapd`,
- starting `dnsmasq`,
- applying NetworkManager changes.
