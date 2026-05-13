# Seed-Kit modules

Modules are shell capabilities stored in `modules/` inside the Seed-Kit monorepo.

They should stay small, readable, and boring. A module should explain what it will do before it changes anything, and any system-changing action should be explicit through `--apply --modules=<name>`.

## Minimal convention

Each module should expose, at minimum:

- `plan`: describe what the module would check or change.
- `apply`: perform the selected action with SAFE confirmation and clear output.
- `status`: planned for later, to report current state without changing anything.
- `uninstall`: planned for later, to remove module-managed local/system state when that is safe and well defined.

Current V0 module plan functions use this shape:

```sh
module_<name>_plan
```

Apply support is currently handled in `seed-kit.sh` for the first real path (`git`). Future modules should keep their action boundaries just as explicit.

## Priority modules

Near-term modules:

- `docker`
- `tailscale`
- `cloudflared`
- `caddy`
- `homepage`

Strategic module:

- `wifi-portal`: temporary hotspot plus Wi-Fi configuration from a phone, especially for Raspberry Pi Zero W, nomadic nodes, and rescue nodes.

`wifi-portal` should start as documentation and SAFE prototype work before it performs system changes. It will likely need careful handling around networking, access point mode, rollback, and SSH rescue paths.

## Dependencies and profiles

Some modules will depend on packages, services, network access, or earlier modules. Document those expectations in the module plan first.

A complex dependency engine is not needed yet. Keep dependencies explicit in prose and module output until repeated real cases justify a small shared helper.

Profiles are planned compositions of modules, stored later under `profiles/`. They are useful for common node shapes, but modules must remain usable directly without profiles.

## Parallel Module Development Threshold

Parallel module development becomes reasonable when:

- the bootstrap runtime is stable
- `seed-kit.sh` can list modules
- `--plan` and `--apply` are stable
- a minimal module convention is documented
- base sudo, network, and logging helpers are clear enough to reuse

Seed-Kit is close to this threshold. The runtime bootstrap, module listing, planning, targeted apply, SAFE confirmation, and sudo UX are in place.

The remaining gap is convention hardening: module apply boundaries and shared helper usage are still mostly implicit. From this point, `wifi-portal` can begin in parallel with engine work, but only as documentation and SAFE prototype work at first.
