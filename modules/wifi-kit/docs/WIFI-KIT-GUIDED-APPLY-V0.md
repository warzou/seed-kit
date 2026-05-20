# Wifi-Kit Guided Apply SAFE V0

## 1) Objectif

This document defines the first guided apply SAFE flow for Wifi-Kit with the current
contract/manifest set.

V0 is **design-first and non-executing**:

- It defines how Seed-Kit core should orchestrate Wifi-Kit apply safely.
- It does not mutate runtime, network, sudoers, or systemd during this phase.
- It enforces explicit confirmations and checkpoints before any mutable step.

## 2) Responsabilités

### Seed-Kit core (orchestration)

Core is responsible for:

- loading module contract and manifests
- resolving phase aliases
- building a dry-run plan from manifest declarations
- enforcing read-only dry-run by default
- handling user confirmation per phase
- executing (future real apply) mutate steps after confirmation
- managing transaction state and append-only logs
- generating rollback actions and executing rollback scoped to Wifi-Kit
- presenting a final result report (success/blocked/fallback)

Core must not hardcode Wifi-Kit logic; it must read declarations from module files.

### Wifi-Kit module (declarations)

Wifi-Kit module is responsible for declarations only:

- capabilities, dependencies, readiness and health checks
- required/target files and paths
- service/wrapper/recovery intent
- forbidden and non-action constraints
- privileged action policy and sudoer shape constraints
- expected ports/runtime assumptions

See:

- `modules/wifi-kit/contract/wifi-kit.contract.sh`
- `modules/wifi-kit/docs/MODULE-CONTRACT.md`
- `modules/wifi-kit/contract/install-files.manifest.sh`
- `modules/wifi-kit/contract/sudoers.manifest.sh`
- `modules/wifi-kit/contract/runtime-service.manifest.sh`
- `modules/wifi-kit/contract/recovery.manifest.sh`

## 3) Phases V0

### 3.1 `plan`

Build a canonical plan from contract aliases:

- read `wifi-kit.contract.sh print`
- resolve alias mapping to preview phases
- build ordered phase list
- identify missing required declarations
- print planned operations

### 3.2 `validate`

Read-only validation pass:

- validate contract/manifests syntax and required fields
- verify dependencies surface and target paths are within approved prefixes
- check `forbidden` / `non-actions` definitions
- verify required port/policy assumptions from contract/manifests
- no file writes and no service/network changes

### 3.3 `install-files-preview`

Manifest-driven dry-run for file installation planning:

- evaluate `install-files.manifest.sh`
- show source -> destination mappings
- show expected modes/ownership
- show directories to prepare
- report replacements/creates (simulated)

No writes are performed in V0.

### 3.4 `configure-sudoers-preview`

Manifest-driven privileged access planning:

- evaluate `sudoers.manifest.sh`
- show exact allowed commands:
  - `start-ap-mode`
  - `return-default-network`
- show forbidden sudo/shell patterns
- validate action whitelist shape and wrapper path

No sudoers file is written in V0.

### 3.5 `install-service-preview`

Manifest-driven normal UI service planning:

- evaluate `runtime-service.manifest.sh`
- show service name/command/user/policy
- validate that normal runtime must remain client-only
- validate recovery remains explicit/captive only
- simulate generated unit and paths

No systemd write/start in V0.

### 3.6 `recovery-preview`

Manifest-driven recovery policy planning:

- evaluate `recovery.manifest.sh`
- show recovery mode:
  - SSID template
  - AP IP and DHCP range
  - captive port
- validate no AP-at-boot and no permanent AP+STA mode
- ensure `reconnect` / recovery actions remain explicit

No AP start or network mutation in V0.

### 3.7 `health-check`

Post-plan/check read-only health:

- aggregate readiness + policy consistency
- surface blockers that must be resolved before real apply
- include explicit warning if `wpa_cli`/`hostapd`/`dnsmasq` visibility mismatch appears

No service starts / no network operations in V0.

### 3.8 `checkpoint` / `report`

After each phase:

- write checkpoint state entries
- aggregate results
- produce operator report:
  - phase status
  - blocked items
- include rollback instructions

## 4) Phase alias mapping

From `WIFI_KIT_PHASE_ALIAS` in contract:

```text
install-files           -> install-files-preview    (install-files.manifest.sh)
install-sudoers-rule    -> configure-sudoers-preview (sudoers.manifest.sh)
install-normal-ui-service -> install-service-preview   (runtime-service.manifest.sh)
recovery-config         -> recovery-preview         (recovery.manifest.sh)
ap-recovery             -> recovery-preview         (recovery.manifest.sh)
```

## 5) Format transaction state (expected V0 shape)

State should be appendable/readable text (or structured key/value) with fields:

- `tx_id`
- `module`
- `contract_version`
- `manifest_versions`
- `selected_phases`
- `mode`
- `checkpoints`
- `planned_operations`
- `blocked_items`
- `forbidden_hits`
- `rollback_actions`
- `status`

### Recommended state file

- `/var/log/seed-kit/wifi-kit/apply-<timestamp>.state`

Minimal schema (conceptual):

```text
tx_id=<string>
module=wifi-kit
contract_version=<string>
manifest_versions=<manifest:file:version,...>
selected_phases=plan,validate,install-files-preview,configure-sudoers-preview,install-service-preview,recovery-preview,health-check
mode=dry-run
checkpoints=...
planned_operations=...
blocked_items=...
forbidden_hits=...
rollback_actions=...
status=ready|blocked|ok|failed|rolled_back
```

No secrets, no PSKs, no tokens, no credentials.

## 6) Append-only log format

Log should be append-only with clear phase progression:

- `/var/log/seed-kit/wifi-kit/apply-<timestamp>.log`

Each entry should include:

- timestamp
- phase
- action
- result
- duration
- blocked_reason (if any)
- confirmation_token (if any)

No secrets in logs.

## 7) Dry-run vs apply

### Dry-run (default)

- no mutations
- no runtime/service/network changes
- no sudoers write
- no systemd write
- no AP mode launch

### Apply (future real mode, explicit)

- only after all required phase confirmations
- each phase has rollback metadata prepared before any mutation
- stop at first blocked or uncertain check

## 8) Confirmations fortes (per phase)

Suggested operator confirmations:

- `CONFIRM WIFI-KIT PLAN`
- `CONFIRM WIFI-KIT VALIDATE`
- `CONFIRM WIFI-KIT INSTALL FILES`
- `CONFIRM WIFI-KIT SUDOERS PLAN`
- `CONFIRM WIFI-KIT SERVICE PLAN`
- `CONFIRM WIFI-KIT RECOVERY PLAN`
- `CONFIRM WIFI-KIT HEALTH CHECK`

Confirmation text should be explicit, phase-scoped, and logged.

## 9) Rollback scoped Wifi-Kit

Rollback actions for V0 guidance must be explicit and scoped:

- remove only Wifi-Kit created files
- remove only Wifi-Kit sudoers entry (future apply only)
- remove only Wifi-Kit installed service unit (future apply only)
- remove/restore only Wifi-Kit install targets
- never touch user Wi-Fi profiles

Rollback should be idempotent and documented before mutation.

## 10) Forbidden actions

V0 forbids:

- no AP at boot
- no networking mutation
- no reboot
- no secrets in any state/log/output
- no arbitrary shell execution
- no runtime start in V0
- no sudoers write in V0
- no systemd write in V0
- no deletion of user Wi-Fi profiles

## 11) Limites V0

- No execution of real install mutations
- No real service installation/start
- No real sudoers edit
- No real AP recovery boot/run
- No real Wi-Fi reconnection paths
- No persistence policy migrations

This is intentionally a guard-rail document and a contract to avoid unsafe implicit behavior.

## 12) Critères avant futur apply réel

Before running true apply:

- all V0 previews are green and deterministic
- no `forbidden_hits`
- explicit operator confirmations available
- manifest versions and alias mappings are stable
- no blocking mismatch between contract and manifests
- state/log schema implemented in core
- rollback path validated in dry-run mode

Once validated, migrate one phase at a time from preview to real apply using the same sequence.
