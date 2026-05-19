# Wifi-Kit SAFE apply model

This document defines the future SAFE apply model for installing Wifi-Kit
through Seed-Kit core.

It is design only. It does not implement apply logic, copy files, change file
permissions or ownership, install sudoers, install systemd units, start
runtime services, start AP mode, change networking, store secrets, or reboot.

## Purpose

Wifi-Kit has enough privileged and network-sensitive pieces that a future apply
must be explicit, checkpointed, and reversible.

The apply model should let Seed-Kit core install Wifi-Kit as a reproducible
module while keeping recovery actions and network changes behind separate,
strongly confirmed flows.

## Inputs

Seed-Kit core should consume the module contract and specialized manifests:

- `contract/wifi-kit.contract.sh`
- `contract/install-files.manifest.sh`
- `contract/sudoers.manifest.sh`
- `contract/runtime-service.manifest.sh`
- `contract/recovery.manifest.sh`

The manifests are declarative. They describe desired files, services, wrapper
rules, recovery behavior, checks, forbidden actions, and non-actions. They do
not execute any operation by themselves.

## Apply principles

- dry-run first
- one phase at a time
- exact confirmation before each persistent phase
- write a checkpoint before each mutation
- validate after each phase
- stop on first uncertainty
- rollback plan shown before any write
- no hidden network ownership transfer
- no secret in logs, Git, manifests, state files, or command output

## Phases

### 1. Preflight

Read-only checks:

- contract and manifests are present and parseable
- target platform is supported
- required and recommended dependencies are visible
- source files exist
- target paths are absolute and in approved prefixes
- no active Wifi-Kit recovery leftovers
- normal UI port `54321` is available
- recovery port `80` is only reserved for explicit AP mode
- current network state is readable
- rollback and recovery plan can be displayed

Preflight must not install packages, write sudoers, write systemd units, copy
files, start services, start AP mode, or change network state.

### 2. Install files

Future persistent writes:

- create approved target directories
- copy declared files under `/opt/seed-kit/wifi-kit/`
- prepare `/etc/seed-kit/wifi-kit/`
- prepare `/var/log/seed-kit/wifi-kit/`
- prepare module-scoped runtime directory policy for `/run/seed-kit/wifi-kit/`

Required confirmation:

```text
INSTALL WIFI-KIT FILES
```

Checkpoint before mutation:

- list target files that do not exist
- list target files that already exist
- record hashes of files that would be replaced
- record ownership and mode of existing target paths

Rollback plan:

- remove only files created by the transaction
- restore files replaced during the transaction from backup
- leave unrelated files untouched

### 3. Configure sudoers

Future persistent writes:

- install one strict sudoers drop-in for the declared wrapper path
- allow only declared wrapper actions:
  - `start-ap-mode`
  - `return-default-network`

Required confirmation:

```text
CONFIGURE WIFI-KIT SUDOERS
```

Required guards:

- wrapper path must match the sudoers manifest
- wrapper must be root-owned
- wrapper must not be writable by the UI user
- sudoers rule must not include wildcards
- sudoers rule must not grant shell access
- sudoers rule must not grant broad `nmcli`, `systemctl`, `hostapd`, or
  `dnsmasq` access
- sudoers syntax must be validated before activation

Rollback plan:

- remove only the Wifi-Kit sudoers drop-in
- do not edit unrelated sudoers files

### 4. Install service

Future persistent writes:

- render the normal UI service from `runtime-service.manifest.sh`
- install `seed-kit-wifi-kit-ui.service`
- configure the dedicated service user policy
- configure log and runtime directory ownership

Required confirmation:

```text
INSTALL WIFI-KIT SERVICE
```

Normal service rules:

- normal UI listens on port `54321`
- normal UI should run as non-root where possible
- normal UI must not start `hostapd`
- normal UI must not start `dnsmasq`
- normal UI must not start AP mode at boot
- captive recovery port `80` is only for explicit recovery mode

Rollback plan:

- stop only the Wifi-Kit normal UI service if it was started by this
  transaction
- disable and remove only the Wifi-Kit unit
- leave unrelated services untouched

### 5. Recovery config

Future persistent writes:

- write non-secret recovery defaults under `/etc/seed-kit/wifi-kit/`
- record recovery timeout policy
- record AP SSID template policy
- record captive portal port policy

Required confirmation:

```text
CONFIGURE WIFI-KIT RECOVERY POLICY
```

Recovery remains explicit:

- no AP at boot
- no AP start during install
- no `hostapd` during install
- no `dnsmasq` during install
- no network change during install
- no Wi-Fi profile deletion
- no AP+STA permanent assumption

Rollback plan:

- remove only recovery config created by this transaction
- do not remove user Wi-Fi profiles
- do not alter current NetworkManager connections

### 6. Validate

Read-only checks after each persistent phase:

- files exist with expected paths
- wrapper exists with expected owner/mode
- sudoers rule shape matches the manifest
- systemd unit exists if installed
- normal UI service remains stopped unless an explicit later phase starts it
- no unexpected `hostapd` or `dnsmasq` is active
- no AP interface was created by install
- NetworkManager still owns `wlan0`
- recovery guard reports clean state

Validation must not start AP mode, connect Wi-Fi, restart network services,
reload unrelated services, write secrets, or reboot.

### 7. Rollback plan

Before any real apply, Seed-Kit must show the rollback plan for every phase it
is about to run.

Rollback should be based on a transaction state file and file backups created
before each mutation. Rollback must be scoped to the Wifi-Kit module and must
not remove user Wi-Fi profiles without separate explicit confirmation.

## State file

Future apply should write a module-scoped transaction state file, for example:

```text
/var/log/seed-kit/wifi-kit/apply-<timestamp>.state
```

The state file should contain non-secret data only:

- transaction id
- Seed-Kit version
- Wifi-Kit contract version
- selected phases
- dry-run result
- confirmation text accepted
- created paths
- replaced paths
- backup paths
- validation result
- rollback result
- final status

The state file must not contain Wi-Fi passwords, AP passwords, tokens, private
keys, tunnel credentials, or browser login URLs.

## Logs

Future apply logs should be append-only and module-scoped, for example:

```text
/var/log/seed-kit/wifi-kit/apply-<timestamp>.log
```

Logs should include:

- phase start and end
- commands planned
- commands executed by Seed-Kit core
- validation summaries
- rollback summaries
- explicit non-actions

Logs must redact secrets and must not include arbitrary environment dumps.

## Recovery path

Recovery AP mode is a future explicit action, not part of normal install.

Before any future AP recovery apply, Seed-Kit must prove:

- wrapper is installed and restricted
- sudoers rule is exact
- hostapd and dnsmasq are present
- recovery guard is installed
- cleanup is available
- the operator has a local fallback path
- timeout policy is visible

If rollback cannot prove safe network access, automation must stop in a
`recovery-required` state and show manual recovery instructions.

## Automatically forbidden

The future apply must never automatically:

- start AP mode
- connect or switch Wi-Fi networks
- restart NetworkManager
- restart networking
- reboot
- delete user Wi-Fi profiles
- run arbitrary shell commands
- grant broad sudo
- write secrets into Git
- log secrets
- start recovery without explicit confirmation
- assume permanent AP+STA mode

## Confirmation model

Each persistent phase should require an exact phrase. A simple `y` is not enough
for privileged or network-adjacent phases.

Suggested confirmations:

- `INSTALL WIFI-KIT FILES`
- `CONFIGURE WIFI-KIT SUDOERS`
- `INSTALL WIFI-KIT SERVICE`
- `CONFIGURE WIFI-KIT RECOVERY POLICY`
- `ROLLBACK WIFI-KIT APPLY`

Recovery actions should use a stronger confirmation that names the interruption
risk, for example:

```text
START WIFI-KIT RECOVERY AP
```

## Minimal future sequence

The first real guided apply should be deliberately narrow:

1. preflight
2. dry-run summary
3. show rollback plan
4. install files
5. validate files
6. stop

Sudoers, service installation, recovery policy, service start, and AP recovery
should remain separate follow-up phases until each has its own validation and
rollback path.

## Current status

This document is architecture only. The current manifests and previews remain
read-only. No real apply command is implemented by this document.
