# Wi-Fi Kit (SAFE / simulation)

`wifi-kit` est un module Seed-Kit pour preparer un flux Wi-Fi minimal, resilient et utilisable sur petit noeud nomade.

Le coeur de `wifi-kit` n'est pas le portail web. Le portail sera seulement une interface possible plus tard. Le coeur est:

- known networks,
- `reconnect-plan`,
- recovery,
- fallback AP plus tard.

Le hotspot est un mode de secours, pas le moteur principal.

## Etat actuel

Cette passe reste SAFE / simulation:

- aucune modification reseau reelle,
- aucun `hostapd`,
- aucun `dnsmasq`,
- aucun NetworkManager,
- aucun secret Wi-Fi manipule.

## Choix V1

V1 privilegie:

- Raspberry Pi OS Lite,
- `wpa_supplicant` direct,
- DHCP existant via `dhcpcd`, `dhclient`, ou default systeme,
- BusyBox `httpd` + CGI shell plus tard pour l'UI,
- `hostapd` + `dnsmasq` seulement plus tard pour le vrai hotspot rescue,
- OpenWRT via `uci` / `wifi` plus tard.

NetworkManager n'est pas retenu en V1 car il est plus lourd, moins adapte aux RPi Zero / faible RAM, et moins proche d'OpenWRT.

## Structure

- `docs/ARCHITECTURE.md`: architecture cible et choix V1.
- `docs/RECOVERY.md`: strategie de bascule AP / client / recovery.
- `docs/SECURITY.md`: stockage des secrets, metadonnees et permissions.
- `docs/ROADMAP.md`: suite technique.
- `docs/PHONE-UI-READONLY.md`: premiere architecture UI telephone read-only.
- `prototype/wifi-kit.sh`: script shell V0 simule.
- `prototype/ui/`: prototype HTML local read-only.

## Utilisation (simulation)

```sh
sh modules/wifi-kit/prototype/wifi-kit.sh status
sh modules/wifi-kit/prototype/wifi-kit.sh scan
sh modules/wifi-kit/prototype/wifi-kit.sh connect "MaWiFi"
sh modules/wifi-kit/prototype/wifi-kit.sh save-known-network "MaWiFi"
sh modules/wifi-kit/prototype/wifi-kit.sh reconnect-plan
sh modules/wifi-kit/prototype/wifi-kit.sh recovery-plan
```

## Simulation connect-safe

`connect-safe-simulate` affiche uniquement les etats transactionnels prevus pour un futur connect-safe. Il ne cree aucun fichier d'etat persistant et ne touche pas au reseau.

```sh
sh modules/wifi-kit/prototype/wifi-kit.sh connect-safe-simulate
sh modules/wifi-kit/prototype/wifi-kit.sh connect-safe-simulate --fail-ip
sh modules/wifi-kit/prototype/wifi-kit.sh connect-safe-simulate --fail-validation
```

Snapshot / restore simules, sans fichier persistant et sans lecture reseau obligatoire:

```sh
sh modules/wifi-kit/prototype/wifi-kit.sh snapshot-simulate
sh modules/wifi-kit/prototype/wifi-kit.sh restore-simulate
sh modules/wifi-kit/prototype/wifi-kit.sh restore-simulate --fail
```

SSH safety simulee, sans inspection de session SSH reelle et sans analyse reseau:

```sh
sh modules/wifi-kit/prototype/wifi-kit.sh ssh-safety-simulate
sh modules/wifi-kit/prototype/wifi-kit.sh ssh-safety-simulate --safe
sh modules/wifi-kit/prototype/wifi-kit.sh ssh-safety-simulate --danger
```

Timeouts connect-safe simules:

```sh
sh modules/wifi-kit/prototype/wifi-kit.sh connect-safe-timeout-simulate
sh modules/wifi-kit/prototype/wifi-kit.sh connect-safe-timeout-simulate --validation-timeout
sh modules/wifi-kit/prototype/wifi-kit.sh connect-safe-timeout-simulate --rollback-timeout
```

## Utilisation read-only reelle

Ces commandes observent l'hote local sans modifier le reseau:

```sh
sh modules/wifi-kit/prototype/wifi-kit.sh backend-detect
sh modules/wifi-kit/prototype/wifi-kit.sh status-real
sh modules/wifi-kit/prototype/wifi-kit.sh scan-real
sh modules/wifi-kit/prototype/wifi-kit.sh scan-real --json
```

Elles ne lancent aucune connexion Wi-Fi, n'ecrivent pas dans `wpa_supplicant`, ne lisent pas de secret, et ne demarrent aucun service.

Le prototype utilise un helper local (`prototype/helpers.sh`) pour retrouver les outils reseau dans `PATH`, puis dans `/usr/sbin`, `/sbin`, `/usr/bin` et `/bin`. Ce helper reste strictement local a `wifi-kit`.

`scan-real` est la base du futur backend read-only du portail. Le mode texte affiche `ssid`, `signal`, `channel` et `security`. Le mode `--json` expose un format stable pour une future UI locale, y compris quand `iw` manque ou que le scan est indisponible, sans connexion, sans cache persistant et sans mutation reseau.

Diagnostic SAFE unique:

```sh
sh modules/wifi-kit/prototype/wifi-kit.sh safe-diagnose
sh modules/wifi-kit/prototype/wifi-kit.sh safe-diagnose --json
```

`safe-diagnose` regroupe uniquement des lectures et simulations: backend, runtime-state, snapshot preview, scan read-only et simulation `connect-safe`. Il sert de preflight avant tout futur `connect-safe` reel et ne modifie rien.

## Prototype UI read-only

Le prototype UI telephone reste local, statique et optionnel:

```sh
sh modules/wifi-kit/prototype/ui/render-readonly-ui.sh > /tmp/wifi-kit-ui.html
```

La page generee embarque uniquement des donnees read-only (`safe-diagnose --json`, `scan-real --json`, `state-snapshot --simulate --json`). Elle presente un parcours type setup Wi-Fi, mais les actions de connexion restent des apercus desactives. Elle ne collecte aucun secret et ne lance aucun portail captif.

Backend HTTP local read-only, manuel et optionnel:

```sh
python3 modules/wifi-kit/prototype/ui/serve-readonly.py --host 127.0.0.1 --port 8088
```

Ce serveur expose seulement des endpoints `GET` JSON et la page statique. Il ne fournit aucun endpoint d'action et ne demarre pas automatiquement.

## Stabilite Wi-Fi terrain

Sur Raspberry Pi Zero 2 W, un retour terrain a montre que `wlan0 power_save=on` peut rendre le Wi-Fi instable en idle.

Commandes SAFE:

```sh
sh modules/wifi-kit/prototype/wifi-kit.sh stability-status
sh modules/wifi-kit/prototype/wifi-kit.sh stability-plan
```

Application manuelle current-boot uniquement, a lancer seulement sur la cible RPi quand explicitement decide:

```sh
sudo sh modules/wifi-kit/prototype/wifi-kit.sh stability-apply-current-boot wlan0
```

Cette application ne persiste rien apres reboot, ne modifie pas de config, ne lance aucun service, et ne change aucun SSID/connexion.

## Integration core

`wifi-kit` est enregistre comme module plan-only (`module_wifi_kit_plan`) et expose un apply SAFE / simulation (`module_wifi_kit_apply`).

```sh
sh seed-kit.sh --apply --modules=wifi-kit
```

Cette commande affiche uniquement un plan simule: docs, prototype, status, scan, reconnect-plan et recovery-plan.
