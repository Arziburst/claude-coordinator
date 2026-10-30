#!/usr/bin/env bash
# Start a named worker session in its own git worktree, with the safety settings applied.
#   scripts/start-worker.sh --repo <project repo path> --name "#12 worker: Fix login" --branch 12-fix-login \
#       --model opus [--effort high] --brief-file brief.md --safety <worker settings .json> [--mode auto] [--base main]
#       --report-to <coordinator session> [--contract <file>] [--tester-commit <sha> | --tester-tests <path>]
#       [--launch-from <folder>] [--worktree-root <folder>] [--dry-run]
# --repo:   the project repository (the worktree is created there, not where the script runs).
# --safety: a settings file for the worker (from settings.example.json) with the deny rules, the
#           PreToolUse hook at an ABSOLUTE path and "worktree": {"bgIsolation": "none"}. It is passed
#           with --settings, so workers are protected even when the coordinator's files live outside the
#           repository. The hook's self-test must pass, or no worker starts. Launched from the root
#           without env COORD_PROTECTED_ROOT in it: a notice (edit tools can reach the working copy).
# --model is required: the coordinator picks it per task (CORE §7).
# --effort: low, medium, high, xhigh or max, passed as claude --effort (CORE §7, the contract's budget.effort);
# without it the session runs at the user's default effort for its model.
# Default mode auto (the autonomous level, CORE §3); acceptEdits for the cautious level;
# bypassPermissions is refused by this script.
# The session starts in the repository root (--launch-from overrides it), which the owner trusts once:
# Claude Code refuses --bg in a folder nobody trusted, and a new worktree never is (trust is not
# inherited from a parent). The brief's first line sends it into its worktree (EnterWorktree).
# --worktree-root puts the worktree elsewhere (default <repo>/.claude/worktrees). Launched from a folder
# that is not the repository's root (the self-test: the state repository's worktrees under the trusted
# project), the brief says to work in the worktree by absolute path instead. A repository without an
# origin, or a --base not on origin yet (a lead's integration branch), starts the branch from the local --base.
# The hook path in --safety uses forward slashes: on Windows hooks run through Git Bash, which drops
# backslashes, and a hook that fails to run blocks nothing.
# The worktrees' folder, a coordinator/ state repository at the root and a lead's .lead/ notes in any
# worktree are kept out of the project's git: one line each in its .git/info/exclude, never .gitignore.
# A lead gets a notes folder beside its worktree, <worktree>.lead/ (made, or an existing one kept), named
# in its launch text (#310); a dry run says it would make it.
# --report-to: the session the worker reports to - the coordinator's name as ListAgents shows it now
# (names change on a restart). It heads the brief; at the end the script prints the line that
# subscribes to the new session's idle notice (CORE section 4, Control).
# A worker or a lead: before the launch it prints the conflict foresight (CORE §4a) - merge-queue status
# with the brief's `touches` - as `foresight:` lines; informational, never a stop.
# The contract must pass check-contract before it goes out (CORE §4, #267): --contract <file>, or for a
# worker or a lead without it the contract in the brief (a block after a `---` line, to the next one or
# the end, holding any key check-contract requires, CONTRACT.md), is checked before anything is created (--dry-run too). An ERROR refuses
# the start (exit 1) with check-contract's lines; WARNs are printed and the start goes on; a worker or a
# lead with no contract found: one notice line, the start goes on. Other roles' briefs are not searched.
# --contract only checks a contract; the session reads the brief alone (#331): a --contract whose text is
# not in the brief (its first `id:` line and its first `title:` line both absent from the brief) prints one
# WARN line, and the start goes on (--dry-run too); the brief is never changed.
# The tests_first gate (CORE §4 step 3, #276): a worker whose contract says `tests_first: yes` starts only
# with the tester's tests - --tester-commit <sha>, a commit that is the worker's start point or an ancestor
# of it (a reused worktree's HEAD, else the branch, else the base), or --tester-tests <path>, an existing
# file or folder (a lead's case: the tests its tester subagent returned, kept in its notes folder); else it is
# refused (exit 1) before anything is created (--dry-run too). `tests_first` comes from check-contract
# itself (`check-contract.sh --field tests_first`, one parser): its contract block (the front matter, or a
# top-level `contract:`), never the rest of the file. A start with either flag prints one line naming the tester's tests; both flags together are
# refused. A tester start is not gated. A lead's task gets no task-level tester (#289): a lead whose
# contract says `tests_first: yes`, or a lead given --tester-commit / --tester-tests, is refused (exit 1)
# before anything is created (--dry-run too) - a lead's contract has `tests_first: no - the lead runs the
# tester per sub-contract` (roles/lead.md step 3).
# The brief is passed as the session's first prompt argument (reading it from stdin is unconfirmed).
# A launch text (first line + role + brief) over 24 000 characters goes through a file instead (#291):
# <config>/coordinator/briefs/launch-<branch>-<time>-<pid>.md, decided before anything is created, the
# first message one short instruction to read it in full with the Read tool; one line names the file.
# A launch that fails names what it created and cleanup-worker, and exits 1.
# An assistant (#281): --name "assistant: <name>" (<name> letters, digits, . _ -, not dots only) and
# --brief-file <repo>/coordinator/assistants/<name>/BRIEF.md start a persistent session with NO worktree and NO
# branch, launched from the repository root, --settings the --safety file, whose env COORD_ASSISTANT_DIR must
# name that same folder (folders compared as on disk, in one letter case where paths ignore it). Its launch
# text's first line names the folder: BRIEF.md read in full, NOTES.md kept as its memory, both re-read after a
# compaction or a restart, writes only inside the folder, questions to --report-to by SendMessage; then
# roles/assistant.md (when the core has it) and the brief. A session of that name already listed (claude agents
# --json --all, any state) is refused; --branch, --base, --worktree-root, --launch-from, --contract,
# --tester-commit and --tester-tests are refused; each refusal exits 1 before anything is created. Nothing is
# written into the folder (the coordinator's skill writes BRIEF.md and NOTES.md). After the launch: the attach
# command (`claude attach "assistant: <name>"`, and `claude attach <id>` when the launch printed the id).
# Reference script — run it with --dry-run first on a new machine (TOOLKIT.md).
set -euo pipefail

repo="" name="" branch="" model="" effort="" mode="auto" brief="" safety="" base="main" from="" report="" wtroot="" contract="" tcommit="" ttests="" dry=0 given=""
need() { [ $# -ge 2 ] && [ -n "$2" ] || { echo "missing value for $1" >&2; exit 1; }
         case "$2" in -*) echo "missing value for $1 (got the flag $2)" >&2; exit 1 ;; esac; }
while [ $# -gt 0 ]; do
  case "$1" in --branch|--base|--worktree-root|--launch-from|--contract|--tester-commit|--tester-tests) given="${given:-$1}" ;; esac
  case "$1" in
    --repo) need "$@"; repo="$2"; shift 2 ;;
    --name) need "$@"; name="$2"; shift 2 ;;
    --branch) need "$@"; branch="$2"; shift 2 ;;
    --model) need "$@"; model="$2"; shift 2 ;;
    --effort) need "$@"; effort="$2"; shift 2 ;;
    --mode) need "$@"; mode="$2"; shift 2 ;;
    --brief-file) need "$@"; brief="$2"; shift 2 ;;
    --safety) need "$@"; safety="$2"; shift 2 ;;
    --base) need "$@"; base="$2"; shift 2 ;;
    --launch-from) need "$@"; from="$2"; shift 2 ;;
    --worktree-root) need "$@"; wtroot="$2"; shift 2 ;;
    --report-to) need "$@"; report="$2"; shift 2 ;;
    --contract) need "$@"; contract="$2"; shift 2 ;;
    --tester-commit) need "$@"; tcommit="$2"; shift 2 ;;
    --tester-tests) need "$@"; ttests="$2"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done
# an assistant (#281): a session beside the coordinator, no worktree and no branch - a worker's flags are refused
asst=""; case "$name" in "assistant:"*) asst=1 ;; esac
if [ -n "$asst" ] && [ -n "$given" ]; then
  echo "refused: $given with an assistant ($name) - an assistant has no worktree, branch, base or contract; it starts from the repository root" >&2; exit 1
fi
# a brief that is missing, or empty / blanks only, would start a worker with no task (#226)
if [ -n "$brief" ]; then
  [ -f "$brief" ] || { echo "--brief-file: $brief does not exist" >&2; exit 1; }
  grep -q '[^[:space:]]' "$brief" || { echo "--brief-file: $brief is empty - a worker with no task would start" >&2; exit 1; }
fi
[ -n "$repo" ] && [ -n "$name" ] && { [ -n "$branch" ] || [ -n "$asst" ]; } && [ -n "$model" ] && [ -n "$report" ] && [ -f "$brief" ] && [ -f "$safety" ] || {
  echo "usage: --repo <path> --name <session name> --branch <branch> --model <model> [--effort <level>] --brief-file <file> --safety <settings.json> --report-to <session> [--contract <file>] [--tester-commit <sha> | --tester-tests <path>] [--mode auto] [--base main] [--launch-from <folder>] [--worktree-root <folder>] [--dry-run]" >&2
  [ -z "$asst" ] || echo "an assistant: --repo <path> --name \"assistant: <name>\" --model <model> [--effort <level>] --brief-file <repo>/coordinator/assistants/<name>/BRIEF.md --safety <settings.json> --report-to <session> [--mode auto] [--dry-run]" >&2
  exit 1; }
[ -z "$contract" ] || [ -f "$contract" ] || { echo "--contract: $contract does not exist" >&2; exit 1; }
[ -z "$tcommit" ] || [ -z "$ttests" ] || { echo "--tester-commit and --tester-tests are alternatives: give one - the tester's commit, or (a lead's case) the path of the tests its tester returned (CORE §4 step 3)" >&2; exit 1; }
[ "$(printf '%s' "$mode" | tr '[:upper:]' '[:lower:]')" = "bypasspermissions" ] && { echo "refusing bypassPermissions for a worker (TOOLKIT.md Safety: only the owner's own explicit setup)" >&2; exit 1; }
case "$effort" in ""|low|medium|high|xhigh|max) ;; *) echo "--effort: low, medium, high, xhigh or max (got $effort)" >&2; exit 1 ;; esac
eff=(); [ -z "$effort" ] || eff=(--effort "$effort")
# Absolute paths: both files are used after "cd" into the worktree.
abs() { (cd "$(dirname "$1")" && printf '%s/%s' "$(pwd)" "$(basename "$1")"); }
safety="$(abs "$safety")"; brief="$(abs "$brief")"
# a relative --worktree-root is taken from the current folder (git would resolve it against the repository)
case "$wtroot" in ""|/*|[A-Za-z]:[/\\]*) ;; *) wtroot="$(pwd)/$wtroot" ;; esac
# the same folder in another letter case is the same folder on Windows and (by default) macOS
fold() { case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*|Darwin) printf '%s' "$1" | tr '[:upper:]' '[:lower:]' ;; *) printf '%s' "$1" ;; esac; }

root="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repository: $repo" >&2; exit 1; }
# an assistant's name and folder: <root>/coordinator/assistants/<name>/, its brief BRIEF.md there
aname="" adir=""
if [ -n "$asst" ]; then
  aname="${name#assistant: }"
  { [ "assistant: $aname" = "$name" ] && [[ "$aname" =~ ^[A-Za-z0-9._-]+$ ]] && case "$aname" in *[!.]*) true ;; *) false ;; esac; } ||
    { echo "refused: the assistant name \"${name#assistant:}\" in --name \"$name\" - write \"assistant: <name>\", <name> letters, digits, . _ - (not dots only)" >&2; exit 1; }
  adir="$root/coordinator/assistants/$aname"
  # a folder as it lies on disk (links resolved), C:/... on Windows, no trailing /, in one letter case where paths ignore it
  fcanon() { local q; q="$( (cd "$1" 2>/dev/null && pwd -P) || true)"; [ -n "$q" ] || q="$1"
    command -v cygpath >/dev/null 2>&1 && q="$(cygpath -m "$q")"
    while :; do case "$q" in ?*/) q="${q%/}" ;; *) break ;; esac; done; fold "$q"; }
  [ "$(basename "$brief")" = BRIEF.md ] && [ "$(fcanon "$(dirname "$brief")")" = "$(fcanon "$adir")" ] ||
    { echo "refused: an assistant's brief is $adir/BRIEF.md (its folder in coordinator/assistants/), got $brief" >&2; exit 1; }
  # COORD_ASSISTANT_DIR in the safety file's env: the guard keeps the assistant's writes inside that folder
  aenv="$(sed -n 's/.*"COORD_ASSISTANT_DIR"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$safety" | head -n 1 | sed 's#\\\\#/#g' | tr '\\' '/')"
  [ -n "$aenv" ] || { echo "refused: no COORD_ASSISTANT_DIR in the env of $safety - it must name the assistant's folder $adir" >&2; exit 1; }
  [ "$(fcanon "$aenv")" = "$(fcanon "$adir")" ] ||
    { echo "refused: COORD_ASSISTANT_DIR in $safety is $aenv - it must name the assistant's folder $adir" >&2; exit 1; }
  from="$root"
fi
wt="${wtroot:-$root/.claude/worktrees}/$branch"
from="${from:-$root}"
[ -d "$from" ] || { echo "no folder to launch from: $from" >&2; exit 1; }
# the branch exactly as named: on a case-insensitive file system a branch that differs only in letter
# case is the same branch file and the same worktree folder (show-ref and [ -d ] would say it exists);
# with packed refs git lets both exist, so another one in another letter case is refused even then
heads="$(git -C "$root" for-each-ref --format='%(refname)' refs/heads | sed 's#^refs/heads/##')"
has_branch=0; printf '%s\n' "$heads" | grep -qxF -- "$branch" && has_branch=1
other="$(printf '%s\n' "$heads" | while IFS= read -r b; do [ -n "$b" ] && [ "$b" != "$branch" ] && [ "$(fold "$b")" = "$(fold "$branch")" ] && printf '%s\n' "$b"; done | head -n 1 || true)"
[ -z "$other" ] || { echo "branch $branch differs only in letter case from the existing $other: on this file system they are one branch - pick another name" >&2; exit 1; }

# Safety settings: the hook path inside the file must exist and pass its self-test.
if grep 'safety-guard\.' "$safety" | sed 's/\\"//g' | grep -q '\\'; then
  echo "safety settings: write the hook path with forward slashes (C:/...): hooks run through Git Bash on Windows, which drops backslashes, and a hook that fails to run blocks nothing" >&2; exit 1
fi
# the guard's PreToolUse line (the SessionStart self-test line carries --self-test / -SelfTest)
n="$(grep -n 'safety-guard\.' "$safety" | grep -v -e '-SelfTest' -e '--self-test' | head -n 1 | cut -d: -f1 || true)"
[ -n "$n" ] || { echo "safety settings: no PreToolUse safety-guard hook in $safety" >&2; exit 1; }
# a PowerShell shell around the hook turns its exit 2 (block) into 1 (a non-blocking error), unless the
# command passes the code through; the shell field sits in the same hook object, between its braces
if awk -v n="$n" '{ l[NR] = $0 } END { s = n; while (s > 1 && l[s] !~ /[{]/) s--; e = n; while (e < NR && l[e] !~ /[}]/) e++
       for (i = s; i <= e; i++) if (l[i] ~ /"shell"[ \t]*:[ \t]*"powershell"/) exit 0; exit 1 }' "$safety" &&
   ! sed -n "${n}p" "$safety" | grep -q 'exit \$LASTEXITCODE'; then
  echo "safety settings: the hook runs under a PowerShell shell without \"; exit \$LASTEXITCODE\": its block (exit 2) would reach Claude Code as a non-blocking error (1)" >&2; exit 1
fi
# the guard's path in one line of the file: quoted ("..." is \"...\" inside the JSON string, or '...'),
# so it may hold a space, or else the word without spaces
hookpath() {
  local p
  p="$(printf '%s\n' "$1" | sed -nE 's/.*\\"([^"]*safety-guard\.(sh|ps1))\\".*/\1/p')"
  [ -n "$p" ] || p="$(printf '%s\n' "$1" | sed -nE "s/.*'([^']*safety-guard\.(sh|ps1))'.*/\1/p")"
  [ -n "$p" ] || p="$(printf '%s\n' "$1" | grep -oE '[^" ]*safety-guard\.(sh|ps1)' | head -n 1)"
  printf '%s' "$p"
}
# every guard path in the file must exist; the self-test runs the PreToolUse hook itself
while IFS= read -r l; do
  p="$(hookpath "$l")"
  [ -f "$p" ] || { echo "safety settings: hook not found at '$p' (use an absolute path; quote a path with a space)" >&2; exit 1; }
done <<EOF
$(grep 'safety-guard\.' "$safety")
EOF
hook="$(hookpath "$(sed -n "${n}p" "$safety")")"
case "$hook" in *.sh) ;; *) hook="" ;; esac
[ -n "$hook" ] || { echo "safety settings: the PreToolUse guard is not safety-guard.sh - start a PowerShell-hook file with start-worker.ps1" >&2; exit 1; }
grep -q 'bgIsolation' "$safety" || { echo "safety settings: add \"worktree\": {\"bgIsolation\": \"none\"}" >&2; exit 1; }
selftest=$(bash "$hook" --self-test || true)
[ -n "$selftest" ] || { echo "safety settings: the hook's self-test printed nothing ($hook)" >&2; exit 1; }
[ "$selftest" = "safety-guard: OK" ] || { echo "$selftest" >&2; exit 1; }
# an assistant is one session per name: one already listed (running or stopped) is refused, never a second
if [ -n "$asst" ] && command -v claude >/dev/null 2>&1; then
  ex="$(claude agents --json --all 2>/dev/null | tr -d '\r\n' | tr '}' '\n' | sed 's/"name": *"/"name":"/' | grep -F "\"name\":\"$name\"" | head -n 1 || true)"
  if [ -n "$ex" ]; then
    xid="$(printf '%s\n' "$ex" | sed -n 's/.*"id": *"\([^"]*\)".*/\1/p')"
    [ -n "$xid" ] || xid="$(printf '%s\n' "$ex" | sed -n 's/.*"sessionId": *"\([^"]*\)".*/\1/p')"
    xst="$(printf '%s\n' "$ex" | sed -n 's/.*"state": *"\([^"]*\)".*/\1/p')"
    echo "refused: the session \"$name\" exists already (${xid:-no id}${xst:+, $xst}) - wake it (SendMessage, claude attach), or remove it on the owner's word first" >&2; exit 1
  fi
fi

# The contract passes check-contract before it goes out (CORE §4, #267), checked before anything is
# created: --contract <file>, or for a worker or a lead (the role from the name, as the foresight below)
# the first block after a `---` line of the brief - up to the next `---` or the brief's end - that holds
# any key check-contract requires at its top level but title (id, intent, acceptance, non_goals,
# do_not_decide, tests_first; title is common in quoted front matter, #267): a contract missing some of them is still checked, never "none found"
crole="$(printf '%s' "$name" | sed -n 's/^\(#[^ ]* \)\{0,1\}\([a-z]*\):.*/\2/p')"
cfile="$contract" clabel="$contract" ctmp=""
if [ -z "$contract" ]; then case "$crole" in worker|lead|"")
  ctmp="$(mktemp "${TMPDIR:-/tmp}/start-worker-contract.XXXXXX")"
  # the temporary file goes on any way out, a kill included (the traps are lifted after the check)
  trap 'rm -f "$ctmp"' EXIT; trap 'exit 1' HUP INT TERM
  # each `---` line ends a candidate block and opens the next (a rule above the contract is no contract)
  B="$(printf '\357\273\277')" awk 'BEGIN { B = ENVIRON["B"] }
    { sub(/\r$/, ""); if (NR == 1 && index($0, B) == 1) $0 = substr($0, length(B) + 1) }
    /^---[ \t]*$/ { if (on && k) { printf "---\n%s---\n", buf; done = 1; exit } on = 1; buf = ""; k = 0; next }
    on { buf = buf $0 "\n"; if ($0 ~ /^(id|intent|acceptance|non_goals|do_not_decide|tests_first):/) k = 1 }
    END { if (!done && on && k) printf "---\n%s---\n", buf }' "$brief" > "$ctmp"
  if [ -s "$ctmp" ]; then cfile="$ctmp" clabel="contract in the brief"
  else echo "contract: none found in the brief - check-contract not run (CORE §4)"; fi ;;
esac; fi
if [ -n "$cfile" ]; then
  crc=0; cout="$(bash "$(dirname "$0")/check-contract.sh" "$cfile" 2>&1)" || crc=$?
  # its lines name the file it read: the brief's contract by that name, not by the temporary file
  printf '%s\n' "$cout" | F="$cfile" L="$clabel" awk 'BEGIN { F = ENVIRON["F"] ": "; L = ENVIRON["L"] ": " }
    index($0, F) == 1 { $0 = L substr($0, length(F) + 1) } { print }'
  [ "$crc" = 0 ] || { echo "refused: the contract fails check-contract - fix the ERROR lines above before it goes out (CORE §4)" >&2; exit 1; }
fi
if [ -n "$contract" ]; then
  # the contract's first `id:` and `title:` lines against the brief's lines, all trimmed
  cin="$(B="$(printf '\357\273\277')" awk 'BEGIN { B = ENVIRON["B"] } FNR == 1 { f++; if (index($0, B) == 1) $0 = substr($0, length(B) + 1) }
    { sub(/\r$/, ""); gsub(/^[ \t]+|[ \t]+$/, "") }
    f == 1 && /^(id|title):/ { k = substr($0, 1, index($0, ":")); if (!(k in want)) want[k] = $0; next }
    f == 2 { have[$0] = 1 }
    END { n = 0; for (k in want) { n++; if (want[k] in have) { print "yes"; exit } } print (n ? "no" : "yes") }' "$contract" "$brief")"
  [ "$cin" = yes ] || echo "WARN: --contract only checks the contract - the session will not see it: its text (its id: and title: lines) is not in the brief; put the contract into the brief file (#331)"
fi
# the tests_first gate (CORE §4 step 3, #276): a worker's contract with `tests_first: yes` needs the
# tester's tests; a lead runs its own tester, a tester writes them
# - its value as check-contract itself reads it (its --field option: one parser, so the two never
# disagree), asked once the contract has passed it. A lead's task gets no task-level tester (#289): the
# lead runs the tester per sub-contract (roles/lead.md step 3), so a lead whose contract says yes, or a
# lead given --tester-commit / --tester-tests, is refused
tfyes=0
if [ -n "$cfile" ]; then case "$crole" in worker|lead|"")
  tfv="$(bash "$(dirname "$0")/check-contract.sh" --field tests_first "$cfile" 2>&1)" ||
    { printf '%s\n' "$tfv" >&2; echo "refused: check-contract could not read tests_first (CORE §4 step 3)" >&2; exit 1; }
  printf '%s\n' "$tfv" | tr -d '\r' | tr '[:upper:]' '[:lower:]' | grep -Eq '^yes([[:space:],:;(]|$)' && tfyes=1 ;; esac; fi
[ -z "$ctmp" ] || { rm -f "$ctmp"; trap - EXIT HUP INT TERM; }
if [ "$crole" = lead ] && { [ -n "$tcommit" ] || [ -n "$ttests" ]; }; then
  echo "refused: a lead's task gets no task-level tester - start the lead without --tester-commit / --tester-tests; its contract has \`tests_first: no - the lead runs the tester per sub-contract\` (roles/lead.md step 3)" >&2; exit 1
fi
if [ "$crole" = lead ] && [ "$tfyes" = 1 ]; then
  echo "refused: $clabel has tests_first: yes, but a lead's task gets no task-level tester - a lead's contract has \`tests_first: no - the lead runs the tester per sub-contract\`, yes belongs only in its sub-contracts (roles/lead.md step 3)" >&2; exit 1
fi
if [ "$tfyes" = 1 ] && [ -z "$tcommit" ] && [ -z "$ttests" ]; then
  echo "refused: $clabel has tests_first: yes - start the worker with the tester's tests: --tester-commit <sha> or --tester-tests <path> (CORE §4 step 3)" >&2; exit 1
fi
if [ -n "$ttests" ]; then
  [ -e "$ttests" ] || { echo "--tester-tests: $ttests does not exist - give the tester's tests file or folder (CORE §4 step 3)" >&2; exit 1; }
  echo "tester's tests: $ttests"
fi
tfull=""
if [ -n "$tcommit" ]; then
  tfull="$(git -C "$root" rev-parse -q --verify "$tcommit^{commit}" 2>/dev/null)" ||
    { echo "--tester-commit: $tcommit is not a commit in $root - give the sha of the tester's commit (CORE §4 step 3)" >&2; exit 1; }
fi

run() { if [ "$dry" = 1 ]; then echo "[dry-run] $*"; else "$@" || { echo "$1 failed" >&2; exit 1; }; fi; }

# no origin (a local-only repository, e.g. a state repository without a remote): the local base branch;
# a base not on origin yet (a lead's integration branch before its first push): the local one too
if [ -n "$asst" ]; then start=""   # no branch, so no base
elif [ -n "$(git -C "$root" config --get remote.origin.url)" ]; then
  # git's first error line goes into the message; a failure other than "no such branch" (2) is retried
  # once: a transient DNS or network error should not stop a start
  lsr() { err="$(git -C "$root" ls-remote -q --exit-code --heads origin "$base" 2>&1 >/dev/null)"; }
  rc=0; lsr || rc=$?
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
    echo "origin did not answer: retrying once in 3 s"; sleep 3; rc=0; lsr || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then run git -C "$root" fetch -q origin "$base"; start="origin/$base"
  elif [ "$rc" -eq 2 ] && git -C "$root" show-ref -q --verify "refs/heads/$base"; then
    echo "base $base is not on origin yet: the branch starts from the local $base"; start="$base"
  elif [ "$rc" -eq 2 ]; then echo "base $base: not on origin and no local branch" >&2; exit 1
  else
    err="$(printf '%s\n' "$err" | tr -d '\r' | grep -v '^ *$' | head -n 1)"
    echo "cannot reach origin to read the base $base: $err" >&2; exit 1
  fi
else start="$base"; fi
# the tester's commit is on the worker's start point (it or an ancestor of it): a reused worktree's HEAD,
# else the existing branch, else the base - still before anything is created
if [ -n "$tfull" ]; then
  if [ -e "$wt/.git" ]; then sp="$(git -C "$wt" rev-parse -q --verify HEAD 2>/dev/null || true)" spl="the worktree's HEAD"
  elif [ "$has_branch" = 1 ]; then sp="refs/heads/$branch" spl="the branch $branch"
  else sp="$start" spl="the base $start"; fi
  tshort="$(printf '%s' "$tfull" | cut -c1-7)"
  [ -n "$sp" ] && git -C "$root" merge-base --is-ancestor "$tfull" "$sp" 2>/dev/null ||
    { echo "--tester-commit: $tcommit is not on the worker's start point ($spl): neither it nor an ancestor of it - the tester's commit goes on the task branch or its base (CORE §4 step 3)" >&2; exit 1; }
  echo "tester's tests: commit $tshort, on $spl"
fi

# The launch text (the first line, the role, the brief) and the way it goes, decided before anything is
# created (#291): up to 24 000 characters on the command line; above it - Windows cuts a command line at
# 32 767, after the worktree and branch exist - in a file beside the kept briefs (pruned with them), and
# the session's first message is a short instruction to read that file
notice=""
if [ -n "$asst" ]; then
  # an assistant: its folder is its memory - it lives on across compactions and restarts from the files there
  first="YOUR FOLDER is $adir/ - you are the assistant \"$aname\": no worktree, no branch. Read $adir/BRIEF.md in full before anything else and keep $adir/NOTES.md as your memory; re-read both after every compaction (a summary loses rules) and after a restart. Write only inside $adir/; never change, commit, push or open a PR in the project."
  grep -Eq '"COORD_PROTECTED_ROOT"[[:space:]]*:[[:space:]]*"[^"]' "$safety" ||
    notice="notice: COORD_PROTECTED_ROOT is not set in $safety: edit tools can reach the working copy (TOOLKIT Safety)"
elif [ "$(fold "$(cd "$from" && pwd -P)")" = "$(fold "$(cd "$root" && pwd -P)")" ]; then
  first="FIRST ACTION, before anything else: use the EnterWorktree tool with path = $wt. Work only inside it; never change files outside it."
  # it starts in the owner's working copy: the guard keeps the edit tools out of it only with
  # COORD_PROTECTED_ROOT in the safety file's env (a notice, not a failure)
  grep -Eq '"COORD_PROTECTED_ROOT"[[:space:]]*:[[:space:]]*"[^"]' "$safety" ||
    notice="notice: COORD_PROTECTED_ROOT is not set in $safety: edit tools can reach the working copy (TOOLKIT Safety)"
else
  # launched outside the repository (its root not trusted): EnterWorktree into another repository's
  # worktree asks for permission and the session would wait, so it works there by absolute path
  first="YOUR WORKING COPY is $wt, a worktree of $root. Work in it by absolute path (git -C $wt ..., files under $wt); do not use EnterWorktree; never change files outside it."
fi
if [ -n "$asst" ]; then first="$first
Questions to: the session named \"$report\" (SendMessage) - only what your folder, the run log and the journal do not hold."
else first="$first
Report to: the session named \"$report\" (SendMessage) - your report and your questions."; fi
# the role from the name (#<task> <role>: <title>): a session is not a subagent, so its role file's body
# heads the brief (TOOLKIT Roles) - from this core's roles/, unless the brief already carries it
role="$(printf '%s' "$name" | sed -n 's/^\(#[^ ]* \)\{0,1\}\([a-z]*\):.*/\2/p')"
rolef="$(dirname "$0")/../roles/$role.md" roletext="" rolemsg=""
if [ -n "$role" ] && [ -f "$rolef" ]; then
  body="$(awk 'NR == 1 && /^---/ { f = 1; next } f && /^---/ { f = 0; next } !f' "$rolef")"
  key="$(printf '%s\n' "$body" | grep -m 1 . || true)"
  if [ -n "$key" ] && tr -d '\r' < "$brief" | grep -qF -- "$key"; then rolemsg="role $role: already in the brief"
  else roletext="$body"; rolemsg="role $role: roles/$role.md heads the brief"; fi
fi
# a lead's notes (sub-contracts, briefs, run notes, the tester's test copies, evidence) live beside its
# worktree, in <worktree>.lead/, where the project's own checks (test runners, linters) never read them (#310)
notes=""
if [ "$role" = lead ]; then
  notes="$wt.lead"
  # never a git working copy (a registered worktree, or a folder holding a .git entry): its files would be
  # mixed with the notes and lost at the cleanup - refused before anything is created
  nwc=""
  [ -e "$notes/.git" ] && nwc=1
  nc="$(fold "$notes")" np=""
  [ -d "$notes" ] && np="$(cd -P -- "$notes" 2>/dev/null && pwd -P)"
  command -v cygpath >/dev/null 2>&1 && { nc="$(fold "$(cygpath -m "$notes")")"; [ -z "$np" ] || np="$(cygpath -m "$np")"; }
  [ -z "$np" ] || np="$(fold "$np")"
  while IFS= read -r l; do
    case "$l" in "worktree "*) x="$(fold "${l#worktree }")"
      { [ "$x" = "$nc" ] || { [ -n "$np" ] && [ "$x" = "$np" ]; }; } && nwc=1 ;; esac
  done <<EOF
$(git -C "$root" worktree list --porcelain 2>/dev/null | tr -d '\r')
EOF
  [ -z "$nwc" ] || { echo "refused: the lead's notes path $notes is a git working copy (a worktree or a folder holding .git) - a notes folder never is one; move that worktree away or start the lead on another branch" >&2; exit 1; }
  # the one exception to "never change files outside it", right after the first line
  nl='
'
  first="${first%%"$nl"*}
Your notes folder: $notes - the one exception to \"never change files outside it\": beside your worktree, never inside it; your sub-contracts, briefs, run notes, the tester's test copies and evidence go there (roles/lead.md).
${first#*"$nl"}"
fi
full="$first

${roletext:+$roletext

}$(cat "$brief")"
# characters, not bytes, in any locale: UTF-8 continuation bytes are not counted
nchars="$(printf '%s' "$full" | LC_ALL=C tr -d '\200-\277' | wc -c | tr -d ' ')"
bd="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/coordinator/briefs"
# the session (a native program on Windows) reads the path it is given: C:/..., not /c/...
command -v cygpath >/dev/null 2>&1 && bd="$(cygpath -m "$bd")"
lfile=""
[ "$nchars" -le 24000 ] || lfile="$bd/launch-$(printf '%s' "${branch:-assistant-$aname}" | tr -c 'A-Za-z0-9._-' '-')-$(date +%Y%m%d-%H%M%S)-$$.md"

# The worktrees' folder stays out of its repository's git, like coordinator/ (INIT 3.4): a line in the
# local .git/info/exclude, never .gitignore - nothing the project's history, its team or a client sees.
wroot="${wtroot:-$root/.claude/worktrees}"
if [ -n "$asst" ]; then :   # an assistant creates nothing: no worktree, no exclude line
elif [ "$dry" = 1 ]; then
  echo "[dry-run] keep $wroot out of its repository's git (.git/info/exclude)"
else
  mkdir -p "$wroot"
  if prefix="$(git -C "$wroot" rev-parse --show-prefix 2>/dev/null)" && [ -n "$prefix" ] &&
     ! git -C "$wroot" check-ignore -q x; then
    common="$(git -C "$wroot" rev-parse --path-format=absolute --git-common-dir)"
    ex="$common/info/exclude"; mkdir -p "$common/info"
    # a file without a final newline would glue the new line to its last one (e.g. coordinator/)
    [ -s "$ex" ] && [ -n "$(tail -c 1 "$ex")" ] && printf '\n' >> "$ex"
    printf '/%s\n' "$prefix" >> "$ex" &&
      echo "added /$prefix to the repository's .git/info/exclude"
  fi
fi
# The coordinator's own state repository (<root>/coordinator, INIT 3.4) never shows in the project's git
# either: a project that got `git init` after coordinator/ existed has no line for it yet
if [ -z "$asst" ] && [ -e "$root/coordinator/.git" ] && ! git -C "$root" check-ignore -q coordinator/; then
  if [ "$dry" = 1 ]; then echo "[dry-run] add /coordinator/ to the repository's .git/info/exclude"
  else
    common="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)"
    ex="$common/info/exclude"; mkdir -p "$common/info"
    [ -s "$ex" ] && [ -n "$(tail -c 1 "$ex")" ] && printf '\n' >> "$ex"
    printf '/coordinator/\n' >> "$ex" &&
      echo "added /coordinator/ to the repository's .git/info/exclude"
  fi
fi
# An older lead kept its sub-contracts, briefs and run notes in <its worktree>/.lead/ (now beside it, #310),
# never committed: one line, which info/exclude applies to every worktree of the repository
if [ -z "$asst" ] && ! git -C "$root" check-ignore -q .lead/x; then
  if [ "$dry" = 1 ]; then echo "[dry-run] add /.lead/ to the repository's .git/info/exclude"
  else
    common="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)"
    ex="$common/info/exclude"; mkdir -p "$common/info"
    [ -s "$ex" ] && [ -n "$(tail -c 1 "$ex")" ] && printf '\n' >> "$ex"
    printf '/.lead/\n' >> "$ex" &&
      echo "added /.lead/ to the repository's .git/info/exclude"
  fi
fi

if [ -n "$asst" ]; then made="nothing (an assistant has no worktree or branch)"
elif [ -d "$wt" ]; then
  # only a worktree of this repository is reused; a stale folder there is refused, never entered
  wtop="$(git -C "$wt" rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$wtop" ] && [ "$(fold "$(cd "$wtop" && pwd -P)")" = "$(fold "$(cd "$wt" && pwd -P)")" ] &&
    [ "$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir)" = "$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)" ] ||
    { echo "$wt exists but is not a worktree of $root: remove or rename it first" >&2; exit 1; }
  # and only with this branch checked out (a folder in another letter case is the same folder)
  cur="$(git -C "$wt" symbolic-ref --short -q HEAD || true)"
  [ "$cur" = "$branch" ] || { echo "$wt has ${cur:-a detached HEAD} checked out, not $branch" >&2; exit 1; }
  echo "reusing worktree $wt"
  made="nothing new (the worktree $wt was reused)"
else
  if [ "$has_branch" = 1 ]; then made="the worktree $wt (on the existing branch $branch)"
  else made="the worktree $wt and the branch $branch"; fi
  # with a tester's commit, git's own "HEAD is now at <sha>" is left out: the line above names the commit
  wq=(); [ -z "$tfull" ] || wq=(-q)
  if [ "$has_branch" = 1 ]; then run git -C "$root" worktree add ${wq[@]+"${wq[@]}"} "$wt" "$branch"
  else run git -C "$root" worktree add ${wq[@]+"${wq[@]}"} --no-track -b "$branch" "$wt" "$start"; fi
fi

# the lead's notes folder beside its worktree: made once, an existing one kept as it is
if [ -n "$notes" ]; then
  if [ "$dry" = 1 ]; then echo "[dry-run] create the notes folder $notes"
  elif [ -d "$notes" ]; then echo "notes folder: $notes (kept)"
  else
    mkdir -p "$notes" ||
      { echo "cannot create the notes folder $notes. Created: $made - clean it with cleanup-worker (--worktree $wt), or start again with the same branch" >&2; exit 1; }
    echo "notes folder: $notes"
  fi
fi
[ -z "$notice" ] || echo "$notice"
[ -z "$rolemsg" ] || echo "$rolemsg"
# conflict foresight (CORE §4a, #242): the open PRs changing what the brief's `touches` names - inline
# `touches: [a, b]` or a block list (`touches:` then one `- a` per line, as check-contract takes it, #258) -,
# printed for the coordinator, never a stop - for a worker or a lead (gh missing or failing: a notice)
case "$role" in worker|lead|"")
  # a comment needs a blank before it (docs/c#.md is a path); blank and comment lines inside the list are skipped
  tl="$(tr -d '\r' < "$brief" | awk '
    !on && /^[ \t]*touches:/ { s = $0; sub(/^[ \t]*touches:[ \t]*/, "", s); sub(/[ \t]+#.*$/, "", s); sub(/^#.*$/, "", s)
      if (s ~ /^\[/) { sub(/^\[/, "", s); sub(/\].*$/, "", s); print s; exit }
      if (s == "") { on = 1; next }
      exit }
    on && /^[ \t]*(#.*)?$/ { next }
    on && /^[ \t]*-[ \t]/ { s = $0; sub(/^[ \t]*-[ \t]*/, "", s); sub(/[ \t]+#.*$/, "", s); out = out (out == "" ? "" : ",") s; next }
    on { exit }
    END { if (on) print out }')"
  if [ -z "$(printf '%s' "$tl" | tr -d ' ,')" ]; then
    echo "foresight: no touches in the brief - check the open PRs against the task yourself (CORE §4a)"
  else
    ta=(); set -f; oifs="$IFS"; IFS=','
    for t in $tl; do t="$(printf '%s' "$t" | sed "s/^[[:space:]\"']*//; s/[[:space:]\"']*\$//")"; [ -z "$t" ] || ta+=(--touches "$t"); done
    IFS="$oifs"; set +f
    mq="$(cd "$(dirname "$0")" && pwd)/merge-queue.sh"
    if fo="$(cd "$root" && bash "$mq" status ${ta[@]+"${ta[@]}"} 2>&1)"; then
      printf '%s\n' "$fo" | grep -E '^(TOUCHES|merge-queue status:)' | sed 's/^/foresight: /' || true
    else echo "foresight: merge-queue status failed - check the open PRs against the task yourself (CORE §4a): $(printf '%s\n' "$fo" | head -n 1)"; fi
  fi ;;
esac
if [ "$dry" = 1 ]; then
  [ -z "$lfile" ] || echo "[dry-run] brief through a file: $nchars characters of launch text, over 24000 - it would go to $lfile and the first message would point to it"
  if [ -n "$asst" ]; then where="the folder $adir/, questions to \"$report\""; else where="working copy $wt, report to \"$report\""; fi
  echo "[dry-run] (cd $from && claude --bg --name \"$name\" --model $model${effort:+ --effort $effort} --permission-mode $mode --settings $safety <$where, ${roletext:+the role, }then the brief>)"
else
  msg="$full"
  if [ -n "$lfile" ]; then
    mkdir -p "$bd" && printf '%s\n' "$full" > "$lfile" ||
      { echo "launch not started: cannot write the brief file $lfile. Created: $made - clean it with cleanup-worker (--worktree $wt), or start again with the same branch" >&2; exit 1; }
    msg="Your brief is too long for the command line ($nchars characters), so it is in the file \"$lfile\". Before anything else, read that whole file with the Read tool (in parts with offset and limit if a read is cut short), then follow it as your brief: it holds your first action, your report address, your role and your task."
    echo "brief through a file: $nchars characters of launch text, over 24000 - the session's first message points to $lfile"
  fi
  # a launch that fails leaves the worktree and branch: say so, and how to clean them
  # an assistant's launch output is read for its id (`backgrounded · <id> · <name>`), then printed as it came
  bgo="$(mktemp "${TMPDIR:-/tmp}/start-worker-bg.XXXXXX")"
  lrc=0; ( cd "$from" && claude --bg --name "$name" --model "$model" ${eff[@]+"${eff[@]}"} --permission-mode "$mode" --settings "$safety" "$msg" ) > "$bgo" || lrc=$?
  cat "$bgo"; bgid="$(tr -d '\r' < "$bgo" | sed -n 's/.*backgrounded[^0-9A-Za-z]*\([0-9A-Za-z][0-9A-Za-z-]*\).*/\1/p' | head -n 1)"; rm -f "$bgo"
  [ "$lrc" = 0 ] ||
    { [ -z "$lfile" ] || rm -f "$lfile"
      if [ -n "$asst" ]; then echo "launch failed: claude --bg did not start the session. Created: $made - start again" >&2; exit 1; fi
      echo "launch failed: claude --bg did not start the session. Created: $made - clean it with cleanup-worker (--worktree $wt), or start again with the same branch" >&2; exit 1; }
  # wait (up to 20 s) until the new session is listed, so the subscribe below does not race it
  i=0
  # the listing is JSON: a backslash or a double quote in the name is escaped there
  jname="$(printf '%s' "$name" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  while [ "$i" -lt 20 ]; do
    claude agents --json 2>/dev/null | grep -qF "\"$jname\"" && break
    i=$((i + 1)); sleep 1
  done
  [ "$i" -lt 20 ] || echo "not listed after 20 s: if the subscribe fails, retry it in a few seconds" >&2
  # the brief as sent, kept by the session's id: hooks/after-compact.sh points the session back to it after
  # a compaction (a summary loses rules); briefs older than 14 days are pruned
  sid="$(claude agents --json 2>/dev/null | tr -d '\r\n' | tr '}' '\n' | grep -F "\"$jname\"" |
    sed -n 's/.*"sessionId": *"\([0-9a-fA-F-]*\)".*/\1/p' | tail -n 1)"
  if [ -n "$sid" ]; then
    mkdir -p "$bd" && printf '%s\n' "$full" > "$bd/$sid.md" && echo "brief kept for after a compaction: $bd/$sid.md"
    find "$bd" -name '*.md' -type f -mtime +14 -exec rm -f {} + 2>/dev/null || true
  else echo "no sessionId in the listing: the brief is not kept for after a compaction" >&2; fi
  if [ -n "$asst" ]; then
    echo "attach: claude attach \"$name\""
    [ -z "$bgid" ] || echo "attach: claude attach $bgid"
  fi
fi
echo "subscribe: SendMessage(to: \"$name\", notify_when_idle: true)"
