#!/usr/bin/env bash
# Clean up after a merged task: stop and remove the worker session, remove its worktree and branch —
# only if the worktree exists, is clean, every commit is on the remote and a merged PR has exactly the
# pushed head (a reused branch name with newer commits does not count) (CORE §8).
# Otherwise report and change nothing.
#   scripts/cleanup-worker.sh --worktree <path> [--session <id>] [--dry-run]
# --session: the short job id (`id` in claude agents --json) or the full sessionId (mapped to its job id).
# Exit codes: 0 cleaned (or would be, with --dry-run); 1 usage error or a failed removal;
# 3 a check failed, nothing changed; 4 SESSION KEPT: claude agents --json --all still lists the session
# after claude rm - the worktree and branch are left as is; 5 SESSION FOREIGN: the listing gives the
# session a working folder outside this project (the repository's main checkout, its .claude/worktrees,
# the worktree itself, the folder whose .claude/worktrees holds it) - nothing is stopped, removed or
# changed (CORE §1.17); a session the listing does not have is handled as before (Windows:
# cleanup-worker.ps1, the same checks and codes).
set -euo pipefail

session="" wt="" dry=0
usage="usage: --worktree <path> [--session <id>] [--dry-run]"
need() { [ $# -ge 2 ] && [ -n "$2" ] || { echo "missing value for $1; $usage" >&2; exit 1; }
         case "$2" in -*) echo "missing value for $1 (got the flag $2); $usage" >&2; exit 1 ;; esac; }
while [ $# -gt 0 ]; do
  case "$1" in
    --session) need "$@"; session="$2"; shift 2 ;;
    --worktree) need "$@"; wt="$2"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done
[ -n "$wt" ] || { echo "$usage" >&2; exit 1; }

run() { if [ "$dry" = 1 ]; then echo "[dry-run] $*"; else "$@"; fi; }
stop_here() { echo "$1 - left as is" >&2; exit 3; }
is_uuid() { local re='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'; [[ "$1" =~ $re ]]; }
# objects <claude agents --json output>: one session object per line; field <key> <object>: its string value
objects() { printf '%s' "$1" | tr -d '\r\n' | tr '}' '\n'; echo; }
field() { printf '%s\n' "$2" | sed -n "s/.*\"$1\": *\"\\([^\"]*\\)\".*/\\1/p"; }
# a folder in one form for comparing: / separators (a JSON \\ is one \), none trailing, Git Bash's /c/x
# as c:/x, lower case where letter case in paths is ignored (Windows, macOS)
case "${OSTYPE:-}" in msys*|cygwin*) os=win ;; darwin*) os=mac ;; *) os="" ;; esac
canon() {
  local x
  x="$(printf '%s' "$1" | sed 's#\\\\#/#g' | tr '\\' '/')"
  # [:upper:]: in a UTF-8 locale also Ü or Д (APFS and NTFS fold them too), in C the ASCII letters
  [ -n "$os" ] && x="$(printf '%s' "$x" | tr '[:upper:]' '[:lower:]')"
  while :; do case "$x" in ?*/) x="${x%/}" ;; *) break ;; esac; done
  if [ "$os" = win ]; then case "$x" in /[a-z]|/[a-z]/*) x="${x:1:1}:${x:2}" ;; esac; fi
  printf '%s' "$x"
}

# The main repository is found from the worktree itself, so this runs from any folder.
[ -d "$wt" ] || stop_here "NO WORKTREE: $wt does not exist (check the path)"
common="$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ||
  stop_here "NOT A WORKTREE: $wt is not a git working copy"
gitdir="$(git -C "$wt" rev-parse --path-format=absolute --git-dir)"
[ "$gitdir" = "$common" ] && stop_here "MAIN CHECKOUT: $wt is the repository itself, not a worker worktree"
root="$(dirname "$common")"
[ -n "$(git -C "$wt" status --porcelain)" ] && stop_here "NOT CLEAN: $wt has uncommitted changes"
branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD)"
git -C "$wt" fetch -q || stop_here "FETCH FAILED: cannot confirm $branch is on the remote"
# its remote branch: the upstream, or origin/<branch> when it was pushed without -u; none when it was
# deleted after the merge and a fetch pruned it (fetch.prune) - then only a merged PR's head can show
# that every commit is on the remote
u=""
if git -C "$wt" rev-parse -q --verify '@{u}' >/dev/null; then u='@{u}'
elif git -C "$wt" rev-parse -q --verify "refs/remotes/origin/$branch" >/dev/null; then u="origin/$branch"; fi
if [ -n "$u" ]; then
  [ -n "$(git -C "$wt" log --oneline "$u..")" ] && stop_here "UNPUSHED: $branch has commits not on its remote"
  up="$(git -C "$wt" rev-parse "$u")"
else up="$(git -C "$wt" rev-parse HEAD)"; fi
command -v gh >/dev/null 2>&1 || stop_here "NO gh: cannot verify the PR for $branch is merged"
heads="$(cd "$wt" && gh pr list --head "$branch" --state merged --json headRefOid --jq '.[].headRefOid' 2>/dev/null)" ||
  stop_here "UNKNOWN: could not check the PR for $branch"
if [ -z "$heads" ]; then
  [ -n "$u" ] && stop_here "NOT MERGED: no merged PR for $branch"
  stop_here "NO UPSTREAM: $branch was never pushed"
fi
if ! printf '%s\n' "$heads" | grep -qx "$up"; then
  # a server-side commit on top of the pushed head (gh pr update-branch merges the base into the PR):
  # the merged PR's head then has the pushed head as an ancestor; a reused name with newer commits does not
  found=""
  for h in $heads; do
    git -C "$wt" cat-file -e "$h^{commit}" 2>/dev/null || git -C "$wt" fetch -q origin "$h" 2>/dev/null || true
    if git -C "$wt" merge-base --is-ancestor "$up" "$h" 2>/dev/null; then found="$h"; break; fi
  done
  if [ -z "$found" ]; then
    [ -n "$u" ] && stop_here "NOT MERGED: no merged PR for $branch has its pushed head ${up:0:7} (branch name reused?)"
    stop_here "UNPUSHED: $branch is on no remote branch, and no merged PR for it contains its head ${up:0:7}"
  fi
  echo "merged as ${found:0:7}: the PR's head has a server-side commit on top of the pushed head ${up:0:7}"
fi
[ -n "$u" ] || echo "its remote branch is gone (deleted after the merge): the merged PR's head contains ${up:0:7}"

id=""
if [ -n "$session" ]; then
  # stop / rm take the short job id (`id` in claude agents --json); they refuse a full sessionId ("No job
  # matching", 2.1.296), so a full one is mapped through the listing, else to its first 8 characters
  # ids are lower-case hex in the listing: a sessionId or job id typed in upper case is the same session
  case "$session" in *[!0-9A-Fa-f-]*) ;; *) session="$(printf '%s' "$session" | tr 'A-F' 'a-f')" ;; esac
  id="$session"
  # no claude on PATH: nothing can be stopped or removed - the session is reported kept (exit 4)
  has_claude=1; command -v claude >/dev/null 2>&1 || has_claude=""
  raw=""; [ -n "$has_claude" ] && { raw="$(claude agents --json --all 2>/dev/null)" || raw=""; }
  if is_uuid "$session"; then
    id="$(objects "$raw" | while IFS= read -r o; do [ "$(field sessionId "$o")" = "$session" ] && { field id "$o"; break; }; done || true)"
    [ -n "$id" ] || id="$(printf '%s' "$session" | cut -c1-8)"
    echo "session $session: job id $id"
  fi
  # only this project's sessions (CORE §1.17): a listed session whose working folder is outside the
  # repository's main checkout (its .claude/worktrees included) and the worktree (with the folder whose
  # .claude/worktrees holds it) is left alone
  scwd="$(objects "$raw" | while IFS= read -r o; do [ "$(field id "$o")" = "$id" ] && { field cwd "$o"; break; }; done || true)"
  if [ -n "$scwd" ]; then
    # each folder also as it lies on disk (links resolved; on Windows an 8.3 name in its long form)
    pw=-P; [ "$os" = win ] && pw=-W
    phys() { (cd -P -- "$1" 2>/dev/null && pwd $pw) || true; }
    sc="$(printf '%s' "$scwd" | sed 's#\\\\#\\#g')"
    top="$(git -C "$wt" rev-parse --path-format=absolute --show-toplevel 2>/dev/null)" || top=""
    own="" dirs=()
    for d in "$root" "$root/.claude/worktrees" "$top" "$wt" "$(phys "$root")" "$(phys "$wt")"; do
      [ -n "$d" ] || continue
      d="$(canon "$d")"; dirs+=("$d")
      # the folder whose .claude/worktrees holds the worktree (a state repository's worktree started
      # from the project root, as the self-test does)
      case "$d/" in ?*/.claude/worktrees/?*) dirs+=("${d%%/.claude/worktrees/*}") ;; esac
    done
    for c in "$sc" "$(phys "$sc")"; do
      [ -n "$c" ] || continue
      c="$(canon "$c")"
      for d in "${dirs[@]}"; do case "$c/" in "$d/"*) own=1; break 2 ;; esac; done
    done
    if [ -z "$own" ]; then
      echo "SESSION FOREIGN: $id ($sc): not this project's session - nothing done" >&2
      exit 5
    fi
  fi
  # a session stopped already (the order in TOOLKIT *Usage*) may refuse the stop: that is fine
  [ -n "$has_claude" ] && { run claude stop "$id" || true; }
  if [ "$dry" = 1 ]; then echo "[dry-run] claude rm $id"
  else
    if [ -n "$has_claude" ]; then rc=0; out="$(claude rm "$id" 2>&1)" || rc=$?
    else rc=127; out="claude: command not found"; fi
    [ -z "$out" ] || printf '%s\n' "$out"
    # removed only when the listing no longer has it; no listing at all: the rm's exit code decides
    lrc=127; [ -n "$has_claude" ] && { lrc=0; raw="$(claude agents --json --all 2>/dev/null)" || lrc=$?; }
    kept=""
    if [ "$lrc" = 0 ]; then
      kept="$(objects "$raw" | while IFS= read -r o; do [ "$(field id "$o")" = "$id" ] && { echo y; break; }; done || true)"
    elif [ "$rc" != 0 ]; then kept=y; fi
    if [ -n "$kept" ]; then
      if [ "$rc" = 0 ]; then why="it exited 0, the session is still listed"
      else why="$(printf '%s\n' "$out" | tr -d '\r' | sed '/^[[:space:]]*$/d' | head -n 1)"; why="${why:-exit $rc}"; fi
      echo "SESSION KEPT: $id (claude rm failed: $why)" >&2
      echo "worktree $wt and branch $branch left as is: remove the session (claude rm $id), then run this again" >&2
      exit 4
    fi
  fi
fi
run git -C "$root" worktree remove "$wt" || { echo "REMOVE FAILED: git worktree remove $wt" >&2; exit 1; }
run git -C "$root" branch -d "$branch" || echo "branch $branch kept (not fully merged locally)"
echo "cleaned: ${id:-no session} ${wt}"
