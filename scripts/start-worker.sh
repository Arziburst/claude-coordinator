#!/usr/bin/env bash
# Start a named worker session in its own git worktree.
#   scripts/start-worker.sh --name "APP-12 Fix login" --branch 12-fix-login --model opus \
#       --brief-file brief.md [--mode acceptEdits] [--base main] [--dry-run]
# Creates .claude/worktrees/<branch> from origin/<base> (or reuses it), then starts a background
# session there. --model is required: the coordinator picks it per task (CORE §7).
# Default mode acceptEdits; auto only where PROJECT.md allows it; bypassPermissions refused.
# The brief is passed as the session's first prompt argument (reading it from stdin is unconfirmed).
# Reference script — run it with --dry-run first on a new machine (TOOLKIT.md).
set -euo pipefail

name="" branch="" model="" mode="acceptEdits" brief="" base="main" dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --name) name="$2"; shift 2 ;;
    --branch) branch="$2"; shift 2 ;;
    --model) model="$2"; shift 2 ;;
    --mode) mode="$2"; shift 2 ;;
    --brief-file) brief="$2"; shift 2 ;;
    --base) base="$2"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done
[ -n "$name" ] && [ -n "$branch" ] && [ -n "$model" ] && [ -f "$brief" ] || {
  echo "usage: --name <session name> --branch <branch> --model <model> --brief-file <file> [--mode acceptEdits] [--base main] [--dry-run]" >&2; exit 1; }
[ "$mode" = "bypassPermissions" ] && { echo "refusing bypassPermissions for a worker (TOOLKIT.md: containers only)" >&2; exit 1; }

root="$(git rev-parse --show-toplevel)"
wt="$root/.claude/worktrees/$branch"

run() { if [ "$dry" = 1 ]; then echo "[dry-run] $*"; else "$@"; fi; }

run git -C "$root" fetch -q origin "$base"
if [ -d "$wt" ]; then
  echo "reusing worktree $wt"
elif git -C "$root" show-ref -q --verify "refs/heads/$branch"; then
  run git -C "$root" worktree add "$wt" "$branch"
else
  run git -C "$root" worktree add -b "$branch" "$wt" "origin/$base"
fi

# The worktree exists already, so the session must not create another one (bgIsolation: none).
settings='{"worktree":{"bgIsolation":"none"}}'
if [ "$dry" = 1 ]; then
  echo "[dry-run] (cd $wt && claude --bg --name \"$name\" --model $model --permission-mode $mode --settings '$settings' <brief>)"
else
  ( cd "$wt" && claude --bg --name "$name" --model "$model" --permission-mode "$mode" --settings "$settings" "$(cat "$brief")" )
fi
