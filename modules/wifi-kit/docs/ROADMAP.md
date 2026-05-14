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

`scan-real --json` prepare le futur backend read-only du portail avec un format stable: backend, interface, timestamp, SSID, SSID cache, signal, frequence, canal et securite estimee. Cette sortie reste sans connexion, sans ecriture et sans secret.

Le helper local `prototype/helpers.sh` garde la detection des outils reseau dans `wifi-kit` sans ajouter de couche globale au core Seed-Kit.

## Prochaine etape

- Valider le prototype read-only reel sur Raspberry Pi avec `docs/REAL-READONLY-TEST.md`.
- Collecter les resultats terrain: OS, outils, interfaces, IP, route par defaut, scan SSID ou erreur propre.
- Valider la stabilite Wi-Fi current-boot avec `docs/WIFI-STABILITY.md`.
- Formaliser `connect-safe` avec `docs/CONNECT-SAFE.md`.
- Finaliser le rollback avec `docs/ROLLBACK-DESIGN.md`.
- Finaliser le design SSH safety avec `docs/SSH-SAFETY.md`.
- Garder le `connect-safe` reel interdit tant que l'architecture, le rollback, les timeouts et le chemin recovery ne sont pas valides.

## Prototypes suivants autorises

- Prototype `transaction-state`: premiere version disponible via `connect-safe-simulate`.
- Prototype `snapshot`: premiere version disponible via `snapshot-simulate`.
- Prototype `runtime-state show`: snapshot read-only du runtime, sans secret et sans ecriture reseau.
- Prototype `state-snapshot --simulate`: apercu read-only du futur snapshot rollback, en texte ou JSON stable, sans secret et sans persistance complexe.
- Prototype `restore`: premiere version disponible via `restore-simulate`.
- Prototype `timeout`: premiere version disponible via `connect-safe-timeout-simulate`.
- Prototype `ssh-awareness`: premiere version disponible via `ssh-safety-simulate`.
- Prototype `connect-safe --simulate`: flow transactionnel lisible, sans secret et sans apply reel.
- Prototype `safe-diagnose`: preflight unique combinant runtime-state, snapshot preview, scan read-only et simulation connect-safe.
- Prototype UI read-only: premiere page statique disponible via `prototype/ui/render-readonly-ui.sh`.
- Prototype HTTP read-only: endpoints `GET` JSON locaux via `prototype/ui/serve-readonly.py`.
- Prototype `rollback-plan`.
- Toujours sans apply reseau reel.

## Backend read-only du futur portail

- Utiliser `scan-real` comme base terminal.
- Utiliser `scan-real --json` comme base API/UI locale.
- Utiliser `state-snapshot --simulate --json` comme base runtime-state/rollback preview.
- Utiliser `safe-diagnose --json` comme resume stable pour une future API/UI locale.
- Garder `prototype/ui/` statique et read-only tant que rollback/recovery ne sont pas valides.
- Garder le serveur HTTP manuel, local par defaut, GET-only et sans endpoint d'action.
- Garder le backend testable seul en SSH.
- Ne pas ajouter de connexion, sauvegarde, cache persistant, AP mode ou ecriture `wpa_supplicant`.
- Garder le futur portal-ui derriere `connect-safe`, rollback, recovery et SSH safety.

## V2 - mode reel controle

- Ecriture controlee via `wpa_supplicant` quand les garde-fous seront documentes.
- Gestion des priorites et resultats de reconnexion.
- Page de connexion telephone en CGI shell minimal.
- Sauvegarde des metadonnees de reseaux connus sans mot de passe.

## V3 - rescue hotspot et OpenWRT

- Hotspot rescue reel via `hostapd` + `dnsmasq`.
- Backend OpenWRT via `uci` / `wifi`.
- Tests manuels de bout en bout sur Raspberry Pi OS Lite et OpenWRT.
