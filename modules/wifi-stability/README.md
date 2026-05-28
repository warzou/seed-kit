# wifi-stability

`wifi-stability` is a Seed-Kit module for reducing idle Wi-Fi dropouts on Raspberry Pi nodes.

It is intentionally narrow: it checks `wlan0` power save and can disable it after SAFE confirmation.

## Why it exists

Field tests on Raspberry Pi Zero 2 W showed that `wlan0 power_save=on` can make an otherwise healthy node become unreachable while idle.

Wifi-Kit depends on stable Wi-Fi availability, so `wifi-stability` is applied as a prerequisite before fresh Wifi-Kit installs on Raspberry Pi targets.

## Plan

```sh
sh seed-kit.sh --plan
```

The module reports:

- whether the target looks like a Raspberry Pi;
- whether `wlan0` exists;
- the current `wlan0 power_save` state when `iw` is available.

## Apply

```sh
sh seed-kit.sh --apply --modules=wifi-stability
```

On Raspberry Pi with `wlan0 power_save=on`, the module can:

- run `sudo iw dev wlan0 set power_save off`;
- install a systemd oneshot service so the setting is restored after boot.

It does not reboot, restart NetworkManager, restart networking, change SSID, or delete Wi-Fi profiles.

## Service

```text
/etc/systemd/system/seed-kit-wifi-stability.service
```

## Rollback

```sh
sudo systemctl disable seed-kit-wifi-stability.service
sudo rm /etc/systemd/system/seed-kit-wifi-stability.service
sudo systemctl daemon-reload
```

Rollback does not change the current Wi-Fi connection. Reboot behavior returns to the platform default unless another service sets power save.

## Limitations

V1 is Raspberry Pi focused and only handles `wlan0` power save. It does not diagnose router-side instability, DHCP issues, DNS issues, or Internet outages. Use `link-watch` for Internet availability logging.
