# Module dependencies

## Goal

Seed-Kit modules can declare their dependencies in a small shell-readable form.

This is documentation first. It is not a dependency engine, not an orchestrator,
and not an installer.

## Shape

A module may expose:

```sh
module_<name>_dependencies
```

Each module may provide an equivalent declaration for its own domain. The
declaration belongs to the module, but Seed-Kit core remains the SAFE engine that
decides how declarations are displayed, checked, or used later.

The function prints plain lines:

```text
requires: network
requires: sudo
package-source: official Docker apt repository
package: docker-ce
package: docker-ce-cli
provides: docker
provides: docker compose
manual: add user to docker group only if explicitly desired
```

For richer modules, the declaration may also follow the generic module contract
described in `docs/MODULE-CONTRACT.md`. That contract covers metadata,
dependency levels, capabilities, files, target paths, runtime services,
privileged wrappers, sudoers requirements, readiness checks, rollback phases,
forbidden automatic actions, and secrets policy.

## Rules

- read-only output only
- V1 stays a simple shell declaration
- no package install
- no service start
- no secret handling
- no automatic dependency resolution
- no profile orchestration
- no rollback engine
- modules must not reimplement package managers such as apt, apk, or opkg

## CLI preview

The read-only helper is:

```sh
sh seed-kit.sh modules deps docker
```

It should print the module declaration and exit. It must not inspect the remote
network, run apt, call sudo, or mutate the machine.

## Ready model

Dependency declarations only describe what may be needed. They do not mean a
module or system package is ready for use.

Seed-Kit uses the Ready model to separate installation from configuration,
validation, and operator-owned identity steps. See `docs/READY-MODEL.md`.

## Wifi-Kit integration

Wifi-Kit is the first module expected to need host networking tools, a normal UI
service, a recovery/AP mode, and a privileged wrapper.

The core integration contract is documented in `docs/WIFI-KIT-INTEGRATION.md`.
That document is design-only for now: no sudoers, systemd unit, network change,
or runtime file install is implied by the dependency declaration. The reusable
contract model is documented in `docs/MODULE-CONTRACT.md`.

The Wifi-Kit declaration is owned by the Wifi-Kit module contract and consumed by
Seed-Kit core as a plan-only interface. The current core preview may expose:

- required system packages such as `python3`, `network-manager`, `hostapd`,
  `dnsmasq`, `iw`, `iproute2`, and recommended `rfkill`
- dependency levels: required, recommended, and conditional
- capabilities such as normal UI, Wi-Fi scan, return to default network,
  AP recovery, recovery guard, readiness checks, and uninstall preview
- target paths under `/opt/seed-kit/wifi-kit/`, `/etc/seed-kit/wifi-kit/`,
  `/var/log/seed-kit/wifi-kit/`, and `/run/seed-kit/wifi-kit/`
- the normal UI port `54321` and recovery captive portal port `80`
- the future wrapper-only sudoers boundary
- future sub-plans such as `install-packages`, `install-files`,
  `configure-sudoers-preview`, `install-service-preview`, `recovery-preview`,
  `readiness-preview`, and `uninstall-preview`

Those previews must stay read-only until a guided apply is explicitly designed
and validated.

Conditional dependency examples:

- Wi-Fi scan can work with NetworkManager, `nmcli`, `wpa_cli`, and `iw` without
  `hostapd` or `dnsmasq`
- normal UI needs `python3`, UI files, and a free port `54321`
- recovery AP needs `hostapd`, `dnsmasq`, the strict wrapper, and a validated
  sudoers rule
- `rfkill` is recommended for diagnostics but should not block base planning

## Why not a resolver yet?

Field use is still shaping the real module graph. A resolver would be premature
until repeated module pressure proves the exact behavior needed.

For now, declarations are useful for:

- operator review
- package-driven PRA planning
- future profile validation
- documenting manual post-install steps

## Non-goals

- no automatic install order
- no recursive dependency expansion
- no hidden module apply
- no machine restore
