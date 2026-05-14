# Phone UI read-only design

This document defines the first SAFE phone UI direction for `wifi-kit`.

It is read-only.
It does not connect Wi-Fi, write `wpa_supplicant`, start `hostapd` or
`dnsmasq`, restart networking, reboot, or run a real `connect-safe`.

## Objective

The first UI must help an operator understand the node state before any future
network change exists.

It should show:

- runtime state,
- Wi-Fi scan data,
- snapshot preview,
- `safe-diagnose` summary,
- clear SAFE boundaries.

It must not show:

- Wi-Fi passwords,
- PSK values,
- connection buttons,
- SSID change forms,
- AP/hotspot controls,
- service restart controls.

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
