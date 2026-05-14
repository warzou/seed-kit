# Seed-Kit product direction

## Main mission

Seed-Kit is a minimal shell toolkit for quickly preparing a node.

It should help an operator:

- install a fresh node quickly,
- install Seed-Kit modules and profiles,
- prepare a reproducible node,
- get as close as possible to a one-command flow when it is safe.

The core goal is simple: take a fresh machine and make it operational quickly.

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
- an advanced dependency engine,
- an opaque rollback system.

If a workflow becomes risky, Seed-Kit should explain the next manual step
instead of pretending the risk disappeared.

## Modules

Modules are installable capabilities that can be planned and applied
individually.

Profiles are small named compositions of modules. They help describe common
node shapes without becoming a dependency graph or an orchestration engine.

Some modules can be repo-backed and fetched sparsely when the full repository is
not needed. `wifi-kit` is the first strategic repo-backed module, because it may
grow documentation, prototypes, assets, and tests beyond the single-file core.

Future modules should stay optional unless they are required for a documented
profile.

## Reconstruction mode

Reconstruction is optional. It should not become a dependency of the core.

Future reconstruction work may include:

- guided restore steps,
- `profile-state` inventory and dry-run flows,
- encrypted archives,
- private operator checklists,
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
entrypoint, apply a clear profile, and reach an operational node quickly.

Advanced reconstruction should remain layered on top:

- core first,
- modules second,
- profiles third,
- private profile-state only when explicitly needed.
