# Seed-Kit - Context

Seed-Kit is a lightweight POSIX-shell toolkit for installing and resuming small machines:
Debian, Raspberry Pi OS, mini VPS, and later OpenWRT/Flint.

## Core Rule

Do one thing well: install tools, apps, and GitHub repos cleanly on small machines.
Seed-Kit keeps to a minimal bootstrap/install/restore role and avoids becoming an orchestration platform.

Everything else is secondary.

## Must Stay

* lightweight, readable, modular
* SSH-friendly
* low RAM / low overhead
* no heavy dependencies
* simple shell first
* small diffs
* field-test driven

## Current V0

* `seed-kit.sh` entrypoint
* simple OS detection
* simple backends: `debian`, `raspberrypi`, `openwrt`
* placeholder modules: `git`, `docker`, `tailscale`, `homepage`
* modular monorepo layout: `modules/`, `backends/`, `docs/`, and planned `profiles/`
* minimal inline terminal UI
* one real minimal apply path: `--apply --modules=git`
* generated bootstrap runtime can be removed with `--uninstall-runtime`
* read-only diagnostics: `doctor`, `--self-check`, `self-update --plan`
* safe update path: `self-update --apply` uses only `git pull --ff-only`
* profile-state supports SAFE reconstruction planning and package verification

Principal mental flow:

1. Fresh install
2. Seed-Kit installer
3. Restore/replay package or profile
4. Guided human steps only when required

`restore <package>` is the intended principal restore concept (implementation naming can follow current CLI names),
and `guided` must only describe human-judgment steps.

## Architecture Direction

Seed-Kit is a modular monorepo, not a collection of separate module repositories.

Keep:

* `seed-kit.sh` as engine and only entrypoint
* `modules/` as installable capabilities
* `profiles/` as planned module compositions
* `backends/` as OS support
* `docs/` as project documentation
* minimal SSH-friendly UI integrated in `seed-kit.sh`

Product direction:

* Docker is optional, not part of the minimal base.
* Tailscale is host-level and must not depend on Docker.
* Minimal resilient node: `tailscale`, `cloudflared`, `caddy`, `homer`.
* Edge services node: `tailscale`, `cloudflared`, `caddy`, `docker`, `homepage`.
* `wifi-kit` replaces the old `wifi-portal` concept and must use a temporary minimal HTTP server, compatible with BusyBox `httpd`.

## UX Direction

Direction: calm modern terminal UI.

Seed-Kit should feel like a small machine-aware cockpit, not a shell script.

Keep:

* spatial layout
* strong visual hierarchy
* lowercase labels where calmness helps
* low visual noise
* contextual machine info
* simple recommendations
* responsive width
* ANSI used sparingly
* light Unicode with ASCII fallback
* clean `NO_COLOR` behavior

Avoid:

* retro UNIX look
* hacker dashboard
* cyberpunk styling
* noisy ASCII art
* flashy effects
* colors everywhere
* old vertical menu as the main experience

## Technical Guardrails

Use:

* POSIX shell where practical
* `printf`
* minimal in-script terminal helpers in `seed-kit.sh`
* BusyBox-compatible patterns when possible

Avoid:

* Python unless truly needed
* Node.js
* ncurses, dialog, whiptail, gum, Textual, Bubble Tea
* complex plugin systems
* enterprise architecture
* generic abstractions before real need

Avoid for now (anti-bloat):

* complex planners
* checkpoint engines
* readiness/state layers that create runtime dependency
* state managers for pseudo-workflows
* full framework-style shell abstractions

Principle:

* remove > rewrite
* simplify > abstract
* concrete behavior > simulation

## Not Now

* advanced restore
* complex secrets
* GDrive/rclone backend
* advanced profiles
* orchestration frameworks
* distributed system
* multi-layer abstractions
* restore/replay command engines or checkpointing before end-to-end manual flow is clear

## Workflow

1. Keep README short.
2. Read this file before changing direction.
3. Make small, focused diffs.
4. Test shell syntax and terminal rendering.
5. Validate on real SSH before polishing further.
6. Do not push without validation.
