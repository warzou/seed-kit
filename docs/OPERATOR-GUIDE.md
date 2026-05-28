# Seed-Kit operator guide

Seed-Kit is a SAFE shell-first toolkit for preparing and maintaining small nodes.

Default rule: inspect first, apply only after the command explains what it will do.

## Normal workflow

```sh
sh seed-kit.sh --plan
sh seed-kit.sh --modules
sh seed-kit.sh --apply --modules=<module>
```

Use targeted commands for module-specific operations when they exist:

```sh
sh seed-kit.sh install wifi-kit
sh seed-kit.sh link-watch status
sh seed-kit.sh link-watch logs
```

## Safety expectations

Seed-Kit modules should:

- describe changes before applying them;
- ask for confirmation before privileged or persistent changes;
- use `sudo` only at the point it is needed;
- avoid storing secrets;
- avoid rebooting, restarting NetworkManager, changing DNS, or changing routes unless a module explicitly documents that behavior.

## Module docs

Use the module README first:

- `modules/wifi-kit/README.md`
- `modules/link-watch/README.md`
- `modules/wifi-stability/README.md`

Use global docs for project-wide concepts:

- `docs/ARCHITECTURE.md`
- `docs/MODULES.md`
- `docs/PRODUCT-DIRECTION.md`

## Troubleshooting posture

When a node is unstable, collect evidence before applying fixes:

```sh
sh seed-kit.sh --plan
sh seed-kit.sh link-watch status
sh seed-kit.sh link-watch logs
```

For Wifi-Kit runtime issues, use the Wifi-Kit UI diagnostics and the module-specific docs under `modules/wifi-kit/docs/`.
