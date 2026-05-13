# External official modules

This document prepares official external modules for rebuilding a fresh `rpi-edge` SD card without depending on `warzou` repositories.

The target modules are:

- `tailscale`
- `cloudflared`
- `caddy`
- `homer`
- `docker`
- `homepage`

These modules live inside the Seed-Kit monorepo. They may install upstream packages or guide official setup steps, but they must not require private repos, secrets, or credentials.

Docker is optional. It is useful for the edge services path, but it is not part of the minimal resilient host-level base.

Tailscale is host-level. It must not depend on Docker.

## Core helper shape

Seed-Kit should keep shared helpers small and boring:

- `plan`: show what would happen before any change.
- `apply`: run only after explicit module selection.
- `sudo`: check access immediately before privileged actions.
- `network`: detect obvious offline state before package downloads.
- `logging`: print clear step labels and failures.

Helpers should stay in `seed-kit.sh` until repeated module pressure proves a small shared file is needed.

## Apply convention

Each real apply path should:

- check current state first
- stop early when already installed
- require `--modules=<name>` selection
- use SAFE confirmation unless `-y` is provided
- check `sudo` immediately before privileged actions
- check network before package downloads
- avoid storing secrets or tokens
- print manual follow-up steps for auth flows

`--plan` remains the normal first step.

## Module matrix

| module | plan | apply | network required | sudo required | secrets required |
| --- | --- | --- | --- | --- | --- |
| `tailscale` | installed status, official apt install plan, auth note | install-only | yes | yes | no |
| `cloudflared` | installed status, official apt install plan, tunnel note | install-only | yes | yes | no |
| `caddy` | installed status, official package plan, service note | later | yes | yes | no |
| `homer` | lightweight dashboard plan, static files/service note | later | maybe | maybe | no |
| `docker` | installed status, package source plan, daemon note | later | yes | yes | no |
| `homepage` | config/deploy plan, dependency note | later | maybe | maybe | no |

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

## Module details

### tailscale

Seed-Kit should check whether Tailscale is installed and describe the official package install path.

Seed-Kit should not automate `tailscale up`, store auth keys, or log in to a tailnet. It can print the manual next command later.

Tailscale is a host-level module and must not depend on Docker.

Current apply scope: install-only through the official Tailscale apt repository on Debian/Raspberry Pi OS. After install, Seed-Kit prints `sudo tailscale up` as a manual next step.

### cloudflared

Seed-Kit should check whether `cloudflared` is installed and describe the official package install path.

Seed-Kit should not create tunnels, store credentials, configure Cloudflare accounts, or run token-based login.

Current apply scope: install-only through the official Cloudflare apt repository. Seed-Kit does not run `cloudflared tunnel login`, create tunnels, install tunnel services, or store credentials.

### caddy

Seed-Kit should check whether Caddy is installed and describe the official package install path.

Seed-Kit should not publish sites, edit DNS, or assume certificate automation is safe until a module plan is explicit.

### homer

Seed-Kit should treat Homer as the lightweight dashboard path for Raspberry Pi Zero 2 W, rescue nodes, nomadic nodes, and low-RAM hosts.

Homer should not require Docker in the minimal resilient node path. It can be served by a minimal host-level web service when that path is defined.

### docker

Seed-Kit should check whether Docker is installed and describe the official install path for Debian/Raspberry Pi OS.

Seed-Kit should not configure registries, deploy compose stacks, or log in to any container registry yet.

Docker is optional and belongs to the edge services path.

### homepage

Seed-Kit should plan a small local homepage deployment after the web/runtime choices are clearer.

Seed-Kit should not depend on a private repo, pull secrets, or deploy user-specific configuration in the core path.

Homepage remains optional and is likely Docker-dependent.

### wifi-kit

`wifi-kit` replaces the older `wifi-portal` concept.

It should provide temporary Wi-Fi onboarding and recovery:

- temporary hotspot
- phone onboarding
- SSID scan
- Wi-Fi password entry
- QR code
- network connection
- recovery/reconnect flow

`wifi-kit` must not depend on Docker, Homepage, Caddy, or Internet access.

It should use a temporary minimal HTTP server, compatible with BusyBox `httpd`, with low overhead for Raspberry Pi Zero W, OpenWRT, and rescue nodes.

Caddy remains useful later for the final node, not for first-boot Wi-Fi onboarding.

## Current readiness

Real apply work should wait for one more helper pass.

The next useful core pass is to add tiny reusable checks for:

- command already installed
- network reachability for package installs
- sudo availability before privileged actions
- consistent apply step output

After that, `tailscale`, `cloudflared`, `caddy`, and `docker` can each start with install-only apply paths. `homer` can start as a low-overhead dashboard plan. `homepage` should wait until the Docker/edge-services path is explicit.
