# Plan de recovery (V0 SAFE + simulation)

## Objectif

Assurer qu’un nœud retrouve automatiquement un état utilisable sans intervention manuelle
si la connexion réseau client échoue trop souvent.

## États et transitions

### 1) AP/bootstrap

- État initial.
- Porte d’entrée pour l’utilisateur (téléphone).
- En V0, la commande `status` et `scan` sont simulées.
- Sortie de cet état quand une tentative `connect` est faite.

### 2) Client

- État cible après connexion réussie.
- On conserve:
  - `last_successful_ssid`,
  - `retry_count`,
  - `last_error`.
- Si une connexion échoue, on augmente `retry_count`.

### 3) Recovery

- État de retour de secours quand les tentatives de reconnexion échouent.
- Utilise `recovery-plan` pour décrire une stratégie de secours.
- Objectif: limiter la casse, garder la fenêtre de configuration ouverte, éviter la boucle.

## Plan de récupération (simulé)

- seuil d’alerte: `retry_count >= 3`,
- en mode `client`:
  - tenter un plan `reconnect-plan`,
  - vérifier les réseaux connus (sans secrets),
  - revenir en AP si tous les plans sont épuisés.
- en mode `recovery`:
  - garder le mode AP actif (simulé),
  - proposer une liste sans secret des réseaux connus,
  - attendre un déclenchement utilisateur.

## Sécurité recovery

- aucune opération de reset root de service réseau réel en V0,
- aucune suppression/écrasement automatique de configuration non simulée,
- aucune écriture de secret.

## Points d’arbitrage réseau (V1+)

- Quand basculer automatiquement vers AP depuis `recovery` (immédiat vs délai),
- durée des essais de reconnexion simulés (court/long),
- fréquence maximum de bascule pour éviter le thrashing.
