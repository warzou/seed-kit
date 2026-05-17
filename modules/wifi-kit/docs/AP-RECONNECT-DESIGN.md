# Wifi-Kit AP fallback and known-network reconnect design

Status: design plus gated hardware-test prototypes. AP test helpers remain
explicitly gated and must not run without a separate real-test validation.

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

Still forbidden in the normal product path:

- unattended hostapd start or configuration;
- dnsmasq start or configuration;
- persistent NetworkManager mutation;
- systemd-networkd mutation;
- wpa_supplicant mutation;
- wpa_cli select_network, enable_network, reconfigure, or save_config;
- route changes;
- IP changes;
- reboot;
- network restart;
- ungated real connect-safe apply;
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

- no known validated Wi-Fi works, or explicit recovery is requested;
- rollback to a previous client network is not possible;
- the hardware supports the requested mode;
- SSH safety rules accept the risk;
- the AP lifetime is bounded;
- the UI remains local and explicit.

Future AP mode may need hostapd and dnsmasq. The current AP-only radio test
uses hostapd only; it does not start dnsmasq and does not implement a captive
portal.

For V1, AP-only recovery is preferred over permanent AP+STA on the same radio.
When Wi-Fi is connected but internet validation fails, Wifi-Kit should not
blindly start AP automatically. It should first classify the failure: local
network available but no internet can still be a valid maintenance state. AP
auto-start should be reserved for no usable Wi-Fi, explicit recovery, or a
future policy that deliberately treats the current state as unrecoverable.

The first minimal AP radio test uses hostapd only. Real hostapd execution
requires root privileges because it must ask the kernel driver to change Wi-Fi
interface mode. Running hostapd without root is expected to fail with a driver
permission error such as `Could not set interface wlan0 flags (DOWN):
Operation not permitted`.

The future captive portal is a separate layer: AP plus dnsmasq DHCP/DNS, the
Wifi-Kit UI server, and Android/iOS captive-network detection endpoints. It is
not implemented by the minimal AP radio test.

## AP recovery UX target

The V1 recovery UX is an AP-only mode with local DHCP, local DNS, and the
Wifi-Kit mobile UI served from the node. It is entered only when no usable
Wi-Fi exists or when recovery is explicitly requested.

Target network:

```text
interface: wlan0
ssid: Wifi-Kit-<hostname>
ap_ip: 192.168.50.1/24
dhcp_range: 192.168.50.20-192.168.50.80
ui_url: http://192.168.50.1:8080/
```

Target startup order:

```text
snapshot NetworkManager state
disconnect wlan0 from NetworkManager
assign 192.168.50.1/24 to wlan0
start hostapd on wlan0
start dnsmasq with temporary config for DHCP and local DNS
start the local Python UI bound to 192.168.50.1
serve captive-network detection endpoints in a future UI layer
```

`dnsmasq` should be started with a temporary config under `/tmp`, not through a
persistent system service. It should bind only to the AP interface, hand out a
small private DHCP range, advertise `192.168.50.1` as router/DNS, and resolve
unknown names to the AP IP only during recovery.

The captive portal layer is intentionally separate from the radio/DHCP layer.
Future endpoints should cover common platform probes such as Android
`/generate_204`, Apple `/hotspot-detect.html`, and Windows network connectivity
checks. Those endpoints should redirect or serve the local Wifi-Kit UI without
requiring internet access.

Exit from recovery should happen through a future UI action:

1. User selects a Wi-Fi target and enters the password locally.
2. Wifi-Kit runs the NetworkManager connect-safe flow with rollback.
3. If validation succeeds, Wifi-Kit stops UI/dnsmasq/hostapd, deletes temporary
   configs, returns `wlan0` to NetworkManager, and stays in client mode.
4. If validation fails, Wifi-Kit keeps or restarts AP recovery so the user can
   correct the Wi-Fi settings.

No AP password, Wi-Fi password, admin password, or backend secret should be
written to repository files, persistent configs, or unredacted logs.

## Recovery guard

Wifi-Kit needs a small recovery guard before it grows a full systemd service.
The guard is a standalone, idempotent helper that can audit or clean up an
interrupted AP recovery session. Its default mode must be read-only.

Prototype:

```text
modules/wifi-kit/prototype/wifi-kit-recovery-guard.sh
```

Read-only modes:

- `status`: summarize known Wifi-Kit AP recovery runtime state;
- `audit`: status plus temporary files, NetworkManager state, and radio state.

Cleanup mode:

- stop only Wifi-Kit `hostapd` if the pidfile and process cmdline match the
  known temporary hostapd config path;
- stop only Wifi-Kit `dnsmasq` if the pidfile and process cmdline match the
  known temporary dnsmasq config path;
- remove Wifi-Kit pidfiles and temporary configs;
- keep logs by default, with a future explicit option to remove them;
- delete `wlan0_ap` only when it is the expected test interface and has a safe
  AP-like type;
- remove `192.168.50.1/24` from `wlan0` if present;
- set `wlan0` managed again when NetworkManager is available;
- reconnect the previous active NetworkManager connection best effort when the
  runtime state file exists.

The guard must not use aggressive `systemctl` operations. It must not stop a
global `dnsmasq.service`, kill unrelated dnsmasq or hostapd processes, reboot,
restart networking, call `save_config`, or touch non-Wifi-Kit files.

Future boot integration:

1. Run the guard early at boot, before starting the Wifi-Kit UI.
2. Audit first and log the result without secrets.
3. If stale Wifi-Kit runtime artifacts are detected, run cleanup.
4. Hand the node back to normal NetworkManager client mode.
5. Only after cleanup succeeds should recovery AP or UI flows be considered.

This protects the node from a crash or power loss during AP recovery where
hostapd, dnsmasq, `wlan0_ap`, or `192.168.50.1/24` might otherwise remain
half-configured.

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
- enter temporary AP-only recovery only if no known network works or explicit
  recovery is requested;
- keep AP mode bounded, explicit, and recovery-oriented;
- prefer a second Wi-Fi adapter if reliable AP plus client mode becomes a real
  requirement.

## Pocket-node AP radio test result

A first real hostapd test on `wlan0` confirmed that hostapd can start and
configure beacons, but it is not stable while NetworkManager owns the same
interface as the active client connection.

Observed hostapd log markers:

```text
nl80211: ssid=Wifi-Kit-pocket-node
nl80211: hidden SSID not in use
wlan0: AP-ENABLED
nl80211: Drv Event 16 (NL80211_CMD_STOP_AP) received for wlan0
Interface wlan0 is unavailable -- stopped
nl80211: Connect event
nl80211: Set drv->ssid based on scan res info to 'GL-MT6000-d53'
```

Interpretation:

- the SSID was not intentionally hidden;
- hostapd reached `AP-ENABLED`;
- NetworkManager/wpa_supplicant activity on `wlan0` triggered scan/connect
  events and the driver stopped AP mode;
- `wlan0` direct is not a good base for persistent AP plus STA behavior.

The follow-up dedicated AP virtual interface test used `wlan0_ap`, while
leaving `wlan0` under NetworkManager as the STA/client interface. Hostapd
started, the config contained `ssid=Wifi-Kit-pocket-node`, and the SSID was
not intentionally hidden, but the driver failed when setting beacons:

```text
wlan0_ap: AP-ENABLED
nl80211: Beacon set failed: -95 (Operation not supported)
Failed to set beacon parameters
```

During that test `wlan0_ap` ended up exposed as managed rather than a stable AP
interface, and the SSID was not visible from Windows or phone scans. Cleanup
stopped hostapd, removed `wlan0_ap`, and returned `wlan0` to NetworkManager.

Conclusion: AP+STA single-radio is not reliable enough for V1 on pocket-node /
Raspberry Pi Zero 2 W. Keep AP+STA as a lab-only investigation or use a second
Wi-Fi adapter for a product path that needs simultaneous AP and client mode.

The next V1 hardware path is AP-only recovery:

```text
snapshot NetworkManager state
nmcli device disconnect wlan0
hostapd -d /tmp/wifi-kit-hostapd-test.conf
stop hostapd
remove secret config
restore wlan0 to NetworkManager
reconnect previous active connection best effort
```

This path intentionally interrupts the current Wi-Fi client connection during
the recovery window, so it must be bounded, local, and rollback-aware.

AP-only prerequisites:

- `hostapd`;
- `dnsmasq` or `dnsmasq-base` for recovery DHCP/DNS;
- `nmcli`;
- `python3` for the current V1 local UI server;
- root privileges for NetworkManager disconnect/reconnect and hostapd;
- bounded max duration;
- runtime-only WPA2 passphrase;
- cleanup that deletes the secret config and keeps only logs plus redacted
  config.

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
7. Validate AP-only recovery with hostapd on lab hardware.
8. Add plan-only recovery UX with dnsmasq and local UI.
9. Validate recovery UX on lab hardware.
10. Only then expose a UI action path.
