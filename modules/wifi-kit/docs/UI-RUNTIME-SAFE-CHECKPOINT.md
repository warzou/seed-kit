# Wifi-Kit UI/runtime SAFE checkpoint

Status: validated on `pocket-node` after `894da7c`.

This note records the current UI/runtime contract so future work does not
rediscover the repo/runtime/process split.

## Validated commits

- `894da7c fix: add safe UI restart after runtime update`
- `66dfc09 fix: improve maintenance responsive layout`
- `158efb4 fix: prevent false success on runtime update`
- `2cc1c98 fix: simplify recovery config settings layout`

## Runtime shape

- Source UI: `modules/wifi-kit/prototype/ui/`
- Installed runtime UI: `/opt/seed-kit/wifi-kit/ui/`
- Installed service: `wifi-kit-ui.service`
- Service command: `python3 ui/serve-readonly.py --host 0.0.0.0 --port 54321`

The service runs from `/opt/seed-kit/wifi-kit`, not directly from the Git
working tree.

## Update flow

Validated flow:

1. `/updates/check`
2. `/updates/install` with confirmation
3. clean Git repo check
4. `git pull --ff-only`
5. SAFE wrapper action `reinstall-runtime`
6. runtime files copied to `/opt/seed-kit/wifi-kit`
7. `runtime-version` written under `/opt`
8. backend verifies repo commit, runtime commit, and served UI file
9. UI shows: `Mise a jour installee. Redemarrage de l'interface requis.`
10. user clicks `Redemarrer l'interface`
11. POST `/ui/restart`
12. SAFE wrapper action `restart-ui`
13. `wifi-kit-ui.service` restarts and loads the new Python backend

## Repo/runtime/process split

Important distinction:

- Git repo updated does not mean `/opt` runtime is updated.
- `/opt` runtime updated does not mean the running Python process has loaded
  the new backend code.
- The served HTML can change immediately because it is read from disk per
  request, while Python route logic stays in memory until service restart.

The false-success bug came from reporting update success after Git/reinstall
without proving that `/opt` and the served UI matched the repo. The backend now
checks runtime commit and UI markers before reporting success.

## Recovery config UX

Recovery settings were simplified from dashboard-style mini-cards into one
vertical settings surface:

- AP password: empty field keeps the existing password.
- Failsafe: mode is shown as observation or automatic.
- Watchdog: shown as a simple connection monitoring setting.
- Recovery delay: shown as seconds with clear wording.

The old global `Enregistrer recovery` pattern and the isolated `s` unit were
removed.

## Maintenance layout

Maintenance now follows a stable responsive layout:

- Update card is full width.
- Reboot and shutdown sit below it.
- Mobile: stacked vertically.
- Wider screens: reboot and shutdown use two columns.
- The previous three-column mosaic was removed to avoid compressed cards.

## SAFE UI restart

The UI restart path is deliberately narrow:

- Endpoint: `POST /ui/restart`
- Wrapper action: `/opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh restart-ui`
- Sudoers entry allows only that exact wrapper action.
- Wrapper restarts only `wifi-kit-ui.service`.

It does not:

- reboot the node;
- shut down the node;
- restart NetworkManager;
- touch Wi-Fi/AP state;
- accept a user-selected service name;
- execute arbitrary shell commands.

## Known bootstrap limit

The first deployment of `/ui/restart` needed one external SAFE restart because
the old Python backend did not know the new endpoint yet.

After `894da7c` is installed and `wifi-kit-ui.service` has loaded it, future
updates are autonomous through the UI:

`update install -> runtime deploy -> restart UI button -> backend reload`.

## Validation snapshot

Validated on `pocket-node`:

- repo commit: `894da7c`
- runtime commit: `894da7c`
- `runtime_synced=true`
- `/ui/restart` returns `started`
- `wifi-kit-ui.service` PID changes after restart
- UI comes back on port `54321`
- Recovery config layout is served from `/opt`
- Maintenance layout is served from `/opt`

No reboot, shutdown, NetworkManager restart, Wi-Fi action, or AP action was
part of this validation.
