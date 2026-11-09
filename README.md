# cyr-ius/.github

Shared GitHub configuration for cyr-ius repositories.

- `FUNDING.yml`: default funding file for every repository.
- `.github/workflows/`: reusable workflows. Home Assistant ones are prefixed `ha-`
  (GitHub does not support reusable workflows in sub-directories).
- `ha/`: Home Assistant integration templates and `ha/sync.sh` to install them
  in a local repository (`ha/sync.sh [--prune] [--force] <repo>...`).
- `py/`: Python library (PyPI) templates and `py/sync.sh [--prune] <repo>...`.
  Workflows prefixed `py-`; `gh-release.yml`, `dependabot-automerge.yml` and
  `stale.yml` are shared by every family.

- `web/`: web application (uv backend + Node frontend + Docker image) templates
  and `web/sync.sh [--prune] <repo>...`. Workflows prefixed `web-`. Release
  model: development on `dev`, Release Please on the default branch, which
  dispatches the repository's `publish.yml` (CI, tag/version check, Docker
  image on GHCR and Docker Hub, GitHub release) and merges the release back
  into `dev`. `web/templates/workflows/` are rewritten on every sync;
  `web/templates/once/` are project specific and only written when missing.
  Repository setup: the `DOCKERHUB_TOKEN` secret (Read, Write, Delete, for the
  Docker Hub description); a `dev` ruleset requiring the CI checks (the
  Dependabot auto-merge needs them), with the admin role and deploy keys as
  bypass; a write deploy key whose private key is the `DEV_SYNC_KEY` secret,
  used to merge the release back into the protected `dev`.

PyPI trusted publishing does not support reusable workflows, so the publish
job stays in each library's `python-publish.yml` (environment `release`);
`py-build.yml` builds the distributions it publishes.

Callers reference workflows by the `v1` tag:
`uses: cyr-ius/.github/.github/workflows/ha-lint.yml@v1`
