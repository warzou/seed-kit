# Module contract

## Goal

Seed-Kit modules may publish a small, shell-readable contract that Seed-Kit core
can display, validate later, and eventually apply through guided SAFE steps.

The contract belongs to the module. Seed-Kit core consumes it. Core must not
reimplement module-specific runtime behavior or hide privileged/network actions
behind generic orchestration.

## Contract sections

A module contract may describe:

- module metadata: id, type, platform, backend, and modes
- required dependencies
- recommended dependencies
- optional or conditional dependencies
- capabilities
- installable files
- target paths
- runtime services
- privileged wrappers
- sudoers requirements
- persistent config
- volatile runtime directories
- readiness checks
- health checks
- install phases
- rollback phases
- forbidden automatic actions
- secrets policy

## Dependency levels

Required dependencies are needed for the base module flow. Missing required
dependencies should block a future real apply for the relevant phase.

Recommended dependencies improve behavior but are not hard blockers. For
example, `rfkill` is useful for radio diagnostics but should not block every
Wifi-Kit preview.

Conditional dependencies are tied to capabilities or phases. For example,
Wifi-Kit scan/read-only status can work without `hostapd` and `dnsmasq`, but
recovery AP mode requires them together with a privileged wrapper and strict
sudoers rule.

## Capabilities

Capabilities describe what a module can do without implying that Seed-Kit will
do it automatically.

Examples:

- normal UI
- Wi-Fi scan
- AP recovery
- privileged recovery wrapper
- boot cleanup guard
- readiness diagnostics
- uninstall preview

Each capability should state its dependency needs and whether it is read-only,
persistent, privileged, or network-changing.

## Seed-Kit core role

Seed-Kit core may:

- show the contract
- plan phases
- validate read-only prerequisites
- stage files for inspection
- guide explicit operator-confirmed steps
- report readiness and health

Seed-Kit core must not:

- run arbitrary module commands
- infer broad sudoers rules
- write secrets into Git
- start network-changing modes without explicit action
- reboot or restart networking as a generic module behavior
- delete user data without explicit confirmation

## CLI shape

Current modules expose plain shell functions:

```sh
module_<name>_dependencies
module_<name>_plan
```

Those functions print plain text and remain read-only. A future structured
format can be added once repeated modules prove the exact fields needed.

Current examples:

```sh
sh seed-kit.sh modules deps wifi-kit
sh seed-kit.sh --plan --modules=wifi-kit
sh seed-kit.sh modules validate wifi-kit
```

## Wifi-Kit reference mapping

Wifi-Kit is the first concrete contract that exercises conditional dependencies,
privileged wrappers, sudoers preview, systemd preview, recovery mode, and
network safety boundaries.

Wifi-Kit maps to this contract as:

- metadata: `id=wifi-kit`, `type=network-ui`, `platform=raspberrypi/debian`,
  `backend=networkmanager`, `mode=normal-ui + ap-recovery`
- required dependencies: `python3`, `network-manager`, `nmcli`, `wpa_cli`,
  `iw`, `iproute2`
- recommended dependencies: `rfkill`
- conditional dependencies: `hostapd` and `dnsmasq` for recovery AP mode
- capabilities: normal UI, scan, default Wi-Fi return, AP recovery, recovery
  guard, readiness checks, uninstall preview
- forbidden automatic actions: no reboot, no `save_config`, no AP start without
  explicit action, no sudoers write during dry-run, no secret in Git, no Wi-Fi
  profile deletion, no permanent AP+STA assumption, no arbitrary shell commands

## V1 status

This document is a contract and planning model only. It does not install
packages, write sudoers, install systemd services, change networking, start an
AP, launch runtime services, or handle secrets.

## Core consumption model (Seed-Kit)

Seed-Kit consumes module contracts in a read-only, POSIX-simple way:

- module contract path: `modules/<module>/contract/<module>.contract.sh`
- contract command: `sh <contract>.sh print`
- optional helper function in module script: `module_<name>_contract <mode>` (for
  example, `module_wifi_kit_contract dependencies`)
- source-able shell variables are allowed inside the module-owned contract, but
  V1 core consumption does not source the contract into the main Seed-Kit shell

Current resolution order in Seed-Kit for `modules deps` is:

1. if a contract file exists and `sh <contract>.sh print` succeeds, Seed-Kit prints
   that output
2. if the module exposes `module_<name>_contract`, Seed-Kit calls it
3. fallback to `module_<name>_dependencies`

No contract output is applied automatically. Everything remains V1 read-only and
preview-oriented.

Each contract remains responsible for module-specific details (required/recommended/
conditional dependencies, capabilities, wrappers, phases, safety policy). Seed-Kit
remains the safe engine for plan/read/preview/confirm flow.

If structured parsing is needed later, the preferred shape is a module-provided
print mode that emits simple sectioned text or `KEY=value` lines from a child
`sh` process. The core should not parse arbitrary shell code or run contract
actions directly.

## Validate preview

`sh seed-kit.sh modules validate <module>` is a read-only preview command. It
loads the same contract source as `modules deps`, then checks simple local
prerequisites without installing packages or changing services.

For V1, the generic validator consumes repeated `KEY=value` lines such as:

```sh
WIFI_KIT_DEPENDENCIES_REQUIRED=python3
WIFI_KIT_DEPENDENCIES_RECOMMENDED=rfkill
WIFI_KIT_DEPENDENCIES_CONDITIONAL=hostapd
WIFI_KIT_CAPABILITIES=wifi-scan
```

The command reports:

- required dependencies as OK or missing
- recommended dependencies as optional
- conditional dependencies as capability blockers
- capabilities as available, unavailable, or declared without a generic rule

The validator is intentionally conservative. It uses read-only checks such as
`command -v` and simple command-name mappings (`network-manager` to `nmcli`,
`iproute2` to `ip`). It does not run module actions, write sudoers, install
systemd units, start AP mode, or infer secrets.

If a module has no structured contract yet, Seed-Kit falls back to the existing
dependency text and explains that structured validation is unavailable.
