# Seed-Kit modules

Modules are shell capabilities stored in `modules/` inside the Seed-Kit monorepo.

They should stay small, readable, and boring. A module should explain what it will do before it changes anything, and any system-changing action should be explicit through `--apply --modules=<name>`.

Seed-Kit stays a single repository for now. The scalable documentation boundary is:

- one module = one module folder when the module grows beyond a single shell file;
- one module = one short README for operators;
- one module = optional `docs/` for architecture, runtime, safety, logging, and troubleshooting detail.

Single-file modules such as `modules/cloudflared.sh` can stay as files until they need dedicated docs or assets. Growing modules should add a sibling folder such as `modules/link-watch/` without moving the shell entrypoint immediately.

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

## Documentation convention

Global docs stay in `docs/` and explain Seed-Kit as a product:

- [ARCHITECTURE.md](ARCHITECTURE.md): core layout and runtime modes.
- [MODULES.md](MODULES.md): module conventions and module index.
- [OPERATOR-GUIDE.md](OPERATOR-GUIDE.md): safe operator workflow.
- [PRODUCT-DIRECTION.md](PRODUCT-DIRECTION.md): project philosophy and non-goals.

Module docs stay near the module:

```text
modules/<module>/
  README.md
  docs/
    ARCHITECTURE.md
    TROUBLESHOOTING.md
    SAFETY.md
```

Do not create empty documentation trees just to satisfy the shape. Add files when they carry useful operator or maintenance knowledge.

Current mapping:

| Module | Current entrypoint | Module docs status | Next documentation step |
| --- | --- | --- | --- |
| `wifi-kit` | `modules/wifi-kit.sh` plus `modules/wifi-kit/` | Rich but too broad | Split long docs into `WATCHDOG.md`, `NETWORKING.md`, `UI.md`, and `FRESH-INSTALL.md` later |
| `link-watch` | `modules/link-watch.sh` | README added | Add `docs/LOGGING.md` after first overnight run |
| `wifi-stability` | `modules/wifi-stability.sh` | README added | Add Raspberry Pi troubleshooting notes when more field data exists |
| `cloudflared` | `modules/cloudflared.sh` | Global-only | Add module README when apply path grows beyond install-only |
| `homer` | `modules/homer.sh` | Global-only | Add module README when static placeholder becomes a real service |
| `tailscale`, `caddy`, `docker`, `homepage` | `modules/*.sh` | Global-only | Keep in global module matrix until implementation expands |

Existing Wifi-Kit docs should not be moved wholesale yet. Prefer small redirects or index updates first, then move one topic at a time when links can be checked.

## Priority modules

Near-term modules:

- `tailscale`
- `wifi-stability`
- `link-watch`
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
- `wifi-stability`
- `cloudflared`
- `caddy`
- `homer`

Edge services node:

- `tailscale`
- `cloudflared`
- `caddy`
- `docker`
- `homepage`

Docker is optional. Tailscale, Wi-Fi stability, Cloudflared, Caddy, and Homer are host-level modules for the minimal node path. Homepage remains optional and likely depends on Docker or a heavier web services stack.

Tailscale apply scope is install-only: no `tailscale up`, no auth keys, no stored secrets, and no automatic tailnet join.

Wi-Fi stability V1 is Raspberry Pi only. It can disable `wlan0` power save for the current boot with `sudo iw dev wlan0 set power_save off` after SAFE confirmation.

It can also persist that setting with a small systemd oneshot service at `/etc/systemd/system/seed-kit-wifi-stability.service`. It does not reboot, restart NetworkManager, restart dhcpcd, or restart networking.

Manual rollback:

```sh
sudo systemctl disable seed-kit-wifi-stability.service
sudo rm /etc/systemd/system/seed-kit-wifi-stability.service
sudo systemctl daemon-reload
```

Cloudflared apply scope is install-only: no Cloudflare login, no tunnel creation, no tunnel service install, no token, and no stored credentials.

Caddy apply scope is install-only: no site config, no reverse proxy automation, no DNS automation, no firewall changes, and no certificate provisioning.

Homer V1 creates a local static placeholder at `/srv/seed-kit/homer/index.html`. It does not install upstream Homer yet, and it does not configure Docker, Homepage, Caddy, DNS, firewall rules, or certificates.

## Dependencies and profiles

Some modules will depend on packages, services, network access, or earlier modules. Document those expectations in the module plan first.

A complex dependency engine is not needed yet. Keep dependencies explicit in prose and module output until repeated real cases justify a small shared helper.

## Single module apply

Use `--apply-module=<module>` to retest or repair one specific module without rerunning a whole profile:

```sh
sh seed-kit.sh --apply-module=homer
```

This command applies only the selected module. It does not resolve dependencies automatically, perform rollback, retry failed actions, or keep a state engine.

Field note: `--apply-module=homer` was validated on `rpi-edge-audit.lan`; it skipped cleanly when the Homer placeholder was already present and reported `[OK] homer`.

Profiles are planned compositions of modules, stored later under `profiles/`. They are useful for common node shapes, but modules must remain usable directly without profiles.

Profile naming and V1 compositions are documented in [PROFILES.md](PROFILES.md). In V1, profiles are plan-only aids; they do not apply modules automatically.

## Parallel Module Development Threshold

Parallel module development becomes reasonable when:

- the bootstrap runtime is stable
- `seed-kit.sh` can list modules
- `--plan` and `--apply` are stable
- a minimal module convention is documented
- base sudo, network, and logging helpers are clear enough to reuse

Seed-Kit is close to this threshold. The runtime bootstrap, module listing, planning, targeted apply, SAFE confirmation, and sudo UX are in place.

The remaining gap is convention hardening: module apply boundaries and shared helper usage are still mostly implicit. From this point, `wifi-kit` can begin in parallel with engine work, but only as documentation and SAFE prototype work at first.
