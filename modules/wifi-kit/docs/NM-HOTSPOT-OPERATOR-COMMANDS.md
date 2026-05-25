# Wifi-Kit NM Hotspot Operator Commands

This document covers the experimental NetworkManager-only recovery hotspot lab.
It does not replace the validated hostapd/dnsmasq recovery flow.

The normal Wifi-Kit UI runs on port `54321`.

The NM-hotspot recovery UI is expected at:

```sh
http://192.168.50.1:80
```

The lab helper is:

```sh
modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh
```

By default every lab command is dry-run. Real mutation requires:

```sh
WIFI_KIT_NM_AP_LAB_APPLY=1
```

Do not set that variable unless you intentionally want the node to change Wi-Fi
state.

## Validated Runtime Milestone

Pocket-node validation confirmed the NM-hotspot recovery engine can complete a
real recovery path without command-line Wi-Fi intervention:

- the NM hotspot starts;
- the recovery UI starts automatically at `http://192.168.50.1:80`;
- `status` reports `hotspot_active=true`, `ui_recovery_active=true`, and
  `port_80_listening=true`;
- from the recovery UI, the user returned to the Flint Wi-Fi;
- LAN SSH came back after the return;
- no reboot occurred;
- the historical hostapd/dnsmasq recovery flow remains intact.

This is a motor milestone for the NM-hotspot lab: AP startup, automatic
recovery UI lifecycle, and explicit Wi-Fi return are now validated together.
The mode remains experimental until captive portal behavior and the remaining
connection-error UX are hardened.

## Concepts

`rollback` is technical cleanup only:

- stop the NM-hotspot recovery UI;
- stop/delete the lab hotspot profile `wifi-kit-recovery-ap`;
- do not reconnect any Wi-Fi profile.

`return-last-good` is an explicit user return to the last validated Wi-Fi:

- uses `last_good_connection` if it resolves to a NetworkManager profile;
- otherwise tries to resolve `last_good_ssid` to an existing Wi-Fi profile.

`return-primary` is an explicit user return to the configured primary Wi-Fi:

- uses `return_connection` if it resolves to a NetworkManager profile;
- otherwise tries to resolve `return_ssid` to an existing Wi-Fi profile.

This distinction matters: Flint/primary is a boot fallback and an explicit user
choice, not an implicit runtime fallback.

## Lab Helper Commands

### audit

```sh
sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh audit
```

Shows current tooling and capability context. It prints NetworkManager status,
Wi-Fi profiles when `nmcli` is available, and `iw` valid interface combinations
when `iw` is installed.

Dry-run: always read-only.

Apply: not applicable.

Use when: checking whether the target has the tools needed for a NM-hotspot lab.

Risk: none expected; read-only.

### plan

```sh
sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh plan
```

Prints the planned NM-hotspot commands:

- create `wifi-kit-recovery-ap`;
- configure AP mode, fixed 2.4 GHz channel, WPA2-only, and `ipv4.method shared`;
- start the recovery UI on `192.168.50.1:80`;
- scan while AP is active;
- stop/delete only the lab profile.

Dry-run: always read-only.

Apply: not applicable.

Use when: reviewing the exact sequence before any real lab action.

Risk: none expected; read-only.

### create-profile

```sh
sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh create-profile
```

Prints the commands that would create or update the lab profile
`wifi-kit-recovery-ap`.

Real apply:

```sh
WIFI_KIT_NM_AP_LAB_APPLY=1 sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh create-profile
```

Use when: preparing the NM-only hotspot profile before starting it.

Risk: writes a NetworkManager connection profile named `wifi-kit-recovery-ap`.
It must not touch user profiles.

### start-hotspot

```sh
sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh start-hotspot
```

Prints the command that would bring up the NM hotspot. It also prints the
follow-up `start-ui` command.

Real apply:

```sh
WIFI_KIT_NM_AP_LAB_APPLY=1 sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh start-hotspot
```

In apply mode, `start-hotspot` also starts the recovery UI with:

```sh
WIFI_KIT_RECOVERY_BACKEND=nm-hotspot
WIFI_KIT_NM_AP_LAB=1
WIFI_KIT_RUNTIME_CONFIG=<runtime.conf>
```

Use when: starting a complete NM-hotspot recovery lab session.

Risk: changes `wlan0` into AP mode and may disconnect the current SSH path.

### start-ui

```sh
sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh start-ui
```

Prints the command that would start the recovery UI on `192.168.50.1:80`.

Real apply:

```sh
WIFI_KIT_NM_AP_LAB_APPLY=1 sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh start-ui
```

The UI runs in the background with:

- pidfile: `/tmp/wifi-kit-nm-ap-lab-ui.pid`;
- log: `/tmp/wifi-kit-nm-ap-lab-ui.log`.

Use when: the NM hotspot is already active but the recovery UI is missing.

Risk: binds port `80`; fails if another recovery UI already owns that port.

### status

```sh
sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh status
```

Shows:

- whether `wifi-kit-recovery-ap` is active;
- whether the recovery UI pidfile points to a live process;
- whether port `80` is listening;
- the recovery UI URL;
- the UI log path;
- configured and resolved `last_good_*`;
- configured and resolved `return_*` / primary target.

Dry-run: always read-only.

Apply: not applicable.

Use when: diagnosing "AP visible but UI missing", or choosing between
`return-last-good` and `return-primary`.

Risk: none expected; read-only.

### stop-ui

```sh
sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh stop-ui
```

Prints the pidfile-based UI stop action.

Real apply:

```sh
WIFI_KIT_NM_AP_LAB_APPLY=1 sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh stop-ui
```

Use when: stopping only the lab recovery UI while leaving the hotspot state to
be handled separately.

Risk: stops the process referenced by `/tmp/wifi-kit-nm-ap-lab-ui.pid`.

### rollback

```sh
sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh rollback
```

Prints cleanup only:

- stop UI;
- `nmcli connection down wifi-kit-recovery-ap`;
- `nmcli connection delete wifi-kit-recovery-ap`.

It does not reconnect Flint or any other Wi-Fi.

Real apply:

```sh
WIFI_KIT_NM_AP_LAB_APPLY=1 sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh rollback
```

Use when: cleaning the lab hotspot without choosing a Wi-Fi target.

Risk: after cleanup, the node may have no Wi-Fi unless NetworkManager chooses
one by policy. Prefer `return-last-good` or `return-primary` when you want a
specific return target.

### return-last-good

```sh
sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh return-last-good
```

Prints cleanup plus an explicit return to the last validated Wi-Fi profile.

Real apply:

```sh
WIFI_KIT_NM_AP_LAB_APPLY=1 sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh return-last-good
```

Use when: leaving AP recovery and trying the most recently validated Wi-Fi.

Risk: if the last-good AP is unavailable, SSH/UI can drop. The command refuses
if no matching NetworkManager profile can be resolved.

### return-primary

```sh
sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh return-primary
```

Prints cleanup plus an explicit return to the configured primary Wi-Fi
(`return_connection` / `return_ssid`), currently Flint on the validated node.

Real apply:

```sh
WIFI_KIT_NM_AP_LAB_APPLY=1 sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh return-primary
```

Use when: intentionally returning to the primary / boot fallback Wi-Fi.

Risk: this is an explicit user action, not automatic runtime fallback. It may
move the node away from the current test network.

### stop-hotspot

```sh
sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh stop-hotspot
```

Prints the commands that would stop and delete the NM lab hotspot profile.

Real apply:

```sh
WIFI_KIT_NM_AP_LAB_APPLY=1 sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh stop-hotspot
```

Use when: stopping only the hotspot profile. In most operator flows, prefer
`rollback`, `return-last-good`, or `return-primary`.

Risk: stops/deletes `wifi-kit-recovery-ap`; it does not stop UI unless called
through `rollback` or a return command.

## Captive Portal Lab

The recovery UI already handles common captive probe paths when clients reach
`192.168.50.1:80`:

- Android: `/generate_204`, `/gen_204`;
- iOS: `/hotspot-detect.html`, `/library/test/success.html`;
- Windows: `/connecttest.txt`, `/ncsi.txt`.

The current NM-hotspot lab does not yet install captive DNS interception.
Windows may request:

- `www.msftconnecttest.com/connecttest.txt`;
- `www.msftncsi.com/ncsi.txt`.

If those hostnames do not resolve to `192.168.50.1`, the HTTP endpoints are
never reached and Windows may not open the captive portal automatically.

Read-only audit:

```sh
sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh captive-audit
```

Plan the candidate DNS mapping:

```sh
sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh captive-plan
```

Print the candidate config without writing it:

```sh
sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh captive-enable-dry-run
```

The first captive lab lot is intentionally dry-run only. It proposes a
NetworkManager shared-mode dnsmasq snippet under:

```sh
/etc/NetworkManager/dnsmasq-shared.d/wifi-kit-nm-hotspot-captive.conf
```

with explicit mappings for:

- `www.msftconnecttest.com`;
- `www.msftncsi.com`;
- `captive.apple.com`;
- `connectivitycheck.gstatic.com`;
- `clients3.google.com`.

Do not enable the DNS snippet automatically with `start-hotspot` yet. A future
controlled lab should write the file, reconnect the NM hotspot if required, and
validate Windows/iOS/Android captive behavior before making it part of the
normal NM-hotspot flow.

## NetworkManager Diagnostic Commands

Read-only diagnostics:

```sh
nmcli device wifi list
nmcli connection show
nmcli connection show --active
nmcli device status
nmcli device show wlan0
ip addr show wlan0
ss -lntp | grep ':80'
```

Useful logs:

```sh
cat /tmp/wifi-kit-nm-ap-lab-ui.log
journalctl -u wifi-kit-ui.service -n 80 --no-pager
```

Avoid `systemctl restart NetworkManager` during NM-hotspot tests unless that is
an explicit recovery decision.

## Recovery UI Actions

Available or planned from the recovery UI:

- view recovery status;
- scan Wi-Fi networks;
- select or change Wi-Fi;
- return to the last known Wi-Fi;
- return to the primary Wi-Fi;
- keep or restore AP recovery when a test fails.

Current limitation: `/wifi/connect` for NM-hotspot recovery is still being
stabilized. A wrong password or driver limitation may still degrade UX. Treat
connect tests as lab actions.

## Operator Scenarios

### Start complete NM-hotspot recovery

Dry-run first:

```sh
sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh create-profile
sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh start-hotspot
```

Real lab:

```sh
WIFI_KIT_NM_AP_LAB_APPLY=1 sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh create-profile
WIFI_KIT_NM_AP_LAB_APPLY=1 sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh start-hotspot
```

Then open:

```sh
http://192.168.50.1:80
```

### Verify the recovery UI

```sh
sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh status
ss -lntp | grep ':80'
cat /tmp/wifi-kit-nm-ap-lab-ui.log
```

### Return to last-good Wi-Fi

Dry-run:

```sh
sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh return-last-good
```

Real lab:

```sh
WIFI_KIT_NM_AP_LAB_APPLY=1 sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh return-last-good
```

### Return to primary / Flint

Dry-run:

```sh
sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh return-primary
```

Real lab:

```sh
WIFI_KIT_NM_AP_LAB_APPLY=1 sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh return-primary
```

### Cleanup without reconnecting

Dry-run:

```sh
sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh rollback
```

Real lab:

```sh
WIFI_KIT_NM_AP_LAB_APPLY=1 sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh rollback
```

### Diagnose missing UI on port 80

```sh
sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh status
ss -lntp | grep ':80'
cat /tmp/wifi-kit-nm-ap-lab-ui.log
```

If the hotspot is active but the UI is missing:

```sh
sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh start-ui
```

Real lab:

```sh
WIFI_KIT_NM_AP_LAB_APPLY=1 sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh start-ui
```

### Manual return to Flint if needed

Prefer the helper:

```sh
sh modules/wifi-kit/prototype/wifi-kit-nm-ap-lab.sh return-primary
```

If manual NetworkManager recovery is explicitly chosen:

```sh
nmcli connection up netplan-wlan0-GL-MT6000-d53 ifname wlan0
```

Only run the manual command when you intentionally want Flint.

## SAFE Reminders

- No reboot is required for the lab flow.
- Do not restart NetworkManager unless explicitly deciding to recover that way.
- Do not re-enable the runtime watchdog while debugging NM-hotspot behavior.
- Keep the historical hostapd/dnsmasq flow intact as fallback.
- Never store or log client Wi-Fi passwords.
- Use dry-run first; set `WIFI_KIT_NM_AP_LAB_APPLY=1` only for an intentional
  real lab action.
