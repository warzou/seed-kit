# connect-safe design

This document defines the future `connect-safe` mode for `wifi-kit`.

No real network change is implemented by this document. It is architecture, safety, rollback, state, and flow design only.

## Objective

`connect-safe` should connect a node to a new Wi-Fi network while minimizing the risk of losing access.

Core goals:

- connect a node to a new Wi-Fi network,
- minimize SSH/access loss risk,
- automatically rollback on failure,
- keep recovery paths explicit,
- avoid opaque network magic.

## Identified risks

- SSH access is lost.
- DHCP does not provide an IP address.
- Default route is broken or replaced incorrectly.
- PSK is wrong.
- Target AP disappears.
- Roaming chooses the wrong AP.
- `wlan0` becomes stuck.
- Future hotspot recovery fails.
- Node becomes isolated.

## Mandatory guardrails

Every real `connect-safe` implementation must include:

- backup of relevant config before any modification,
- connection timeout,
- IP validation,
- default route validation,
- minimal reachability validation,
- automatic rollback,
- explicit logs,
- test/simulation mode,
- recovery path.

The implementation must never log PSK values or copy Wi-Fi secrets into `wifi-kit` business files.

## Dangerous conditions

`connect-safe` is high risk when:

- current SSH access uses `wlan0`,
- there is no fallback interface,
- there is no secondary route,
- the node is headless,
- there is no physical access.

In these conditions, real apply should either refuse, require a stronger confirmation, or require a proven recovery path.

## Proposed states

- `readonly`: observe current state and build a plan.
- `preparing`: snapshot network state and backup config.
- `connecting`: attempt the new Wi-Fi configuration.
- `validating`: wait for IP, route, and reachability checks.
- `success`: commit metadata and record success.
- `rollback`: restore previous config/state.
- `recovery-required`: automatic rollback failed or access remains uncertain.

## Transactional idea

Pseudo-flow:

```text
snapshot current network state
backup relevant config
prepare candidate config
attempt connection
wait for IP
validate default route
validate minimal reachability
if validation succeeds:
  commit metadata
  record success
else:
  rollback config
  restore previous state
  record failure
  enter recovery-required if rollback cannot be proven
```

Timeouts must be explicit at each phase. A hung DHCP attempt or blocked Wi-Fi operation must not leave the node in an unknown state.

## Transactional V1 simulation flow

The prototype command is:

```sh
sh modules/wifi-kit/prototype/wifi-kit.sh connect-safe --simulate
```

It is simulation-only and must not ask for a real SSID, PSK, or secret.

The current snapshot preview command is:

```sh
sh modules/wifi-kit/prototype/wifi-kit.sh state-snapshot --simulate
sh modules/wifi-kit/prototype/wifi-kit.sh state-snapshot --simulate --json
```

It exists to preview the runtime state that a future real transaction would need
before any candidate Wi-Fi change is considered.

The documented transaction order is:

1. `preflight`: confirm tools, stability, SSH safety, and rollback path.
2. `detect-interface`: identify the target Wi-Fi interface and backend.
3. `snapshot-current-state`: capture SSID metadata, IP, route, power-save, backend, `wpa_supplicant` state, and timestamp.
4. `build-change-plan`: prepare a metadata-only plan without writing config.
5. `strong-confirmation`: require explicit operator acceptance before any future real apply.
6. `future-controlled-attempt`: perform a bounded attempt only in a future implementation.
7. `validation`: require IP, route, minimal reachability, and SSH safety.
8. `commit-or-rollback`: commit only after validation, otherwise rollback.
9. `state-journal`: record non-secret state transitions for review.

The snapshot preview must stay minimal and non-secret:

- backend detected,
- target Wi-Fi interface,
- current SSID presence metadata when readable, without raw SSID values,
- current IP,
- default route,
- `power_save` state,
- SSH client metadata,
- SSH route interface metadata,
- timestamp,
- minimal runtime fingerprint.

Abort conditions include:

- SSH appears to use the target Wi-Fi interface,
- rollback path is missing,
- IP timeout,
- route validation failure,
- reachability failure,
- rollback cannot be proven.

In V1, this remains a planning model. It does not perform the future controlled attempt.

## Runtime snapshot preview

`runtime-state show` is the current read-only snapshot preview for future
`connect-safe` recovery work.

It may inspect:

- timestamp,
- hostname and OS family,
- backend hint,
- SSH client route,
- default routes,
- Wi-Fi interface state,
- Wi-Fi power-save state,
- minimal tool fingerprint.

It must not include:

- Wi-Fi passwords,
- raw `wpa_supplicant` content,
- Cloudflare or Tailscale credentials,
- full system dumps,
- persistent archives.

This keeps the snapshot useful for rollback design without turning it into a
secret store.

## SSH-aware behavior

Before any real apply, `connect-safe` must detect whether SSH is currently routed through the interface being changed.

If SSH is currently via `wlan0`, the operation is dangerous. Future behavior should prefer:

- simulation only,
- require explicit operator confirmation,
- require an alternate access path,
- require a tested rollback window,
- require a future recovery hotspot safety net.

## Future hotspot recovery

The hotspot recovery mode is not implemented yet.

Later, it could act as a safety net when rollback cannot restore client connectivity. In that future design, the node could expose a temporary rescue AP for manual recovery from a phone.

Even then, hotspot recovery must remain a fallback path, not the main connection engine.

## Forbidden in V1

V1 must not include:

- complex orchestration,
- enterprise captive portal handling,
- intelligent multi-AP roaming,
- mesh networking,
- complex auto-routing,
- opaque network magic,
- real apply without architecture validation.

## V1 boundary

For now, `connect-safe` remains design-only.

Allowed next work:

- plan-only command design,
- simulation output,
- preflight checks,
- rollback design,
- test fixtures.

Still forbidden:

- real Wi-Fi connection,
- writing `wpa_supplicant`,
- `hostapd`,
- `dnsmasq`,
- NetworkManager apply,
- service creation,
- route changes.
