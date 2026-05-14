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

## Future HTTP shape

Later, the same inputs could be exposed through a tiny local HTTP layer:

- BusyBox `httpd` static files,
- CGI shell endpoints,
- one JSON endpoint for `safe-diagnose`,
- one JSON endpoint for `scan-real`,
- simple polling from the browser.

This is only a future direction.
No HTTP server, AP mode, captive portal, or hotspot rescue is enabled now.

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
