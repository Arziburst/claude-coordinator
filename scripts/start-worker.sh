#!/usr/bin/env bash
# Start a named worker session in its own git worktree, with the safety settings applied.
#   scripts/start-worker.sh --repo <project repo path> --name "#12 worker: Fix login" --branch 12-fix-login \
#       --model opus --brief-file brief.md --safety <worker settings .json> [--mode auto] [--base main]
#       --report-to <coordinator session> [--launch-from <folder>] [--worktree-root <folder>] [--dry-run]
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
# --worktree-root puts the worktree elsewhere (default <repo>/.claude/worktrees). Launched from a folder
# that is not the repository's root (the self-test: the state repository's worktrees under the trusted
# project), the brief says to work in the worktree by absolute path instead. A repository without an
# origin starts the branch from the local --base.
# The hook path in --safety uses forward slashes: on Windows hooks run through Git Bash, which drops
# backslashes, and a hook that fails to run blocks nothing.
# --report-to: the session the worker reports to - the coordinator's name as ListAgents shows it now
# (names change on a restart). It heads the brief; at the end the script prints the line that
# subscribes to the new session's idle notice (CORE section 4, Control).
# The brief is passed as the session's first prompt argument (reading it from stdin is unconfirmed).
# Reference script — run it with --dry-run first on a new machine (TOOLKIT.md).
set -euo pipefail

repo="" name="" branch="" model="" mode="auto" brief="" safety="" base="main" from="" report="" wtroot="" dry=0
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
    --worktree-root) need "$@"; wtroot="$2"; shift 2 ;;
    --report-to) need "$@"; report="$2"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done
[ -n "$repo" ] && [ -n "$name" ] && [ -n "$branch" ] && [ -n "$model" ] && [ -n "$report" ] && [ -f "$brief" ] && [ -f "$safety" ] || {
  echo "usage: --repo <path> --name <session name> --branch <branch> --model <model> --brief-file <file> --safety <settings.json> --report-to <session> [--mode auto] [--base main] [--launch-from <folder>] [--worktree-root <folder>] [--dry-run]" >&2; exit 1; }
[ "$mode" = "bypassPermissions" ] && { echo "refusing bypassPermissions for a worker (TOOLKIT.md Safety: only the owner's own explicit setup)" >&2; exit 1; }
# Absolute paths: both files are used after "cd" into the worktree.
abs() { (cd "$(dirname "$1")" && printf '%s/%s' "$(pwd)" "$(basename "$1")"); }
safety="$(abs "$safety")"; brief="$(abs "$brief")"

root="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repository: $repo" >&2; exit 1; }
wt="${wtroot:-$root/.claude/worktrees}/$branch"
from="${from:-$root}"
[ -d "$from" ] || { echo "no folder to launch from: $from" >&2; exit 1; }

# Safety settings: the hook path inside the file must exist and pass its self-test.
if grep 'safety-guard\.' "$safety" | sed 's/\\"//g' | grep -q '\\'; then
  echo "safety settings: write the hook path with forward slashes (C:/...): hooks run through Git Bash on Windows, which drops backslashes, and a hook that fails to run blocks nothing" >&2; exit 1
fi
# a PowerShell shell around the hook turns its exit 2 (block) into 1 (a non-blocking error), unless the
# command passes the code through; the hook object's fields sit next to its command line
n="$(grep -n 'safety-guard\.' "$safety" | grep -v -e '-SelfTest' -e '--self-test' | head -n 1 | cut -d: -f1)"
if [ -n "$n" ] && sed -n "$((n > 3 ? n - 3 : 1)),$((n + 3))p" "$safety" | grep -q '"shell"[[:space:]]*:[[:space:]]*"powershell"' &&
   ! sed -n "${n}p" "$safety" | grep -q 'exit \$LASTEXITCODE'; then
  echo "safety settings: the hook runs under a PowerShell shell without \"; exit \$LASTEXITCODE\": its block (exit 2) would reach Claude Code as a non-blocking error (1)" >&2; exit 1
fi
hook=$(grep -o '[^"]*safety-guard\.sh' "$safety" | head -1 | sed 's/^bash //' || true)
[ -n "$hook" ] && [ -f "$hook" ] || { echo "safety settings: hook not found at '$hook' (use an absolute path)" >&2; exit 1; }
grep -q 'bgIsolation' "$safety" || { echo "safety settings: add \"worktree\": {\"bgIsolation\": \"none\"}" >&2; exit 1; }
selftest=$(bash "$hook" --self-test)
[ "$selftest" = "safety-guard: OK" ] || { echo "$selftest" >&2; exit 1; }

run() { if [ "$dry" = 1 ]; then echo "[dry-run] $*"; else "$@" || { echo "$1 failed" >&2; exit 1; }; fi; }

# The worktrees' folder stays out of its repository's git, like coordinator/ (INIT 3.4): a line in the
# local .git/info/exclude, never .gitignore - nothing the project's history, its team or a client sees.
wroot="${wtroot:-$root/.claude/worktrees}"
if [ "$dry" = 1 ]; then
  echo "[dry-run] keep $wroot out of its repository's git (.git/info/exclude)"
else
  mkdir -p "$wroot"
  if prefix="$(git -C "$wroot" rev-parse --show-prefix 2>/dev/null)" && [ -n "$prefix" ] &&
     ! git -C "$wroot" check-ignore -q x; then
    common="$(git -C "$wroot" rev-parse --path-format=absolute --git-common-dir)"
    mkdir -p "$common/info" && printf '/%s\n' "$prefix" >> "$common/info/exclude" &&
      echo "added /$prefix to the repository's .git/info/exclude"
  fi
fi

# no origin (a local-only repository, e.g. a state repository without a remote): the local base branch
if [ -n "$(git -C "$root" config --get remote.origin.url)" ]; then
  run git -C "$root" fetch -q origin "$base"; start="origin/$base"
else start="$base"; fi
if [ -d "$wt" ]; then
  echo "reusing worktree $wt"
elif git -C "$root" show-ref -q --verify "refs/heads/$branch"; then
  run git -C "$root" worktree add "$wt" "$branch"
else
  run git -C "$root" worktree add --no-track -b "$branch" "$wt" "$start"
fi

if [ "$(cd "$from" && pwd -P)" = "$(cd "$root" && pwd -P)" ]; then
  first="FIRST ACTION, before anything else: use the EnterWorktree tool with path = $wt. Work only inside it; never change files outside it."
else
  # launched outside the repository (its root not trusted): EnterWorktree into another repository's
  # worktree asks for permission and the session would wait, so it works there by absolute path
  first="YOUR WORKING COPY is $wt, a worktree of $root. Work in it by absolute path (git -C $wt ..., files under $wt); do not use EnterWorktree; never change files outside it."
fi
first="$first
Report to: the session named \"$report\" (SendMessage) - your report and your questions."
if [ "$dry" = 1 ]; then
  echo "[dry-run] (cd $from && claude --bg --name \"$name\" --model $model --permission-mode $mode --settings $safety <working copy $wt, report to \"$report\", then the brief>)"
else
  ( cd "$from" && claude --bg --name "$name" --model "$model" --permission-mode "$mode" --settings "$safety" "$first

$(cat "$brief")" )
  # wait (up to 20 s) until the new session is listed, so the subscribe below does not race it
  i=0
  while [ "$i" -lt 20 ]; do
    claude agents --json 2>/dev/null | grep -qF "\"$name\"" && break
    i=$((i + 1)); sleep 1
  done
  [ "$i" -lt 20 ] || echo "not listed after 20 s: if the subscribe fails, retry it in a few seconds" >&2
fi
echo "subscribe: SendMessage(to: \"$name\", notify_when_idle: true)"
