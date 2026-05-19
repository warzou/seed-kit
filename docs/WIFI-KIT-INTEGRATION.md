# Wifi-Kit integration design

## Goal

Wifi-Kit is the Seed-Kit module for local Wi-Fi recovery and onboarding.

This document prepares the core integration contract only. It does not install
Wifi-Kit, write sudoers files, install systemd units, start access points, or
change networking.

## Scope V1

Seed-Kit core should eventually provide:

- a read-only plan
- dependency declaration
- validation checks
- guided install steps
- explicit privileged boundaries
- post-install tests

Seed-Kit core must not turn Wifi-Kit into hidden orchestration. Every network
changing action must stay explicit, inspectable, and operator confirmed.

## System dependencies

Wifi-Kit depends on host-level tools rather than Docker:

- `NetworkManager` / `nmcli`
- `wpa_cli`
- `hostapd`
- `dnsmasq`
- `python3`
- `iw`
- `iproute2`
- `rfkill` when available

The dependency declaration should remain shell-readable and read-only. Seed-Kit
core may display or validate it later, but should not implement a dependency
resolver until field use proves the exact behavior needed.

Example declaration shape:

```sh
module_wifi_kit_dependencies
```

```text
requires: debian-like
requires: sudo
package: network-manager
package: wpasupplicant
package: hostapd
package: dnsmasq
package: python3
package: iw
package: iproute2
package: rfkill
provides: wifi-kit ui
provides: wifi recovery ap
manual: configure recovery SSID/password outside Git
manual: validate sudoers before enabling privileged actions
```

## File layout

Stable paths should keep code, config, logs, and runtime state separate:

```text
/opt/seed-kit/wifi-kit/        installed module runtime files
/etc/seed-kit/wifi-kit/        persistent local config
/var/log/seed-kit/wifi-kit/    logs
/run/seed-kit/wifi-kit/        runtime pid/state sockets
```

Temporary recovery data may use `/run` or `/tmp` only when cleanup is strict and
the data is not needed after reboot.

## Normal UI service

The normal UI target is:

- port: `54321`
- user: non-root if possible
- start: automatic only after explicit install/apply design is accepted
- boot behavior: normal UI only, no AP recovery at boot by default

The normal service must not start `hostapd`, `dnsmasq`, or captive recovery by
itself.

## Recovery/AP mode

Recovery mode is a separate explicit action:

- captive portal port: `80`
- AP tools: `hostapd` and `dnsmasq`
- lifetime: temporary
- cleanup: strict

Recovery cleanup must only stop Wifi-Kit-owned processes and must return `wlan0`
to NetworkManager ownership when possible. It must not broadly kill unrelated
network services.

## Privileged wrapper

Privileged operations should go through one root-owned wrapper with a narrow
action whitelist.

Initial allowed actions:

- `start-ap-mode`
- `return-default-network`

Rules:

- no arbitrary shell
- no free-form user command parameters
- no direct sudo access to implementation scripts
- no secrets printed to logs
- sudoers grants only `NOPASSWD` for the wrapper path
- sudoers is not applied until the design and install step are explicitly
  validated

Seed-Kit should generate or install sudoers only in a later guided step with a
clear preview and confirmation.

## Boot cleanup guard

A future guard should handle incomplete recovery sessions after reboot.

It should:

- run at boot before or alongside the normal UI service
- remove only Wifi-Kit runtime state
- stop only Wifi-Kit-owned `hostapd`/`dnsmasq` processes
- hand `wlan0` back to NetworkManager when possible
- avoid reboot, broad network restart, or global service resets

## Persistent configuration

Persistent config belongs under `/etc/seed-kit/wifi-kit/`.

Expected fields:

- normal UI port, default `54321`
- recovery SSID
- recovery AP password
- default known network label or id
- interface, default `wlan0`

Rules:

- no secrets in Git
- strict permissions for config containing local secrets
- no Wi-Fi PSK copied into Seed-Kit package metadata or logs
- NetworkManager/wpa_supplicant remain the source of truth for Wi-Fi secrets

## Future Seed-Kit flow

The future safe flow should be staged:

```text
plan -> validate -> apply-guided -> post-install tests
```

Planned commands may look like:

```sh
sh seed-kit.sh modules deps wifi-kit
sh seed-kit.sh --plan --modules=wifi-kit
sh seed-kit.sh --apply --modules=wifi-kit
```

V1 apply, once implemented, should install files and dependencies only. It
should not start AP mode, reconnect Wi-Fi, or write sudoers until those guided
steps are individually designed and confirmed.

## Non-goals

- no hidden network cutover
- no reboot
- no broad network restart
- no automatic AP at boot
- no manual sudoers edits on target nodes
- no stored Wi-Fi secrets in Git
- no Docker, Homepage, or Caddy dependency
- no cloud sync
- no generic orchestration engine

## Risks to resolve before apply

- exact package names differ across Debian, Raspberry Pi OS, and OpenWRT
- NetworkManager and wpa_supplicant ownership can conflict
- `hostapd`/`dnsmasq` must not disturb existing services
- port `80` requires root or a controlled privilege boundary
- sudoers mistakes can create privilege escalation
- recovery cleanup must avoid breaking the current SSH path

