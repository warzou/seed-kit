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
- `GET /api/snapshot-preview`
- `GET /api/ui-data`

The server uses fixed command lists only. It does not accept arbitrary command
input and does not expose POST actions.

This remains a local prototype.
No AP mode, captive portal, or hotspot rescue is enabled now.

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
