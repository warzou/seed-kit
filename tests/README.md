# Seed-Kit smoke tests

Seed-Kit tests are intentionally small and shell-first.

Run all smoke tests:

```sh
sh tests/run-smoke.sh
```

Run only profile-state smoke tests:

```sh
sh tests/profile-state-smoke.sh
```

These tests are:

- POSIX-light shell scripts,
- framework-free,
- local only,
- limited to temporary files under `/tmp`,
- designed to clean up after themselves.

They do not:

- restore files,
- upload to cloud,
- encrypt data,
- create real backups,
- mutate system configuration.

This is deliberately minimal. Smoke tests should protect the SAFE behavior of
core workflows without turning Seed-Kit into a test framework project.
