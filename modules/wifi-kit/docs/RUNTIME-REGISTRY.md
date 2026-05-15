# Wifi-Kit runtime registry plan

Status: prototype fixture only. No runtime file under `/etc` is created by this
work.

The Wifi-Kit runtime registry is the future local metadata layer used to decide
which Wi-Fi networks should be attempted at boot and which network is the
fallback candidate.

The registry must never contain Wi-Fi secrets. It stores metadata only.
Credentials remain owned by the platform network backend, for example
wpa_supplicant on Raspberry Pi OS Lite or a future OpenWRT backend.

## Fixture scope

Current files are fixtures under the repository:

```text
modules/wifi-kit/fixtures/registry/known-networks.fixture.json
```

They are intended for local parsing and plan-only tests. They are not installed
and are not runtime state.

## JSON format

Top-level fields:

- `schema`: fixture schema identifier.
- `metadata`: notes and safety flags.
- `known_networks`: list of network metadata entries.
- `last_success`: last validated connection metadata.
- `fallback_network`: fallback network metadata.

Network fields:

- `ssid`: local SSID label. Treat as potentially sensitive in logs.
- `ssid_hash`: redacted/hash-friendly identifier for logs.
- `priority`: lower number means earlier boot candidate.
- `favorite`: optional preference flag.
- `validated`: true only after successful validation.
- `role`: `primary`, `fallback`, or `candidate`.
- `backend`: planned backend identifier, such as `rpios-wpa`.
- `interface`: expected Wi-Fi interface.
- `expected_gateway`: optional validation hint.
- `last_success`: last successful validation timestamp.
- `last_failure`: last failed attempt timestamp.
- `retry_count`: metadata counter only.

Forbidden fields:

- PSK;
- passphrase;
- password;
- wpa_supplicant network blocks;
- private keys;
- tokens;
- Tailscale state;
- host SSH keys.

## Boot candidate rules

The plan-only prototype uses a deliberately simple ordering:

1. Include only networks with `validated=true`.
2. Sort by ascending `priority`.
3. Prefer `favorite=true` when priority is otherwise equal.
4. Keep the `fallback_network` visible as the recovery candidate.
5. Report inconsistent data rather than trying to fix it.

## Safety guarantees

The current prototype:

- reads only repository fixtures;
- does not read `/etc`;
- does not write runtime state;
- does not call wpa_cli;
- does not call hostapd;
- does not call dnsmasq;
- does not expose UI actions;
- does not store or print secrets.