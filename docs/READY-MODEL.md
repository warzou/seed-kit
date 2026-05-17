# Ready model

## Installed is not Ready

Seed-Kit separates installation from readiness.

A package can be installed and still not be ready to replace a node. Some steps
require identity, trust, browser login, DNS review, or operator validation.

## Lifecycle

```text
Installed -> Configured -> Validated -> Ready
```

- Installed: the binary or package is present on the system.
- Configured: local configuration or identity material is present.
- Validated: Seed-Kit can check the shape or status without changing anything.
- Ready: the operator has enough evidence to proceed to the next manual step.

## Vocabulary

- System: host packages/installations such as `docker`, `tailscale`,
  `cloudflared`, `caddy`, or `git`.
- Modules: internal Seed-Kit modules such as `wifi-stability` or `wifi-kit`.
- Services: application services carried by a package, such as `homepage` or a
  compose stack.
- Manual identities: trust or login steps such as Tailscale auth or Cloudflare
  tunnel credentials.

## Seed-Kit Role

Seed-Kit can:

- install explicit system packages
- diagnose current state
- guide the next manual action
- validate staged or deployed configs

Seed-Kit does not:

- restore secrets automatically
- perform browser/login flows automatically
- perform DNS or cutover automatically
- hide orchestration behind opaque commands
- start services as part of readiness checks

## Tailscale Example

Tailscale can be installed without being connected.

Readiness should show:

```text
tailscale:
  installed: yes
  connected: no
  ready: no
  next: sudo tailscale up
```

The operator runs `sudo tailscale up` manually. Expected result:

- the node appears in the tailnet
- `tailscale ip` returns an IP
- readiness becomes `yes`

Seed-Kit must not run `tailscale up` automatically.

## Cloudflared Example

Cloudflared can be installed without tunnel credentials or config.

Readiness should show:

```text
cloudflared:
  installed: yes
  configured: no/unknown
  ready: no
  next: cloudflared tunnel login/create/configure
```

The operator performs the Cloudflare login, tunnel creation, route, and config
review manually. Expected result:

- tunnel credentials are present
- tunnel configuration is detected
- readiness becomes `yes`

Seed-Kit must not run Cloudflare login or create DNS/cutover automatically.

## Future Wifi-Kit Example

Wifi-Kit should follow the same model in its own separated flow:

- Installed: required local tools or module files are present.
- Configured: target SSID/connection material is declared by the operator.
- Validated: current network state can be inspected safely.
- Ready: the operator has confirmed the network path and fallback plan.

Seed-Kit core must not treat Wifi-Kit as a hidden dependency resolver or an
automatic network cutover engine.
