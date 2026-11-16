# shellcheck shell=bash
# Shared --commit / --pr / --merge handling for the */sync.sh scripts.
#
# Sourced by ha/, py/ and web/sync.sh, which must define sync_repo <path>
# before calling sync_all. A script may define publish_base <repo> to choose
# the branch the pull request targets (default: the repository's origin/HEAD).
#
# With one of these options the repository's own checkout is left untouched:
# the templates are synced into a temporary worktree created from the
# up-to-date remote base branch, so local branches and uncommitted work are
# never mixed into the change.
#
#   --commit         commit the sync on a local branch ci/sync-templates-<sha>
#   --pr             also push it (over SSH) and open a pull request
#   --merge          also enable auto-merge (squash) on the pull request
#   --message=TEXT   commit / pull request title
#                    (default: "ci: sync shared CI templates")

PUBLISH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBLISH_MODE=
PUBLISH_MESSAGE="ci: sync shared CI templates"
PUBLISH_ARGS=()

# Parse a publishing option; returns 1 if the argument is not one.
publish_option() {
  case $1 in
    --commit) [[ -n $PUBLISH_MODE ]] || PUBLISH_MODE=commit ;;
    --pr) [[ $PUBLISH_MODE == merge ]] || PUBLISH_MODE=pr ;;
    --merge) PUBLISH_MODE=merge ;;
    --message=*) PUBLISH_MESSAGE=${1#--message=} ;;
    *) return 1 ;;
  esac
}

if ! declare -F publish_base >/dev/null; then
  publish_base() {
    local head
    head=$(git -C "$1" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null) || head=origin/main
    echo "${head#origin/}"
  }
fi

# owner/name of the origin GitHub repository, or nothing.
publish_slug() {
  local url
  url=$(git -C "$1" remote get-url origin 2>/dev/null) || return 0
  url=$(sed -E 's#^(https://github\.com/|ssh://git@github\.com/|git@github\.com:)##; s#\.git$##; s#/$##' <<<"$url")
  [[ $url =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] && echo "$url"
}

publish_cleanup() {
  local repo=$1 wt=$2 branch=$3 keep_branch=$4
  git -C "$repo" worktree remove --force "$wt"
  rmdir "$(dirname "$wt")" 2>/dev/null || true
  $keep_branch || git -C "$repo" branch -q -D "$branch"
}

publish_repo() {
  local repo=${1%/} slug base branch tmp wt name stat pr out
  slug=$(publish_slug "$repo")
  if [[ -z $slug ]]; then
    echo "skip $repo: no GitHub origin remote" >&2
    return
  fi
  if ! git -C "$repo" fetch -q origin; then
    echo "skip $repo: git fetch failed" >&2
    return
  fi
  base=$(publish_base "$repo")
  branch=ci/sync-templates-$PUBLISH_SHA
  if git -C "$repo" show-ref --quiet "refs/heads/$branch"; then
    echo "skip $repo: branch $branch already exists (delete it or commit the templates first)" >&2
    return
  fi

  # The worktree keeps the repository's directory name: some scripts derive
  # values from it (web/sync.sh: Docker image name).
  name=$(basename "$(cd "$repo" && pwd)")
  tmp=$(mktemp -d)
  wt=$tmp/$name
  if ! git -C "$repo" worktree add -q -b "$branch" "$wt" "origin/$base"; then
    rmdir "$tmp"
    echo "skip $repo: cannot create a worktree from origin/$base" >&2
    return
  fi

  (cd "$tmp" && sync_repo "$name")
  git -C "$wt" add -A
  if git -C "$wt" diff --cached --quiet; then
    echo "  $repo: already up to date"
    publish_cleanup "$repo" "$wt" "$branch" false
    return
  fi
  stat=$(git -C "$wt" diff --cached --stat)

  # Hook output is only shown when the commit fails.
  if ! out=$(git -C "$wt" commit -q -m "$PUBLISH_MESSAGE" -m "Synced from cyr-ius/.github@$PUBLISH_SHA (${PUBLISH_ARGS[*]})." 2>&1); then
    echo "$out" >&2
    echo "  $repo: commit failed (hooks?), worktree kept in $wt" >&2
    return
  fi

  if [[ $PUBLISH_MODE == commit ]]; then
    publish_cleanup "$repo" "$wt" "$branch" true
    echo "  $repo: committed on branch $branch (based on origin/$base)"
    return
  fi

  if ! git -C "$wt" push -q "git@github.com:$slug.git" "HEAD:refs/heads/$branch"; then
    echo "  $repo: push failed, worktree kept in $wt" >&2
    return
  fi
  if ! pr=$(gh pr create -R "$slug" -B "$base" -H "$branch" -t "$PUBLISH_MESSAGE" \
    -b "$(printf 'Sync of the shared CI templates from cyr-ius/.github@%s (`%s`).\n\n```\n%s\n```\n' \
      "$PUBLISH_SHA" "${PUBLISH_ARGS[*]}" "$stat")"); then
    echo "  $repo: pull request creation failed (branch $branch pushed)" >&2
    publish_cleanup "$repo" "$wt" "$branch" true
    return
  fi
  publish_cleanup "$repo" "$wt" "$branch" false
  echo "  $repo: $pr"

  if [[ $PUBLISH_MODE == merge ]]; then
    if gh pr merge "$pr" --squash --auto --delete-branch >/dev/null 2>&1; then
      echo "  $repo: auto-merge enabled"
    else
      echo "  $repo: auto-merge not available on this repository, merge it by hand" >&2
    fi
  fi
}

# Run sync_repo (or publish_repo) on each repository.
sync_all() {
  local repo
  if [[ -n $PUBLISH_MODE ]]; then
    PUBLISH_SHA=$(git -C "$PUBLISH_ROOT" rev-parse --short HEAD)
    if [[ -n $(git -C "$PUBLISH_ROOT" status --porcelain -- ':!docs') ]]; then
      echo "warning: $PUBLISH_ROOT has uncommitted changes, they are published too" >&2
    fi
    if [[ $PUBLISH_MODE != commit ]] && ! command -v gh >/dev/null; then
      echo "error: --pr / --merge need the gh CLI" >&2
      exit 1
    fi
  fi
  for repo in "$@"; do
    if [[ -n $PUBLISH_MODE ]]; then
      publish_repo "$repo"
    else
      sync_repo "$repo"
    fi
  done
}
