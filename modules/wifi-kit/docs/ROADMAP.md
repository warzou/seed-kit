# Roadmap wifi-kit

## V0 - SAFE + simulation (ce flux)

- docs completes (`ARCHITECTURE`, `RECOVERY`, `SECURITY`, `ROADMAP`),
- prototype shell `prototype/wifi-kit.sh` sans action reseau reelle,
- gestion d'etat minimale:
  - mode (`ap/client/recovery`),
  - last successful SSID,
  - known networks,
  - last error,
  - retry count.
- integration core plan-only (`module_wifi_kit_plan`) + `--apply --modules=wifi-kit` en SAFE simulation:
  - check docs,
  - check prototype,
  - `status`, `scan`, `reconnect-plan`, `recovery-plan` (dry-run uniquement).

Objectif: rendre le flux de travail clair et testable sans casser le core.

## V1 - integration core + apply garde

- module appliquable en simulation uniquement via `module_wifi_kit_apply`,
- hook `--modules=wifi-kit` dans le core utilise en mode no-op safe,
- `plan` oriente actions reelles documentees,
- prototype `apply` en mode dry-run.

### Arbitrages reseau a decider

- choisir l'implementation de base Wi-Fi:
  - NetworkManager uniquement ou support Wi-Fi supplicant natif en fallback,
  - hostapd + dnsmasq direct ou approche plus simple selon l'OS.
- definir un point de verite pour les profils connus (`wpa_supplicant` vs autre).

## V2 - mode reel controle

- service minimal HTTP BusyBox/httpd + templates local,
- page de connexion telephone (SSR minimale),
- sauvegarde reelle des SSID connus (sans mot de passe en texte),
- reconnection automatisee avec backoff et seuils,
- bascule AP/client recovery operationnelle.

## V3 - hardening operationnel

- persistance chiffree des credentials la ou possible,
- observabilite legere,
- tests manuels de bout en bout sur Debian/RPi/OpenWRT.
