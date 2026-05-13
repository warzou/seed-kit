# Seed-Kit architecture

Seed-Kit is a modular monorepo.

The project keeps one entrypoint:

```sh
sh seed-kit.sh
```

`seed-kit.sh` is the engine, bootstrap entrypoint, and lightweight terminal UX. It detects the local system, loads the matching backend, lists modules, prints plans, and applies selected modules.

## Layout

```text
seed-kit.sh  engine, entrypoint, bootstrap runtime, SSH-friendly UX
modules/     installable capabilities
profiles/    planned module compositions
backends/    OS support and backend-specific plans
docs/        project documentation
```

Modules are not separate Git repositories. They live in this monorepo and should stay easy to read, copy, review, and test.

## Principles

Seed-Kit core is offline-first. Copying `seed-kit.sh` to a fresh node must remain useful without fetching code from the network.

Modules may require network access or `sudo` when they install system packages or configure system services. That work must be explicit, visible in `--plan`, and guarded by SAFE prompts before `--apply`.

The default path is SAFE:

- `--plan` explains before doing work.
- `--modules` lists known capabilities.
- `--apply` without selected modules does not perform real actions.
- `--apply --modules=...` is explicit and still uses module-level safety checks.
- Seed-Kit should run as a normal user and use `sudo` only for actions that need it.

Keep the core small. Avoid heavy frameworks, YAML manifests, dependency engines, plugin systems, and abstractions before real module pressure proves they are needed.

## Runtime

The bootstrap runtime is intentionally minimal. It creates local `lib/`, `modules/`, and `backends/` placeholders so a copied single file can become usable on a fresh node.

The full repository runtime provides richer module plans and real implementation detail.

Use `sh seed-kit.sh --uninstall-runtime` to remove only generated local runtime directories when testing a fresh bootstrap flow.
