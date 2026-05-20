# SAFE APPLY ORCHESTRATION V0

## Goal

SAFE APPLY V0 defines how Seed-Kit will plan future module apply flows before
any real mutation exists.

V0 is dry-run only. It renders an operator-readable transaction plan from module
contracts and specialized manifests. It does not copy files, create directories,
change permissions, write sudoers, install systemd units, change networking,
start runtimes, start AP mode, reboot, or handle secrets.

## Command

```sh
sh seed-kit.sh apply-plan <module> --dry-run
```

`--dry-run` is mandatory. Any future non-dry-run apply must be introduced as a
separate, reviewed step with explicit confirmations.

For checkpoint-engine preview:

```sh
sh seed-kit.sh apply-plan wifi-kit --dry-run --with-checkpoints
```

With `--with-checkpoints`, the planner renders additional V0 metadata targets and
status model without creating files.

## Inputs

The planner consumes the same read-only contract sources used by module
previews:

- main contract: `modules/<module>/contract/<module>.contract.sh print`
- fallback function: `module_<name>_contract print`
- specialized manifests:
  - `install-files.manifest.sh`
  - `runtime-service.manifest.sh`
  - `sudoers.manifest.sh`
  - `recovery.manifest.sh`

Specialized manifests are preferred for their phase. The main contract remains
the backward-compatible fallback.

## Phase Model

The V0 plan is intentionally sequential:

1. `preflight`
2. `install-packages`
3. `install-files`
4. `configure-sudoers`
5. `install-service`
6. `recovery`
7. `validate`

Each future mutating phase must have:

- an operator-visible preview
- an explicit confirmation
- a before checkpoint
- rollback metadata
- a stop-on-failure boundary before the next phase

## Future State Layout

The V0 CLI only displays these paths. It never creates them.

```text
/var/lib/seed-kit/apply/<module>/state
/var/lib/seed-kit/apply/<module>/checkpoints/
/var/log/seed-kit/apply-<module>.log
```

When checkpoint mode is requested, it also displays:

- `/var/lib/seed-kit/apply/<module>/.lock`
- apply journal: `/var/log/seed-kit/apply-<module>.log`
- key/value plan state (future schema):

```text
SEED_KIT_APPLY_PLAN_VERSION=0
SEED_KIT_APPLY_MODULE=wifi-kit
SEED_KIT_APPLY_MODE=dry-run
SEED_KIT_APPLY_PHASE=install-files
SEED_KIT_APPLY_STATUS=planned
SEED_KIT_APPLY_CHECKPOINT=files-staged-before-copy
SEED_KIT_APPLY_ROLLBACK=restore-seed-kit-owned-files
SEED_KIT_APPLY_LOCK=/var/lib/seed-kit/apply/wifi-kit/.lock
SEED_KIT_APPLY_JOURNAL=/var/log/seed-kit/apply-wifi-kit.log
SEED_KIT_APPLY_TIMESTAMP=...
```

Supported phase statuses are:

`pending`, `planned`, `skipped`, `blocked`, `done-future`, `rollback-ready`.

## Future State Format

Future state should be shell-safe `KEY=value` metadata, not arbitrary shell code
to source into Seed-Kit. Values should be written and parsed as data.

Example shape:

```sh
SEED_KIT_APPLY_PLAN_VERSION=0
SEED_KIT_APPLY_MODULE=wifi-kit
SEED_KIT_APPLY_MODE=dry-run
SEED_KIT_APPLY_PHASE=install-files
SEED_KIT_APPLY_STATUS=planned
SEED_KIT_APPLY_CHECKPOINT=files-staged-before-copy
SEED_KIT_APPLY_ROLLBACK=restore-seed-kit-owned-files
```

The future state file should track:

- module id
- plan id/version
- phase status
- checkpoint references
- rollback notes
- validation results
- forbidden actions that remained blocked

## Rollback Model

Rollback must be module-scoped and Seed-Kit-owned.

Future rollback may remove or restore:

- files Seed-Kit installed
- sudoers rules Seed-Kit wrote
- systemd units Seed-Kit installed
- module-scoped runtime state

Rollback must not remove user Wi-Fi profiles, secrets, or unrelated network
state without a separate explicit confirmation.

## Forbidden Automatic Actions

SAFE APPLY must not automatically:

- reboot
- restart networking
- start AP mode
- connect or reconnect Wi-Fi
- run arbitrary shell commands
- write secrets
- apply broad sudoers rules
- call broad `systemctl`, `nmcli`, or network actions
- launch module runtime without an explicit future phase and confirmation

## V0 Limitations

V0 is a planner, not an installer. It proves the shape of the transaction and
the manifest resolution order. Real apply, rollback execution, checkpoint file
creation, and health-based recovery remain future work.
