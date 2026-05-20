# SAFE Apply Plan

Seed-Kit does not have a real module apply engine yet.

The current command is intentionally small:

```sh
sh seed-kit.sh apply-plan <module> --dry-run
```

It only prints the future order of module steps and the manifest sources that
would be consulted. It does not create files or runtime state.

## What It Shows

- module summary
- future step order
- specialized manifest sources when available
- forbidden automatic actions

The future step order is:

1. `modules validate <module>`
2. `modules install-packages-preview <module>`
3. `modules install-files-preview <module>`
4. `modules configure-sudoers-preview <module>`
5. `modules install-service-preview <module>`
6. `modules recovery-preview <module>`

## What It Does Not Do

- no apply
- no package install
- no file copy
- no directory creation
- no chmod/chown
- no sudoers write
- no systemd write
- no service start
- no network change
- no AP mode
- no reboot
- no secrets

## Design Rule

Keep module apply boring and explicit. Future real apply should be added only as
small guided steps with clear confirmations, not as a generic framework.
