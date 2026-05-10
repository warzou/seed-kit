# Seed-Kit - Session Summary

## State

Seed-Kit is a V0 shell toolkit with:

* plan-only `install.sh`
* `seed-kit.sh` entrypoint
* OS detection
* lightweight backends
* placeholder modules
* responsive terminal UI

No real install/restore/secrets work has been added yet.

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

Exploratory styles still available:

```sh
SEED_UI_STYLE=focus sh seed-kit.sh --plan
SEED_UI_STYLE=cockpit sh seed-kit.sh --plan
sh seed-kit.sh --ui-demo
```

## Keep

* calm modern terminal UI
* simple shell helpers in `lib/ui.sh`
* low density
* strong spacing
* small diffs
* real SSH testing

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
