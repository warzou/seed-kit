# link-watch

`link-watch` is a small Seed-Kit module for observing Internet availability.

It is independent from Wifi-Kit. It does not change DNS, routes, Wi-Fi profiles, NetworkManager, firewall rules, or reboot the node.

## Purpose

Use it to answer simple field questions:

- When did Internet go down?
- When did it come back?
- How long was the outage?
- Which target was tested?

## Commands

```sh
sh seed-kit.sh link-watch start
sh seed-kit.sh link-watch stop
sh seed-kit.sh link-watch status
sh seed-kit.sh link-watch logs
sh seed-kit.sh link-watch follow
```

`start`, `stop`, and `uninstall` require SAFE confirmation and may require `sudo` because they manage a systemd service.

## Runtime

Default target:

```text
1.1.1.1
```

Default interval:

```text
5 seconds
```

Logs:

```text
/var/log/seed-kit/link-watch/link-watch.log
/var/log/seed-kit/link-watch/link-watch.state
```

The monitor logs state changes only. It should not write one log line every 5 seconds while the state is unchanged.

## Events

- `monitor-started`
- `internet-ok`
- `internet-down`
- `internet-restored`

When possible, events include target, hostname, interface, latency, and outage duration.

## Rollback

```sh
sh seed-kit.sh link-watch stop
sh seed-kit.sh link-watch uninstall
```

`uninstall` removes the systemd unit only. Logs are intentionally left in place for operator review.

## Limitations

V0 uses ICMP ping. Future extensions may add gateway checks, multiple public targets, DNS checks, HTTP checks, retention, and log rotation.
