# Wifi-Kit module contract

This file documents the exportable contract used by Seed-Kit core to discover module
metadata without hardcoding Wifi-Kit behavior.

## Source point

```sh
. modules/wifi-kit/contract/wifi-kit.contract.sh
module_wifi_kit_contract
```

The file is simple shell (`sh`), sourceable, and read-only by design.

## Consumer contract

Variables available:

- `WIFI_KIT_MODULE_ID`
- `WIFI_KIT_MODULE_TYPE`
- `WIFI_KIT_BACKEND`
- `WIFI_KIT_MODE`
- `WIFI_KIT_TARGET_PATH_APP_DIR`
- `WIFI_KIT_TARGET_PATH_CONFIG_DIR`
- `WIFI_KIT_TARGET_PATH_RUNTIME_DIR`
- `WIFI_KIT_TARGET_PATH_LOG_DIR`
- `WIFI_KIT_RUNTIME_UI_NORMAL_PORT`
- `WIFI_KIT_RUNTIME_UI_RECOVERY_PORT`
- `WIFI_KIT_RUNTIME_UI_NORMAL_COMMAND`
- `WIFI_KIT_WRAPPER_PATH`
- list helpers for:
  - `WIFI_KIT_DEPENDENCIES_REQUIRED`
  - `WIFI_KIT_DEPENDENCIES_RECOMMENDED`
  - `WIFI_KIT_DEPENDENCIES_CONDITIONAL`
  - `WIFI_KIT_CAPABILITIES`
  - `WIFI_KIT_FILES`
  - `WIFI_KIT_WRAPPER_ACTIONS`
  - `WIFI_KIT_READINESS_CHECKS`
  - `WIFI_KIT_HEALTH_CHECKS`
  - `WIFI_KIT_INSTALL_PHASES`
  - `WIFI_KIT_PHASE_ALIASES`
  - `WIFI_KIT_ROLLBACK_PHASES`
  - `WIFI_KIT_FORBIDDEN_ACTIONS`
  - `WIFI_KIT_SECRETS_POLICY`
  - `WIFI_KIT_SUDOERS_REQUIREMENTS`

A helper is also exported:

- `module_wifi_kit_contract`

## Read-only command

```sh
sh modules/wifi-kit/contract/wifi-kit.contract.sh print
```

This prints a stable `KEY=VALUE` stream consumable by scripts.

## Phase aliases

The base contract keeps historical module phase names for compatibility, while
the specialized manifests expose the canonical Seed-Kit preview phase targets.
Seed-Kit core should use `WIFI_KIT_PHASE_ALIAS` entries when mapping module
phases to manifest-driven previews.

Alias entries use this shape:

```text
module-phase|core-preview-phase|manifest-file
```

Current aliases:

- `install-files` -> `install-files-preview` via `install-files.manifest.sh`
- `install-sudoers-rule` -> `configure-sudoers-preview` via `sudoers.manifest.sh`
- `install-normal-ui-service` -> `install-service-preview` via `runtime-service.manifest.sh`
- `recovery-config` -> `recovery-preview` via `recovery.manifest.sh`
- `ap-recovery` -> `recovery-preview` via `recovery.manifest.sh`

## Install-files manifest

Wifi-Kit also exposes a dedicated install-files manifest for Seed-Kit core
preview flows:

```sh
sh modules/wifi-kit/contract/install-files.manifest.sh print
```

The manifest is simple shell, sourceable, and read-only. It describes the
directories, source files, target paths, ownership, modes, and safety policy
needed by a future `install-files-preview` implementation.

Seed-Kit core should consume this manifest instead of hardcoding Wifi-Kit file
paths. The manifest is declarative only: it does not copy files, change
permissions, change ownership, install sudoers, install systemd units, start
runtime processes, start AP mode, or change networking.

The current file entries are:

- `prototype/ui/serve-readonly.py` -> `/opt/seed-kit/wifi-kit/ui/serve-readonly.py`, `root:root`, `0644`
- `prototype/ui/index.html` -> `/opt/seed-kit/wifi-kit/ui/index.html`, `root:root`, `0644`
- `prototype/ap-setup-test.sh` -> `/opt/seed-kit/wifi-kit/ap-setup-test.sh`, `root:root`, `0755`
- `prototype/wifi-kit-connect-recovery.sh` -> `/opt/seed-kit/wifi-kit/wifi-kit-connect-recovery.sh`, `root:root`, `0755`
- `prototype/wifi-kit-recovery-guard.sh` -> `/opt/seed-kit/wifi-kit/wifi-kit-recovery-guard.sh`, `root:root`, `0755`
- `prototype/wifi-kit-action-wrapper.sh` -> `/opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh`, `root:root`, `0755`

The privileged wrapper must be root-owned and must not be writable by the UI
user in the final install. Future config files under `/etc/seed-kit/wifi-kit`
should use strict permissions such as `0600` or `0640`, depending on the final
owner/group model.

## Sudoers manifest

Wifi-Kit exposes a dedicated sudoers manifest for Seed-Kit core preview flows:

```sh
sh modules/wifi-kit/contract/sudoers.manifest.sh print
```

Seed-Kit core should consume this manifest for `configure-sudoers-preview`
instead of hardcoding Wifi-Kit privileged commands. The manifest is declarative
only: it does not write sudoers files, call `visudo`, start runtime processes,
start AP mode, or change networking.

The preview rule shape is:

```text
seed-kit-wifi ALL=(root) NOPASSWD: /opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh start-ap-mode, /opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh return-default-network
```

Only these actions are authorized:

- `start-ap-mode`
- `return-default-network`

Broad sudo shapes remain forbidden, including `sudo sh`, `sudo bash`,
wildcards, direct `nmcli`, direct `systemctl`, direct `hostapd`, direct
`dnsmasq`, free arguments, reboot, and `save_config`.

## Runtime-service manifest

Wifi-Kit exposes a dedicated runtime-service manifest for Seed-Kit core preview
flows:

```sh
sh modules/wifi-kit/contract/runtime-service.manifest.sh print
```

Seed-Kit core should consume this manifest for `install-service-preview`
instead of hardcoding the Wifi-Kit normal UI service. The manifest describes the
future service name, service user placeholder, command, ports, runtime/log
directories, readiness checks, health checks, and non-actions.

The target normal UI service is:

```text
seed-kit-wifi-kit-ui.service
```

The target command is:

```text
python3 /opt/seed-kit/wifi-kit/ui/serve-readonly.py --host 0.0.0.0 --port 54321
```

Normal runtime is client Wi-Fi mode only: no `hostapd`, no `dnsmasq`, no AP at
boot. Recovery remains explicit and temporary, using captive port `80` only
when AP recovery is intentionally started.

The runtime-service manifest is declarative only: it does not write systemd
units, call `systemctl`, start the UI, start AP mode, change networking, write
secrets, or reboot.

## Recovery manifest

Wifi-Kit exposes a dedicated recovery manifest for Seed-Kit core preview flows:

```sh
sh modules/wifi-kit/contract/recovery.manifest.sh print
```

Seed-Kit core should consume this manifest for `recovery-preview` instead of
hardcoding AP/captive recovery details. The manifest describes the explicit
AP/captive recovery mode, SSID template, AP IP, DHCP range, captive UI port,
normal UI port, privileged actions, temporary files, readiness checks, health
checks, rollback expectations, forbidden actions, and secrets policy.

Recovery is explicit and temporary only. Normal boot must not start AP mode,
`hostapd`, or `dnsmasq`. AP+STA permanent mode remains outside the V1 product
path.

The recovery manifest is declarative only: it does not start AP mode, start
`hostapd`, start `dnsmasq`, modify networking, write sudoers, create systemd
units, write secrets, or reboot.

## Contract summary

- `id`: `wifi-kit`
- `type`: `network-ui`
- `backend`: `networkmanager`
- `mode`: `normal-ui+ap-recovery`
- required deps: `python3`, `network-manager`, `nmcli`, `wpa_cli`, `iw`, `iproute2`
- recommended deps: `rfkill`
- conditional deps: `hostapd`, `dnsmasq`, `sudoers-wrapper`, `systemd-service`
- capabilities:
  - `normal-ui`
  - `wifi-scan`
  - `wifi-connect-recovery`
  - `ap-recovery`
  - `captive-portal`
  - `recovery-cleanup`
  - `privileged-actions`
- allowed privileged actions:
  - `start-ap-mode`
  - `return-default-network`
- normal UI ports:
  - `18089` = prototype/dev local workflow only (manual launch only).
  - `54321` = target port for Seed-Kit-installed normal UI service.
- recovery/captive port: `80`

`WIFI_KIT_RUNTIME_UI_NORMAL_PORT` in contract is `54321` to match the future Seed-Kit service target.

## Security and policy

- no network mutation is performed by contract itself
- no secrets are declared in the contract
- no sudoers write, no direct shell execution, and no hostapd/dnsmasq process
  control are done in this artifact

## Prototype and legacy scope

To avoid a parallel orchestration track, keep this file as the only contract
source for Seed-Kit core orchestration. The items below are intentionally
separated by confidence level.

### Active contract surface

- `modules/wifi-kit/contract/*.sh`
- manifest readers (`install-files`, `sudoers`, `runtime-service`,
  `recovery`)
- phase aliases in `wifi-kit.contract.sh`
- SAFE docs:
  `APPLY-SAFE.md`, `MODULE-CONTRACT.md`, `SECURITY-ACTIONS.md`,
  `WIFI-KIT-GUIDED-APPLY-V0.md`

This is the preferred surface for core consumption and future preview/apply
automation.

### Runtime prototype surface

- `modules/wifi-kit/prototype/wifi-kit.sh`
- `modules/wifi-kit/prototype/helpers.sh`
- `modules/wifi-kit/prototype/backends/`
- `modules/wifi-kit/prototype/ui/serve-readonly.py`
- `modules/wifi-kit/prototype/ui/render-readonly-ui.sh`
- `modules/wifi-kit/prototype/wifi-kit-action-wrapper.sh`
- `modules/wifi-kit/prototype/wifi-kit-connect-recovery.sh`
- `modules/wifi-kit/prototype/wifi-kit-recovery-guard.sh`

These scripts are valid product prototypes/examples and useful references for
behaviour, but they must **not** become a second independent orchestration
layer for Seed-Kit core.

### Legacy / plan-only candidates

- `modules/wifi-kit/prototype/connect-safe-plan.sh`
- `modules/wifi-kit/prototype/connect-safe-apply.sh`
- `modules/wifi-kit/prototype/connect-safe-networkmanager.sh`
- `modules/wifi-kit/prototype/connect-safe-scenario-plan.sh`
- `modules/wifi-kit/prototype/ap-reconnect-plan.sh`
- `modules/wifi-kit/prototype/candidate-match-plan.sh`
- `modules/wifi-kit/prototype/registry-plan.sh`
- `modules/wifi-kit/prototype/wpa-cli-scan-results-to-json.sh`

These are not for V0 guided apply work. Keep them for context, but do not
extend them for the contract-driven path; they are future candidates for
archival after migration.

### Ambiguities to resolve

- `NORMAL_UI_PORT` is currently used as `18089` in prototype flow, while the
  contract runtime target is `54321`.
- `modules/wifi-kit/prototype/wifi-kit.sh` still mixes prototype flow,
  readiness checks, and connect-safe helpers.

Both points are non-blockers today but must be clarified before any operational
guided-apply rollout in V0.
