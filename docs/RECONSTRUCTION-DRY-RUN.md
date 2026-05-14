# rpi-edge reconstruction dry-run

This document defines a SAFE reconstruction test from `rpi-edge` to
`rpi3-edge-audit`.

It is a plan only. It does not restore secrets, start production services, move
DNS, change Cloudflare, or replace the production node.

## Scope

- source: `rpi-edge`
- target: `rpi3-edge-audit`
- mode: dry-run / test reconstruction
- private state: reviewed manually, not restored automatically

## SAFE steps

1. Install Seed-Kit on the target.

   ```sh
   sh seed-kit.sh --self-check
   ```

2. Review the replacement profile plan.

   ```sh
   sh seed-kit.sh --profile=rpi-edge-replacement --plan
   ```

3. Apply the minimal resilient base only if needed.

   ```sh
   sh seed-kit.sh --profile=minimal-resilient-node --apply
   ```

4. Retrieve or clone `rpi-edge-vps` in test mode.

   The project should be reviewed as files first. Do not start production
   containers automatically.

5. Do not restore the real `.env` automatically.

   Treat `.env` as sensitive profile-state. It requires encrypted handling and
   human review before any use.

6. Verify Compose and config without starting production.

   Check the expected files:

   - `~/git/rpi-edge-vps/compose/docker-compose.yml`
   - `~/git/rpi-edge-vps/config/caddy`
   - `~/git/rpi-edge-vps/config/homepage`

7. Complete private manual steps only after review.

   Manual steps may include:

   - `sudo tailscale up`
   - Cloudflare tunnel authentication or selection
   - Caddy config review
   - Homepage config review
   - service-by-service validation

## Limits

This dry-run must not perform:

- DNS cutover,
- production replacement,
- plaintext secret restore,
- automatic `.env` copy,
- automatic Cloudflare mutation,
- automatic Tailscale identity clone,
- automatic restore,
- production container start without explicit human approval.

## Success criteria

The dry-run is successful when:

- the target can run the public Seed-Kit profile plan,
- the target can apply the minimal host-level base when needed,
- the `rpi-edge-vps` project structure is visible in test mode,
- sensitive files are identified but not printed,
- Compose and config files can be reviewed,
- remaining manual production steps are explicit.
