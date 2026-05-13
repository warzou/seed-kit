# Seed-Kit

Petit toolkit shell pour installer, deployer et reprendre simplement de petites machines :
Debian, Raspberry Pi OS, OpenWRT/Flint plus tard, mini VPS.

Objectif : une commande simple, une UI texte claire, des modules faciles a ajouter.

Le contexte et les limites du projet sont dans [CONTEXT.md](CONTEXT.md).

## Installation

Target flow: copy `seed-kit.sh`, run `sh seed-kit.sh`.
Bootstrap runtime fetch is not implemented yet.

For the concrete fresh-node SSH flow (bootstrap + plan/modules/apply), see:
docs/FRESH-NODE-FLOW.md

```sh
sh seed-kit.sh
```

## Test rapide

```sh
sh seed-kit.sh --plan
sh seed-kit.sh --detect
sh seed-kit.sh --modules
sh seed-kit.sh --apply
```

## Test terrain (machine fraiche)

```sh
sh seed-kit.sh --plan
sh seed-kit.sh --modules
sh seed-kit.sh --apply
sh seed-kit.sh --apply --modules=git
sh seed-kit.sh --apply --modules=git -y
```

Attendus :

* lisibilite SSH et progression
* message explicite : no modules selected for apply: use --modules=git
* confirmation SAFE [y/N] quand applicatif
* erreurs lisibles en cas de sudo/auth/apt ([apply], [git])
* Git deja installe : [git] already installed
* Git absent : etapes de verification/install affichees

## Direction CLI (V0)

Conventions légères prévues :

- `--plan` : affichage du plan.
- `--modules` : liste des modules disponibles.
- `--apply [--modules=git,docker] [--yes|-y]` : affiche le preview puis applique les modules demandés.
- Sans `--modules`, `--apply` reste en preview-only (aucune action réelle).
- `-y` : passe la confirmation SAFE (`[y/N]`) pour accélérer l’exécution en mode apply.

SAFE rule :

- `sh seed-kit.sh --apply` : aucune action réelle.

Format de progression cible (ambient) :

```text
[1/4] detect system
[2/4] prepare plan
[3/4] confirm safe steps
[4/4] apply
```
