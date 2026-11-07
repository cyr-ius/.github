# cyr-ius/.github

Shared GitHub configuration for cyr-ius repositories.

- `FUNDING.yml`: default funding file for every repository.
- `.github/workflows/`: reusable workflows. Home Assistant ones are prefixed `ha-`
  (GitHub does not support reusable workflows in sub-directories).
- `ha/`: Home Assistant integration templates and `ha/sync.sh` to install them
  in a local repository (`ha/sync.sh [--prune] [--force] <repo>...`).

Callers reference workflows by the `v1` tag:
`uses: cyr-ius/.github/.github/workflows/ha-lint.yml@v1`
