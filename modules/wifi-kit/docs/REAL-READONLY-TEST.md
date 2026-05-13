# wifi-kit real read-only field test

This procedure validates the `wifi-kit` read-only prototype on a real Raspberry Pi target without changing network configuration.

## Scope

Target:

- Raspberry Pi OS Lite preferred,
- current `main` branch,
- `modules/wifi-kit/prototype/wifi-kit.sh`.

Safety contract:

- no Wi-Fi connection attempt,
- no config write,
- no `hostapd`,
- no `dnsmasq`,
- no NetworkManager apply,
- no service start,
- no Wi-Fi secret read, written, or logged.

## Commands on target

Run from the repository root on the Raspberry Pi:

```sh
git pull
git log --oneline -5
sh -n modules/wifi-kit/prototype/wifi-kit.sh
sh modules/wifi-kit/prototype/wifi-kit.sh backend-detect
sh modules/wifi-kit/prototype/wifi-kit.sh status-real
sh modules/wifi-kit/prototype/wifi-kit.sh scan-real || true
```

The final command may fail due to permissions, a busy interface, missing `iw`, or hardware/driver limits. That is acceptable if the failure is explicit and non-destructive.

## Results to collect

Record the command output, then summarize:

- OS detected,
- tools present and missing,
- Wi-Fi interface detected,
- IP detected,
- default route,
- whether SSID scan works,
- if scan does not work: permission error, missing tool, or other clear reason.

Do not collect PSK values, private Wi-Fi config files, tokens, or any secret material.

## Success criteria

The test is successful when:

- script syntax check passes,
- `backend-detect` output is readable,
- `status-real` completes without changing network state,
- `scan-real` succeeds or fails cleanly when permissions/tools are insufficient,
- no network modification is observed,
- no Wi-Fi secret is read, written, or logged.

## What not to do

Do not run any command that connects to Wi-Fi, writes `wpa_supplicant`, starts `hostapd`, starts `dnsmasq`, applies NetworkManager changes, or installs services as part of this test.
