# Sécurité (V0 simulation)

## Règles fortes

- Aucune vraie commande hostapd/dnsmasq/NetworkManager.
- Aucune gestion réelle de mot de passe dans cette passe.
- Les mots de passe, si transmis pour simulation, ne sont jamais loggés.
- `psk` est toujours redressé en `[REDACTED]` dans les sorties.

## Stockage local recommandé (future version réelle)

Pour la suite, stocker l’état sur le nœud avec un chemin contrôlé, par exemple:

- `/var/lib/wifi-kit/` (ou équivalent),
- répertoires en `0700`,
- fichiers d’état en `0600`,
- propriétaire root (ou utilisateur d’administration dédié),
- ACL/groupes minimaux.

Le prototype V0 simule cet emplacement pour rester non-invasif.

## Politique secrets

- Les SSID sont des identifiants non secrets et peuvent être en clair.
- Les PSK ne doivent jamais être écrits en clair dans un fichier.
- Les logs doivent rester lisibles sans secret.
- Toute future persistance de credentials doit utiliser un coffre local adapté au système cible
  (ou chiffrement applicatif).

## Surfaces à éviter V0

- Pas d’export de dump d’état sensible,
- pas de token dans les messages.

## Contrôles de revue recommandés

- vérifier qu’aucune commande ne fait d’IO réseau réelle,
- vérifier qu’aucun `echo` ne montre des secrets,
- vérifier permissions sur répertoire/fichiers d’état,
- vérifier mode de secours cohérent en cas d’échec répété.
