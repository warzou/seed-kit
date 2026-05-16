# Wifi-Kit Raspberry Pi OS backend strategy

Status: design and read-only prototype preparation. No network mutation is
implemented here.

## Recommendation

For modern Raspberry Pi OS / Debian images where NetworkManager owns `wlan0`,
Wifi-Kit should treat NetworkManager as the official primary backend:

```text
raspberrypi-networkmanager
```

The older direct supplicant backend should remain available as an explicit
fallback for minimal images:

```text
raspberrypi-wpa
```

## Current pocket-node observation

`pocket-node` is managed by NetworkManager:

- `NetworkManager.service` is active and enabled;
- `nmcli device status` reports `wlan0` connected;
- active connection is `netplan-wlan0-GL-MT6000-d53`;
- `wpa_supplicant.service` is also active because NetworkManager uses it
  underneath;
- `wpa_cli -i wlan0 status` works, but it is observing the supplicant state
  under NetworkManager.

## Comparison

### Direct `wpa_cli`

Strengths:

- small dependency surface;
- good read-only status and scan access;
- already validated for the temporary field experiment;
- simple rollback when Wifi-Kit owns the temporary network ids.

Risks:

- can conflict with NetworkManager if NetworkManager owns the interface;
- direct `add_network`, `set_network`, and `select_network` bypass the
  configured connection manager;
- backend network ids are volatile;
- AP+STA orchestration would need more manual service coordination;
- not the best default for modern Raspberry Pi OS images with NetworkManager.

### NetworkManager

Strengths:

- default control plane on modern Raspberry Pi OS / Debian images;
- explicit device and connection model through `nmcli`;
- better fit for AP+STA planning, connection profiles, DHCP, and rollback;
- integrates with netplan-generated profiles already present on `pocket-node`;
- easier for a future mobile UI backend to report active connection state.

Risks:

- heavier than direct supplicant control;
- `nmcli` scripting must be careful with secrets and logs;
- rollback needs profile-level cleanup, not only `wpa_cli remove_network`;
- behavior can vary with netplan-generated connections and autoconnect rules;
- first real mutation needs a fresh NetworkManager-specific safety test.

## Proposed minimal architecture

```text
modules/wifi-kit/prototype/backend/
  raspberrypi-networkmanager.sh
  raspberrypi-wpa.sh
```

Common operations:

- `backend_detect`
- `backend_status`
- `backend_scan_readonly`
- `backend_prepare_temporary_profile`
- `backend_connect_temporary`
- `backend_validate`
- `backend_rollback`
- `backend_cleanup`

Initial rule:

- if NetworkManager is active, select `raspberrypi-networkmanager`;
- otherwise, if `wpa_cli` / `wpa_supplicant` are present, select
  `raspberrypi-wpa`;
- otherwise, stay `generic-readonly`.

The runtime registry should record the selected backend as metadata, not as a
secret-bearing config source.

## Next implementation step

Build a read-only NetworkManager helper first:

```text
wifi-kit backend-detect
wifi-kit runtime-state show
wifi-kit nm-status-readonly
```

Current prototype helper:

```text
modules/wifi-kit/prototype/backends/raspberrypi-networkmanager.sh
```

Read-only commands:

- `status [IFACE]`
- `active-connection [IFACE]`
- `device-status`
- `scan [IFACE]`
- `fingerprint [IFACE]`

Only after that should Wifi-Kit design a NetworkManager-specific temporary
connect-safe transaction. Direct `wpa_cli` apply should be treated as a
backend-specific legacy path and should refuse by default when NetworkManager
owns `wlan0`.
