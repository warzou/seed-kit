# Wifi-Kit runtime dependencies

Status: audit and plan only. No dependency installation is implemented here.

This document records the tools and services currently used or assumed by the
Wifi-Kit prototype so a future `wifi-kit doctor` and `wifi-kit install-deps`
flow can manage them explicitly.

## Runtime classes

### Critical runtime dependencies

These are required for the current read-only diagnostics and the already tested
temporary connect-safe path:

- POSIX shell: `sh`
- POSIX tools: `awk`, `sed`, `grep`, `tr`, `date`, `mktemp`, `rm`, `chmod`,
  `mkdir`, `cat`, `sleep`, `printf`
- bounded execution: `timeout`
- system identity and state: `hostname`, `whoami`, `uptime`
- network state: `ip`
- Wi-Fi state and radio capabilities: `iw`
- Raspberry Pi OS / Debian WPA backend: `wpa_cli`, `wpa_supplicant`
- reachability validation: `ping`
- remote guarded apply from the operator workstation: `ssh`

### Optional or future runtime dependencies

These are not required for the current read-only UI, but are needed by future
AP recovery or backend support:

- AP radio service: `hostapd`
- AP DHCP/DNS service: `dnsmasq`
- NetworkManager backend support: `nmcli`, `NetworkManager.service`
- system service inspection and future service management: `systemctl`,
  `journalctl`
- DHCP/backend variants: `dhcpcd`, `dhclient`
- radio block inspection: `rfkill`
- WPA passphrase helper for future controlled config generation:
  `wpa_passphrase`
- package download or install helper if Wifi-Kit manages dependencies later:
  `curl`

### Development and fixture-test dependencies

These are used by local fixture converters and plan scripts, not by the target
node runtime path:

- `node` or `node.exe` for JSON fixture parsing and scan fixture conversion
- `python3` for the local read-only mobile UI backend
- `jq` is not currently required by scripts, but may be useful for future
  diagnostics if adopted deliberately

## Pocket-node audit

Observed target:

- host: `pocket-node`
- OS: Debian GNU/Linux 13 (trixie), Raspberry Pi kernel
- radio: `wlan0`, currently managed/client mode
- current SSID: `GL-MT6000-d53`
- current IPv4: `192.168.8.163/24`
- default route: `192.168.8.1` via `wlan0`

Present commands:

- `sh`, `bash`, `awk`, `sed`, `grep`, `tr`, `cut`, `sort`, `uniq`, `head`,
  `tail`, `date`, `mktemp`, `rm`, `chmod`, `mkdir`, `cat`, `printf`, `sleep`,
  `timeout`
- `hostname`, `whoami`, `uptime`
- `ip` from iproute2 6.15.0
- `iw` 6.9
- `wpa_cli` 2.10
- `wpa_supplicant` 2.10
- `ping` from iputils 20240905
- `ssh` OpenSSH 10.0p2 Debian
- `python3` 3.13.5
- `curl` 8.14.1
- `systemctl` from systemd 257
- `journalctl`
- `nmcli` 1.52.1
- `dnsmasq` 2.91 binary present
- `dhcpcd`
- `busybox`
- `rfkill`
- `wpa_passphrase`

Missing commands or packages:

- `hostapd`
- `node` / `nodejs`
- `jq`
- `dhclient` / `isc-dhcp-client`
- `gawk` (the system has `mawk` as `awk`)

Service state:

- `wpa_supplicant.service`: active, enabled
- `NetworkManager.service`: active, enabled
- `ssh.service`: active, enabled
- `systemd-networkd.service`: inactive, disabled
- `hostapd.service`: not found
- `dnsmasq.service`: not found, although the `dnsmasq` binary is present
- `dhcpcd.service`: not found, although `dhcpcd-base` is installed

Manual package marks observed for relevant packages:

- `curl`
- `dhcpcd-base`
- `iproute2`
- `iputils-ping`
- `network-manager`
- `wpasupplicant`

## Implicit or risky assumptions

- The prototype currently recommends `rpios-wpa` when `wpa_cli` or
  `wpa_supplicant` exists, but `pocket-node` also has NetworkManager active.
  Future mutation code must choose one backend contract and avoid mixing direct
  `wpa_cli` writes with NetworkManager-owned state unless that interaction is
  explicitly validated.
- The real connect-safe prototype uses direct `wpa_cli` operations. That worked
  in the field test, but it should be guarded by backend detection and a
  NetworkManager compatibility check.
- Direct `wpa_cli` apply must refuse when NetworkManager owns `wlan0`. The
  official Raspberry Pi OS backend should use `nmcli`/NetworkManager for future
  mutation flows.
- `hostapd` is planned for AP recovery but is absent on `pocket-node`.
- `dnsmasq` binary is present, but there is no active or installed
  `dnsmasq.service`; AP recovery must not assume a service unit exists.
- `node` is absent on the target, so fixture/dev scripts are not target-runtime
  safe unless Node is treated as dev-only or bundled elsewhere.
- `jq` is absent; do not introduce it into runtime scripts unless it is added to
  dependency management.
- AP+STA is hardware-advertised but constrained by single-channel operation on
  the Raspberry Pi Zero 2 W radio. Reliable product behavior should not depend
  on simultaneous AP plus STA without a dedicated validation path.

## Future dependency architecture

Recommended commands:

- `wifi-kit doctor`
  - read-only
  - prints OS, backend, interface, service state, required tools, optional tools,
    missing packages, and risk flags
  - never installs or starts services
- `wifi-kit install-deps --backend raspberrypi`
  - explicit operator confirmation
  - installs only missing packages for the selected backend
  - does not start AP services
  - disables or masks auto-start for AP services when safe and expected
- `wifi-kit deps plan`
  - prints package names per backend without installing

Suggested backend matrix:

- `raspberrypi-networkmanager`
  - requires `network-manager`, `wpasupplicant`, `iw`, `iproute2`,
    `iputils-ping`
  - optional AP: `hostapd`, `dnsmasq`
- `raspberrypi-wpa`
  - requires `wpasupplicant`, `iw`, `iproute2`, `iputils-ping`
  - optional AP: `hostapd`, `dnsmasq`
- `debian-generic`
  - read-only diagnostics first; mutation disabled until backend ownership is
    known
- `openwrt`
  - separate backend with OpenWRT-native commands; do not reuse Debian package
    assumptions

Install policy:

- default to audit-only;
- never install without explicit operator confirmation;
- never start `hostapd` or `dnsmasq` as part of dependency installation;
- never call `save_config` as part of dependency management;
- never store Wi-Fi secrets in Wifi-Kit files, logs, or package plans.
