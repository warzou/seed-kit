# Wifi-Kit runtime validation

This note records the validated runtime state for the current Wifi-Kit
prototype on `pocket-node`.

## Validated state

- Normal UI is available on port `54321`.
- Normal UI is installed as `wifi-kit-ui.service`.
- The service runs from `/opt/seed-kit/wifi-kit`.
- The validated process shape is:
  `/usr/bin/python3 ui/serve-readonly.py --host 0.0.0.0 --port 54321`.
- Port `54321` listens on `0.0.0.0`.
- Explicit AP recovery mode starts successfully.
- Recovery UI is available on port `80` while AP mode is active.
- `return-default-network` from the AP UI returns to the configured main Wi-Fi.
- The sudoers rule and privileged wrapper work for the allowed Wifi-Kit actions.
- `wifi-kit-boot-guard.service` is installed and enabled.
- `runtime.conf` is owned by `warzy:warzy`.
- `~/.config/wifi-kit` is mode `0700`.
- `~/.config/wifi-kit/runtime.conf` is mode `0600`.
- Runtime config persists the validated last-good Wi-Fi:
  - `last_good_connection=netplan-wlan0-GL-MT6000-d53`
  - `last_good_ssid=GL-MT6000-d53`
- The `/opt` runtime validation was completed after
  `afa3387 fix: install wifi-kit UI service from opt runtime`.
- No AP start, Wi-Fi change, profile deletion, or reboot occurred during the
  `/opt` service validation.

## Seed-Kit install/reinstall flow validated

The Seed-Kit install entrypoint was validated on `pocket-node` after:

- `e9fabb9 feat: add wifi-kit reinstall flow`

Validated command:

```sh
sh seed-kit.sh install wifi-kit
```

The command detected the existing runtime install and prompted:

```text
[wifi-kit] already installed
reinstall? [y/N]
```

Answering `y` completed the reinstall flow:

```text
status=done
apply module completed
[OK] wifi-kit
```

Post-install validation:

- `wifi-kit-ui.service` is `enabled` and `active`.
- `wifi-kit-boot-guard.service` is `enabled` and `inactive`, which is normal
  for this oneshot outside boot/start.
- Port `54321` listens on `0.0.0.0`.
- Local UI check returned `UI_LOCAL_OK`.
- LAN UI check returned `UI_LAN_OK`.
- `/etc/sudoers.d/wifi-kit` parsed OK with `visudo`.
- `/opt/seed-kit/wifi-kit` was updated by the reinstall.
- `~/.config/wifi-kit/runtime.conf` was preserved as `warzy:warzy` mode `0600`.
- No AP start, Wi-Fi change, Wi-Fi profile deletion, or reboot occurred.

## Short install output validated

After `fa316ca feat: simplify wifi-kit install output`, the default
`sh seed-kit.sh install wifi-kit` output was validated on `pocket-node` with
answer `n`.

The default output now shows a short summary:

- install user;
- `/opt` target;
- UI port `54321`;
- sudoers presence;
- systemd unit presence for UI and boot guard;
- runtime config presence.

For an already installed runtime, the command still shows:

```text
[wifi-kit] already installed
reinstall? [y/N]
```

Answering `n` aborts cleanly before sudo or install. The verbose path was also
validated:

```sh
WIFI_KIT_VERBOSE=1 sh seed-kit.sh install wifi-kit
```

Verbose mode prints the raw audit, plan, sudoers preview, and systemd unit
previews. No sudo, install, AP start, Wi-Fi change, or reboot occurred during
the short-output validation.

## Backend status and public JSON redaction validated

After `6743521 fix: restart wifi-kit UI after runtime install`, the runtime was
redeployed on `pocket-node` with:

```sh
sh seed-kit.sh install wifi-kit
```

The reinstall completed with:

```text
wifi-kit-ui=enabled-restarted
wifi-kit-boot-guard=enabled
[OK] wifi-kit
```

The UI restart reloaded the installed backend from `/opt/seed-kit/wifi-kit`.
The following endpoints were validated:

- `/status`
- `/api/ui-data`
- `/api/runtime-config`
- `/api/backend-status`

The public JSON redaction check confirmed that none of these endpoints exposed:

- `12345678`
- `TestAP9876`
- `ap_password_current`
- `recovery_ap_password_current`
- `"ap_password":`

`/api/backend-status` returned runtime mode with actions available, install
state OK, and runtime config readable. No AP start, Wi-Fi change, profile
deletion, or reboot occurred during this validation.

## POST action JSON contract validated

After `c7e52e1 fix: normalize wifi-kit POST action responses`, the real
systemd service from `/opt/seed-kit/wifi-kit` was validated on `pocket-node`.
The temporary repo-launched server was stopped before the test.

Non-destructive POST error cases returned the common action response shape:

```json
{
  "ok": false,
  "action": "wifi-connect-transaction",
  "status": "refused",
  "message": "missing-ssid",
  "error": "missing-ssid",
  "log": ""
}
```

for:

```sh
POST /wifi/connect
{}
```

and:

```json
{
  "ok": false,
  "action": "runtime-config",
  "status": "refused",
  "message": "ap-password-too-short",
  "error": "ap-password-too-short",
  "log": ""
}
```

for:

```sh
POST /api/runtime-config
{"ap_password":"short"}
```

`wifi-kit-ui.service` remained active and port `54321` remained listening.
No AP start, Wi-Fi change, profile deletion, or reboot occurred during this
validation.

## Boot guard model

The minimal boot guard uses this order:

1. Try `last_good_connection` and require Internet validation.
2. Try `return_connection` / main Wi-Fi if last-good is missing or fails.
3. Start AP recovery mode only if the Wi-Fi attempts fail.

The validation criteria are intentionally narrow:

- `last_good_connection` must restore NetworkManager connectivity and pass the
  current Internet probe: default route plus ping.
- `return_connection` may succeed as LAN-only. Internet is probed after the
  connection, and a successful probe updates `last_good_connection` /
  `last_good_ssid`, but failed Internet does not force AP recovery if the main
  Wi-Fi profile connected.
- DNS resolution and `sshd` health are not boot-guard criteria yet.
- `wifi-kit-boot-guard.service` is a `oneshot` service. It is expected to be
  `enabled` and then `inactive` after a completed run.

AP recovery remains explicit and temporary. It stays active until the user asks
Wifi-Kit to return to the main Wi-Fi.

## Runtime disconnect policy

Runtime disconnects are intentionally different from boot recovery.

If the node already had a valid Wi-Fi connection during runtime and later loses
that connection, Wifi-Kit should prefer the last validated Wi-Fi. It must not
fall back automatically to the configured return/main Wi-Fi during runtime.
AP recovery is a boot-time fallback after bounded startup recovery fails, or an
explicit user action.

Target policy names:

- `runtime_disconnect_policy=ap_after_grace_then_return_check`
- `runtime_retry_target=last_good_connection`
- `runtime_retry_timeout=indefinite-or-configurable`
- `boot_recovery_policy=ap_after_timeout`
- `ap_recovery_actions=new_wifi|retry_primary|stay_ap`

The runtime recovery watchdog makes this policy explicit for installed nodes:

- `runtime_recovery_enabled=true` by default;
- `runtime_recovery_grace_seconds=30` by default;
- `runtime_recovery_instability_window_minutes=10` by default;
- `runtime_recovery_instability_threshold=3` by default.

When `last_good_connection` / `last_good_ssid` has been active during runtime
and then disappears, the watchdog starts a grace timer. If last-good returns
before the timer expires, it logs `recovery-cancelled link-restored`. If it is
still absent after the grace period, it starts AP recovery through the existing
wrapper. From AP recovery, the periodic return-check loop takes over and tests
only `last_good_*`; it does not try `return_connection` unless that is also the
last-good target.

If the same SSID disconnects at least
`runtime_recovery_instability_threshold` times within
`runtime_recovery_instability_window_minutes`, the watchdog writes/logs an
`unstable-ssid` state for the backend/UI to expose. This is a diagnostic hint,
not a destructive action.

`return_connection` is a boot-only fallback. NetworkManager autoconnect for the
return/main Wi-Fi may be disabled after a successful Wifi-Kit connection when it
differs from `last_good_connection`; the boot guard can still use it explicitly
with `nmcli connection up`.

The AP recovery UI must not treat AP mode as abandoning the main Wi-Fi. While
in AP recovery it should clearly offer:

1. configure a new Wi-Fi;
2. retry the configured main Wi-Fi;
3. stay in AP recovery.

## AP return-check run-once validated

The AP return-check `run-once` flow was validated on `pocket-node` from active
AP recovery mode.

Validated behavior:

- `ap-return-check-once` stopped AP recovery.
- Wifi-Kit reconnected to `GL-MT6000-d53`.
- `wlan0` returned with IP `192.168.8.163/24`.
- The default route returned through `192.168.8.1`.
- The return-check log contained:
  - `status=ap-stop-starting`
  - `status=connect-starting`
  - `status=success`
- The normal UI on port `54321` was active after the return.
- `/api/backend-status` returned OK.
- The old preview server was stopped; the active backend was the installed
  `/opt` service.

## AP recovery return-check option

Permanent parallel AP+STA mode is not the target behavior for Raspberry Pi Zero
2 W class hardware. Field and lab work showed that a single-radio permanent
AP+STA assumption is not reliable enough for the product path.

The safer recovery option is a periodic return check while the node is already
in AP recovery:

- `return_check_enabled=false` by default;
- `return_check_interval_minutes=1` by default in the runtime UI;
- `return_check_target=last_good_ssid`;
- `return_check_mode=periodic-from-ap`.

When enabled, Wifi-Kit may periodically pause normal AP recovery activity long
enough to test whether the last good SSID is visible again. If the target is
detected, it may attempt a controlled reconnect to the configured main Wi-Fi.
If that reconnect succeeds, Wifi-Kit exits AP recovery and returns to normal
mode. If it fails, Wifi-Kit returns to or remains in AP recovery.

This check must be punctual, bounded, and compatible with one Wi-Fi radio. It
must not be implemented as a permanent AP+STA mode. The motivating field case
is a remote box reboot: the node may be in local AP recovery while the upstream
box is unavailable, then return by itself when the last good SSID comes back.

## Field incident note

A real field incident confirmed why runtime disconnects should not immediately
open AP recovery. The Flint 2.4 GHz environment was disturbed by an older
client WWAN / pocket-box interface. `pocket-node` became temporarily
unreachable, but later returned successfully after the WWAN side was disabled
on Flint.

Conclusion: during a runtime outage after a previously valid Wi-Fi session,
Wifi-Kit should keep trying the known main Wi-Fi instead of automatically
switching to AP recovery. AP recovery remains the correct fallback at boot when
no usable Wi-Fi is recovered within a configurable timeout.

## Remaining install work

This runtime state was validated manually on the prototype target. A future
Seed-Kit install integration still needs to own the durable installation flow:

- install files under `/opt/seed-kit/wifi-kit/`;
- install and validate the sudoers drop-in;
- install and enable the normal UI and boot guard services;
- manage runtime config path and permissions;
- keep AP recovery separate from normal boot unless Wi-Fi recovery fails.

The validated runtime behavior should be treated as the target behavior for
that future installer work, not as a complete Seed-Kit apply implementation.

## Known installer gaps / next integration steps

- `install_user` is still targeted to `warzy` in the prototype path.
- Systemd units should be generated dynamically by the future Seed-Kit install
  flow instead of carrying pocket-node-specific values.
- Upgrade and overwrite behavior must be designed explicitly before replacing
  existing sudoers or systemd units.
- The future target command should become:

```sh
seed-kit install wifi-kit
```
