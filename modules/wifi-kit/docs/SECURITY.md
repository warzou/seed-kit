# Securite wifi-kit

## Regles fortes

- Aucune vraie commande `hostapd`, `dnsmasq` ou NetworkManager en V0/V1 docs.
- Aucun mot de passe Wi-Fi stocke dans les fichiers metier de `wifi-kit`.
- Aucun mot de passe Wi-Fi affiche dans les logs.
- Les sorties doivent rester lisibles sans secret.

## Source de verite des secrets

Pour V1, `wpa_supplicant` reste la source de verite des secrets Wi-Fi.

`wifi-kit` ne doit pas recopier les PSK dans ses propres fichiers. Son role est de piloter et documenter le flux resilient autour des reseaux connus, pas de devenir un coffre de secrets.

## Metadonnees autorisees

`wifi-kit` peut garder uniquement des metadonnees non secretes:

- `ssid`,
- `priority`,
- `last_success`,
- `last_failure`,
- `retry_count`.

Ces metadonnees servent au `reconnect-plan`, a la recovery et au futur fallback AP.

## Permissions futures

Emplacement cible pour la configuration locale:

- `/etc/seed-kit/wifi-kit/`
- proprietaire: `root:root`
- repertoire: `0700`
- fichiers sensibles eventuels: `0600`

Si un fichier runtime separe est necessaire plus tard, il devra garder le meme principe de moindre exposition.

## Surfaces a eviter

- Pas d'export de dump d'etat contenant des secrets.
- Pas de token dans les messages.
- Pas de PSK dans les traces de shell.
- Pas d'ecriture automatique dans `wpa_supplicant` avant une etape explicitement dediee.

## Controles de revue recommandes

- verifier qu'aucune commande ne fait d'I/O reseau reelle quand le mode annonce est SAFE,
- verifier qu'aucun `echo` ne montre des secrets,
- verifier les permissions sur repertoires et fichiers,
- verifier que la recovery reste non destructive.
