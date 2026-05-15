# Service reconstruction

Seed-Kit is oriented toward service reconstruction, not full machine backup.

The central idea:

- a node is disposable,
- its useful function should be reconstructible.

## Service state

Service state is the small, intentional information needed to rebuild what the
node does.

This is what Seed-Kit should help preserve or describe:

- compose files,
- service configuration,
- ports and domains,
- required Seed-Kit modules,
- reconstruction order,
- operator notes,
- explicit small sensitive files when intentionally chosen.

## Data state

Data state is not backed up by default.

Seed-Kit does not try to preserve:

- user data,
- media,
- databases,
- logs,
- caches,
- full Docker volumes,
- full SD card images.

Those may need separate, service-specific backup decisions.

## Private storage

Seed-Kit core lives in public Git.

Node-specific packages and inventories should live in private storage chosen by
the operator, such as GDrive or another private location.

Those artifacts should be:

- small,
- targeted,
- verifiable,
- encrypted when they contain sensitive material,
- accessible from both the node and an operator workstation.

## Non-goals

Seed-Kit is not:

- a full machine clone,
- an incremental backup engine,
- an automatic restore system,
- a permanent cloud sync agent,
- a secret vault,
- an orchestration platform.

## Example: RustDesk

For a RustDesk service, preserve:

- compose/config,
- ports and domains,
- dependencies,
- reconstruction notes.

Do not preserve by default:

- logs,
- cache,
- full runtime directory,
- full SD card image.

## Future direction

Seed-Kit may later help:

- audit a service,
- classify what is worth preserving,
- ask the operator for an explicit decision,
- produce a small reconstruction package.

It should still avoid automatic restore unless that is explicitly designed and
validated much later.
