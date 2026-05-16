# Wifi-Kit dependency declaration

Status: declarative module dependency contract. Wifi-Kit does not install
system packages by itself.

Seed-Kit core defines the module dependency model in
`docs/MODULE-DEPENDENCIES.md` starting with commit
`1ec3f4c docs: define module dependency declarations`. Wifi-Kit aligns with
that model by declaring what it needs, exposing read-only checks, and producing
plans that a future Seed-Kit core flow can orchestrate.

## Responsibility split

Wifi-Kit is responsible for:

- declaring runtime requirements for the Wifi-Kit module;
- detecting the active backend and current dependency state;
- exposing `doctor` / `check` style read-only output;
- producing a plan for missing packages and future capabilities;
- refusing `install --apply` until Seed-Kit core owns the reviewed install
  orchestration.

Seed-Kit core is responsible for the future cross-module dependency flow:

- reading module dependency declarations;
- showing the combined plan to the operator;
- requesting explicit approval;
- invoking the correct module hooks in a controlled install phase;
- keeping install policy consistent across modules.

Wifi-Kit should therefore avoid becoming a standalone package manager.

## Current backend

The official Raspberry Pi OS backend is:

```text
raspberrypi-networkmanager
```

NetworkManager owns `wlan0` on the validated `pocket-node` target. Direct
`wpa_cli` mutation is a legacy/lab fallback and must refuse when NetworkManager
owns the interface.

## Current capabilities

Wifi-Kit currently exposes:

- read-only backend and runtime status;
- NetworkManager read-only preflight;
- dependency `check`;
- dependency `plan`;
- dependency `install --dry-run`;
- intentional refusal for dependency `install --apply`;
- NetworkManager connect-safe plan and preflight, with real apply gated
  separately.

No dependency command starts services, changes Wi-Fi, launches AP mode, calls
`save_config`, or reads secrets.

## Dependency classes

### required

Required for the current Raspberry Pi OS NetworkManager backend:

- `ip` package `iproute2`
- `iw` package `iw`
- `wpa_cli` package `wpasupplicant`
- `wpa_supplicant` package `wpasupplicant`
- `ping` package `iputils-ping`
- `nmcli` package `network-manager`
- `systemctl` package `systemd`

### optional

Useful for operator workflows or local UI/dev support, but not required for the
core NetworkManager runtime path:

- `ssh` package `openssh-client`
- `python3` package `python3`

### future_ap

Needed later for real AP/configuration hotspot work, but not required by the
current NetworkManager connect-safe backend:

- `hostapd` package `hostapd`
- `dnsmasq` package `dnsmasq`

These stay separate because AP mode has additional radio, service, channel, and
rollback risks. Installing packages is not the same as enabling AP behavior.

## Commands

Prototype dependency helper:

```text
modules/wifi-kit/prototype/wifi-kit-deps.sh
```

Read-only check:

```text
sh modules/wifi-kit/prototype/wifi-kit-deps.sh check
```

Plan-only output:

```text
sh modules/wifi-kit/prototype/wifi-kit-deps.sh plan
```

Dry-run install plan:

```text
sh modules/wifi-kit/prototype/wifi-kit-deps.sh install --dry-run
```

Intentional refusal:

```text
sh modules/wifi-kit/prototype/wifi-kit-deps.sh install --apply
```

`install --apply` is refused on purpose until Seed-Kit core provides the
reviewed orchestration layer for real installs.

## Why Wifi-Kit does not install directly

Wifi-Kit is a module, not the system-level package orchestrator. Direct package
installation inside the module would duplicate Seed-Kit core policy, make
cross-module planning harder, and blur the safety boundary around service
installation.

The safe current contract is:

1. Wifi-Kit declares and checks dependencies.
2. Wifi-Kit reports missing packages and capability classes.
3. Seed-Kit core later coordinates approved installs across modules.
4. Wifi-Kit keeps all network mutation, AP mode, and dependency installation
   behind explicit gates.

