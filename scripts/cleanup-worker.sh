#!/usr/bin/env bash
# Clean up after a merged task: stop and remove the worker session, remove its worktree and branch —
# only if the worktree is clean and nothing is unpushed (CORE §8). Otherwise report and change nothing.
#   scripts/cleanup-worker.sh --session <id> --worktree <path> [--dry-run]
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

if [ -d "$wt" ]; then
  if [ -n "$(git -C "$wt" status --porcelain)" ]; then
    echo "NOT CLEAN: $wt has uncommitted changes — left as is" >&2; exit 3
  fi
  branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD)"
  if git -C "$wt" rev-parse -q --verify '@{u}' >/dev/null && [ -n "$(git -C "$wt" log --oneline '@{u}..')" ]; then
    echo "UNPUSHED: $wt ($branch) has commits not on its remote — left as is" >&2; exit 3
  fi
fi

if [ -n "$session" ]; then
  run claude stop "$session" || true
  run claude rm "$session" || true
fi
if [ -d "$wt" ]; then
  run git worktree remove "$wt"
  run git branch -d "$branch" || echo "branch $branch kept (not fully merged locally)"
fi
echo "cleaned: ${session:-no session} ${wt}"
