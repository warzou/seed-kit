# Phone UI read-only design

This document defines the first SAFE phone UI direction for `wifi-kit`.

It is read-only.
It does not connect Wi-Fi, write `wpa_supplicant`, start `hostapd` or
`dnsmasq`, restart networking, reboot, or run a real `connect-safe`.

## Objective

The first UI must help an operator understand the node state before any future
network change exists.

The main screen should feel like a simple phone Wi-Fi onboarding flow, in French
by default:

- current node connection state,
- available Wi-Fi networks when scan is possible,
- disabled connect buttons,
- human scan-unavailable messages,
- clear read-only/Safe badges.

Advanced diagnostics remain available, but they should be hidden behind a
technical details section. The default view should not look like a developer
console.

It should show:

- runtime state,
- Wi-Fi scan data,
- snapshot preview,
- `safe-diagnose` summary,
- clear SAFE boundaries.

It must not show:

- Wi-Fi passwords,
- PSK values,
- enabled connection buttons,
- SSID change forms,
- AP/hotspot controls,
- service restart controls.

Disabled future-action buttons are allowed when they clearly communicate that
real connection is not implemented yet.

## Scan limitations

`scan-real --json` can return `status=unavailable`.
This is expected in some SAFE/read-only contexts.

Backend order:

- `wpa_cli -i <iface> scan_results` first, because it reads cached supplicant scan results without requesting a connection change,
- `iw dev <iface> scan` as fallback only.

The prototype intentionally does not call `wpa_cli scan`, `select_network`, `enable_network`, `save_config`, or `reconfigure`.

`wpa_cli scan` is reserved for an explicit refresh command only:

```sh
sh modules/wifi-kit/prototype/wifi-kit.sh scan-real --refresh --json
```

That mode is opt-in, uses a short timeout, then returns to `scan_results`.
If the refresh fails, the prototype should prefer existing cached results over a
hard failure. The phone UI must not trigger this refresh automatically.

Common reasons:

- `iw` is missing,
- the process lacks the capabilities required for active scan,
- the Wi-Fi interface is busy maintaining the current connection,
- the driver refuses active scan without elevated permissions.

The UI must explain these cases without suggesting a network restart or
reconnection. The current link is more important than showing a perfect network
list.

The user-facing message should avoid raw reasons like `iw-scan-failed` or
`scan-readonly-failed` on the main screen. Raw reasons can remain visible in
advanced diagnostics. The main screen should show which backend produced the
result, for example `wpa_cli scan_results` or `iw fallback`.

## Signal display

The phone UI should present Wi-Fi signal like a phone selector, not like raw
radio diagnostics.

Network cards show:

- SSID as the main title,
- visual signal bars,
- readable quality (`Excellent`, `Tres bon`, `Bon`, `Moyen`, `Faible`),
- dBm value as secondary detail,
- channel and security badges,
- disabled future connection action.

Signal quality is derived from dBm using a deliberately simple table:

- `>= -50`: Excellent,
- `>= -60`: Tres bon,
- `>= -67`: Bon,
- `>= -75`: Moyen,
- otherwise: Faible.

This is display-only. It must not trigger scans, connections, roaming decisions,
or network writes.


## Connection preparation simulation

The phone UI may let the user select a visible network and open a local password
field, but this remains frontend-only simulation.

Rules:

- selecting a network only updates the page state,
- the password field has no `name` attribute and is not submitted,
- no password is sent to the HTTP server,
- no password is logged or copied into raw JSON/debug panels,
- the `Prepare connection` action only renders a local plan,
- no POST endpoint is used,
- no `connect-safe` real apply is called.

The simulated plan should explain the future SAFE sequence in user language:

- current snapshot required,
- controlled future attempt,
- short timeout,
- automatic rollback,
- SSH validation before any future commit.

This is intentionally not a connection form yet. It is a UX rehearsal for the
future `connect-safe` flow after rollback and recovery are validated.

## Backend inputs


The read-only UI can use existing prototype commands:

```sh
sh modules/wifi-kit/prototype/wifi-kit.sh safe-diagnose --json
sh modules/wifi-kit/prototype/wifi-kit.sh scan-real --json
sh modules/wifi-kit/prototype/wifi-kit.sh state-snapshot --simulate --json
```

These outputs are already designed to be stable enough for a small local UI.

## Prototype shape

Current prototype:

```sh
sh modules/wifi-kit/prototype/ui/render-readonly-ui.sh > /tmp/wifi-kit-ui.html
```

The rendered page is static HTML with embedded JSON.
It requires no server and no heavy dependency.

The static template is:

```text
modules/wifi-kit/prototype/ui/index.html
```

It can be opened directly for demo data, or rendered from live read-only
commands using `render-readonly-ui.sh`.

## Local HTTP prototype

The first HTTP prototype is also read-only and manual:

```sh
python3 modules/wifi-kit/prototype/ui/serve-readonly.py --host 127.0.0.1 --port 8088
```

Endpoints:

- `GET /`
- `GET /api/runtime-state`
- `GET /api/safe-diagnose`
- `GET /api/scan`
- `GET /api/scan?refresh=1`
- `GET /api/scan-refresh`
- `GET /api/snapshot-preview`
- `GET /api/ui-data`

The server uses fixed command lists only. It does not accept arbitrary command
input and does not expose POST actions.

`GET /api/scan` remains passive and calls `scan-real --json`.
`GET /api/scan?refresh=1` and `GET /api/scan-refresh` are explicit refresh
requests and call only `scan-real --refresh --json`.

The phone UI must not refresh automatically on page load. The user-facing
refresh button is GET-only, shows a loading message, and updates only the scan
section. It must not connect, save, select, enable, or reconfigure Wi-Fi.

This remains a local prototype.
No AP mode, captive portal, or hotspot rescue is enabled now.

## UI action capabilities

The current UI mixes read-only status, explicit plans, and a few gated recovery
actions. Buttons must not imply that an unavailable action will run.

Capability states:

- `readonly`: reads state or scan data only.
- `planned`: displays the future plan and performs no mutation.
- `requires-recovery`: can run only while AP recovery is active.
- `requires-privileged-wrapper`: can run only after the strict wrapper and
  sudoers rule are installed and explicitly enabled.
- `real-enabled`: performs a real action in the narrow allowed context.
- `placeholder`: visible UX rehearsal only; no backend persistence or mutation.

Current action matrix:

| UI action | State | Notes |
| --- | --- | --- |
| Scan Wi-Fi | `readonly` | `GET /wifi/scan?refresh=1`; may trigger a bounded scan refresh, but does not connect, save, enable, or reconfigure Wi-Fi. |
| Connecter un Wi-Fi | `requires-recovery` / `real-enabled` | Real only from AP recovery with root privileges; normal mode returns `409 recovery-required` and shows the plan. Password is runtime-only and must not be logged. |
| Wi-Fi par défaut | `requires-recovery` / `real-enabled` | Stops AP recovery and returns wlan0 to NetworkManager; must be explicit because the captive portal disappears on success. |
| Activer le mode AP | `requires-privileged-wrapper` | Planned by default. Real execution requires `WIFI_KIT_ENABLE_PRIVILEGED_ACTIONS=1` plus the strict sudo wrapper. |
| Retour au réseau initial | `requires-privileged-wrapper` | Planned by default. Real execution is limited to the whitelisted default NetworkManager connection. |
| Mot de passe AP recovery | `placeholder` | The current UI only previews a future AP password change. No value is persisted, sent as a durable config, or used by AP recovery yet. |
| `/exit-recovery`, `/reboot-recovery`, `/set-recovery-password` | `placeholder` | Endpoints remain plan-only placeholders and should not be presented as real controls until a SAFE backend exists. |

The AP recovery password flow remains placeholder until Wifi-Kit has a
contracted persistence/API model outside Git with strict permissions.

## Field validation milestone

Validated on `pocket-node.lan` from branch `wifi-kit-work` up to commit
`e680276 feat: add wifi-kit connection prep simulation`.

Observed result:

- phone UI served temporarily from the read-only HTTP prototype,
- `wpa_cli` scan backend used successfully,
- passive scan returned cached Wi-Fi results,
- explicit refresh returned 7 visible networks,
- network selection worked in the phone UI,
- local password field was displayed,
- `Prepare connection` rendered only a SAFE simulated plan,
- no password was sent to the backend,
- no password appeared in diagnostics JSON,
- no password appeared in server logs.

Commands and endpoints exercised:

- `GET /`,
- `GET /api/ui-data`,
- `GET /api/scan`,
- `GET /api/scan?refresh=1`,
- `GET /api/scan-refresh`,
- `GET /api/runtime-state`,
- `GET /api/safe-diagnose`,
- `GET /api/snapshot-preview`,
- `POST /api/scan` returned `405`.

Safety guarantees confirmed during the field test:

- no real `connect-safe`,
- no `wpa_supplicant` write,
- no `save_config`,
- no `reconfigure`,
- no `select_network`,
- no `enable_network`,
- no `hostapd`,
- no `dnsmasq`,
- no reboot,
- no network restart,
- no SSID or PSK change.

Current limits:

- the UI is still a read-only onboarding rehearsal,
- `Prepare connection` is frontend simulation only,
- the password field is local browser state only,
- the HTTP backend remains GET-only,
- no access control or captive portal exists yet,
- no real AP/bootstrap/rescue mode is enabled.

Next UI step:

- improve the visual phone experience around network cards, selected state,
  reassurance copy, and advanced diagnostics.

Separate future step:

- real `connect-safe` can only be considered after rollback, timeout,
  SSH-safety, and recovery flows are validated end to end.

## Future HTTP shape

Later, the same inputs could be exposed through BusyBox `httpd` static files and
CGI shell endpoints. That future shape should keep the same GET-only boundary
until `connect-safe`, rollback, and recovery are validated.

## Safety boundary

The phone UI must remain behind the safety model:

- `wifi-stability` first,
- read-only diagnostics,
- rollback design,
- SSH safety,
- `connect-safe` simulation,
- real apply only after later architecture validation.

The UI is not the product core.
The core remains known networks, recovery, rollback, and safe reconnection.
