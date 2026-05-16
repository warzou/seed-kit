# Seed-Kit

Petit toolkit shell pour installer, deployer et reprendre simplement de petites machines:
Debian, Raspberry Pi OS, OpenWRT/Flint plus tard, mini VPS.

Objectif : une commande simple, une UI texte claire, des modules faciles a ajouter.

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

## Installation

Target flow: copy `seed-kit.sh`, run `sh seed-kit.sh`.

For the concrete fresh-node SSH flow (bootstrap + plan/modules/apply), see:
docs/FRESH-NODE-FLOW.md

```sh
sh seed-kit.sh
```

## Bootstrap minimal

Commande cible future pour une machine fraiche :

```sh
curl -fsSL https://raw.githubusercontent.com/warzou/seed-kit/main/bootstrap.sh | sh
```

Puis :

```sh
cd ~/seed-kit
sh seed-kit.sh doctor
```

Le bootstrap V1 installe seulement `git` si absent, via `apt` et confirmation
interactive, puis clone ou met a jour `~/seed-kit`. Il ne configure pas Docker,
Tailscale, Cloudflare, le reseau, les secrets, ni de restore.

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
- `--apply [--modules=git,docker] [--yes|-y]` : preview puis apply SAFE des modules demandes.
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
