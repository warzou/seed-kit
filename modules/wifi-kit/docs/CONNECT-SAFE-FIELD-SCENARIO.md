# Wifi-Kit connect-safe field scenario: GL-MT6000-d53 to SFR_7B28

Status: first temporary field test succeeded. The target profile remained
runtime-only and was removed after forced rollback.

This document records the first field scenario for connect-safe and keeps the
runtime-only safety boundaries explicit.

## Scenario

Current stable network A:

```text
GL-MT6000-d53
```

Future temporary target network B:

```text
SFR_7B28
```

Rollback / fallback network:

```text
GL-MT6000-d53
```

## Secret policy

The target network passphrase is temporary operator input only. It must never be
committed, pushed, written to fixtures, logged, printed in diffs, or stored in
Wifi-Kit metadata.

The fixture represents this with:

```text
secret_source=operator-runtime-only
```

## Future apply flow

The first real test must remain temporary and rollbackable:

1. Snapshot current network A, IP, route, gateway, backend state, and SSH safety.
2. Prepare target B as a temporary attempt.
3. Wait for DHCP/IP with a short timeout.
4. Validate default route.
5. Validate gateway or bounded reachability.
6. Validate SSH safety or rediscovery path.
7. Report temporary success only.
8. Roll back automatically to A for the first field test.
9. Validate rollback to A.
10. Do not persist and do not promote B during the first apply test.

## First successful temporary field test

The first successful temporary A -> B -> rollback test was performed on
`pocket-node` with rollback forced even though the target network validated.

Observed networks:

```text
A / rollback: GL-MT6000-d53
B / target:   SFR_7B28
```

Target validation:

```text
target_ssid=SFR_7B28
target_ip=192.168.1.37
target_gateway=192.168.1.1
gateway_ping=OK
reachability_ping=OK
```

The apply instrumentation detected stale A-side network state during the
transition and waited for fresh B-side DHCP/route data before validation:

```text
stale_ip_detected=yes
stale_gateway_detected=yes
previous_ip=192.168.8.163
previous_gateway=192.168.8.1
fresh_target_ip=192.168.1.37
fresh_target_gateway=192.168.1.1
```

Rollback and cleanup:

```text
rollback_ssid=GL-MT6000-d53
rollback_validated=yes
cleanup_temporary_profile=done
target_profile_present_final=no
save_config=not-called
final_readiness=OK
```

No target passphrase was committed, logged, written to a fixture, or stored in
Wifi-Kit metadata. The target secret was provided as runtime-only operator
input for the temporary test.

## Rediscovery strategy

Because the IP may change after moving to SFR_7B28, the operator should prepare
at least one rediscovery path before any future real apply:

- DHCP lease lookup on the target router;
- hostname resolution, for example `pocket-node.lan`, if supported;
- Tailscale or another independent management path if present;
- automatic rollback to GL-MT6000-d53;
- physical access for the first real test.


## Future runtime-only target profile creation

Discovery on `pocket-node` showed the current rollback network in
`wpa_cli list_networks`:

```text
network id: 0
ssid: GL-MT6000-d53
flags: [CURRENT]
```

This id is only a current observation. It must be revalidated immediately before
any future apply test because backend network ids can change.

The target network `SFR_7B28` is visible in scan results but is not currently
present in `wpa_cli list_networks`. A future real test therefore needs a
runtime-only temporary profile for B.

Planned future command family, shown as documentation only:

```sh
# read-only preflight
wpa_cli -i wlan0 list_networks
wpa_cli -i wlan0 status

# future apply phase only: create temporary B profile
TARGET_ID="$(wpa_cli -i wlan0 add_network)"
wpa_cli -i wlan0 set_network "$TARGET_ID" ssid '"SFR_7B28"'

# future apply phase only: runtime secret, never logged
wpa_cli -i wlan0 set_network "$TARGET_ID" psk '"<RUNTIME_SECRET_NOT_LOGGED>"'

# future apply phase only: temporary attempt
wpa_cli -i wlan0 select_network "$TARGET_ID"

# future rollback
wpa_cli -i wlan0 select_network "$ROLLBACK_ID"

# future cleanup of temporary B profile
wpa_cli -i wlan0 remove_network "$TARGET_ID"

# forbidden for the first field test
# wpa_cli -i wlan0 save_config
```

Important boundaries:

- `add_network` is future apply only;
- `set_network ssid` is future apply only;
- `set_network psk` must receive the secret at runtime only;
- the real passphrase must never be committed, pushed, logged, displayed in a
  diff, written to a fixture, or stored in Wifi-Kit metadata;
- `select_network` is future apply only;
- rollback must target the revalidated id for `GL-MT6000-d53`;
- `remove_network` should remove the temporary `SFR_7B28` profile after the
  test;
- `save_config` remains forbidden for the first field test;
- the first field test should roll back to `GL-MT6000-d53` even if `SFR_7B28`
  works.

Operator confirmations required before any future real apply:

- confirm this is `pocket-node`;
- confirm physical access or a secondary management path exists;
- confirm `GL-MT6000-d53` is still `[CURRENT]`;
- confirm the rollback id was revalidated immediately before the attempt;
- confirm `SFR_7B28` is visible or intentionally targeted;
- confirm the target secret will be provided runtime-only;
- confirm no `save_config` will be executed;
- confirm the temporary target profile will be removed after the test;
- confirm rollback to `GL-MT6000-d53` is required even on target success.

## Recommended initial timeouts

```text
wait_ip_seconds=30
validation_seconds=20
rollback_seconds=30
rediscovery_seconds=60
```

These values are intentionally conservative and easy to reason about. They can
be tuned after dry-run review on the target node.

## Still missing before real apply

- read-only profile ID discovery;
- runtime-only secret input design;
- SSH safety gate;
- DHCP lease rediscovery procedure;
- rollback proof on GL-MT6000-d53;
- explicit operator confirmation gate;
- no persistence boundary review.

## Safety boundaries

This scenario does not call `wpa_cli`, does not select a network, does not call
`save_config`, does not restart networking, does not run hostapd or dnsmasq,
does not reboot, does not read `/etc`, and does not store secrets.
