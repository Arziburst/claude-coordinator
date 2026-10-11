#!/usr/bin/env bash
# Clean up after a merged task: stop and remove the worker session, remove its worktree and branch —
# only if its PR is merged, the worktree is clean and every commit is on the remote (CORE §8).
# Otherwise report and change nothing.
#   scripts/cleanup-worker.sh --worktree <path> [--session <id>] [--dry-run]
set -euo pipefail

session="" wt="" dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --session) session="$2"; shift 2 ;;
    --worktree) wt="$2"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done
[ -n "$wt" ] || { echo "usage: --worktree <path> [--session <id>] [--dry-run]" >&2; exit 1; }

run() { if [ "$dry" = 1 ]; then echo "[dry-run] $*"; else "$@"; fi; }
stop_here() { echo "$1 - left as is" >&2; exit 3; }

# The main repository is found from the worktree itself, so this runs from any folder.
root=""
[ -d "$wt" ] && root="$(dirname "$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir)")"
branch=""
if [ -d "$wt" ]; then
  [ -n "$(git -C "$wt" status --porcelain)" ] && stop_here "NOT CLEAN: $wt has uncommitted changes"
  branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD)"
  git -C "$wt" rev-parse -q --verify '@{u}' >/dev/null || stop_here "NO UPSTREAM: $branch was never pushed"
  git -C "$wt" fetch -q || stop_here "FETCH FAILED: cannot confirm $branch is on the remote"
  [ -n "$(git -C "$wt" log --oneline '@{u}..')" ] && stop_here "UNPUSHED: $branch has commits not on its remote"
  if command -v gh >/dev/null 2>&1; then
    merged=$(cd "$wt" && gh pr list --head "$branch" --state merged --json number --jq 'length' 2>/dev/null || echo "?")
    [ "$merged" = "0" ] && stop_here "NOT MERGED: no merged PR for $branch"
    [ "$merged" = "?" ] && stop_here "UNKNOWN: could not check the PR for $branch"
  else
    stop_here "NO gh: cannot verify the PR for $branch is merged"
  fi
fi

if [ -n "$session" ]; then
  run claude stop "$session" || true
  run claude rm "$session" || true
fi
if [ -d "$wt" ]; then
  run git -C "$root" worktree remove "$wt"
  run git -C "$root" branch -d "$branch" || echo "branch $branch kept (not fully merged locally)"
fi
echo "cleaned: ${session:-no session} ${wt}"
