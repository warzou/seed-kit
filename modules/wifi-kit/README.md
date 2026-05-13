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
- `prototype/wifi-kit.sh`: script shell V0 simule.

## Utilisation (simulation)

```sh
sh modules/wifi-kit/prototype/wifi-kit.sh status
sh modules/wifi-kit/prototype/wifi-kit.sh scan
sh modules/wifi-kit/prototype/wifi-kit.sh connect "MaWiFi"
sh modules/wifi-kit/prototype/wifi-kit.sh save-known-network "MaWiFi"
sh modules/wifi-kit/prototype/wifi-kit.sh reconnect-plan
sh modules/wifi-kit/prototype/wifi-kit.sh recovery-plan
```

## Integration core

`wifi-kit` est enregistre comme module plan-only (`module_wifi_kit_plan`) et expose un apply SAFE / simulation (`module_wifi_kit_apply`).

```sh
sh seed-kit.sh --apply --modules=wifi-kit
```

Cette commande affiche uniquement un plan simule: docs, prototype, status, scan, reconnect-plan et recovery-plan.
