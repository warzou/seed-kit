# Architecture wifi-kit

## Principe

`wifi-kit` doit fournir un flux Wi-Fi minimal et robuste pour des noeuds nomades ou resilients.

Le coeur de `wifi-kit` n'est pas le portail web. Le portail est une interface possible, utile plus tard pour un telephone, mais le moteur principal reste:

- les reseaux connus,
- le `reconnect-plan`,
- la recovery,
- le fallback AP plus tard.

Le hotspot est un mode de secours. Il ne doit pas devenir le moteur principal du module.

## Choix techniques V1

Pour V1, la cible officielle est:

- Raspberry Pi OS Lite,
- `wpa_supplicant` direct,
- DHCP existant via `dhcpcd`, `dhclient`, ou le default systeme,
- BusyBox `httpd` + CGI shell plus tard pour l'UI,
- `hostapd` + `dnsmasq` seulement plus tard pour le vrai hotspot rescue,
- OpenWRT via `uci` / `wifi` plus tard.

NetworkManager n'est pas retenu en V1:

- plus confortable, mais plus lourd,
- moins adapte aux RPi Zero / faible RAM,
- moins proche d'OpenWRT,
- moins aligné avec l'objectif "minimal resilient node".

## Structure de module

```text
modules/wifi-kit/
  README.md
  docs/
    ARCHITECTURE.md
    RECOVERY.md
    SECURITY.md
    ROADMAP.md
  prototype/
    wifi-kit.sh
```

## Etats modelises

Etat minimal:

- `mode`: `ap`, `client`, `recovery`,
- `last_successful_ssid`,
- `known_networks`,
- `last_error`,
- `retry_count`.

Metadonnees futures par reseau connu:

- `ssid`,
- `priority`,
- `last_success`,
- `last_failure`,
- `retry_count`.

`wifi-kit` ne stocke pas les mots de passe Wi-Fi dans ses propres fichiers metier. `wpa_supplicant` reste la source de verite des secrets Wi-Fi.

## Flux cible

- Au boot, lire l'etat local et les metadonnees connues.
- Construire un `reconnect-plan` sans secret.
- Tenter plus tard une reconnexion controlee via le backend choisi.
- Passer en `recovery` si les echecs depassent un seuil.
- Activer un fallback AP plus tard seulement pour garder une porte de secours.

## Prototype V0

Le prototype actuel reste 100% SAFE / simulation:

- `status`,
- `scan`,
- `connect <SSID>`,
- `save-known-network <SSID>`,
- `reconnect-plan`,
- `recovery-plan`.

Il ne lance pas `hostapd`, `dnsmasq`, NetworkManager, ni aucune modification reseau reelle.

## Prochaine etape technique

Apres cette documentation, la prochaine etape est un prototype read-only reel:

- `backend-detect`,
- `scan-real`,
- `status-real`.

Cette etape read-only ne doit faire aucune connexion, aucune ecriture reseau, aucun `hostapd` / `dnsmasq` reel.
