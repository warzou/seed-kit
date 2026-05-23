# Wifi-Kit runtime validation

This note records the validated runtime state for the current Wifi-Kit
prototype on `pocket-node`.

## Validated state

- Normal UI is available on port `54321`.
- Explicit AP recovery mode starts successfully.
- Recovery UI is available on port `80` while AP mode is active.
- `return-default-network` from the AP UI returns to the configured main Wi-Fi.
- The sudoers rule and privileged wrapper work for the allowed Wifi-Kit actions.
- `wifi-kit-boot-guard.service` is installed and enabled.
- Runtime config persists the validated last-good Wi-Fi:
  - `last_good_connection=netplan-wlan0-GL-MT6000-d53`
  - `last_good_ssid=GL-MT6000-d53`

## Boot guard model

The minimal boot guard uses this order:

1. Try `last_good_connection` and require Internet validation.
2. Try `return_connection` / main Wi-Fi if last-good is missing or fails.
3. Start AP recovery mode only if the Wi-Fi attempts fail.

AP recovery remains explicit and temporary. It stays active until the user asks
Wifi-Kit to return to the main Wi-Fi.

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
