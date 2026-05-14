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

## Field test note: validated reconstruction dry-run

A real reconstruction dry-run was validated from `rpi-edge` to
`rpi3-edge-audit`.

Validated flow:

- Seed-Kit was retrieved on the target.
- `git` was installed through Seed-Kit only.
- A test snapshot of `rpi-edge-vps` was transferred without the real `.env`.
- `profile-state inventory` completed successfully.
- `profile-state backup --dry-run` completed successfully.

Detected as expected:

- `rpi-edge-vps`
- `compose/docker-compose.yml`
- `config/caddy`
- `config/homepage`
- missing `.env`

Safety confirmations:

- no secret content was read,
- no real restore was performed,
- no Docker Compose stack was started,
- no `tailscale up` was run,
- no Cloudflare login or tunnel mutation was performed,
- no DNS cutover was performed,
- `/etc/machine-id` and host SSH keys were excluded as `do-not-clone`.

Docker volumes were unknown or not accessible to the `codex` user during this
test. That is not blocking for the dry-run; real volume backup will require an
explicit encrypted backup design and appropriate operator privileges.

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
