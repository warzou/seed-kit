# Wifi-Kit AP fallback and known-network reconnect design

Status: design only, plan-only. No real AP mode is implemented here.

This document defines the safe target architecture for two future Wifi-Kit capabilities:

- reconnecting automatically to Wi-Fi networks already known and validated;
- starting a temporary Wifi-Kit access point only when no known network works.

Nothing in this document authorizes real network mutation yet. The current implementation must remain read-only or simulation-only until rollback, timeouts, SSH safety, and recovery paths are validated on hardware.

## Product goal

At boot, a resilient node should try to join a previously validated Wi-Fi. If one works, the node stays in client mode. If none works, it should expose a temporary Wifi-Kit AP so a phone can open the local UI and prepare a new Wi-Fi configuration.

Target flow:

1. Try known and validated Wi-Fi profiles in priority order.
2. Validate IP, gateway, DNS, and expected reachability.
3. Stay on the first network that passes validation.
4. If all known networks fail, enter recovery planning.
5. Start a temporary AP only in a future implementation with explicit safety checks.
6. Let the user select a new Wi-Fi from the phone UI.
7. Test the new Wi-Fi through connect-safe.
8. Promote it to known and validated only after validation succeeds.
9. Roll back to the previous state or return to AP mode on failure.

## Scope boundaries

Allowed in this design phase:

- metadata model;
- boot flow design;
- UI flow design;
- plan-only CLI output;
- rollback and recovery planning.

Still forbidden in this phase:

- hostapd start or configuration;
- dnsmasq start or configuration;
- NetworkManager mutation;
- systemd-networkd mutation;
- wpa_supplicant mutation;
- wpa_cli select_network, enable_network, reconfigure, or save_config;
- route changes;
- IP changes;
- reboot;
- network restart;
- real connect-safe apply;
- endpoint POST actions.

## State model

Wifi-Kit should not own Wi-Fi secrets. Secrets remain in the platform network backend, for example wpa_supplicant on Raspberry Pi OS Lite or a future OpenWRT backend.

Wifi-Kit may own local metadata only.

Recommended future runtime directory:

```text
/etc/seed-kit/wifi-kit/
```

Recommended permissions:

```text
/etc/seed-kit/wifi-kit/            root:root 700
/etc/seed-kit/wifi-kit/*.json      root:root 600
/etc/seed-kit/wifi-kit/*.jsonl     root:root 600
```

Potential metadata files:

```text
known-networks.json
validated-networks.json
fallback-network.json
last-success.json
runtime-state.json
connect-attempts.jsonl
```

Metadata fields may include:

- ssid;
- ssid_hash for logs or redacted views;
- priority;
- favorite;
- validated;
- last_success;
- last_failure;
- retry_count;
- backend;
- interface;
- expected_gateway;
- expected_dns;
- expected_route_interface;
- validation_source;
- validation_timestamp;
- notes.

Metadata must not include:

- PSK;
- raw passphrase;
- wpa_supplicant network block with secrets;
- host SSH keys;
- machine-id;
- full Tailscale state;
- unredacted secrets in logs.

SSID values can be sensitive in some environments. Logs should prefer redacted SSID or ssid_hash unless the user explicitly requests local debug output.

## Known, validated, favorite, and fallback networks

Known network:

- Wifi-Kit has metadata for the SSID.
- The backend may already know the credentials.
- The network is not necessarily safe to auto-join yet.

Validated network:

- The node has previously connected successfully.
- IP, gateway, and basic reachability checks passed.
- Metadata records when validation happened.

Favorite or priority network:

- A validated network preferred during boot.
- Priority should remain simple: lower number means try earlier, or a single favorite flag can override normal ordering.

Fallback Flint network:

- A known validated network treated as a rescue candidate.
- It is not magic and should not be hardcoded globally.
- It should be represented as metadata, for example role=fallback.
- It should be tried before temporary AP mode when configured and safe.

## Boot flow

The future boot flow should be short, bounded, and rollback-aware.

```text
state=boot
state=preflight
state=load-known-networks
state=sort-candidates
state=try-candidate
state=waiting-ip
state=validating
state=success
```

If validation fails:

```text
state=try-candidate
state=validation-failed
state=rollback-or-next-candidate
```

If no known network works:

```text
state=known-networks-exhausted
state=recovery-required
state=temporary-ap-planned
```

Validation should remain minimal:

- interface is up;
- IP address exists;
- default route exists;
- gateway is reachable if safe to test;
- DNS is usable if safe to test;
- SSH safety is not worse than before;
- timeout has not expired.

## Temporary AP fallback

Temporary AP mode is a recovery path, not the main engine.

It should start only when:

- no known validated Wi-Fi works;
- rollback to a previous client network is not possible;
- the hardware supports the requested mode;
- SSH safety rules accept the risk;
- the AP lifetime is bounded;
- the UI remains local and explicit.

Future AP mode may need hostapd and dnsmasq, but they are not active in the current Wifi-Kit implementation.

Temporary AP metadata should include:

- ap_ssid;
- interface;
- channel;
- start_time;
- max_lifetime;
- reason;
- recovery_state.

No AP password or admin secret should be logged.

## One Wi-Fi adapter: client plus AP?

On Raspberry Pi class hardware, a single Wi-Fi adapter may or may not support client mode and AP mode at the same time. This depends on the chipset, driver, firmware, regulatory domain, channel constraints, and valid interface combinations.

Safe V1 assumption:

- do not rely on simultaneous client plus AP on one adapter;
- prefer client mode first;
- if client mode fails, stop planning client attempts before planning AP mode;
- use a second Wi-Fi adapter if simultaneous AP plus client is required;
- validate the exact hardware with iw list before any real AP design.

For pocket-node/Raspberry Pi Zero 2 W style hardware, Wifi-Kit should assume single-radio limitations unless hardware tests prove otherwise.


## Pocket-node read-only hardware audit

A read-only hardware audit was performed on `pocket-node` to prepare the
future AP/reconnect design. No network mutation was performed during the audit.
No hostapd, dnsmasq, connect-safe apply, network restart, reboot, or Wi-Fi
configuration write was executed.

Observed state:

- host: `pocket-node`;
- interface: `wlan0`;
- driver: `brcmfmac`;
- chipset: `BCM43430/2`;
- firmware path: `brcm/brcmfmac43430b0-sdio`;
- current mode: `managed` / client;
- current client channel during audit: channel 6, 2437 MHz;
- power save: off.

`iw list` reports AP support and a valid interface combination that includes
one managed interface plus one AP interface:

```text
#{ managed } <= 1, #{ AP } <= 1, #{ P2P-client } <= 1, #{ P2P-device } <= 1,
total <= 4, #channels <= 1
```

Interpretation:

- AP mode is advertised by the driver;
- managed plus AP is advertised as possible;
- the strong constraint is `#channels <= 1`;
- AP plus client simultaneous mode would need to stay on the same radio channel;
- if the client network changes channel, the AP/client combination becomes
  fragile or unsuitable;
- Raspberry Pi Zero 2 W class hardware should still be treated as a single-radio
  recovery device, not as a reliable AP-plus-client router.

SAFE V1 recommendation:

- do not depend on simultaneous AP plus client for the main product flow;
- try known and validated client networks first;
- stay in client mode if one works;
- enter temporary AP recovery only if no known network works;
- keep AP mode bounded, explicit, and recovery-oriented;
- prefer a second Wi-Fi adapter if reliable AP plus client mode becomes a real
  requirement.

## UI flow

The phone UI should remain read-only until connect-safe apply is implemented and reviewed separately.

Future UI flow:

1. Show current node state.
2. Show read-only scan results.
3. Let the user select an SSID.
4. Keep the password local until an explicit future apply flow exists.
5. Show connect-safe plan.
6. Require strong confirmation before any real mutation.
7. Run a bounded temporary connection attempt.
8. Validate IP, gateway, DNS, and SSH safety.
9. Promote the network to known and validated only after success.
10. Roll back or return to AP recovery on failure.

The UI must not expose an action endpoint until the CLI path is validated.

## Lockout risks

Primary risks:

- SSH currently uses wlan0;
- no secondary interface exists;
- the node is headless;
- DHCP succeeds but route is wrong;
- DNS fails while IP appears valid;
- wrong PSK;
- AP disappears during validation;
- rollback cannot restore connectivity;
- temporary AP cannot start;
- one-radio AP/client conflict;
- timeout too short or too long.

Anti-lockout guardrails:

- plan-only default;
- explicit apply mode later;
- short bounded transaction;
- snapshot before mutation;
- rollback before commit;
- never persist until validation passes;
- detect SSH route before mutation;
- refuse unsafe cases by default;
- keep Flint/fallback metadata explicit;
- require physical access or second network path for first real tests.

## New Wi-Fi promotion

A new Wi-Fi becomes known only after the user explicitly selects it and the backend accepts a future temporary attempt.

A new Wi-Fi becomes validated only after:

- IP validation succeeds;
- route validation succeeds;
- DNS or gateway reachability succeeds;
- SSH safety is acceptable;
- rollback is no longer required;
- metadata is written without secrets.

If validation fails:

- do not promote the network;
- increment failure metadata if appropriate;
- roll back to previous network if possible;
- otherwise return to recovery/AP planning.

## Implementation order

Recommended sequence:

1. Keep current read-only UI and scan stable.
2. Add plan-only boot reconnect simulation.
3. Add local metadata schema docs.
4. Add read-only hardware capability checks.
5. Add connect-safe CLI apply behind explicit refusal-by-default gates.
6. Validate rollback on a lab node with physical access.
7. Only then design temporary AP apply.
8. Only then expose a UI action path.
