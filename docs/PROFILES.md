# Seed-Kit profiles

Profiles are named module compositions for common machine shapes.

A module is one capability, such as `tailscale`, `wifi-stability`, or `homer`.
A profile is a suggested set of modules for a target node shape.

Profiles are public and must not contain secrets, credentials, private restore data, or cloud configuration. Restore flows, local configs, and secrets stay separate.

## Naming

`node` means Tailscale is expected or planned.

Examples:

- `rpi0-pocket`: small Raspberry Pi Zero style pocket/rescue device.
- `rpi0-pocket-node`: pocket/rescue node with Tailscale.
- `rpi3-edge`: Raspberry Pi 3 edge host without the node assumption.
- `rpi3-edge-node`: Raspberry Pi 3 edge node with Tailscale.
- `minimal-resilient-node`: host-level resilient base.
- `edge-services-node`: resilient base plus heavier service modules.

## V1 profiles

`minimal-resilient-node`:

- `wifi-stability`
- `tailscale`
- `cloudflared`
- `caddy`
- `homer`

`edge-services-node`:

- `minimal-resilient-node`
- `docker`
- `homepage`

For now, profiles are planning aids. They do not apply modules automatically, resolve dependencies, restore configs, or install secrets.
