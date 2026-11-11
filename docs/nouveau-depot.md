# Ouvrir un nouveau dépôt

Ce guide décrit la mise en place d'un nouveau dépôt pour chacune des trois familles qui
utilisent les workflows réutilisables de ce dépôt :

| Famille | Dossier local | Préfixe des workflows | Script |
| --- | --- | --- | --- |
| [Intégration Home Assistant](#intégration-home-assistant) | `/media/data/ha-integrations` | `ha-` | `ha/sync.sh` |
| [Bibliothèque Python (PyPI)](#bibliothèque-python-pypi) | `/media/data/api-projets` | `py-` | `py/sync.sh` |
| [Application web](#application-web) | `/media/data/web-projets` | `web-` | `web/sync.sh` |

Les dépôts appellent les workflows par le tag `v1`
(`uses: cyr-ius/.github/.github/workflows/<workflow>.yml@v1`).

## Règles communes

- **Les scripts `sync.sh` lisent la branche par défaut dans `origin/HEAD`.** Après un clone
  ou un `git init`, renseignez-la : `git remote set-head origin -a`.
- **Les tags de version n'ont pas de préfixe `v`** : `1.2.3`, et `1.2.3-beta1` pour une
  pré-version.
- **Poussez en SSH** (`git@github.com:cyr-ius/<dépôt>.git`) : une modification de
  `.github/workflows/` demande le scope `workflow`, que le token HTTPS n'a pas.
- **L'auto-merge Dependabot exige des checks requis** sur la branche ciblée par Dependabot.
  Sans ruleset qui les exige, le job `automerge / dependabot` échoue avec
  « Protected branch rules not configured for this branch ».
- **Les checks requis se désignent par leur nom affiché**, de la forme
  `<job appelant> / <job appelé>` (par exemple `lint / lint`). Ils doivent s'exécuter sur
  chaque pull request : un check qui ne tourne que sur certains chemins (la documentation par
  exemple) bloque les autres pull requests.
- **Après une modification de ce dépôt**, une fois la pull request mergée, déplacez le tag
  `v1` : `git tag -f v1 origin/main && git push -f origin v1`.

### Créer un ruleset

Les rulesets de chaque famille sont donnés en JSON. Pour les créer :

```bash
gh api -X POST repos/cyr-ius/<dépôt>/rulesets --input ruleset.json
```

L'`integration_id` `15368` désigne GitHub Actions, l'auteur des checks. Pour modifier un
ruleset existant : `gh api repos/cyr-ius/<dépôt>/rulesets` donne son identifiant, puis
`gh api -X PUT repos/cyr-ius/<dépôt>/rulesets/<id> --input ruleset.json`.

## Intégration Home Assistant

Une intégration personnalisée publiée par HACS, avec une seule branche (`main`) et une
release par tag.

### 1. Créer le dépôt

```bash
cd /media/data/ha-integrations
gh repo create cyr-ius/hass-<nom> --public --description "<description>" --clone
cd hass-<nom>
git remote set-url origin git@github.com:cyr-ius/hass-<nom>.git
```

Le dépôt doit contenir **exactement un** `custom_components/<domaine>/manifest.json` : le
script en tire le domaine et le nom de l'intégration. Ajoutez à la racine :

- `hacs.json` : `name`, `homeassistant` (version minimale), `render_readme: true` ;
- `pyproject.toml` et `uv.lock` (`uv lock`), avec le groupe de développement qui fournit
  `pytest` et `prek` ;
- `.pre-commit-config.yaml` (hooks lancés par le workflow de lint) ;
- `tests/` si l'intégration a des tests : sans ce dossier, le script n'installe pas
  `tests.yml`.

Prenez un dépôt existant comme modèle, par exemple `hass-pure-spa`.

### 2. Installer la CI

```bash
/media/data/dotgithub/ha/sync.sh .
```

- **Réécrits à chaque synchronisation** : les workflows `lint.yml`, `tests.yml` (seulement si
  le dépôt a un dossier `tests/`), `validate.yml`, `release.yml`, `dependabot-automerge.yml`,
  `stale.yml`, et `dependabot.yml` (écosystèmes détectés : actions, uv, pre-commit,
  devcontainer). Ne les modifiez pas dans le dépôt : changez le modèle dans `ha/templates/`.
- **Écrits une seule fois, puis propres au projet** : les modèles d'issue
  (`.github/ISSUE_TEMPLATE/`) et de pull request (`.github/PULL_REQUEST_TEMPLATE.md`), quand
  le dépôt n'en a pas. `--force` les remplace par les modèles.
- **Supprimés avec `--prune`** : les anciens workflows propres au dépôt (`hassfest.yaml`,
  `pytest.yml`, `release.yaml`...), remplacés par les modèles.

Commitez, puis poussez sur `main`.

### 3. Configurer le dépôt

- **Description et topics** : la validation HACS (`validate / HACS Action`) vérifie
  notamment que le dépôt a une description et des topics (`home-assistant`, `hacs`,
  `integration`...), et que les issues sont activées.
- **Ruleset `Protect`** sur la branche par défaut :

  ```json
  {
    "name": "Protect",
    "target": "branch",
    "enforcement": "active",
    "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
    "rules": [
      { "type": "deletion" },
      { "type": "non_fast_forward" },
      {
        "type": "pull_request",
        "parameters": {
          "required_approving_review_count": 0,
          "dismiss_stale_reviews_on_push": false,
          "require_code_owner_review": false,
          "require_last_push_approval": false,
          "required_review_thread_resolution": false
        }
      },
      {
        "type": "required_status_checks",
        "parameters": {
          "strict_required_status_checks_policy": false,
          "required_status_checks": [
            { "context": "lint / lint", "integration_id": 15368 },
            { "context": "tests / pytest", "integration_id": 15368 },
            { "context": "validate / Hassfest", "integration_id": 15368 }
          ]
        }
      }
    ]
  }
  ```

  Retirez `tests / pytest` si le dépôt n'a pas de tests.

Aucun secret n'est nécessaire.

### 4. Publier une version

1. Mettez `version` à jour dans `custom_components/<domaine>/manifest.json` et mergez.
2. Poussez le tag correspondant : `git tag 1.2.3 && git push origin 1.2.3`.

Le workflow `release` refuse un tag différent de la version du manifeste, puis crée la release
GitHub avec des notes générées (pré-version si le tag contient un `-`). HACS propose ensuite
la mise à jour.

## Bibliothèque Python (PyPI)

Une bibliothèque publiée sur PyPI par *trusted publishing*, avec une seule branche et une
publication par tag.

### 1. Créer le dépôt

```bash
cd /media/data/api-projets
gh repo create cyr-ius/<nom> --public --description "<description>" --clone
cd <nom>
git remote set-url origin git@github.com:cyr-ius/<nom>.git
```

Le projet se construit avec `pyproject.toml` (version dans `[project]`) ; `uv.lock` est
recommandé (sinon Dependabot suit `pip`). Ajoutez `.pre-commit-config.yaml` et `tests/`. Prenez
une bibliothèque existante comme modèle, par exemple `aiosysbus`.

### 2. Installer la CI

```bash
/media/data/dotgithub/py/sync.sh .
```

- **Réécrits à chaque synchronisation** : tous les fichiers du script, à savoir les workflows
  `lint.yml`, `tests.yml` (seulement si le dépôt a un dossier `tests/` ; Python 3.14 et 3.15
  par défaut, voir `py-tests.yml`), `python-publish.yml`, `dependabot-automerge.yml`,
  `stale.yml`, et `dependabot.yml` (écosystèmes détectés : actions, uv ou pip, pre-commit). Ne
  les modifiez pas dans le dépôt : changez le modèle dans `py/templates/`.
- **Écrit une seule fois** : rien, la famille n'a pas de fichier propre au projet.
- **Supprimés avec `--prune`** : les anciens workflows propres au dépôt, remplacés par les
  modèles.

Commitez, puis poussez sur la branche par défaut.

`python-publish.yml` reste dans le dépôt au lieu d'appeler un workflow réutilisable : PyPI
n'accepte pas le *trusted publishing* depuis un workflow réutilisable.

Une fois la CI passée une première fois, créez le **ruleset `Protect`** sur la branche par
défaut (voir [Créer un ruleset](#créer-un-ruleset)). Il exige les checks des workflows
installés : `lint / lint` et un `tests / pytest (<version>)` par version de Python testée.

```json
{
  "name": "Protect",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [
          { "context": "lint / lint", "integration_id": 15368 },
          { "context": "tests / pytest (3.14)", "integration_id": 15368 },
          { "context": "tests / pytest (3.15)", "integration_id": 15368 }
        ]
      }
    }
  ]
}
```

- Sans dossier `tests/`, retirez les deux entrées `tests / pytest (...)`.
- Si `tests.yml` passe d'autres versions (`python-versions`), mettez une entrée par version.
- Le ruleset ne bloque pas le push du tag : il ne vise que la branche par défaut.

### 3. Configurer PyPI et le dépôt

- **Environnement `release`** : Settings → Environments → New environment → `release`
  (ou `gh api -X PUT repos/cyr-ius/<nom>/environments/release`). Le job de publication s'y
  exécute.
- ***Trusted publisher* PyPI** : sur pypi.org, Your account → Publishing (*pending publisher*
  pour un projet qui n'existe pas encore), ou Manage → Publishing pour un projet existant :
  - propriétaire `cyr-ius`, dépôt `<nom>` ;
  - workflow `python-publish.yml` ;
  - environnement `release`.
- **Ruleset `Protect`** sur la branche par défaut : voir l'exemple à la fin de
  [2. Installer la CI](#2-installer-la-ci-1).

Aucun secret n'est nécessaire : PyPI fait confiance au token OIDC du workflow.

### 4. Publier une version

1. Mettez `version` à jour dans `pyproject.toml` et mergez.
2. Poussez le tag correspondant : `git tag 1.2.3 && git push origin 1.2.3`.

Le workflow construit les distributions, refuse un tag différent de la version du paquet
(`1.0.0-beta1` correspond à `1.0.0b1`), publie sur PyPI puis crée la release GitHub.

## Application web

Une application FastAPI + Angular livrée en une image Docker, développée sur `dev` et publiée
par Release Please. Le point de départ est le template
[angular-fastapi-scaffold](https://github.com/cyr-ius/angular-fastapi-scaffold) (clone local :
`/media/data/web-projets/__skeleton__`), dont `AGENTS.md` décrit le code et les règles de
développement.

### 1. Créer le dépôt depuis le template

```bash
cd /media/data/web-projets
gh repo create cyr-ius/<nom> --template cyr-ius/angular-fastapi-scaffold --public --clone
cd <nom>
git remote set-url origin git@github.com:cyr-ius/<nom>.git
git remote set-head origin -a
```

Renommez l'application : `name` dans `docker-compose.yml`, valeur par défaut d'`APP_NAME` dans
`backend/app/config.py`, `<title>` dans `frontend/src/index.html`, `name` dans
`frontend/package.json` et `backend/pyproject.toml`.

### 2. Installer la CI

```bash
/media/data/dotgithub/web/sync.sh .
```

- **Réécrits à chaque synchronisation** : `release-please.yml`, `dependabot-automerge.yml`,
  `stale.yml`.
- **Écrits une seule fois, puis propres au projet** : `ci.yml`, `docker.yml`, `docs.yml`,
  `publish.yml`, `release-please-config.json`, `.release-please-manifest.json` et
  `version.txt`.
- **Modifié sans être réécrit** : `dependabot.yml`, dont chaque entrée reçoit
  `target-branch: "dev"` si le fichier n'a encore aucun `target-branch`.
- **Supprimés avec `--prune`** : les anciens workflows propres au dépôt
  (`create-release.yml`, `docker-publish.yml`, `lint.yml`...), remplacés par les modèles.

Vérifiez ensuite :

- `image:` dans `.github/workflows/docker.yml` : le script prend le nom du **dossier**, faux
  dans un worktree (`<nom>-ci`) ;
- `smoke-port` et `smoke-args` dans `docker.yml` : le test de démarrage de l'image doit fournir
  les réglages obligatoires de l'application (valeurs factices) ;
- la version de `.release-please-manifest.json` et de `version.txt` : le script prend celle de
  `frontend/package.json`. Pour un projet existant, mettez celle du dernier tag ; alignez
  `backend/pyproject.toml`, `backend/uv.lock`, `frontend/package.json` et
  `frontend/package-lock.json` sur la même version ;
- `docs.yml` n'est écrit que si le projet a un `mkdocs.yml` (documentation publiée sur GitHub
  Pages).

Commitez sur la branche par défaut, poussez, puis créez `dev` :

```bash
git push origin HEAD
git push origin HEAD:dev
```

### 3. Configurer le dépôt

**Secret `DOCKERHUB_TOKEN`** : un token d'accès Docker Hub du compte `cyrius44`, avec le droit
**Read, Write, Delete** (la mise à jour de la description du dépôt Docker Hub le demande ;
sinon, la publication échoue avec « Forbidden » et la release reste en brouillon).

```bash
gh secret set DOCKERHUB_TOKEN --repo cyr-ius/<nom>
```

**Ruleset `Protect`** sur la branche par défaut, avec les checks `ci / backend`,
`ci / frontend` et `docker / image` :

```json
{
  "name": "Protect",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [
          { "context": "ci / backend", "integration_id": 15368 },
          { "context": "ci / frontend", "integration_id": 15368 },
          { "context": "docker / image", "integration_id": 15368 }
        ]
      }
    }
  ]
}
```

**Ruleset `dev`** : les mêmes checks, pour l'auto-merge Dependabot, sans obligation de pull
request. Les administrateurs et les deploy keys passent outre, pour pousser directement et
pour le report des releases :

```json
{
  "name": "dev",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/heads/dev"], "exclude": [] } },
  "bypass_actors": [
    { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" },
    { "actor_id": null, "actor_type": "DeployKey", "bypass_mode": "always" }
  ],
  "rules": [
    { "type": "deletion" },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [
          { "context": "ci / backend", "integration_id": 15368 },
          { "context": "ci / frontend", "integration_id": 15368 },
          { "context": "docker / image", "integration_id": 15368 }
        ]
      }
    }
  ]
}
```

GitHub Actions ne peut pas figurer parmi les exceptions d'un ruleset sur un dépôt personnel
(GitHub l'ignore sans erreur) : le report de la release sur `dev` passe donc par une deploy
key.

**Deploy key `DEV_SYNC_KEY`** : après une release, le job `sync-dev` merge la branche par défaut
dans `dev` et pousse avec cette clé. La clé privée ne sort pas d'un dossier temporaire :

```bash
tmp=$(mktemp -d)
ssh-keygen -q -t ed25519 -N "" -C "dev-sync@<nom>" -f "$tmp/key"
gh repo deploy-key add "$tmp/key.pub" --repo cyr-ius/<nom> --allow-write --title "Release Please dev sync"
gh secret set DEV_SYNC_KEY --repo cyr-ius/<nom> <"$tmp/key"
rm -rf "$tmp"
```

**GitHub Pages** (si le projet a `docs.yml`) : Settings → Pages → Source « GitHub Actions ».

### 4. Développer et publier

- Le développement se fait sur `dev` (directement ou par pull request), avec des messages
  [Conventional Commits](https://www.conventionalcommits.org/) : `feat:` et `fix:` déclenchent
  une version, `feat!:` ou `BREAKING CHANGE:` une version majeure ; `ci:`, `docs:`, `chore:`
  n'en déclenchent pas.
- Pour publier : ouvrez une pull request de `dev` vers la branche par défaut et mergez-la (merge
  commit). Release Please ouvre ou met à jour sa pull request de release (CHANGELOG, versions).
- Mergez la pull request de release : le tag est créé, `publish.yml` vérifie la version, pousse
  l'image sur GHCR et Docker Hub (`cyrius44/<image>`), crée la release GitHub, puis `sync-dev`
  reporte le commit de release sur `dev`.

Ne poussez pas de tag de version à la main.

Si la CI de la pull request de release échoue après une correction mergée sur la branche par
défaut, Release Please ne la reconstruit que si son contenu change : utilisez « Update branch »
sur la pull request pour relancer la CI. En ligne de commande :

```bash
# Numéro de la pull request de release ouverte
gh pr list --repo cyr-ius/<dépôt> --label "autorelease: pending"
# Merge la branche par défaut dans la pull request, ce qui relance la CI
gh pr update-branch <numéro> --repo cyr-ius/<dépôt>
```

`gh pr update-branch` demande gh 2.53 ou plus récent. Avec une version plus ancienne, passez par
l'API :

```bash
gh api -X PUT repos/cyr-ius/<dépôt>/pulls/<numéro>/update-branch
```

## Liste de contrôle

| Étape | Home Assistant | PyPI | Web |
| --- | --- | --- | --- |
| Dépôt créé, remote SSH, `origin/HEAD` renseigné | ✓ | ✓ | ✓ |
| `sync.sh` lancé, fichiers vérifiés et poussés | ✓ | ✓ | ✓ |
| Ruleset `Protect` sur la branche par défaut | ✓ | ✓ | ✓ |
| Description et topics (HACS) | ✓ | | |
| Environnement `release` et *trusted publisher* PyPI | | ✓ | |
| Branche `dev` et ruleset `dev` | | | ✓ |
| Secrets `DOCKERHUB_TOKEN` et `DEV_SYNC_KEY` (deploy key) | | | ✓ |
| Première version publiée | tag | tag | Release Please |
