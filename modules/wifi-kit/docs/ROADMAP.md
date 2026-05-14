# Roadmap wifi-kit

## V0 - SAFE + simulation

- Docs de base (`ARCHITECTURE`, `RECOVERY`, `SECURITY`, `ROADMAP`).
- Prototype shell `prototype/wifi-kit.sh` sans action reseau reelle.
- Integration module plan-only via `module_wifi_kit_plan`.
- Apply SAFE / simulation via `module_wifi_kit_apply`.

## V1 - choix techniques documentes

Choix officiel V1:

- Raspberry Pi OS Lite,
- `wpa_supplicant` direct,
- DHCP existant via `dhcpcd`, `dhclient`, ou default systeme,
- BusyBox `httpd` + CGI shell plus tard pour l'UI,
- `hostapd` + `dnsmasq` seulement plus tard pour le vrai hotspot rescue,
- OpenWRT via `uci` / `wifi` plus tard.

NetworkManager n'est pas retenu en V1:

- plus confortable, mais plus lourd,
- moins adapte aux RPi Zero / faible RAM,
- moins proche d'OpenWRT,
- moins "minimal resilient node".

Le coeur produit reste:

- known networks,
- `reconnect-plan`,
- recovery,
- fallback AP plus tard.

Le hotspot est un mode de secours, pas le moteur principal.

## Prototype read-only reel

Commandes ajoutees au prototype:

- `backend-detect`,
- `scan-real`,
- `status-real`.

Contraintes:

- aucune connexion,
- aucune ecriture reseau,
- aucun `hostapd` reel,
- aucun `dnsmasq` reel,
- aucune manipulation de secret Wi-Fi.

`backend-detect` detecte les outils disponibles et recommande `rpios-wpa` quand Raspberry Pi OS / Debian + `wpa_supplicant` sont pertinents.

`status-real` affiche les interfaces Wi-Fi, les adresses IP visibles et la route par defaut si disponible.

`scan-real` utilise `iw dev <iface> scan` quand possible et ne remonte que SSID + signal.

Le helper local `prototype/helpers.sh` garde la detection des outils reseau dans `wifi-kit` sans ajouter de couche globale au core Seed-Kit.

## Prochaine etape

- Valider le prototype read-only reel sur Raspberry Pi avec `docs/REAL-READONLY-TEST.md`.
- Collecter les resultats terrain: OS, outils, interfaces, IP, route par defaut, scan SSID ou erreur propre.
- Valider la stabilite Wi-Fi current-boot avec `docs/WIFI-STABILITY.md`.
- Formaliser `connect-safe` avec `docs/CONNECT-SAFE.md`.
- Finaliser le rollback avec `docs/ROLLBACK-DESIGN.md`.
- Garder le `connect-safe` reel interdit tant que l'architecture, le rollback, les timeouts et le chemin recovery ne sont pas valides.

## Prototypes suivants autorises

- Prototype `transaction-state`: premiere version disponible via `connect-safe-simulate`.
- Prototype `snapshot`: premiere version disponible via `snapshot-simulate`.
- Prototype `restore`: premiere version disponible via `restore-simulate`.
- Prototype `timeout`.
- Prototype `rollback-plan`.
- Toujours sans apply reseau reel.

## V2 - mode reel controle

- Ecriture controlee via `wpa_supplicant` quand les garde-fous seront documentes.
- Gestion des priorites et resultats de reconnexion.
- Page de connexion telephone en CGI shell minimal.
- Sauvegarde des metadonnees de reseaux connus sans mot de passe.

## V3 - rescue hotspot et OpenWRT

- Hotspot rescue reel via `hostapd` + `dnsmasq`.
- Backend OpenWRT via `uci` / `wifi`.
- Tests manuels de bout en bout sur Raspberry Pi OS Lite et OpenWRT.
