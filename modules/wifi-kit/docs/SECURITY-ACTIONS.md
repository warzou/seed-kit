# Wifi-Kit Privileged UI Actions

Wifi-Kit normally runs its mobile UI without root privileges. Some recovery-test
actions need root because they temporarily change Wi-Fi mode or ask
NetworkManager to reconnect a known profile.

This document defines the prototype safety model. It is not an installer and it
does not modify sudoers automatically.

## Goals

Allow the UI to trigger only these actions:

- `start-ap-mode`
- `return-default-network`

Everything else must be refused.

## Wrapper

Prototype wrapper:

```sh
modules/wifi-kit/prototype/wifi-kit-action-wrapper.sh
```

The wrapper accepts exactly one argument and whitelists the action name.

`start-ap-mode` runs the already validated AP recovery flow:

- SSID: `Wifi-Kit-<hostname>`
- AP password test value: `12345678`
- timeout: `300` seconds
- hostapd, dnsmasq, and captive UI remain temporary
- no secret is written to repository files or wrapper logs

`return-default-network` only runs:

```sh
nmcli connection up "netplan-wlan0-GL-MT6000-d53"
```

No client-provided connection name is accepted.

Wrapper log:

```text
/tmp/wifi-kit-action-wrapper.log
```

The log contains timestamps, action names, and statuses. It must not contain
Wi-Fi passwords.

## Backend Activation

The UI backend keeps privileged actions disabled by default.

To allow the backend to call the wrapper, the process must be started with:

```sh
WIFI_KIT_ENABLE_PRIVILEGED_ACTIONS=1
```

When the variable is absent, `POST /start-ap-mode` and
`POST /return-default-network` return a planned response and do not mutate the
system.

When enabled, the backend calls:

```sh
sudo -n sh modules/wifi-kit/prototype/wifi-kit-action-wrapper.sh start-ap-mode
sudo -n sh modules/wifi-kit/prototype/wifi-kit-action-wrapper.sh return-default-network
```

`sudo -n` is required so HTTP requests never block waiting for an interactive
password prompt. If sudo is not authorized, the backend returns:

```text
privileged-action-not-authorized
```

Before launching an action, the backend checks the exact wrapper command with
`sudo -n -l`. This keeps the probe non-mutating while still matching the
command-specific sudoers rule.

## Future sudoers Shape

Seed-Kit should install any sudoers rule later, after an explicit dependency and
security flow. A future rule should be restricted to the wrapper path and the
service account that runs Wifi-Kit.

Wifi-Kit exposes the sudoers rule shape as a read-only contract for Seed-Kit
core previews:

```sh
sh modules/wifi-kit/contract/sudoers.manifest.sh print
```

Seed-Kit core should consume this manifest for `configure-sudoers-preview`.
The manifest describes the installed wrapper path, expected ownership, exact
allowed actions, exact allowed commands, forbidden broad sudo shapes, and
readiness checks. It does not write `/etc/sudoers`, call `visudo`, start AP
mode, or change networking.

Example shape only, not applied by this repository:

```text
seed-kit-wifi ALL=(root) NOPASSWD: /opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh start-ap-mode, /opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh return-default-network
```

The real path must be absolute and owned by a trusted user. Seed-Kit should
avoid broad rules such as `ALL`, unrestricted `nmcli`, unrestricted `sh`, or any
wildcard that permits arbitrary parameters.

The placeholder service user is currently `seed-kit-wifi`. Seed-Kit core may
validate or refine the final service account before any future apply.

## Explicit Non-Goals

- no broad sudo
- no arbitrary shell commands from HTTP
- no user-provided command parameters
- no reboot
- no `save_config`
- no aggressive `systemctl`
- no automatic sudoers modification in the prototype

## Risks

- Starting AP mode intentionally interrupts normal Wi-Fi access while recovery
  starts.
- Returning to the default network is restricted to the current test profile
  `netplan-wlan0-GL-MT6000-d53`; this should become a managed runtime setting
  later.
- The wrapper path and file ownership matter. A production installation must
  ensure the wrapper cannot be edited by the unprivileged UI user.
