# Seed-Kit product direction

## Main mission

Seed-Kit is a minimal shell toolkit for quickly preparing or restoring a node.

It should help an operator:

- install Seed-Kit on a fresh node,
- restore/replay a node package or profile,
- install only the modules needed for that restore,
- ask for human action only when the step is inherently manual.

The core goal is simple: take a fresh machine and make it operational again
from an explicit package/profile, without hiding risky steps.

## Philosophy

Seed-Kit should remain:

- shell-first,
- lightweight,
- low overhead,
- SSH-friendly,
- SAFE by default,
- minimal in dependencies,
- offline-friendly where possible,
- public and generic at the core.

The project should prefer clear terminal output, small files, and explicit
operator decisions over hidden automation.

## What Seed-Kit is not

Seed-Kit is not:

- Kubernetes,
- Ansible,
- Terraform,
- a complex orchestrator,
- a secret vault,
- a module dependency database,
- an opaque rollback system.

If a workflow becomes risky, Seed-Kit should explain the next manual step
instead of pretending the risk disappeared.

## Modules

Modules are installable capabilities that own their own dependencies and
configuration flow.

Profiles are small named compositions of modules. They help describe common
node shapes without becoming a dependency graph or an orchestration engine.

Some modules can be repo-backed and fetched sparsely when the full repository is
not needed. `wifi-kit` is the first strategic repo-backed module, because it may
grow documentation, prototypes, assets, and tests beyond the single-file core.

Seed-Kit core should read what a module declares, install the declared
requirements after confirmation, then hand control to the module installer when
one exists. Core should not memorize module-specific internals.

## Reconstruction mode

Reconstruction is package/profile oriented. It should stay explicit and small.

Current reconstruction work may include:

- restore/replay a package one step at a time,
- `profile-state` inventory and dry-run flows,
- private operator checklists and archives,
- explicit validation before a node replaces another node.

The public core should stay useful even when no private profile-state archive
exists.

## Security boundary

Seed-Kit must keep private state separate from public Git.

Security rules:

- secrets stay out of the public repository,
- restore is explicit only,
- production cutover requires human validation,
- Tailscale reconnect may remain manual,
- Cloudflare authentication may remain manual,
- encrypted archives are required before backing up private state.

Seed-Kit can guide sensitive work, but it should not silently own secrets.

## Long-term vision

Seed-Kit should make it practical to take a fresh machine, run a small shell
entrypoint, restore/replay a clear package/profile, and reach an operational
node quickly.

Advanced reconstruction should remain layered on top:

- core first,
- modules second,
- profiles third,
- private profile-state only when explicitly needed.
