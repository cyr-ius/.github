#!/usr/bin/env bash
# Sync the web application CI templates into local repositories.
#
# Usage: web/sync.sh [--prune] <repo> [<repo>...]
#
#   --prune  remove the legacy workflow files replaced by the templates
#
# templates/workflows/* are always (re)written. templates/once/* are project
# specific: they are only written when missing, with values detected from the
# repository (image name, port, backend directory...), then edited by hand.
# Release Please files (config, manifest, version.txt) are also only written
# when missing. Expects a backend managed by uv and a frontend/ directory.
set -euo pipefail

TEMPLATES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/templates"

# Workflow files from the previous per-repository CI, replaced by the templates.
LEGACY_WORKFLOWS=(
  auto-approve.yml
  create-release.yml
  docker-publish.yml
  lint.yml
  release.yml
  stale.yaml
)

usage() {
  sed -n '2,13s/^# \{0,1\}//p' "$0"
  exit "${1:-0}"
}

prune=false
repos=()
for arg in "$@"; do
  case $arg in
    --prune) prune=true ;;
    -h | --help) usage ;;
    -*) echo "unknown option: $arg" >&2; usage 1 ;;
    *) repos+=("$arg") ;;
  esac
done
((${#repos[@]})) || usage 1

# Escape a string for use as a sed replacement.
sed_escape() {
  printf '%s' "$1" | sed 's/[&/\]/\\&/g'
}

render() {
  local src=$1 dest=$2 var args=()
  for var in BRANCH IMAGE TITLE DESCRIPTION PORT BACKEND_DIR BACKEND_PREFIX PROJECT VERSION_FILES; do
    args+=(-e "s/{{$var}}/$(sed_escape "${!var}")/g")
  done
  mkdir -p "$(dirname "$dest")"
  sed "${args[@]}" "$src" >"$dest"
}

# Value of an OCI label in the legacy docker-publish.yml, if any.
legacy_label() {
  local repo=$1 key=$2
  local file=$repo/.github/workflows/docker-publish.yml
  [[ -f $file ]] || return 0
  sed -n "s/^ *org\.opencontainers\.image\.$key=//p" "$file" | head -1
}

sync_repo() {
  local repo=${1%/} f version
  if [[ ! -f $repo/frontend/package.json ]]; then
    echo "skip $repo: expected frontend/package.json" >&2
    return
  fi
  if [[ -f $repo/uv.lock ]]; then
    BACKEND_DIR=. BACKEND_PREFIX=
  elif [[ -f $repo/backend/uv.lock ]]; then
    BACKEND_DIR=backend BACKEND_PREFIX=backend/
  else
    echo "skip $repo: expected uv.lock or backend/uv.lock" >&2
    return
  fi

  IMAGE=$(basename "$(cd "$repo" && pwd)")
  TITLE=$(legacy_label "$repo" title)
  TITLE=${TITLE:-$IMAGE}
  DESCRIPTION=$(legacy_label "$repo" description)
  DESCRIPTION=${DESCRIPTION:-$IMAGE}
  PORT=$( [[ -f $repo/Dockerfile ]] && sed -n 's/^EXPOSE \([0-9]*\).*/\1/p' "$repo/Dockerfile" | head -1 || true)
  PORT=${PORT:-8000}
  PROJECT=$(python3 -c 'import sys, tomllib; print(tomllib.load(open(sys.argv[1], "rb"))["project"]["name"].lower())' "$repo/${BACKEND_PREFIX}pyproject.toml")
  VERSION_FILES="${BACKEND_PREFIX}pyproject.toml frontend/package.json"
  BRANCH=$(git -C "$repo" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/master)
  BRANCH=${BRANCH#origin/}

  local gh=$repo/.github
  mkdir -p "$gh/workflows"

  if $prune; then
    for f in "${LEGACY_WORKFLOWS[@]}"; do
      rm -f -- "$gh/workflows/$f"
    done
  fi

  for f in "$TEMPLATES"/workflows/*.yml; do
    render "$f" "$gh/workflows/$(basename "$f")"
  done

  for f in "$TEMPLATES"/once/*.yml; do
    if [[ $(basename "$f") == docs.yml && ! -f $repo/mkdocs.yml ]]; then continue; fi
    [[ -f $gh/workflows/$(basename "$f") ]] || render "$f" "$gh/workflows/$(basename "$f")"
  done

  [[ -f $repo/release-please-config.json ]] ||
    render "$TEMPLATES/once/release-please-config.json" "$repo/release-please-config.json"
  version=$(jq -r .version "$repo/frontend/package.json")
  [[ -f $repo/.release-please-manifest.json ]] ||
    printf '{\n  ".": "%s"\n}\n' "$version" >"$repo/.release-please-manifest.json"
  if jq -e '.packages["."]["release-type"] == "simple"' "$repo/release-please-config.json" >/dev/null &&
    [[ ! -f $repo/version.txt ]]; then
    echo "$version" >"$repo/version.txt"
  fi

  echo "synced $repo (image: $IMAGE, port: $PORT, backend: $BACKEND_DIR, branch: $BRANCH)"
}

for repo in "${repos[@]}"; do
  sync_repo "$repo"
done
