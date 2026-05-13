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

- `tailscale`
- `cloudflared`
- `caddy`
- `homer`
- `docker`
- `homepage`

External official module boundaries are documented in [EXTERNAL-MODULES.md](EXTERNAL-MODULES.md).

Strategic module:

- `wifi-kit`: temporary hotspot plus Wi-Fi configuration from a phone, especially for Raspberry Pi Zero W, nomadic nodes, and rescue nodes.

`wifi-kit` should start as documentation and SAFE prototype work before it performs system changes. It must not depend on Docker, Homepage, Caddy, or Internet access. It should use a temporary minimal HTTP server compatible with BusyBox `httpd`, with low overhead for Raspberry Pi Zero W, OpenWRT, and rescue nodes.

## Node shapes

Minimal resilient node:

- `tailscale`
- `cloudflared`
- `caddy`
- `homer`

Edge services node:

- `tailscale`
- `cloudflared`
- `caddy`
- `docker`
- `homepage`

Docker is optional. Tailscale, Cloudflared, Caddy, and Homer are host-level modules for the minimal node path. Homepage remains optional and likely depends on Docker or a heavier web services stack.

Tailscale apply scope is install-only: no `tailscale up`, no auth keys, no stored secrets, and no automatic tailnet join.

Cloudflared apply scope is install-only: no Cloudflare login, no tunnel creation, no tunnel service install, no token, and no stored credentials.

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

The remaining gap is convention hardening: module apply boundaries and shared helper usage are still mostly implicit. From this point, `wifi-kit` can begin in parallel with engine work, but only as documentation and SAFE prototype work at first.
