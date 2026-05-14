# wifi-kit Wi-Fi stability note

## Symptom observed

On Raspberry Pi Zero 2 W, `wlan0` may become unstable while idle when Wi-Fi power saving is enabled.

Observed state:

```text
wlan0 power_save=on
```

## Cause identified

The current field hypothesis is that Wi-Fi power saving can make the radio less reliable for an always-on resilient node, especially before a future bootstrap/hotspot flow.

This is important because `wifi-kit` depends on a stable base radio before designing `connect-safe`, recovery, or hotspot/bootstrap behavior.

## Current-boot fix validated manually

The manually validated current-boot fix is:

```sh
sudo iw dev wlan0 set power_save off
```

`wifi-kit` exposes this as a guarded command:

```sh
sudo sh modules/wifi-kit/prototype/wifi-kit.sh stability-apply-current-boot wlan0
```

## Limits

- The change is not persistent across reboot.
- No system configuration is written.
- No service is created or modified.
- No Wi-Fi connection, SSID change, `hostapd`, `dnsmasq`, or NetworkManager apply is performed.

## Risks

- Power usage may increase.
- The command may require root or `CAP_NET_ADMIN`.
- Interface names may differ across targets, so the interface must be detected or passed explicitly.
- The setting may be reset by reboot or by another network manager.

## Rollback

Rollback options:

```sh
sudo iw dev wlan0 set power_save on
```

or reboot the node.

## Safe commands

Read-only status:

```sh
sh modules/wifi-kit/prototype/wifi-kit.sh stability-status
```

Plan only:

```sh
sh modules/wifi-kit/prototype/wifi-kit.sh stability-plan
```

Current-boot apply, only on the target RPi and only when explicitly requested:

```sh
sudo sh modules/wifi-kit/prototype/wifi-kit.sh stability-apply-current-boot wlan0
```
