# Wifi-Kit READY FOR FRESH INSTALL

Status: ready for a controlled fresh-install validation on a blank Raspberry Pi
Zero 2 W.

This document captures the current validated Wifi-Kit state before testing a
new node from scratch. It is an operator checklist, not an install log.

## Validated State

The following behavior has been validated on the current pocket-node:

- Normal Wifi-Kit UI runs from the installed runtime under `/opt` and is
  reachable on port `54321`.
- NetworkManager hotspot recovery starts and serves the recovery UI at
  `http://192.168.50.1:80`.
- Captive probes can be routed through `/portal`, with the full recovery UI
  still available at `/recovery`, but Windows captive auto-open is not a
  guaranteed recovery path.
- Recovery UI can return the node to the Flint network.
- Update check is read-only and reports branch, remote, local commit, and
  update status.
- Update install uses a SAFE flow: clean repo check, fast-forward-only update,
  then runtime reinstall. Runtime reinstall is also available when Git is
  already current.
- SAFE reboot is enabled and validated.
- SAFE shutdown is enabled and validated.
- Installed runtime paths under `/opt/seed-kit/wifi-kit` are coherent with the
  repository runtime.
- Implicit hostapd AP fallback paths have been removed from the main runtime
  flow.
- The UI distinguishes normal UI access count from AP client count.

## Current Architecture

- Normal UI:
  - Service-backed UI on port `54321`.
  - Intended for normal LAN access after the node has joined Wi-Fi.
- Recovery AP:
  - NetworkManager hotspot backend.
  - Recovery address: `192.168.50.1`.
  - Recovery UI port: `80`.
- Captive portal:
  - Known captive endpoints redirect to `/portal`.
  - `/portal` is a minimal landing page.
  - The full Wi-Fi recovery UI remains at `/recovery`.
  - Reliable manual access remains `http://192.168.50.1`.
- Update/reinstall flow:
  - `/updates/check` is read-only.
  - `/updates/install` requires confirmation and refuses dirty repositories.
  - Updates use `git pull --ff-only`.
  - Runtime reinstall is run through the SAFE action path after update, or when
    the repo is already current.
- SAFE wrappers:
  - Privileged actions go through `wifi-kit-action-wrapper.sh`.
  - Actions are explicit and whitelisted.
  - System power actions are gated and logged.
- Sudoers:
  - Whitelists only the expected Wifi-Kit wrapper/action paths.
  - No arbitrary shell or user-controlled command execution is allowed.
- Logs:
  - Runtime actions write under `/tmp/wifi-kit-actions/`.
  - NM hotspot lab UI logs use `/tmp/wifi-kit-nm-ap-lab-ui.log`.

## Expected User Flow

1. The node boots normally and tries to reach the configured Wi-Fi.
2. Normal operation exposes the UI on port `54321`.
3. If recovery is needed, the node starts the NetworkManager hotspot.
4. A Windows, iPhone, or Android client joins the recovery AP.
5. If captive auto-open appears, it opens `/portal`.
6. If captive auto-open does not appear, the operator opens
   `http://192.168.50.1` manually.
7. The operator opens the full recovery UI at `http://192.168.50.1/recovery`.
8. The operator selects a Wi-Fi network and starts connection from the UI.
9. If the node joins Wi-Fi successfully, the AP disappears and the normal UI
   returns on the LAN.
10. Operators can then use update check, update install/reinstall, reboot, and
   shutdown through SAFE UI actions.

## Experimental Or Known Limits

- iPhone captive portal is still a constrained webview. The full recovery UI is
  available, but long-running transitions should use persistent inline status
  messages rather than popups.
- Wi-Fi connect popups were intentionally removed for captive compatibility.
- hostapd remains in the tree only as an explicit legacy fallback or diagnostic
  path. It is not the default AP backend for the main runtime flow.
- Raspberry Pi Zero 2 W Wi-Fi behavior can vary with firmware, regulatory
  domain, channel, AP/client transitions, and local RF conditions.
- NM-hotspot scan/connect behavior is the preferred path, but fresh hardware
  validation must still confirm captive portal and Wi-Fi transition stability.
- Windows captive auto-open may fail or be delayed. The supported fallback is:
  join `Wifi-Kit-<hostname>`, then open `http://192.168.50.1` manually.
- Wifi-Kit maps common Windows captive DNS probe hostnames to `192.168.50.1`
  when the NM recovery hotspot starts, but Windows captive UI remains
  best-effort rather than guaranteed.
- SSH in AP recovery uses the node user account, for example
  `ssh warzy@192.168.50.1`. The AP password is only the Wi-Fi WPA passphrase;
  it is not the SSH password.
- Boot guard and runtime recovery must remain distinct:
  - boot can use last-good, then primary/return Wi-Fi, then AP recovery.
  - runtime recovery must not fall back automatically to the primary/return
    Wi-Fi unless explicitly requested by the user or boot guard.

## Fresh Install Procedure Planned

Use this as the planned operator flow for the blank Pi Zero 2 W test:

1. Prepare the Pi OS image and ensure SSH/local console access.
2. Clone the repository on the node.
3. Check out branch `wifi-kit-work`.
4. Run the Wifi-Kit runtime install/reinstall command from the repo.
5. Verify installed files under `/opt/seed-kit/wifi-kit`.
6. Verify expected services:
   - normal UI service for port `54321`;
   - boot guard service, normally oneshot/inactive after a completed run;
   - runtime watchdog service only as configured for the test phase.
7. Confirm sudoers contains only the Wifi-Kit SAFE wrapper entries.
8. Open the normal UI on port `54321`.
9. Trigger controlled AP recovery.
10. Validate NM hotspot, captive portal, recovery UI, Wi-Fi return, update,
    reboot, shutdown, and logs.

## Fresh Install Validation Checklist

- Normal UI:
  - port `54321` reachable;
  - `/api/backend-status` returns OK;
  - `/api/ui-data` returns coherent mode/status.
- Runtime install:
  - `/opt/seed-kit/wifi-kit` contains current scripts and UI files;
  - service unit paths point to `/opt`, not a preview checkout.
- AP recovery:
  - NM hotspot starts;
  - recovery AP is visible from Windows and iPhone;
  - node answers on `192.168.50.1`;
  - recovery UI is reachable on port `80`.
- Captive portal:
  - Windows captive flow reaches the portal when captive DNS/browser behavior
    cooperates;
  - iPhone captive flow reaches the portal when captive DNS/browser behavior
    cooperates;
  - `/portal` opens;
  - `/recovery` opens from the portal.
- Manual recovery access:
  - `http://192.168.50.1` opens after joining `Wifi-Kit-<hostname>`;
  - `ssh warzy@192.168.50.1` is available when SSH is enabled and credentials
    are known;
  - the AP password is not reused as the SSH password.
- Wi-Fi return:
  - recovery UI can return to the selected Wi-Fi;
  - return to Flint remains available when explicitly selected;
  - no automatic runtime fallback to Flint occurs when last-good differs.
- Update:
  - update check reports branch, remote, local commit, and status;
  - update install refuses dirty repos;
  - update install can reinstall runtime even when Git is already current.
- Power actions:
  - reboot requires checkbox confirmation and uses the SAFE wrapper;
  - shutdown requires checkbox confirmation and uses the SAFE wrapper;
  - no power action is available through GET.
- Logs:
  - action logs are written under `/tmp/wifi-kit-actions/`;
  - update logs include before/after commit and reinstall status;
  - system power logs record requested action and gate status.

## SAFE Notes

- No implicit reboot.
- No implicit shutdown.
- No arbitrary NetworkManager restart.
- No arbitrary shell execution.
- No user-controlled command construction for privileged actions.
- POST-only for mutating actions.
- Checkbox confirmation is required for update install/reinstall and system
  power actions.
- Privileged actions must pass through strict Wifi-Kit wrappers.
- Sudoers entries must remain narrow and action-specific.
- Recovery AP changes must not delete user NetworkManager profiles.
- Secrets must not be logged, exposed through JSON, or written to docs.

## Suggested Fresh Install Result

The fresh Pi Zero 2 W test should end with:

- normal UI reachable after joining Wi-Fi;
- recovery AP available when requested;
- captive portal usable on Windows and iPhone;
- Wi-Fi return working from recovery UI;
- update check/install/reinstall working through the SAFE path;
- reboot and shutdown available only through confirmed SAFE actions;
- logs sufficient to diagnose every transition.
