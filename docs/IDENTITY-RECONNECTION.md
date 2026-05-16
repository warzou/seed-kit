# Identity reconnection

## Goal

Reconstruct the service without cloning the machine identity.

Seed-Kit service packages can preserve compose files, configs, notes,
manifests, and checksums. They should not preserve host identity, network
identity, tunnel credentials, or trust material. Those identities are
reconnected deliberately by the operator.

## Tailscale

Simple flow:

1. install tailscale
2. run tailscale login
3. open the login URL
4. authenticate
5. verify tailscale status
6. validate private access before public exposure

`tailscaled.state` is not restored. The rebuilt node joins the tailnet cleanly
as a new or intentionally reconnected node.

## Cloudflare

Simple flow:

1. install cloudflared
2. run cloudflared tunnel login
3. open the Cloudflare URL
4. authenticate
5. reconnect or recreate the tunnel
6. verify the systemd service
7. verify the domain and tunnel before exposure

Cloudflare credentials are not restored automatically. Tunnel identity remains
a manual operator decision.

## SSH trust

A new SSH host key is normal after reconstruction.

Verify the fingerprint, then accept the new key explicitly. Do not copy SSH host
keys between nodes. SSH trust should describe the rebuilt machine, not pretend
it is the old machine.

## Hostname

The operator may keep or change the hostname.

Keeping the hostname can make service reconstruction simpler. Changing it can
make audits and cutover safer. Avoid running two active nodes with the same
hostname unless the transition is tightly controlled.

## DNS and cutover

Validate services before public exposure:

1. validate local service files
2. validate Docker compose shape if Docker is used
3. validate Caddy/Homepage behavior
4. validate Tailscale/private access
5. validate Cloudflare tunnel and DNS targets
6. perform public cutover only after private checks pass

DNS and public exposure are final cutover steps, not package restore steps.

## Philosophy

- identities are recreated intentionally
- services are reconstructed
- nodes are disposable
- no automatic identity cloning

The package helps rebuild the service. The operator reconnects identity, trust,
network exposure, and production cutover.
