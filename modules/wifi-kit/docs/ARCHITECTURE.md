# Architecture cible (v0 prototype)

## Principe

`wifi-kit` doit fournir un flux d’embarquement Wi-Fi minimal et robuste pour des nœuds nomades:

- mode `AP/bootstrap` pour configuration depuis téléphone,
- mode `client` pour usage normal du réseau externe,
- mode `recovery` en cas d’échec de connexion répété.

Cette passe V0 est **100% simulée** (no hostapd, no dnsmasq, no NetworkManager réel).

## Structure de module proposée

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

## Contrôles simulés

Le prototype expose des commandes SAFE:

- `status`
- `scan`
- `connect <SSID>`
- `save-known-network <SSID>`
- `reconnect-plan`
- `recovery-plan`

Toutes ces commandes :

- lisent un état local simulé,
- mettent à jour un état local simulé,
- écrivent des logs non sensibles,
- ne changent rien au réseau réel.

## Modèle d’état (V0)

État minimal gardé localement:

- `mode` : `ap`, `client`, `recovery`,
- `last_successful_ssid`,
- `known_networks`,
- `last_error`,
- `retry_count`.

`known_networks` est une liste d’objets sans secret:

- `ssid`,
- `last_seen_at`,
- `added_at`,
- `last_result`.

## Chemin de pilotage (simulation)

- au boot / bootstrap: `mode=ap`,
- tentative `connect`: passe en `client` si succès, met à jour `last_successful_ssid`,
- échec de connexion: incrémente `retry_count`, renseigne `last_error`,
- dépassement de seuil: bascule logique vers `recovery`,
- `recovery` garde les nœuds de secours, puis tente une reconnection via un plan (`reconnect-plan`).

## Contraintes du design

Shell-first, pas de Docker/Caddy/CMS lourd, faible empreinte RAM, compatible BusyBox/httpd plus tard, sans dépendre d’Internet.

Le code V0 reste volontairement compact:

- scripts POSIX `/bin/sh`,
- fichiers d’état simples,
- pas de framework.

## Interfaces prévues plus tard

- UI HTTP minimale compatible BusyBox/httpd,
- JSON status API local (optionnel),
- action "plan/apply/recovery" avec garde-fous,
- persistence réelle des profils Wi-Fi autorisée par design (hors V0).
