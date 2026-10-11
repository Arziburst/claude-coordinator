#!/usr/bin/env bash
# Start a named worker session in its own git worktree, with the safety settings applied.
#   scripts/start-worker.sh --repo <project repo path> --name "#12 worker: Fix login" --branch 12-fix-login \
#       --model opus --brief-file brief.md --safety <worker settings .json> [--mode auto] [--base main]
#       [--launch-from <folder>] [--dry-run]
# --repo:   the project repository (the worktree is created there, not where the script runs).
# --safety: a settings file for the worker (from settings.example.json) with the deny rules, the
#           PreToolUse hook at an ABSOLUTE path and "worktree": {"bgIsolation": "none"}. It is passed
#           with --settings, so workers are protected even when the coordinator's files live outside the
#           repository. The hook's self-test must pass, or no worker starts.
# --model is required: the coordinator picks it per task (CORE §7).
# Default mode auto (the autonomous level, CORE §3); acceptEdits for the cautious level;
# bypassPermissions is refused by this script.
# The session starts in the repository root (--launch-from overrides it), which the owner trusts once:
# Claude Code refuses --bg in a folder nobody trusted, and a new worktree never is (trust is not
# inherited from a parent). The brief's first line sends it into its worktree (EnterWorktree).
# The hook path in --safety uses forward slashes: on Windows hooks run through Git Bash, which drops
# backslashes, and a hook that fails to run blocks nothing.
# The brief is passed as the session's first prompt argument (reading it from stdin is unconfirmed).
# Reference script — run it with --dry-run first on a new machine (TOOLKIT.md).
set -euo pipefail

repo="" name="" branch="" model="" mode="auto" brief="" safety="" base="main" from="" dry=0
need() { [ $# -ge 2 ] && [ -n "$2" ] || { echo "missing value for $1" >&2; exit 1; }; }
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) need "$@"; repo="$2"; shift 2 ;;
    --name) need "$@"; name="$2"; shift 2 ;;
    --branch) need "$@"; branch="$2"; shift 2 ;;
    --model) need "$@"; model="$2"; shift 2 ;;
    --mode) need "$@"; mode="$2"; shift 2 ;;
    --brief-file) need "$@"; brief="$2"; shift 2 ;;
    --safety) need "$@"; safety="$2"; shift 2 ;;
    --base) need "$@"; base="$2"; shift 2 ;;
    --launch-from) need "$@"; from="$2"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done
[ -n "$repo" ] && [ -n "$name" ] && [ -n "$branch" ] && [ -n "$model" ] && [ -f "$brief" ] && [ -f "$safety" ] || {
  echo "usage: --repo <path> --name <session name> --branch <branch> --model <model> --brief-file <file> --safety <settings.json> [--mode auto] [--base main] [--launch-from <folder>] [--dry-run]" >&2; exit 1; }
[ "$mode" = "bypassPermissions" ] && { echo "refusing bypassPermissions for a worker (TOOLKIT.md Safety: only the owner's own explicit setup)" >&2; exit 1; }
# Absolute paths: both files are used after "cd" into the worktree.
abs() { (cd "$(dirname "$1")" && printf '%s/%s' "$(pwd)" "$(basename "$1")"); }
safety="$(abs "$safety")"; brief="$(abs "$brief")"

root="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repository: $repo" >&2; exit 1; }
wt="$root/.claude/worktrees/$branch"
from="${from:-$root}"
[ -d "$from" ] || { echo "no folder to launch from: $from" >&2; exit 1; }

# Safety settings: the hook path inside the file must exist and pass its self-test.
if grep 'safety-guard\.' "$safety" | grep -q '\\'; then
  echo "safety settings: write the hook path with forward slashes (C:/...): hooks run through Git Bash on Windows, which drops backslashes, and a hook that fails to run blocks nothing" >&2; exit 1
fi
hook=$(grep -o '[^"]*safety-guard\.sh' "$safety" | head -1 | sed 's/^bash //' || true)
[ -n "$hook" ] && [ -f "$hook" ] || { echo "safety settings: hook not found at '$hook' (use an absolute path)" >&2; exit 1; }
grep -q 'bgIsolation' "$safety" || { echo "safety settings: add \"worktree\": {\"bgIsolation\": \"none\"}" >&2; exit 1; }
selftest=$(bash "$hook" --self-test)
[ "$selftest" = "safety-guard: OK" ] || { echo "$selftest" >&2; exit 1; }

run() { if [ "$dry" = 1 ]; then echo "[dry-run] $*"; else "$@" || { echo "$1 failed" >&2; exit 1; }; fi; }

run git -C "$root" fetch -q origin "$base"
if [ -d "$wt" ]; then
  echo "reusing worktree $wt"
elif git -C "$root" show-ref -q --verify "refs/heads/$branch"; then
  run git -C "$root" worktree add "$wt" "$branch"
else
  run git -C "$root" worktree add --no-track -b "$branch" "$wt" "origin/$base"
fi

first="FIRST ACTION, before anything else: use the EnterWorktree tool with path = $wt. Work only inside it; never change files outside it."
if [ "$dry" = 1 ]; then
  echo "[dry-run] (cd $from && claude --bg --name \"$name\" --model $model --permission-mode $mode --settings $safety <EnterWorktree $wt, then the brief>)"
else
  ( cd "$from" && claude --bg --name "$name" --model "$model" --permission-mode "$mode" --settings "$safety" "$first

$(cat "$brief")" )
fi
