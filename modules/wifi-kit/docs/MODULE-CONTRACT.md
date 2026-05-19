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
  - `18089` currently used in current prototype/test workflow.
  - `54321` is the target port for Seed-Kit-installed normal UI service.
- recovery/captive port: `80`

`WIFI_KIT_RUNTIME_UI_NORMAL_PORT` in contract is `54321` to match the future Seed-Kit service target.

## Security and policy

- no network mutation is performed by contract itself
- no secrets are declared in the contract
- no sudoers write, no direct shell execution, and no hostapd/dnsmasq process
  control are done in this artifact
