#!/usr/bin/env bash
# The scripted steps of the coordinator's self-test (procedures/SELFTEST.md; Windows: selftest.ps1 -
# the same steps and output). The steps with real sessions are run by the coordinator, not here - but
# for the guard's probe sessions, which `probes` starts and checks itself.
#   scripts/selftest.sh scripts                      1: the core's checks and scripts on fixtures
#   scripts/selftest.sh env [--repo <owner/name>]    2: claude, git and gh versions; read-only GitHub
# In a project (procedures/SELFTEST.md, the normal case) - the state repository, evidence kept:
#   scripts/selftest.sh prepare --project <root> --state <coordinator dir> --core <commit>
#                                                    3: the project's git ignores .claude/worktrees;
#                                                       branch selftest/<commit>/base from the state branch,
#                                                       its worktree <root>/.claude/worktrees/selftest/<commit>/base
#   scripts/selftest.sh verify --project <root> --state <coordinator dir> --core <commit> [--state-repo <owner/name>]
#                                                    6: no session or worktree left; the evidence is there
#                                                       (base, st1 merged into it, the merged PR); nothing deleted
# The safety guard as Claude Code runs it (TOOLKIT Safety; a hook that fails to run blocks nothing):
#   scripts/selftest.sh hooks --settings <settings.json>   the guard hook's command: forward slashes, no $env:,
#                                                       no PowerShell shell that turns its exit 2 into 1;
#                                                       env COORD_PROTECTED_ROOT: a folder, edit tools matched
#   scripts/selftest.sh hookcheck --session <id> [--expect edit|probe]   a session told to push to main
#                                                       (edit: to Write into the protected root; probe: to echo
#                                                       the probe token): its transcript shows the block, not
#                                                       a non-blocking hook error
#   scripts/selftest.sh probes --project <root> [--worker-settings <file>] [--own] [--edit-root <root>]
#                          [--model <m>] [--timeout <s>]   2a: the probe sessions, started from <root> and
#                                                       checked as hookcheck does: push (the worker file),
#                                                       push (own settings), edit (a Write into <root>); a
#                                                       token in <root>/.claude/coordinator-probe.txt for
#                                                       the run only; each stopped (step 6 removes it).
#                                                       Model haiku, timeout 300 s by default
# For the core itself (the maintainer, CI) - a sandbox, kept between runs or removed:
#   scripts/selftest.sh sandbox [--in <folder>]      3: a repository with a local bare origin,
#                                                       at <folder>/coordinator-selftest (default: home): a fixed
#                                                       path, so the owner trusts its repo once per machine;
#                                                       a sandbox kept by clean --keep is reused
#   scripts/selftest.sh clean --sandbox <dir> [--keep] [--state-repo <owner/name>]
#                                                    6: no worktree, branch, session or selftest/* branch
#                                                       left; then the sandbox folder is removed - or, with
#                                                       --keep, kept: only main, at the sandbox's first commit
# Prints `PASS|FAIL|SKIP <step>: <what>` per check, then `selftest <step>: <p> pass, <f> fail, <s> skipped`;
# probes also `BLOCKED <session name> (launch failed: <its first output line>)`, then `, <b> blocked`.
# Exit 1 on any FAIL or BLOCKED, 2 on a usage error.
set -u
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/.." && pwd)"
usage() { sed -n '2,42s/^# \{0,1\}//p' "$0"; exit 2; }
[ $# -gt 0 ] || usage
step="$1"; shift
p=0; f=0; s=0; nb=0
pass() { echo "PASS $step: $1"; p=$((p + 1)); }
fail() { echo "FAIL $step: $1"; f=$((f + 1)); }
skip() { echo "SKIP $step: $1"; s=$((s + 1)); }
finish() {
  if [ "$nb" -gt 0 ]; then echo "selftest $step: $p pass, $f fail, $s skipped, $nb blocked"; exit 1; fi
  echo "selftest $step: $p pass, $f fail, $s skipped"; [ "$f" -eq 0 ] || exit 1; exit 0
}
# check <what> -- command...: PASS when it exits 0
check() { local what="$1"; shift 2; if "$@" >/dev/null 2>&1; then pass "$what"; else fail "$what"; fi; }
g() { git -c user.email=selftest@localhost -c user.name=selftest "$@"; }
marker=".coordinator-selftest"
# the sandbox's first commit, which sandbox records in the marker as `initial <commit>` (outside the
# repository, where no git command in the sandbox can move it); empty for a sandbox from an older core
initial() { tr -d '\r' < "$1/$marker" 2>/dev/null | sed -n 's/^initial \([0-9a-f]\{40,\}\)$/\1/p' | head -n 1; }
# the untracked and ignored files of a repository, except .claude/settings.local.json: the permissions
# the owner gave its sessions there, kept with the sandbox like the trust
untracked() { git -C "$1" status --porcelain --ignored --untracked-files=all | grep -v -x -e '?? .claude/settings.local.json' -e '!! .claude/settings.local.json'; }
# kept_why <sandbox>: nothing when it is a kept sandbox ready for the next run (only main, at the first
# commit, in the repo and in its origin; no worktree; nothing untracked), else why it is not
kept_why() {
  local d="$1" r="$1/repo" i
  i="$(initial "$d")"
  [ -n "$i" ] || { echo "no first commit recorded in its $marker"; return; }
  [ "$(git -C "$r" rev-parse --git-dir 2>/dev/null)" = .git ] &&
    [ "$(git -C "$d/remote.git" rev-parse --is-bare-repository 2>/dev/null)" = true ] ||
    { echo "no repo and remote.git"; return; }
  [ "$(git -C "$r" worktree list --porcelain | grep -c '^worktree ')" -le 1 ] || { echo "worktrees left"; return; }
  [ "$(git -C "$r" for-each-ref --format='%(refname)' refs/heads)" = refs/heads/main ] &&
    [ "$(git -C "$d/remote.git" for-each-ref --format='%(refname)' refs/heads)" = refs/heads/main ] ||
    { echo "branches other than main"; return; }
  [ "$(git -C "$r" symbolic-ref -q HEAD)" = refs/heads/main ] && [ "$(git -C "$r" rev-parse -q --verify refs/heads/main)" = "$i" ] &&
    [ "$(git -C "$d/remote.git" rev-parse -q --verify refs/heads/main)" = "$i" ] || { echo "main is not at the first commit"; return; }
  [ -z "$(untracked "$r")" ] || echo "changed or untracked files in the repo"
}
# abspath <dir>: the folder as an absolute path (Windows: C:/..., as cygpath -m gives it, not the shell's
# /c/... or /tmp/...); as given when it cannot be entered
abspath() {
  local a
  a="$(cd "$1" 2>/dev/null && pwd)" || { printf '%s\n' "$1"; return; }
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$a"; else printf '%s\n' "$a"; fi
}
# physpath <dir>: the same folder as it lies on disk (links resolved, cd -P), nothing when it cannot be
# entered: a run's session lists its cwd in that form (/private/tmp, not /tmp, on macOS)
physpath() {
  local a
  a="$(cd -P "$1" 2>/dev/null && pwd -P)" || return 0
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$a"; else printf '%s\n' "$a"; fi
}
# own_roots <project> <state>: the folders whose sessions are this run's, one per line - the project root
# and the state repository (their .claude/worktrees are inside them) and the worktree roots the state
# repository's PROJECT.md names (its Settings row "Worktree roots", read as the retro reads it: relative
# to the root, split by , or ;; none / - / <fill> for none)
own_roots() {
  local b w x
  b="$(abspath "$1" | tr '\\' '/')"; b="${b%/}"
  printf '%s\n' "$b"; physpath "$1"; abspath "$2"; physpath "$2"
  [ -f "$2/PROJECT.md" ] || return 0
  LC_ALL=C awk -F '|' '{ sub(/\r$/, "") }
    $2 ~ /^[ \t]*[*]*Worktree roots[*]*[ \t]*$/ { v = $3; gsub(/`/, "", v); n = split(v, a, /[,;]/)
      for (i = 1; i <= n; i++) { x = a[i]; sub(/^[ \t]+/, "", x); sub(/[ \t]+$/, "", x); y = tolower(x)
        if (x != "" && x != "-" && y != "none" && y != "n/a" && x !~ /^<.*>$/) print x } }' "$2/PROJECT.md" |
  while IFS= read -r w; do
    w="$(printf '%s' "$w" | tr '\\' '/')"
    case "$w" in
      /* | [A-Za-z]:*) ;;
      *) x="$b"
         while :; do case "$w" in ../*) x="${x%/*}"; w="${w#../}" ;; ./*) w="${w#./}" ;; ..) x="${x%/*}"; w="" ;; *) break ;; esac; done
         w="$x${w:+/$w}" ;;
    esac
    printf '%s\n' "$w"; physpath "$w"
  done
}
# st_sessions <folders>: the self-test sessions claude agents --json --all still lists, in any state (a
# done one too): a name with `selftest` or `probe:`, or starting with `#st`. One whose cwd is one of the
# folders (one per line) or inside it is this run's: `O <name> (<id>)`; one elsewhere (another project
# self-testing on this machine, #158) or without a cwd is not: `F <id> (<cwd>)`. Paths are compared with
# \ read as /, repeated / as one, in lower case, C:/x as /c/x, without a trailing /
st_sessions() {
  claude agents --json --all 2>/dev/null | tr -d '\r\n' | tr '}' '\n' | ROOTS="$1" LC_ALL=C awk '
    function norm(p) { gsub(/\\/, "/", p); gsub(/\/+/, "/", p); p = tolower(p)
      if (p ~ /^[a-z]:(\/|$)/) p = "/" substr(p, 1, 1) substr(p, 3)
      sub(/\/$/, "", p); return p }
    # the value of a string field, its \\ read as one backslash
    function field(o, k,   v, i, r) { if (!match(o, "\"" k "\": *\"[^\"]*\"")) return ""
      v = substr(o, RSTART, RLENGTH); sub(/^"[A-Za-z]*": *"/, "", v); sub(/"$/, "", v); r = ""
      while ((i = index(v, "\\")) > 0) { r = r substr(v, 1, i); v = substr(v, i + 1); if (substr(v, 1, 1) == "\\") v = substr(v, 2) }
      return r v }
    function inside(c,   i) { if (c == "") return 0; c = norm(c)
      for (i = 1; i <= nr; i++) if (c == R[i] || substr(c, 1, length(R[i]) + 1) == R[i] "/") return 1
      return 0 }
    BEGIN { m = split(ENVIRON["ROOTS"], A, "\n"); nr = 0; for (i = 1; i <= m; i++) if (A[i] != "") R[++nr] = norm(A[i]) }
    { nm = field($0, "name"); if (nm !~ /^#st/ && !index(nm, "selftest") && !index(nm, "probe:")) next
      c = field($0, "cwd"); id = field($0, "id")
      if (inside(c)) print "O " nm " (" id ")"; else print "F " id " (" (c == "" ? "no cwd" : c) ")" }'
}
# sessions <folders>: the session check of verify and clean; another folder's self-test sessions are
# named (SKIP foreign ...), never counted and never advised for removal
sessions() {
  local x n
  if ! command -v claude >/dev/null 2>&1; then skip "no claude: sessions not checked"; return; fi
  x="$(st_sessions "$1")"
  printf '%s\n' "$x" | sed -n 's/^F /SKIP foreign self-test session /p'
  n="$(printf '%s\n' "$x" | sed -n 's/^O //p' | awk 'NR > 1 { printf ", " } { printf "%s", $0 }')"
  [ -z "$n" ] && pass "no self-test session left" || fail "sessions left (in step 6's order: claude stop <id>, read its cost, delete its status file, claude rm <id>): $n"
}
# find_tx <id>: the transcript of the session whose id starts with <id>, in $tx; else exit 1 (none yet)
# or 2 (a pattern or path character in the id, or several transcripts: names none) with why in $tx
find_tx() {
  local all
  # the id is a prefix, not a pattern; a prefix of several sessions names none of them
  case "$1" in *[][*?/\\]*) tx="the session id $1 holds a pattern or path character"; return 2 ;; esac
  all="$(find "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects" -maxdepth 2 -name "$1*.jsonl" 2>/dev/null)"
  [ -n "$all" ] || { tx="no transcript for session $1"; return 1; }
  if [ "$(printf '%s\n' "$all" | wc -l | tr -d ' ')" -gt 1 ]; then
    tx="ambiguous session $1: $(printf '%s\n' "$all" | sed 's|.*/||; s|\.jsonl$||' | LC_ALL=C sort | paste -sd ' ' -)"; return 2
  fi
  tx="$all"
}
# the folder whose projects/ holds the transcripts, as find_tx reads it (C:/... in Git Bash)
cfgdir() {
  local d="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$d"; else printf '%s\n' "$d"; fi
}
# fsig <file>: its size and git hash (the bytes as they are, no filters)
fsig() { printf '%s %s\n' "$(wc -c < "$1" | tr -d ' ')" "$(git hash-object --no-filters -- "$1" 2>/dev/null)"; }
# the guard's block of the probe token (hooks/safety-guard, #259)
probe_block="Blocked by safety-guard: the self-test's probe token (.claude/coordinator-probe.txt)"
# decided <transcript> <edit|probe>: whether a probe whose turn has not ended yet already shows its
# verdict - the block, a non-blocking error, or (edit) a write that went through
decided() {
  grep '"hook_non_blocking_error"' "$1" | grep -q 'safety-guard' && return 0
  if [ "$2" = edit ]; then grep -Eq "Blocked by safety-guard: the owner's working copy is never edited by a worker|File created successfully at|has been updated successfully" "$1"
  else grep '"tool_result"' "$1" | grep -qF "$probe_block"; fi
}
# verdict <transcript> <push|edit|probe> [<label>]: the PASS or FAIL line of a probe session, from its
# transcript (hookcheck and probes; <label>: before the message)
verdict() {
  local tf="$1" pre="${3:+$3: }"
  if grep '"hook_non_blocking_error"' "$tf" | grep -q 'safety-guard'; then
    fail "${pre}the guard blocked, but Claude Code got it as a non-blocking error: a shell wrapper turns exit 2 into 1"
  elif [ "$2" = edit ]; then
    # the edit probe: a Write into the root (COORD_PROTECTED_ROOT) - only the guard's working-copy
    # block counts, which it gives for Edit / Write / MultiEdit / NotebookEdit calls only
    if grep -q "Blocked by safety-guard: the owner's working copy is never edited by a worker" "$tf"; then
      pass "${pre}the edit tool's write into the working copy was blocked through Claude Code"
    elif grep -Eq 'File created successfully at|has been updated successfully' "$tf"; then
      fail "${pre}the write into the working copy went through: COORD_PROTECTED_ROOT is not in the settings' env, or its matcher leaves out the edit tools"
    else fail "${pre}no working-copy block in the transcript: the hook did not run (its matcher, COORD_PROTECTED_ROOT, or the settings were not loaded)"; fi
  elif [ "$2" = probe ]; then
    # the token probe: only the guard's block of the probe token, in a tool's result (not a message
    # quoting it), counts: the hook ran from that session's settings, through its shell, and exit 2 held
    if grep '"tool_result"' "$tf" | grep -qF "$probe_block"; then
      pass "${pre}the command holding the probe token was blocked through Claude Code"
    else fail "${pre}no block: the hook did not run from these settings, or it runs a guard older than this core (no probe-token rule)"; fi
  elif grep 'Blocked by safety-guard' "$tf" | grep -v "the owner's working copy is never edited" | grep -vqF "$probe_block"; then
    pass "${pre}the push to a protected branch was blocked through Claude Code"
  else fail "${pre}no block in the transcript: the hook did not run (its path, its shell, or the settings were not loaded)"; fi
}

case "$step" in
scripts)
  [ $# -eq 0 ] || usage
  t="$(mktemp -d)"; trap 'rm -r "$t"' EXIT
  # a local copy must not hold the core's CLAUDE.md: Claude Code loads it into every session that reads
  # the copy's files, telling workers they are the coordinator. Only the maintainer's own checkout has
  # .github/ (a project's copy leaves it out), so a copy made by git clone (with .git) counts too
  if [ -f "$core/CLAUDE.md" ] && [ ! -d "$core/.github" ]; then
    fail "the local core copy holds CLAUDE.md: remove it (it tells every worker it is the coordinator)"
  else pass "no CLAUDE.md in a local core copy"; fi
  check "check-core" -- bash "$core/scripts/check-core.sh" "$core"
  check "check-scripts" -- bash "$core/scripts/check-scripts.sh" "$core/scripts"
  check "check-contract on the fixture" -- bash "$core/scripts/check-contract.sh" "$core/tests/selftest/contract.md"
  if command -v jq >/dev/null 2>&1; then
    out="$(CLAUDE_CONFIG_DIR="$t" bash "$core/scripts/statusline.sh" < "$core/tests/selftest/status.json")"
    case "$out" in *"5h 14%"*"week 92%"*) [ -f "$t/coordinator/sessions/selftest-fixture.json" ] &&
      pass "statusline" || fail "statusline: no session file" ;; *) fail "statusline: printed '$out'" ;; esac
  else skip "statusline: no jq (the .sh needs it for its line, TOOLKIT Scripts)"; fi
  out="$(CLAUDE_CONFIG_DIR="$core/tests/session-tokens/claude" bash "$core/scripts/session-tokens.sh" s1)"
  if [ "$out" = "$(tr -d '\r' < "$core/tests/session-tokens/expected.txt")" ]; then pass "session-tokens"
  else fail "session-tokens: differs from tests/session-tokens/expected.txt"; fi
  hook() { printf '{"tool_input":{"command":"%s"}}' "$1" | bash "$core/scripts/hooks/safety-guard.sh" >/dev/null 2>&1; echo $?; }
  [ "$(bash "$core/scripts/hooks/safety-guard.sh" --self-test)" = "safety-guard: OK" ] &&
    pass "safety-guard self-test" || fail "safety-guard self-test"
  [ "$(hook 'git push -u origin selftest/task-1')" = 0 ] && pass "safety-guard allows selftest/*" ||
    fail "safety-guard blocks selftest/*"
  [ "$(hook 'git push origin main')" = 2 ] && [ "$(hook 'git push origin master')" = 2 ] &&
    pass "safety-guard blocks main and master" || fail "safety-guard lets a push to main or master through"
  finish ;;

env)
  repo=""
  while [ $# -gt 0 ]; do case "$1" in --repo) [ $# -ge 2 ] || usage; repo="$2"; shift 2 ;; *) usage ;; esac; done
  for c in claude git; do
    if v="$($c --version 2>/dev/null | head -n 1 | sed "s/^$c version //")" && [ -n "$v" ]; then pass "$c $v"; else fail "$c not found"; fi
  done
  if v="$(gh --version 2>/dev/null | head -n 1 | sed "s/^gh version //")" && [ -n "$v" ]; then pass "gh $v"
  else skip "gh not installed: no PR flow"; repo=""; fi
  if [ -z "$repo" ]; then skip "GitHub: n/a (no --repo)"
  else
    check "gh auth status" -- gh auth status
    check "gh repo view $repo" -- gh repo view "$repo" --json name
    check "gh pr list $repo" -- gh pr list -R "$repo" -L 1
  fi
  finish ;;

sandbox)
  in="$HOME"
  while [ $# -gt 0 ]; do case "$1" in --in) [ $# -ge 2 ] || usage; in="$2"; shift 2 ;; *) usage ;; esac; done
  [ -d "$in" ] || { fail "no folder $in"; finish; }
  # a relative --in made absolute: the repo's origin URL is stored from it, and a relative one breaks
  # every git command run from another folder (a reused sandbox's fetch); an absolute one is kept as given
  case "$in" in /*|[A-Za-z]:[/\\]*) ;; *) in="$(cd "$in" && pwd)" || { fail "cannot enter $in"; finish; } ;; esac
  d="${in%/}/coordinator-selftest"
  if [ -e "$d" ]; then
    # a sandbox kept by clean --keep is reused (its repo's path keeps the owner's trust); nothing else is
    [ -f "$d/$marker" ] || { fail "$d already exists and is not a self-test sandbox (no $marker): nothing changed"; finish; }
    why="$(kept_why "$d")"
    [ -z "$why" ] || { fail "$d already exists and is not clean ($why): run selftest clean --sandbox $d [--keep] first"; finish; }
    pass "reusing the kept sandbox $d"
  else
    mkdir "$d" || { fail "cannot create $d"; finish; }
    : > "$d/$marker"
    if git init -q --bare "$d/remote.git" && git -C "$d/remote.git" symbolic-ref HEAD refs/heads/main &&
       git init -q "$d/repo" && git -C "$d/repo" symbolic-ref HEAD refs/heads/main &&
       printf 'Coordinator self-test sandbox: reset or removed by `selftest clean`.\n' > "$d/repo/README.md" &&
       git -C "$d/repo" add README.md && g -C "$d/repo" commit -q -m "selftest: sandbox" &&
       git -C "$d/repo" remote add origin "$d/remote.git" && git -C "$d/repo" push -q -u origin main 2>/dev/null &&
       printf 'initial %s\n' "$(git -C "$d/repo" rev-parse HEAD)" > "$d/$marker"
    then pass "repository with a local bare origin, branch main"
    else fail "could not set up the repositories"; fi
  fi
  echo "sandbox: $d"
  echo "started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  finish ;;

clean)
  d="" state="" keep=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --sandbox) [ $# -ge 2 ] || usage; d="$2"; shift 2 ;;
      --state-repo) [ $# -ge 2 ] || usage; state="$2"; shift 2 ;;
      --keep) keep=1; shift ;;
      *) usage ;;
    esac
  done
  [ -n "$d" ] || usage
  [ -f "$d/$marker" ] || { fail "$d is not a self-test sandbox (no $marker): nothing removed"; finish; }
  r="$d/repo"
  if [ -n "$keep" ]; then
    # --keep resets the sandbox to its first commit (the marker records it), so it needs both repositories
    i="$(initial "$d")"
    if [ -z "$i" ]; then
      # a sandbox kept by an older core records no first commit: main's single root commit, when its
      # origin has it too, is that commit - recorded now, so the sandbox is reset and kept, not removed
      i="$(git -C "$r" rev-list --max-parents=0 main 2>/dev/null)"
      if [ -n "$i" ] && [ "$(printf '%s\n' "$i" | wc -l | tr -d ' ')" = 1 ] &&
         git -C "$d/remote.git" cat-file -e "$i^{commit}" 2>/dev/null; then
        printf 'initial %s\n' "$i" > "$d/$marker" &&
          pass "recorded the first commit $(git -C "$r" rev-parse --short "$i") of a sandbox from an older core" ||
          { fail "cannot write $d/$marker"; finish; }
      else
        fail "no first commit recorded in $d/$marker and none found (a sandbox from an older core): run selftest clean --sandbox $d without --keep"; finish
      fi
    fi
    [ "$(git -C "$r" rev-parse --git-dir 2>/dev/null)" = .git ] &&
      [ "$(git -C "$d/remote.git" rev-parse --is-bare-repository 2>/dev/null)" = true ] &&
      git -C "$r" cat-file -e "$i^{commit}" 2>/dev/null ||
      { fail "$d has no repo and remote.git with its first commit $i: nothing changed"; finish; }
  fi
  # worktrees (the first one listed is the repository itself): removed only when clean and merged into main
  git -C "$r" worktree list --porcelain | sed -n 's/^worktree //p' | tail -n +2 | while IFS= read -r w; do
    [ -z "$(git -C "$w" status --porcelain 2>/dev/null)" ] &&
      git -C "$r" merge-base --is-ancestor "$(git -C "$w" rev-parse HEAD)" main &&
      git -C "$r" worktree remove "$w"
  done
  left="$(git -C "$r" worktree list --porcelain | grep -c '^worktree ')"
  [ "$left" -le 1 ] && pass "no worktree left" || fail "$((left - 1)) worktree(s) left: not clean or not merged into main"
  for b in $(git -C "$r" for-each-ref --format='%(refname:short)' refs/heads); do
    [ "$b" = main ] && continue
    git -C "$r" merge-base --is-ancestor "$b" main && git -C "$r" branch -q -d "$b"
  done
  b="$(git -C "$r" for-each-ref --format='%(refname:short)' refs/heads | grep -v '^main$')"
  [ -z "$b" ] && pass "no branch left" || fail "branches not merged into main: $(echo $b)"
  # the origin's branches go too (deleted by --keep, removed with the folder otherwise), so each must be
  # merged into the repo's main (the guard blocks pushing main: the origin's own main may lag behind)
  b=""
  [ -d "$d/remote.git" ] && for x in $(git -C "$d/remote.git" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null); do
    [ "$x" = main ] && continue
    git -C "$r" merge-base --is-ancestor "$(git -C "$d/remote.git" rev-parse "refs/heads/$x")" main 2>/dev/null || b="$b $x"
  done
  [ -z "$b" ] && pass "every branch on the origin is merged into main" || fail "branches on the origin not merged into main:$b"
  sessions "$(abspath "$d"; physpath "$d")"
  if [ -n "$state" ]; then
    if n="$(gh api "repos/$state/branches" --paginate --jq '.[].name' 2>/dev/null)"; then
      n="$(printf '%s\n' "$n" | grep '^selftest/')"
      [ -z "$n" ] && pass "no selftest/* branch on $state" || fail "branches left on ${state}: $(echo $n)"
    else fail "cannot list the branches of $state"; fi
  else skip "state repository: not checked (no --state-repo)"; fi
  if [ "$f" -ne 0 ]; then echo "sandbox kept for inspection: $d"
  elif [ -n "$keep" ]; then
    # the folder, its marker, the repo's path (Claude Code trusts a folder by its path) and the origin
    # stay; every other branch goes, main of both goes back to the first commit, untracked files go
    # (git clean on the repo only)
    for x in $(git -C "$d/remote.git" for-each-ref --format='%(refname)' refs/heads); do
      [ "$x" = refs/heads/main ] || git -C "$d/remote.git" update-ref -d "$x"
    done
    ok=""; git -C "$d/remote.git" update-ref refs/heads/main "$i" && git -C "$d/remote.git" symbolic-ref HEAD refs/heads/main &&
      git -C "$r" checkout -q -f main 2>/dev/null && git -C "$r" reset -q --hard "$i" &&
      git -C "$r" fetch -q --prune origin 2>/dev/null && git -C "$r" worktree prune &&
      git -C "$r" clean -q -ffdx -e .claude/settings.local.json && ok=1
    why="$(kept_why "$d")"; [ -n "$ok" ] || why="${why:-a git command failed}"
    if [ -z "$why" ]; then
      pass "only main, at the first commit $(git -C "$r" rev-parse --short "$i"), in the repo and its origin; nothing untracked"
      echo "sandbox kept for the next run: $d"
    else fail "could not reset $d: $why"; fi
  else
    chmod -R u+w "$d" && rm -r "$d" && pass "sandbox removed" || fail "could not remove $d"
  fi
  finish ;;

hooks)
  file=""
  while [ $# -gt 0 ]; do case "$1" in --settings) [ $# -ge 2 ] || usage; file="$2"; shift 2 ;; *) usage ;; esac; done
  [ -n "$file" ] || usage
  [ -f "$file" ] || { fail "no settings file $file"; finish; }
  # The file is read as JSON, as Claude Code loads it (jq when present, else a small reader in awk, as in
  # hooks/safety-guard.sh): a file that is not valid JSON is not loaded at all. Both print the guard's
  # PreToolUse hook - the first hook whose command names safety-guard. and is not its self-test
  # (-SelfTest / --self-test) - as four lines: its command (line breaks and tabs as spaces), its
  # "shell", its "onFailure", and the "matcher" of its own entry (empty when there is none).
  hook_jq='[ .hooks | objects | .PreToolUse | arrays | .[] | objects | . as $v | .hooks | arrays | .[] | objects
    | select((.command | type) == "string") | select(.command | test("safety-guard\\."; "i"))
    | select(.command | test("-selftest|--self-test"; "i") | not)
    | [ (.command | gsub("[\n\r\t]"; " ")), (.shell | strings // ""), (.onFailure | strings // ""), ($v.matcher | strings // "") ] ]
    | first // empty | .[]'
  hook_awk='
  function ws() { while (i <= n && index(" \t\r\n", substr(s, i, 1))) i++ }
  # a string at i: moves i past it and returns its raw body (escapes kept), or "\001" when it is not one
  function str(    r) {
    r = substr(s, i)
    if (!match(r, /^"([^"\\]|\\["\\\/bfnrt]|\\u[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])*"/)) return "\001"
    i += RLENGTH; return substr(r, 2, RLENGTH - 2)
  }
  # the decoded text of a raw string: line breaks and tabs as spaces, a \u escape past ASCII as "?"
  function dec(x,    m, P, k, p, c, o, v, h, j) {
    m = split(x, P, "\\"); o = P[1]
    for (k = 2; k <= m; k++) {
      p = P[k]
      if (p == "") { o = o "\\"; k++; if (k <= m) o = o P[k]; continue }
      c = substr(p, 1, 1); p = substr(p, 2)
      if (c == "n" || c == "t" || c == "r" || c == "b" || c == "f") c = " "
      else if (c == "u") {
        v = 0; h = tolower(substr(p, 1, 4)); p = substr(p, 5)
        for (j = 1; j <= 4; j++) v = v * 16 + index("0123456789abcdef", substr(h, j, 1)) - 1
        c = (v >= 32 && v < 127) ? sprintf("%c", v) : (v == 9 || v == 10 || v == 13) ? " " : "?"
      }
      o = o c p
    }
    gsub(/[\t\r\n]/, " ", o); return o
  }
  # a string under hooks.PreToolUse[e]: the entry'"'"'s matcher, or a hook'"'"'s command, shell or onFailure
  function keep(path, v,    m, e, h) {
    m = split(path, P, SUBSEP)
    if (m == 3 && P[2] == "env" && P[3] == "COORD_PROTECTED_ROOT") { R = v; return }
    if (m == 3 && P[2] == "env" && P[3] == "COORD_PROTECTED_BRANCHES") { B = v; return }
    if (m < 5 || P[2] != "hooks" || P[3] != "PreToolUse" || substr(P[4], 1, 1) != "\001") return
    e = substr(P[4], 2) + 0
    if (m == 5 && P[5] == "matcher") M[e] = v
    else if (m == 7 && P[5] == "hooks" && substr(P[6], 1, 1) == "\001") {
      h = substr(P[6], 2) + 0
      if (P[7] == "command") {
        C[e, h] = v
        if (ge == "" && tolower(v) ~ /safety-guard\./ && tolower(v) !~ /-selftest|--self-test/) { ge = e; gh = h }
      } else if (P[7] == "shell") S[e, h] = v
      else if (P[7] == "onFailure") F[e, h] = v
    }
  }
  # one JSON value at i; path: the keys and array indexes ("\001" n) leading to it. 0: not JSON
  function val(path,    c, k, j) {
    ws(); c = substr(s, i, 1)
    if (c == "{" || c == "[") {
      i++; ws()
      if (substr(s, i, 1) == ((c == "{") ? "}" : "]")) { i++; return 1 }
      j = 0
      while (1) {
        if (c == "{") {
          ws(); if (substr(s, i, 1) != "\"") return 0
          k = str(); if (k == "\001") return 0
          ws(); if (substr(s, i, 1) != ":") return 0
          i++; if (!val(path SUBSEP dec(k))) return 0
        } else { if (!val(path SUBSEP "\001" j)) return 0; j++ }
        ws(); k = substr(s, i, 1); i++
        if (k == ((c == "{") ? "}" : "]")) return 1
        if (k != ",") return 0
      }
    }
    if (c == "\"") { k = str(); if (k == "\001") return 0; keep(path, dec(k)); return 1 }
    if (match(substr(s, i, 64), /^(-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?|true|false|null)/)) { i += RLENGTH; return 1 }
    return 0
  }
  { all = (NR > 1) ? all "\n" $0 : $0 }
  END {
    s = all; n = length(s); i = 1; ge = ""; R = ""; B = ""
    ws(); if (substr(s, i, 1) != "{" || !val("")) exit 3
    ws(); if (i <= n) exit 3
    if (ge != "") { print C[ge, gh]; print S[ge, gh]; print F[ge, gh]; print M[ge]; print R; print B }
  }'
  # a UTF-8 BOM before the JSON is dropped
  json="$(B="$(printf '\357\273\277')" awk 'NR == 1 && index($0, ENVIRON["B"]) == 1 { $0 = substr($0, length(ENVIRON["B"]) + 1) } { print }' "$file")"
  ok="" g="" root="" pbs=""
  if command -v jq >/dev/null 2>&1; then
    printf '%s\n' "$json" | jq -e -s 'length == 1 and (.[0] | type == "object")' >/dev/null 2>&1 &&
      g="$(printf '%s\n' "$json" | jq -r "$hook_jq")" && ok=1
    # env.COORD_PROTECTED_ROOT: the owner's working copy, kept from edit tools (TOOLKIT Safety)
    [ -n "$ok" ] && root="$(printf '%s\n' "$json" | jq -r '.env | objects | .COORD_PROTECTED_ROOT | strings | gsub("[\n\r\t]"; " ")')"
    # env.COORD_PROTECTED_BRANCHES: the branches the guard protects (TOOLKIT Safety)
    [ -n "$ok" ] && pbs="$(printf '%s\n' "$json" | jq -r '.env | objects | .COORD_PROTECTED_BRANCHES | strings | gsub("[\n\r\t]"; " ")')"
  else
    g="$(printf '%s\n' "$json" | awk "$hook_awk")" && ok=1 && root="$(printf '%s\n' "$g" | sed -n 5p)" &&
      pbs="$(printf '%s\n' "$g" | sed -n 6p)"
  fi
  [ -n "$ok" ] || { fail "the settings file is not valid JSON (Claude Code would not load it)"; finish; }
  [ -n "$g" ] || { fail "no safety-guard hook in the file"; finish; }
  pass "a safety-guard hook"
  cmd="$(printf '%s\n' "$g" | sed -n 1p)"; shell="$(printf '%s\n' "$g" | sed -n 2p)"
  onfail="$(printf '%s\n' "$g" | sed -n 3p)"; m="$(printf '%s\n' "$g" | sed -n 4p)"
  # after JSON decoding a path backslash is a single \ (an escaped quote is just ")
  case "$cmd" in *\\*) fail "its path has backslashes: Git Bash drops them and the hook never runs" ;;
    *) pass "its path uses forward slashes" ;; esac
  case "$cmd" in *'$env:'*) fail 'its command uses $env: - bash reads it as $env and the path breaks' ;;
    *) pass 'no $env: in its command' ;; esac
  # an unquoted path must be one word: a space splits it and the hook never runs (letter case as in the .ps1)
  lc="$(printf '%s\n' "$cmd" | tr '[:upper:]' '[:lower:]')"
  if printf '%s\n' "$lc" | grep -Eq "\"[^\"]*safety-guard\.(sh|ps1)\"|'[^']*safety-guard\.(sh|ps1)'"; then pass "its path is quoted or has no space"
  else
    word="$(printf '%s\n' "$lc" | sed 's/safety-guard\..*//; s/.* //')"
    case "$word" in /*|[a-z]:*|'$'*|'~'*) pass "its path is quoted or has no space" ;;
      *) fail "its path has a space and is not quoted: the hook never runs" ;; esac
  fi
  if [ "$shell" = powershell ]; then
    case "$cmd" in *'exit $LASTEXITCODE'*) pass 'a PowerShell shell, with exit $LASTEXITCODE passing the block through' ;;
      *) fail 'a PowerShell shell without "; exit $LASTEXITCODE": the block (exit 2) reaches Claude Code as a non-blocking error (1)' ;; esac
  else pass "no PowerShell shell around it"; fi
  # its entry's matcher must take in the PowerShell tool too: none, "", "*" and ".*" match every tool
  case "$m" in ''|'*'|'.*'|*PowerShell*) pass "its matcher covers the PowerShell tool" ;;
    *) fail "its matcher leaves out PowerShell: the PowerShell tool runs unguarded" ;; esac
  # a hook that fails to run (a wrong path, a crash, a timeout) lets the call through unless it blocks on failure
  if [ "$onfail" = block ]; then pass 'onFailure "block": a guard that fails to run blocks'
  else fail 'no "onFailure": "block": a guard that fails to run lets every call through (Claude Code 2.1.295+)'; fi
  # SendMessage (CORE §1.17): the guard reads its `to` only when the matcher takes that tool in
  case "$m" in ''|'*'|'.*') pass "its matcher covers SendMessage" ;;
    *) if printf 'SendMessage\n' | grep -Eqx -- "$m" 2>/dev/null; then pass "its matcher covers SendMessage"
       else skip "its matcher leaves out SendMessage: a message to another project's session is not guarded (CORE 1.17)"; fi ;; esac
  # the owner's working copy (TOOLKIT Safety): with env COORD_PROTECTED_ROOT the guard keeps the edit
  # tools out of it - so the root is an absolute path to a folder here, and the matcher takes in each
  # edit tool (none, "", "*" and ".*" match every tool; otherwise the whole name must match it)
  if [ -z "$root" ]; then skip "COORD_PROTECTED_ROOT not set: the working copy is not protected from edit tools"
  else
    # on Windows Claude Code passes C:\... file paths, so the root is a drive path: C:/... or C:\..., or
    # Git Bash's /c/... (/mnt/c/..., /cygdrive/c/...), which the guard reads as C:/...
    win=0; case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) win=1 ;; esac
    dir="$root"; [ $win = 1 ] && dir="$(printf '%s' "$root" | sed -E 's#^/(mnt/|cygdrive/)?([A-Za-z])(/|$)#\2:/#')"
    case "$root" in
      /*|\\*|[A-Za-z]:[/\\]*)
        if [ $win = 1 ] && ! printf '%s' "$dir" | grep -Eq '^[A-Za-z]:[/\\]'; then
          fail "COORD_PROTECTED_ROOT is not a drive path (C:/... or C:\\...): $root - Claude Code passes C:\\... file paths on Windows"
        elif [ -d "$dir" ]; then pass "COORD_PROTECTED_ROOT is an absolute path to a folder"
        else fail "COORD_PROTECTED_ROOT is not a folder on this machine: $root"; fi ;;
      *) fail "COORD_PROTECTED_ROOT is not an absolute path: $root" ;;
    esac
    miss=""
    for t in Edit Write MultiEdit NotebookEdit; do
      case "$m" in ''|'*'|'.*') ;; *) printf '%s\n' "$t" | grep -Eqx -- "$m" 2>/dev/null || miss="$miss${miss:+, }$t" ;; esac
    done
    if [ -z "$miss" ]; then pass "its matcher covers Edit, Write, MultiEdit and NotebookEdit"
    else fail "its matcher leaves out $miss: those edit tools reach the working copy unguarded"; fi
  fi
  # the protected branches (TOOLKIT Safety): main, master and the names of env COORD_PROTECTED_BRANCHES
  # (split at spaces and / or commas, each once, letter case ignored). With names set, each protected
  # branch: a push to it, fed to this core's guard with the file's value, must be blocked as a push to
  # that protected branch
  names=(main master); shopt -s nocasematch; set -f
  for b in ${pbs//,/ }; do
    for x in "${names[@]}"; do case "$b" in "$x") continue 2 ;; esac; done
    names+=("$b")
  done
  set +f; shopt -u nocasematch
  if [ -z "$(printf '%s' "$pbs" | tr -d ', \t')" ]; then echo "protected branches: main master (default)"
  else
    echo "protected branches: ${names[*]}"
    # a neutral folder outside any repository: the probe must not depend on the branch this test runs on
    # (on a protected branch the guard would block every push as "push while on <branch>")
    nd="$(mktemp -d)"; ndj="$nd"; command -v cygpath >/dev/null 2>&1 && ndj="$(cygpath -m "$nd")"
    for b in "${names[@]}"; do
      err="$(cd "$nd" && printf '{"tool_input":{"command":"git push origin %s"},"cwd":"%s"}' "$b" "$ndj" |
        COORD_PROTECTED_BRANCHES="$pbs" bash "$core/scripts/hooks/safety-guard.sh" 2>&1 >/dev/null)"; rc=$?
      case "$rc:$err" in
        "2:Blocked by safety-guard: push to a protected branch ($b)."*) pass "the guard blocks a push to $b" ;;
        *) fail "the guard does not block a push to $b as a protected branch (exit $rc)" ;;
      esac
    done
    rmdir "$nd" 2>/dev/null
  fi
  finish ;;

hookcheck)
  id="" expect=push
  while [ $# -gt 0 ]; do
    case "$1" in
      --session) [ $# -ge 2 ] || usage; id="$2"; shift 2 ;;
      --expect) [ $# -ge 2 ] || usage; expect="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  [ -n "$id" ] || usage
  case "$expect" in push|edit|probe) ;; *) usage ;; esac
  find_tx "$id" || { fail "$tx"; finish; }
  verdict "$tx" "$expect"
  finish ;;

probes)
  project="" ws="" own="" er="" model=haiku tmo=300
  while [ $# -gt 0 ]; do
    case "$1" in
      --project) [ $# -ge 2 ] || usage; project="$2"; shift 2 ;;
      --worker-settings) [ $# -ge 2 ] || usage; ws="$2"; shift 2 ;;
      --own) own=1; shift ;;
      --edit-root) [ $# -ge 2 ] || usage; er="$2"; shift 2 ;;
      --model) [ $# -ge 2 ] && [ -n "$2" ] || usage; model="$2"; shift 2 ;;
      --timeout) [ $# -ge 2 ] || usage; tmo="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  # at least one probe; the edit probe runs with the worker safety file
  [ -n "$project" ] && [ -n "$ws$own$er" ] || usage
  [ -z "$er" ] || [ -n "$ws" ] || usage
  case "$tmo" in ''|*[!0-9]*) usage ;; esac
  [ "$tmo" -gt 0 ] || usage
  poll="${COORD_PROBE_POLL:-5}"; case "$poll" in ''|*[!0-9]*) poll=5 ;; esac
  [ -d "$project" ] || { fail "no folder $project"; finish; }
  pd="$(abspath "$project")"
  if [ -n "$ws" ]; then
    [ -f "$ws" ] || { fail "no settings file $ws"; finish; }
    ws="$(abspath "$(dirname "$ws")")/${ws##*/}"
  fi
  # the probes, in launch order: N session names, L labels, E what hookcheck expects, S --settings, P prompts
  N=(); L=(); E=(); S=(); P=(); n=0
  tok="coord-probe-$(date +%s)-$$$RANDOM$RANDOM"
  msg="Run exactly this one shell command: echo $tok
Then report in one line what happened to it, and stop. Do not run anything else."
  add() { N[$n]="$1"; L[$n]="$2"; E[$n]="$3"; S[$n]="$4"; P[$n]="$5"; n=$((n + 1)); }
  [ -z "$ws" ] || add "probe: push" push probe "$ws" "$msg"
  [ -z "$own" ] || add "probe: push (own settings)" "push (own settings)" probe "" "$msg"
  ef="" efold=""
  if [ -n "$er" ]; then
    while :; do case "$er" in ?*/|?*\\) er="${er%?}" ;; *) break ;; esac; done
    if [ -d "$er" ]; then
      er="$(abspath "$er")"
      # the probe's file; one there before the run is recorded (its size and git hash) and must be
      # left as it was
      ef="$er/probe-root.txt"
      [ -e "$ef" ] && efold="$(fsig "$ef")"
      add "probe: edit" edit edit "$ws" "Use the Write tool to create $ef containing x. Do not retry it another way. Report in one line what happened, and stop."
    else fail "edit: no folder $er"; fi
  fi
  [ "$n" -gt 0 ] || finish
  # one probes run per project at a time: a token file holding a valid token, younger than this run's
  # timeout + 60 s, is another run's (nothing launched, the file untouched); an older one is stale (a
  # run killed before its end) and overwritten
  tfile="$pd/.claude/coordinator-probe.txt"; I=(); D=(); T=(); stopped=""
  if [ -f "$tfile" ]; then
    old=""; IFS= read -r old < "$tfile" 2>/dev/null; old="${old%$'\r'}"; old="${old#$'\357\273\277'}"
    case "$old" in *[!A-Za-z0-9-]*) old="" ;; esac
    mt="$(stat -c %Y "$tfile" 2>/dev/null || stat -f %m "$tfile" 2>/dev/null)"
    case "$mt" in ''|*[!0-9]*) mt=0 ;; esac
    age=$(($(date +%s) - mt)); [ "$age" -ge 0 ] || age=0
    if [ ${#old} -ge 16 ] && [ "$age" -lt $((tmo + 60)) ]; then
      echo "BLOCKED probes: another probes run on this project (started $age s ago)"; nb=$((nb + 1)); finish
    fi
    echo "stale token file $tfile ($age s old: a run killed before its end): overwritten"
  fi
  mkc=""; [ -d "$pd/.claude" ] || mkc=1
  # the token, for this run only: removed on every way out (the end, a FAIL, Ctrl-C) while it still
  # holds this run's token, after the sessions are stopped; a .claude folder made for it goes too when
  # empty
  probes_end() {
    local k=0 cur=""
    if [ -z "$stopped" ]; then stopped=1
      while [ "$k" -lt "$n" ]; do [ -z "${I[$k]:-}" ] || claude stop "${I[$k]}" >/dev/null 2>&1; k=$((k + 1)); done
    fi
    [ -f "$tfile" ] && IFS= read -r cur < "$tfile" 2>/dev/null
    [ "${cur%$'\r'}" != "$tok" ] || rm -f "$tfile"
    [ -z "$mkc" ] || rmdir "$pd/.claude" 2>/dev/null
    return 0
  }
  trap probes_end EXIT; trap 'exit 130' INT TERM HUP
  mkdir -p "$pd/.claude" && printf '%s\n' "$tok" > "$tfile" || { fail "cannot write $tfile"; finish; }
  # all launched first, from the project root (trusted), then all waited for
  k=0
  while [ "$k" -lt "$n" ]; do
    if ! command -v claude >/dev/null 2>&1; then out="claude not found on PATH"; rc=1
    elif [ -n "${S[$k]}" ]; then out="$(cd "$pd" && claude --bg --name "${N[$k]}" --model "$model" --settings "${S[$k]}" "${P[$k]}" 2>&1)"; rc=$?
    else out="$(cd "$pd" && claude --bg --name "${N[$k]}" --model "$model" "${P[$k]}" 2>&1)"; rc=$?; fi
    # the short id, from the line `claude stop <id>   stop this session`
    I[$k]="$(printf '%s\n' "$out" | tr -d '\r' | sed -n 's/^.*claude stop \([A-Za-z0-9_-][A-Za-z0-9_-]*\).*$/\1/p' | head -n 1)"
    if [ "$rc" -ne 0 ] || [ -z "${I[$k]}" ]; then
      echo "BLOCKED ${N[$k]} (launch failed: $(printf '%s\n' "$out" | tr -d '\r' | awk 'NF { print; f = 1; exit } END { if (!f) print "no output, exit '"$rc"'" }'))"
      nb=$((nb + 1)); D[$k]=3
    else D[$k]=0; fi
    k=$((k + 1))
  done
  # each transcript polled until its turn ends (turn_duration) or the time is up
  t0="$(date +%s)"
  while :; do
    left=0; k=0
    while [ "$k" -lt "$n" ]; do
      if [ "${D[$k]}" = 0 ]; then
        find_tx "${I[$k]}"; rc=$?
        if [ "$rc" = 0 ] && grep -Eq '"subtype": *"turn_duration"' "$tx"; then D[$k]=1; T[$k]="$tx"
        elif [ "$rc" = 2 ]; then D[$k]=2; T[$k]="$tx"
        else left=$((left + 1)); fi
      fi
      k=$((k + 1))
    done
    [ "$left" -gt 0 ] && [ $(($(date +%s) - t0)) -lt "$tmo" ] || break
    sleep "$poll"
  done
  k=0
  while [ "$k" -lt "$n" ]; do
    case "${D[$k]}" in
      1) verdict "${T[$k]}" "${E[$k]}" "${L[$k]}" ;;
      2) fail "${L[$k]}: ${T[$k]}" ;;
      # the time is up: judged as the transcript stands when it already shows the verdict
      0) find_tx "${I[$k]}"; rc=$?
         if [ "$rc" = 0 ] && decided "$tx" "${E[$k]}"; then verdict "$tx" "${E[$k]}" "${L[$k]}"
         elif [ "$rc" = 0 ]; then fail "${L[$k]}: no answer within $tmo s"
         # no transcript at all: the session writes it somewhere else
         else fail "${L[$k]}: no transcript for session ${I[$k]} under $(cfgdir)/projects: the daemon may use another CLAUDE_CONFIG_DIR"; fi ;;
    esac
    k=$((k + 1))
  done
  # stopped; their cost is read and they are removed in step 6
  k=0; ids=""
  while [ "$k" -lt "$n" ]; do
    if [ -n "${I[$k]}" ]; then
      claude stop "${I[$k]}" >/dev/null 2>&1
      ids="$ids${ids:+, }${N[$k]} (${I[$k]})"
    fi
    k=$((k + 1))
  done
  stopped=1
  [ -z "$ids" ] || echo "stopped: $ids - step 6 reads their cost and removes them"
  # a probe-root.txt the edit probe created is removed - exactly that file; one there before the run
  # is never removed, and must be as it was
  if [ -n "$ef" ] && [ -z "$efold" ] && [ -f "$ef" ]; then
    rm -f "$ef" && echo "removed $ef, which the edit probe created" || fail "edit: could not remove $ef, which the edit probe created"
  elif [ -n "$efold" ]; then
    if [ -e "$ef" ] && [ "$(fsig "$ef")" = "$efold" ]; then echo "left as it was: $ef was there before the edit probe"
    else fail "edit: changed by the edit probe: $ef"; fi
  fi
  finish ;;

prepare|verify)
  project="" state="" c="" repo=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --project) [ $# -ge 2 ] || usage; project="$2"; shift 2 ;;
      --state) [ $# -ge 2 ] || usage; state="$2"; shift 2 ;;
      --core) [ $# -ge 2 ] || usage; c="$2"; shift 2 ;;
      --state-repo) [ "$step" = verify ] && [ $# -ge 2 ] || usage; repo="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  [ -n "$project" ] && [ -n "$state" ] && [ -n "$c" ] || usage
  git -C "$project" rev-parse --show-toplevel >/dev/null 2>&1 || { fail "not a git repository: $project"; finish; }
  git -C "$state" rev-parse --git-dir >/dev/null 2>&1 || { fail "no state repository at $state"; finish; }
  base="selftest/$c/base"; st1="selftest/$c/st1"
  if [ "$step" = prepare ]; then
    # the state repository's worktrees live under the project's trusted root; its git must not see them
    if git -C "$project" check-ignore -q .claude/worktrees/selftest; then pass "the project's git ignores .claude/worktrees"
    else
      ex="$(cd "$project" && git rev-parse --git-path info/exclude)"
      case "$ex" in /*|?:*) ;; *) ex="$project/$ex" ;; esac
      mkdir -p "$(dirname "$ex")" && printf '.claude/worktrees/\n' >> "$ex" &&
        git -C "$project" check-ignore -q .claude/worktrees/selftest && pass "added .claude/worktrees/ to the project's info/exclude" ||
        fail "the project's git does not ignore .claude/worktrees"
    fi
    # the record of the core's own failures (procedures/CORE-FINDINGS.md) in the template's format
    fnd="$state/CORE-FINDINGS.md"
    # its lines without CR and without a UTF-8 BOM (both are fine); UTF-16 (Windows PowerShell 5.1's
    # Out-File) is not read as text at all
    lines() { tr -d '\r' < "$fnd" | B="$(printf '\357\273\277')" awk 'NR == 1 && index($0, ENVIRON["B"]) == 1 { $0 = substr($0, length(ENVIRON["B"]) + 1) } { print }'; }
    if [ ! -f "$fnd" ]; then fail "no CORE-FINDINGS.md in the state repository (INIT 3.4, CORE-FINDINGS.template.md)"
    elif case "$(od -An -tx1 -N2 "$fnd" | tr -d ' \t\n')" in fffe|feff) true ;; *) false ;; esac; then
      fail "CORE-FINDINGS.md is not UTF-8 (re-save it as UTF-8)"
    elif ! lines | grep -qxF '| id | date | core | trigger | what happened (evidence) | workaround | status |'; then
      fail "CORE-FINDINGS.md lacks the template's table header"
    else
      # the status cell, case-sensitive; an empty one is unknown too
      bad="$(lines | awk -F'|' '/^\|/ && !/^\| id \|/ && !/^\|---/ { s = $(NF - 1); gsub(/^[ \t]+|[ \t]+$/, "", s); if (s !~ /^(new|discussed|sent|fixed|dropped|not core)/) print (s == "" ? "<empty>" : s) }' | head -n 1)"
      if [ -z "$bad" ]; then pass "CORE-FINDINGS.md in the template's format"; else fail "CORE-FINDINGS.md: unknown status '$bad'"; fi
    fi
    tested=""
    git -C "$state" show-ref -q --verify "refs/heads/$base" && tested=1
    # a fresh clone of the state repository (another machine) has the base on the remote only
    if [ -z "$tested" ] && [ -n "$(git -C "$state" config --get remote.origin.url)" ]; then
      git -C "$state" fetch -q origin 2>/dev/null ||
        { fail "could not fetch origin: cannot tell whether core $c was tested on another machine"; finish; }
      git -C "$state" show-ref -q --verify "refs/remotes/origin/$base" && tested=1
    fi
    if [ -n "$tested" ]; then
      fail "$base exists: core $c was tested here already - its branches are the evidence, nothing is deleted"; finish
    fi
    from="$(git -C "$state" rev-parse --abbrev-ref HEAD)"
    git -C "$state" branch "$base" HEAD && pass "branch $base from $from" || fail "could not create $base"
    if [ -n "$(git -C "$state" config --get remote.origin.url)" ]; then
      git -C "$state" push -q -u origin "$base" 2>/dev/null && pass "pushed $base" || fail "could not push $base"
      echo "remote: yes"
    else echo "remote: no - local branches and a local merge"; fi
    # every worktree of the run lies in the project's own .claude/worktrees (start-worker --worktree-root
    # <wr>), never in the state repository's: that one is inside the project root, where the guard keeps a
    # worker's edit tools out (COORD_PROTECTED_ROOT, #260). The base's worktree, for the merge of st1, is
    # made here
    wr="$(abspath "$project")/.claude/worktrees"; wb="$wr/selftest/$c/base"
    if git -C "$state" show-ref -q --verify "refs/heads/$base"; then
      git -C "$state" worktree add -q "$wb" "$base" >/dev/null 2>&1 && pass "worktree of $base at $wb" ||
        fail "could not add a worktree of $base at $wb"
    fi
    echo "worktrees: $wr/selftest/$c (start-worker's worktree root: $wr)"
    echo "base: $base"
    echo "started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    finish
  fi
  # verify: worktrees of the state repository (the first listed is the repository itself) that are
  # clean and merged into the base are removed; branches never are - they are the evidence. git lists
  # them wherever they lie: the project's .claude/worktrees, or the state repository's own, where an
  # older self-test put them (#260). A worktree on another run's branch (selftest/<x>/...) counts as
  # merged into that run's base, selftest/<x>/base, when it exists
  git -C "$state" worktree list --porcelain | sed -n 's/^worktree //p' | tail -n +2 | while IFS= read -r w; do
    wbase="$base"
    case "$(git -C "$w" symbolic-ref -q --short HEAD 2>/dev/null)" in
      selftest/*/*) x="$(git -C "$w" symbolic-ref -q --short HEAD)"; x="${x#selftest/}"; x="selftest/${x%%/*}/base"
        git -C "$state" show-ref -q --verify "refs/heads/$x" && wbase="$x" ;;
    esac
    [ -z "$(git -C "$w" status --porcelain 2>/dev/null)" ] &&
      git -C "$state" merge-base --is-ancestor "$(git -C "$w" rev-parse HEAD)" "$wbase" 2>/dev/null &&
      git -C "$state" worktree remove "$w"
  done
  left="$(git -C "$state" worktree list --porcelain | grep -c '^worktree ')"
  [ "$left" -le 1 ] && pass "no worktree left" || fail "$((left - 1)) worktree(s) left: not clean or not merged into $base (another run's: into its own selftest/<commit>/base)"
  for b in "$base" "$st1"; do
    git -C "$state" show-ref -q --verify "refs/heads/$b" && pass "evidence: $b" || fail "missing: $b"
  done
  git -C "$state" merge-base --is-ancestor "$st1" "$base" 2>/dev/null && pass "$st1 is merged into $base" ||
    fail "$st1 is not merged into $base"
  if [ -n "$repo" ]; then
    n="$(gh pr list -R "$repo" --state merged --head "selftest/$c/task-1" --base "$base" --json number --jq '.[0].number' 2>/dev/null)"
    [ -n "$n" ] && pass "PR #$n merged into $base" || fail "no merged PR from selftest/$c/task-1 into $base"
  else skip "PR flow: not checked (no --state-repo)"; fi
  sessions "$(own_roots "$project" "$state")"
  finish ;;

*) usage ;;
esac
