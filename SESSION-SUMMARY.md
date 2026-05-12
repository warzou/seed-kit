# Seed-Kit - Session Summary

## State

Seed-Kit is a V0 shell toolkit with:

* plan-only `install.sh`
* `seed-kit.sh` entrypoint
* OS detection + lightweight backends
* CLI with `--plan`, `--detect`, `--modules`, `--apply` and `-y`
* ambient terminal cockpit UI (responsive split default)
* module list and targetable apply preview flow
* one real minimal action implemented: `--apply --modules=git` on Debian-like systems

## UX Decision

Default UI style: `split`.

Goal: ambient terminal cockpit.

Current UI traits:

* asymmetric layout
* sparse first screen
* lowercase labels
* contextual machine/readiness view
* suggested next step
* responsive wide/narrow rendering
* Unicode + ASCII fallback
* `NO_COLOR` support

Exploratory styles:

```sh
SEED_UI_STYLE=focus sh seed-kit.sh --plan
SEED_UI_STYLE=cockpit sh seed-kit.sh --plan
sh seed-kit.sh --ui-demo
```

## Keep

* calm modern terminal UI
* SAFE behavior: `sh seed-kit.sh --apply` does not run real actions
* simple shell helpers in `lib/ui.sh`
* low density
* strong spacing
* shell-first, minimal, readable implementation
* small diffs
* real SSH testing

Current stable behavior:

* `--apply --modules=git` performs a minimal install check/step when needed
* `--apply --modules=git,docker` applies git and reports `not implemented` for docker in V0
* `-y` only skips SAFE confirmation prompt; it does not skip auth or errors
* non-git modules remain V0 placeholders (`docker`, `tailscale`, `homepage`)
* unknown modules are rejected explicitly

## Avoid

* more UI concepts before field testing
* large docs
* large refactors
* dependencies
* fake dashboards
* complex manifests
* restore/secrets/GDrive work for now

## Resume Workflow

1. Read `CONTEXT.md`.
2. Run `sh seed-kit.sh --ui-demo`.
3. Run `SEED_WIDTH=54 sh seed-kit.sh --plan`.
4. Pick one small next change.
5. Test with `bash -n` and `sh`.
6. Commit only after review.
