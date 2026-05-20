# Seed-Kit

Petit toolkit shell pour installer, deployer et reprendre simplement de petites machines:
Debian, Raspberry Pi OS, OpenWRT/Flint plus tard, mini VPS.

Objectif : une commande simple, une UI texte claire, des packages/profils
rejouables, et des modules faciles a ajouter.

Le contexte et les limites du projet sont dans [CONTEXT.md](CONTEXT.md).
Architecture monorepo: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
Conventions modules: [docs/MODULES.md](docs/MODULES.md).
Stabilisation V1 PRA: [docs/V1-STABILIZATION.md](docs/V1-STABILIZATION.md).
Reconstruction SAFE: [docs/RECONSTRUCT-NODE-SAFE.md](docs/RECONSTRUCT-NODE-SAFE.md).
Doctrine reconstruction services: [docs/SERVICE-RECONSTRUCTION.md](docs/SERVICE-RECONSTRUCTION.md).
Reconnexion identites PRA: [docs/IDENTITY-RECONNECTION.md](docs/IDENTITY-RECONNECTION.md).
Service packages PRA: [docs/SERVICE-PACKAGES.md](docs/SERVICE-PACKAGES.md).
Format minimal service package: [docs/SERVICE-PACKAGE-FORMAT.md](docs/SERVICE-PACKAGE-FORMAT.md).
Premier service package concret: [docs/service-packages/rpi-edge-vps.md](docs/service-packages/rpi-edge-vps.md).
Premier test PRA package: [docs/pra-tests/rpi-edge-vps-on-rpi3-edge-audit.md](docs/pra-tests/rpi-edge-vps-on-rpi3-edge-audit.md).
Premier audit node-specific: [docs/nodes/rpi-edge.md](docs/nodes/rpi-edge.md).
Node remplacement PRA: [docs/nodes/rpi3-edge.md](docs/nodes/rpi3-edge.md).

## Installation

Target flow: download `install-seed-kit.sh`, inspect it, run it.

For the concrete fresh-node SSH flow (bootstrap + plan/modules/apply), see:
docs/FRESH-NODE-FLOW.md

```sh
wget https://raw.githubusercontent.com/warzou/seed-kit/main/install-seed-kit.sh
less install-seed-kit.sh
sh install-seed-kit.sh
```

Then:

```sh
cd ~/seed-kit
sh seed-kit.sh doctor
sh seed-kit.sh restore ~/rpi-edge-service.tar.gz
```

## Installer minimal

Commande cible pour une machine fraiche :

```sh
wget https://raw.githubusercontent.com/warzou/seed-kit/main/install-seed-kit.sh
less install-seed-kit.sh
sh install-seed-kit.sh
```

`install-seed-kit.sh` installe seulement les prerequis minimaux absents
(`git`, `ca-certificates`, et `wget` ou `curl` si necessaire), puis clone ou
met a jour `~/seed-kit` avec un `git pull --ff-only` si le checkout est propre.
Il lance ensuite `~/seed-kit/seed-kit.sh`.

Il ne configure pas Docker, Tailscale, Cloudflare, le reseau, les secrets, ni de
restore.

Usage Seed-Kit ensuite :

```sh
cd ~/seed-kit
sh seed-kit.sh doctor
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

## Commandes utiles

Commandes core legeres :

- `--plan` : affiche le plan.
- `--modules` : liste les modules connus du runtime.
- `modules list` : liste les scripts modules presents dans `modules/`.
- `doctor` : diagnostic read-only court.
- `self-update --plan` : inspecte l'ecart avec `origin`.
- `self-update --apply` : applique uniquement un `git pull --ff-only`.
- `package create --service <name>` : cree un package de reconstruction/replay.
- `package verify <file>` : verifie un package.
- `restore <package>` : verifie, stage, inspecte, puis affiche les prochaines etapes humaines.
- `package apply-guided <file> --step <step>` : compatibilite pour les sous-etapes guidees.
- `--apply [--modules=git,docker] [--yes|-y]` : installe explicitement les modules demandes.
- Sans `--modules`, `--apply` reste en preview-only.
- `-y` : passe la confirmation SAFE (`[y/N]`) pour accelerer un apply explicite.

SAFE rule :

- `sh seed-kit.sh --apply` : aucune action reelle.

Format de progression cible (ambient) :

```text
[1/4] detect system
[2/4] prepare plan
[3/4] confirm safe steps
[4/4] apply
```
