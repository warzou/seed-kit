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
