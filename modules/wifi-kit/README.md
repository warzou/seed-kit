# Wi-Fi Kit

`wifi-kit` est un module Seed-Kit pour preparer un flux Wi-Fi minimal, resilient et utilisable sur petit noeud nomade.

Le coeur de `wifi-kit` n'est pas le portail web. Le portail sera seulement une interface possible plus tard. Le coeur est:

- known networks,
- `reconnect-plan`,
- recovery,
- fallback AP plus tard.

Le hotspot est un mode de secours, pas le moteur principal.

## Etat actuel

Le prototype historique `prototype/wifi-kit.sh` conserve ses commandes SAFE /
simulation et read-only.

Le runtime Wifi-Kit a aussi ete valide sur `pocket-node` avec:

- UI normale permanente sur `54321`,
- mode AP recovery explicite sur `80`,
- retour AP vers Wi-Fi principal,
- sudoers minimal,
- boot guard minimal,
- installation runtime sous `/opt/seed-kit/wifi-kit`.

Voir `docs/RUNTIME-VALIDATION.md`.

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

`scan-real` est la base du futur backend read-only du portail. Il privilegie `wpa_cli -i <iface> scan_results`, strictement lecture seule, afin de mieux fonctionner sur un Raspberry Pi deja connecte. `iw dev <iface> scan` reste un fallback read-only. Le mode texte affiche `ssid`, `signal`, `channel` et `security`. Le mode `--json` expose un format stable pour une future UI locale, y compris quand les outils manquent ou que le scan est indisponible, sans connexion, sans cache persistant et sans mutation reseau.

Refresh radio opt-in, borne par timeout et toujours sans ecriture de config:

```sh
sh modules/wifi-kit/prototype/wifi-kit.sh scan-real --refresh --json
```

Ce mode lit d'abord `scan_results`, tente seulement alors `wpa_cli scan`, relit `scan_results`, puis garde un JSON stable avec `refresh_attempted` et `refresh_status`. Il n'est pas declenche automatiquement par `safe-diagnose` ni par l'UI.

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

La page generee embarque uniquement des donnees read-only (`safe-diagnose --json`, `scan-real --json`, `state-snapshot --simulate --json`). Elle presente maintenant une experience en francais orientee "choisir un Wi-Fi": etat actuel, liste de reseaux quand disponible, bouton de connexion desactive et details techniques replies. Elle ne collecte aucun secret et ne lance aucun portail captif.

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

`wifi-kit` est enregistre comme module Seed-Kit et expose maintenant un chemin
d'installation runtime minimal.

Commande conseillee:

```sh
sh seed-kit.sh install wifi-kit
```

Commande equivalente:

```sh
sh seed-kit.sh --apply --modules=wifi-kit
```

Cette commande appelle `modules/wifi-kit/prototype/install-wifi-kit-runtime.sh`.
Avant toute installation reelle, elle affiche `audit` et `plan`, puis demande
une confirmation courte:

```text
install wifi-kit runtime? [y/N]
```

Si Wifi-Kit est deja installe, elle affiche `already installed` puis demande:

```text
reinstall? [y/N]
```

Le chemin d'installation ne doit pas lancer AP mode, ne doit pas changer de
Wi-Fi, ne doit pas supprimer de profil Wi-Fi, ne doit pas stocker de mot de
passe Wi-Fi client et ne doit pas reboot.
