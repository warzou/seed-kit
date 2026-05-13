# Wi-Fi Kit (SAFE / simulation)

Ce dossier contient la première passe documentaire et de simulation de `wifi-kit` pour Seed-Kit.

## Objectif de cette passe

- ne rien modifier côté réseau réel,
- ne pas démarrer hostapd / dnsmasq / NetworkManager en vrai,
- modéliser l'état et les transitions,
- documenter architecture, recovery, sécurité et feuille de route,
- fournir un prototype shell safe, portable et sans dépendance lourde.

## Structure

- `docs/ARCHITECTURE.md` : architecture cible (états, services, données de pilotage).
- `docs/RECOVERY.md` : stratégie de bascule AP <-> client <-> recovery.
- `docs/SECURITY.md` : stratégie de stockage des secrets / logs / permissions.
- `docs/ROADMAP.md` : étapes V0->V2 avec décisions réseau à arbitrer.
- `prototype/wifi-kit.sh` : script shell V0 simulé.

## Utilisation (simulation)

```sh
sh modules/wifi-kit/prototype/wifi-kit.sh status
sh modules/wifi-kit/prototype/wifi-kit.sh scan
sh modules/wifi-kit/prototype/wifi-kit.sh connect "MaWiFi"
sh modules/wifi-kit/prototype/wifi-kit.sh save-known-network "MaWiFi"
sh modules/wifi-kit/prototype/wifi-kit.sh reconnect-plan
sh modules/wifi-kit/prototype/wifi-kit.sh recovery-plan
```

## Intégration core

`wifi-kit` est enregistré en core comme module plan-only (`module_wifi_kit_plan`).
`module_wifi_kit_apply` est ajouté en V0 final pour un dry-run SAFE
sans action réseau réelle.

Le coeur actuel :
- détecte les modules via des scripts `modules/*.sh`,
- attend des fonctions `module_<nom>_plan`.

Le flux `seed-kit` supporte aujourd'hui:
- `sh seed-kit.sh --apply --modules=wifi-kit` (simulation):
  - check docs,
  - check prototype,
  - status scan reconnect-plan recovery-plan simulation,
  - pas d'action réseau réelle.

### Point de bascule prévue

- Quand le modèle de module commun sera stabilisé, on fera un durcissement de l'`apply` avec dry-run simulé puis actions réseau réelles.
