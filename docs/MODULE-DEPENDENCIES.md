# Module dependencies

## Goal

Seed-Kit modules can declare their dependencies in a small shell-readable form.

This is documentation first. It is not a dependency engine, not an orchestrator,
and not an installer.

## Shape

A module may expose:

```sh
module_<name>_dependencies
```

Each module may provide an equivalent declaration for its own domain. The
declaration belongs to the module, but Seed-Kit core remains the SAFE engine that
decides how declarations are displayed, checked, or used later.

The function prints plain lines:

```text
requires: network
requires: sudo
package-source: official Docker apt repository
package: docker-ce
package: docker-ce-cli
provides: docker
provides: docker compose
manual: add user to docker group only if explicitly desired
```

## Rules

- read-only output only
- V1 stays a simple shell declaration
- no package install
- no service start
- no secret handling
- no automatic dependency resolution
- no profile orchestration
- no rollback engine
- modules must not reimplement package managers such as apt, apk, or opkg

## CLI preview

The read-only helper is:

```sh
sh seed-kit.sh modules deps docker
```

It should print the module declaration and exit. It must not inspect the remote
network, run apt, call sudo, or mutate the machine.

## Ready model

Dependency declarations only describe what may be needed. They do not mean a
module or system package is ready for use.

Seed-Kit uses the Ready model to separate installation from configuration,
validation, and operator-owned identity steps. See `docs/READY-MODEL.md`.

## Why not a resolver yet?

Field use is still shaping the real module graph. A resolver would be premature
until repeated module pressure proves the exact behavior needed.

For now, declarations are useful for:

- operator review
- package-driven PRA planning
- future profile validation
- documenting manual post-install steps

## Non-goals

- no automatic install order
- no recursive dependency expansion
- no hidden module apply
- no machine restore
