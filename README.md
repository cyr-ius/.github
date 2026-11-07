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

PyPI trusted publishing does not support reusable workflows, so the publish
job stays in each library's `python-publish.yml` (environment `release`);
`py-build.yml` builds the distributions it publishes.

Callers reference workflows by the `v1` tag:
`uses: cyr-ius/.github/.github/workflows/ha-lint.yml@v1`
