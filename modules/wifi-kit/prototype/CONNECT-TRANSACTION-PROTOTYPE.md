# Wifi-Kit connect transaction prototype

This prototype explores a guarded Wi-Fi reconnect transaction for a pocket-node
managed with NetworkManager.

It is not a stable Wifi-Kit feature. It is a prototype kept under
`modules/wifi-kit/prototype/` so it can be reviewed, discussed, and tested in a
controlled setting without becoming part of the official install or restore
flow.

The local UI can now call this transaction only through the read-only prototype
server, and only when all runtime gates are satisfied:

- `WIFI_KIT_ENABLE_PRIVILEGED_ACTIONS=1`
- AP recovery context is active
- the UI sends `--dangerous-real-apply` intent
- the exact confirmation phrase is supplied:
  `WIFI-KIT CONNECT SAFE TRANSACTION`

## Role

`wifi-kit-connect-transaction.sh` models one safe-ish Wi-Fi change:

1. inspect the current NetworkManager state;
2. create a temporary Wi-Fi profile for the target SSID;
3. try to connect to that SSID;
4. validate basic network health;
5. roll back to the previous NetworkManager profile on failure;
6. try AP recovery only if rollback also fails.

Passwords are read from stdin in `apply` mode and should not be logged.

## Modes

- `audit`: read-only inspection of local prerequisites and current Wi-Fi state.
- `plan --ssid "<SSID>"`: read-only description of the planned transaction.
- `apply --ssid "<SSID>" --dangerous-real-apply --confirm "WIFI-KIT CONNECT SAFE TRANSACTION"`:
  real NetworkManager changes. This mode is experimental and dangerous.

Recommended testing for now:

```sh
sh modules/wifi-kit/prototype/wifi-kit-connect-transaction.sh audit
sh modules/wifi-kit/prototype/wifi-kit-connect-transaction.sh plan --ssid "<SSID>"
```

Do not run `apply` during normal development.

## Prerequisites

- Linux target using NetworkManager.
- `nmcli` available.
- A known Wi-Fi interface, defaulting to `wlan0`.
- Active SSH service if remote supervision is expected.
- `modules/wifi-kit/prototype/ap-setup-test.sh` present for AP recovery.
- `WIFI_KIT_AP_PSK` set before AP recovery can be attempted.

## Guarantees

- `audit` and `plan` are intended to be read-only.
- `apply` requires root, `--dangerous-real-apply`, and the exact confirmation
  phrase.
- `apply` uses a temporary NetworkManager profile named `wifi-kit-tx-<txid>`.
- Runtime log and state files include the transaction id to avoid basic `/tmp`
  collisions.
- Cleanup only targets the temporary Wifi-Kit transaction profile.
- UI/backend integration refuses to start real work unless privileged actions,
  recovery context, and exact confirmation are all present.
- If AP recovery is needed after rollback failure, the transaction does not
  append AP setup output to its own log, because AP plan text can include a
  runtime passphrase in future-command examples.

## Non-guarantees

- It does not prove that the operator can reconnect over SSH after a Wi-Fi
  change.
- It does not protect against all NetworkManager, driver, DHCP, DNS, or AP
  failure modes.
- It does not make AP recovery safe by itself.
- It is not integrated with the mobile UI, installer, restore flow, or service
- It is not integrated with the installer, restore flow, or service
  orchestration.
- It is not a replacement for a controlled pocket-node test plan.

## Risks

`apply` can disconnect the active SSH session and leave the device unreachable if
the target Wi-Fi, rollback, and AP recovery all fail. Run it only during a
controlled maintenance window with local recovery options available.

AP recovery is intentionally blocked unless `WIFI_KIT_AP_PSK` is explicitly set.
Do not use a weak or shared recovery passphrase.

## TODO

- Add an optional control-plane heartbeat before considering `apply` successful.
- Document a pocket-node test matrix before promoting any part of this prototype.
- Decide whether `audit` and `plan` should become official commands later.
