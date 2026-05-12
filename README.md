# Seed-Kit

Petit toolkit shell pour installer, deployer et reprendre simplement de petites machines :
Debian, Raspberry Pi OS, OpenWRT/Flint plus tard, mini VPS.

Objectif : une commande simple, une UI texte claire, des modules faciles a ajouter.

Le contexte et les limites du projet sont dans [CONTEXT.md](CONTEXT.md).

## Installation

```sh
sh install.sh --plan
```

## Test rapide

```sh
sh seed-kit.sh --plan
sh seed-kit.sh --detect
sh seed-kit.sh --modules
sh seed-kit.sh --apply
```

## Direction CLI (V0)

Conventions légères prévues :

- `--plan` : affichage du plan.
- `--modules` : liste des modules disponibles.
- `--apply` : mode d’application (V0: aperçu seul, pas de changements).
- `-y` : prévu pour confirmation automatique quand l’apply sera actif.

Format de progression cible (ambient) :

```text
[1/4] detect system
[2/4] prepare plan
[3/4] confirm safe steps
[4/4] apply
```
