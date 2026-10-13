#!/usr/bin/env bash
# The scripted steps of the coordinator's self-test (procedures/SELFTEST.md; Windows: selftest.ps1 -
# the same steps and output). The steps with real sessions are run by the coordinator, not here.
#   scripts/selftest.sh scripts                      1: the core's checks and scripts on fixtures
#   scripts/selftest.sh env [--repo <owner/name>]    2: claude, git and gh versions; read-only GitHub
# In a project (procedures/SELFTEST.md, the normal case) - the state repository, evidence kept:
#   scripts/selftest.sh prepare --project <root> --state <coordinator dir> --core <commit>
#                                                    3: the project's git ignores .claude/worktrees;
#                                                       branch selftest/<commit>/base from the state branch
#   scripts/selftest.sh verify --project <root> --state <coordinator dir> --core <commit> [--state-repo <owner/name>]
#                                                    6: no session or worktree left; the evidence is there
#                                                       (base, st1 merged into it, the merged PR); nothing deleted
# The safety guard as Claude Code runs it (TOOLKIT Safety; a hook that fails to run blocks nothing):
#   scripts/selftest.sh hooks --settings <settings.json>   the guard hook's command: forward slashes, no $env:,
#                                                       no PowerShell shell that turns its exit 2 into 1
#   scripts/selftest.sh hookcheck --session <id>       a session told to push to main: its transcript shows
#                                                       the block, not a non-blocking hook error
# For the core itself (the maintainer, CI) - a throwaway sandbox:
#   scripts/selftest.sh sandbox [--in <folder>]      3: a throwaway repository with a local bare origin,
#                                                       at <folder>/coordinator-selftest (default: home): a fixed
#                                                       path, so the owner trusts its repo once per machine
#   scripts/selftest.sh clean --sandbox <dir> [--state-repo <owner/name>]
#                                                    6: no worktree, branch, session or selftest/* branch
#                                                       left; then the sandbox folder is removed
# Prints `PASS|FAIL|SKIP <step>: <what>` per check, then `selftest <step>: <p> pass, <f> fail, <s> skipped`.
# Exit 1 on any FAIL, 2 on a usage error.
set -u
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/.." && pwd)"
usage() { sed -n '2,27s/^# \{0,1\}//p' "$0"; exit 2; }
[ $# -gt 0 ] || usage
step="$1"; shift
p=0; f=0; s=0
pass() { echo "PASS $step: $1"; p=$((p + 1)); }
fail() { echo "FAIL $step: $1"; f=$((f + 1)); }
skip() { echo "SKIP $step: $1"; s=$((s + 1)); }
finish() { echo "selftest $step: $p pass, $f fail, $s skipped"; [ "$f" -eq 0 ] || exit 1; exit 0; }
# check <what> -- command...: PASS when it exits 0
check() { local what="$1"; shift 2; if "$@" >/dev/null 2>&1; then pass "$what"; else fail "$what"; fi; }
g() { git -c user.email=selftest@localhost -c user.name=selftest "$@"; }
marker=".coordinator-selftest"

case "$step" in
scripts)
  [ $# -eq 0 ] || usage
  t="$(mktemp -d)"; trap 'rm -r "$t"' EXIT
  # a local copy (no .git) must not hold the core's CLAUDE.md: Claude Code loads it into every session
  # that reads the copy's files, telling workers they are the coordinator
  if [ -f "$core/CLAUDE.md" ] && [ ! -e "$core/.git" ]; then
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
  d="${in%/}/coordinator-selftest"
  [ -e "$d" ] && { fail "$d already exists: a previous run left it (selftest clean --sandbox $d)"; finish; }
  mkdir "$d" || { fail "cannot create $d"; finish; }
  : > "$d/$marker"
  if git init -q --bare "$d/remote.git" && git -C "$d/remote.git" symbolic-ref HEAD refs/heads/main &&
     git init -q "$d/repo" && git -C "$d/repo" symbolic-ref HEAD refs/heads/main &&
     printf 'Coordinator self-test sandbox: throwaway, removed by `selftest clean`.\n' > "$d/repo/README.md" &&
     git -C "$d/repo" add README.md && g -C "$d/repo" commit -q -m "selftest: sandbox" &&
     git -C "$d/repo" remote add origin "$d/remote.git" && git -C "$d/repo" push -q -u origin main 2>/dev/null
  then pass "repository with a local bare origin, branch main"
  else fail "could not set up the repositories"; fi
  echo "sandbox: $d"
  echo "started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  finish ;;

clean)
  d="" state=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --sandbox) [ $# -ge 2 ] || usage; d="$2"; shift 2 ;;
      --state-repo) [ $# -ge 2 ] || usage; state="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  [ -n "$d" ] || usage
  [ -f "$d/$marker" ] || { fail "$d is not a self-test sandbox (no $marker): nothing removed"; finish; }
  r="$d/repo"
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
  if command -v claude >/dev/null 2>&1; then
    n="$(claude agents --json 2>/dev/null | grep -o '"name": *"[^"]*selftest[^"]*"' | sed 's/^"name": *//')"
    [ -z "$n" ] && pass "no self-test session left" || fail "sessions left: $(echo $n)"
  else skip "no claude: sessions not checked"; fi
  if [ -n "$state" ]; then
    if n="$(gh api "repos/$state/branches" --paginate --jq '.[].name' 2>/dev/null)"; then
      n="$(printf '%s\n' "$n" | grep '^selftest/')"
      [ -z "$n" ] && pass "no selftest/* branch on $state" || fail "branches left on ${state}: $(echo $n)"
    else fail "cannot list the branches of $state"; fi
  else skip "state repository: not checked (no --state-repo)"; fi
  if [ "$f" -eq 0 ]; then
    chmod -R u+w "$d" && rm -r "$d" && pass "sandbox removed" || fail "could not remove $d"
  else echo "sandbox kept for inspection: $d"; fi
  finish ;;

hooks)
  file=""
  while [ $# -gt 0 ]; do case "$1" in --settings) [ $# -ge 2 ] || usage; file="$2"; shift 2 ;; *) usage ;; esac; done
  [ -n "$file" ] || usage
  [ -f "$file" ] || { fail "no settings file $file"; finish; }
  # only the PreToolUse array counts: from its key to the bracket that closes it
  se="$(awk '!s && /"PreToolUse"[ \t]*:/ { s = NR }
    s { t = $0; o = gsub(/\[/, "", t); c = gsub(/\]/, "", t); d += o - c; if (o) seen = 1; if (seen && d <= 0) { print s, NR; exit } }' "$file")"
  ps="${se% *}"; pe="${se#* }"
  # the guard's command there (its SessionStart self-test line carries -SelfTest / --self-test)
  n=""
  [ -n "$se" ] && n="$(awk -v s="$ps" -v e="$pe" 'NR >= s && NR <= e && /safety-guard\./ && !/-SelfTest/ && !/--self-test/ { print NR; exit }' "$file")"
  [ -n "$n" ] || { fail "no safety-guard hook in the file"; finish; }
  pass "a safety-guard hook"
  line="$(sed -n "${n}p" "$file")"
  # a backslash that is not the JSON escape of a quote (\") is a path separator
  if printf '%s\n' "$line" | sed 's/\\"//g' | grep -q '[\]'; then
    fail "its path has backslashes: Git Bash drops them and the hook never runs"
  else pass "its path uses forward slashes"; fi
  case "$line" in *'$env:'*) fail 'its command uses $env: - bash reads it as $env and the path breaks' ;;
    *) pass 'no $env: in its command' ;; esac
  # an unquoted path must be one word: a space splits it and the hook never runs
  cmd="$(printf '%s\n' "$line" | sed 's/^[^:]*:[ \t]*"//; s/",*[ \t]*$//; s/\\"/"/g')"
  if printf '%s\n' "$cmd" | grep -q '"[^"]*safety-guard\.\(sh\|ps1\)"'; then pass "its path is quoted or has no space"
  else
    word="$(printf '%s\n' "$cmd" | sed 's/safety-guard\..*//; s/.* //')"
    case "$word" in /*|[A-Za-z]:*|'$'*|'~'*) pass "its path is quoted or has no space" ;;
      *) fail "its path has a space and is not quoted: the hook never runs" ;; esac
  fi
  # the hook object's own fields sit between its braces
  if awk -v n="$n" '{ l[NR] = $0 } END { a = n; while (a > 1 && l[a] !~ /[{]/) a--; b = n; while (b < NR && l[b] !~ /[}]/) b++
       for (i = a; i <= b; i++) if (l[i] ~ /"shell"[ \t]*:[ \t]*"powershell"/) exit 0; exit 1 }' "$file"; then
    case "$line" in *'exit $LASTEXITCODE'*) pass 'a PowerShell shell, with exit $LASTEXITCODE passing the block through' ;;
      *) fail 'a PowerShell shell without "; exit $LASTEXITCODE": the block (exit 2) reaches Claude Code as a non-blocking error (1)' ;; esac
  else pass "no PowerShell shell around it"; fi
  # its entry's matcher (none: every tool) must take in the PowerShell tool too
  m="$(awk -v s="$ps" -v n="$n" 'NR >= s && NR <= n && /"matcher"[ \t]*:/ { m = $0 } END { print m }' "$file")"
  case "$m" in ''|*PowerShell*|*'"*"'*) pass "its matcher covers the PowerShell tool" ;;
    *) fail "its matcher leaves out PowerShell: the PowerShell tool runs unguarded" ;; esac
  # a hook that fails to run (a wrong path, a crash, a timeout) lets the call through unless it blocks on failure
  if awk -v n="$n" '{ l[NR] = $0 } END { a = n; while (a > 1 && l[a] !~ /[{]/) a--; b = n; while (b < NR && l[b] !~ /[}]/) b++
       for (i = a; i <= b; i++) if (l[i] ~ /"onFailure"[ \t]*:[ \t]*"block"/) exit 0; exit 1 }' "$file"; then
    pass 'onFailure "block": a guard that fails to run blocks'
  else fail 'no "onFailure": "block": a guard that fails to run lets every call through (Claude Code 2.1.295+)'; fi
  finish ;;

hookcheck)
  id=""
  while [ $# -gt 0 ]; do case "$1" in --session) [ $# -ge 2 ] || usage; id="$2"; shift 2 ;; *) usage ;; esac; done
  [ -n "$id" ] || usage
  tf="$(find "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects" -maxdepth 2 -name "$id*.jsonl" 2>/dev/null | head -n 1)"
  [ -n "$tf" ] || { fail "no transcript for session $id"; finish; }
  if grep '"hook_non_blocking_error"' "$tf" | grep -q 'safety-guard'; then
    fail "the guard blocked, but Claude Code got it as a non-blocking error: a shell wrapper turns exit 2 into 1"
  elif grep -q 'Blocked by safety-guard' "$tf"; then pass "the push to a protected branch was blocked through Claude Code"
  else fail "no block in the transcript: the hook did not run (its path, its shell, or the settings were not loaded)"; fi
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
    if [ ! -f "$fnd" ]; then fail "no CORE-FINDINGS.md in the state repository (INIT 3.4, CORE-FINDINGS.template.md)"
    elif ! tr -d '\r' < "$fnd" | grep -qxF '| id | date | core | trigger | what happened (evidence) | workaround | status |'; then
      fail "CORE-FINDINGS.md lacks the template's table header"
    else
      bad="$(tr -d '\r' < "$fnd" | awk -F'|' '/^\|/ && !/^\| id \|/ && !/^\|---/ { s = $(NF - 1); gsub(/^ +| +$/, "", s); if (s !~ /^(new|discussed|sent|fixed|dropped|not core)/) print s }' | head -n 1)"
      if [ -z "$bad" ]; then pass "CORE-FINDINGS.md in the template's format"; else fail "CORE-FINDINGS.md: unknown status '$bad'"; fi
    fi
    if git -C "$state" show-ref -q --verify "refs/heads/$base"; then
      fail "$base exists: core $c was tested here already - its branches are the evidence, nothing is deleted"; finish
    fi
    from="$(git -C "$state" rev-parse --abbrev-ref HEAD)"
    git -C "$state" branch "$base" HEAD && pass "branch $base from $from" || fail "could not create $base"
    if [ -n "$(git -C "$state" config --get remote.origin.url)" ]; then
      git -C "$state" push -q -u origin "$base" 2>/dev/null && pass "pushed $base" || fail "could not push $base"
      echo "remote: yes"
    else echo "remote: no - local branches and a local merge"; fi
    echo "worktrees: $(cd "$project" && pwd)/.claude/worktrees"
    echo "base: $base"
    echo "started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    finish
  fi
  # verify: worktrees of the state repository (the first listed is the repository itself) that are
  # clean and merged into the base are removed; branches never are - they are the evidence
  git -C "$state" worktree list --porcelain | sed -n 's/^worktree //p' | tail -n +2 | while IFS= read -r w; do
    [ -z "$(git -C "$w" status --porcelain 2>/dev/null)" ] &&
      git -C "$state" merge-base --is-ancestor "$(git -C "$w" rev-parse HEAD)" "$base" 2>/dev/null &&
      git -C "$state" worktree remove "$w"
  done
  left="$(git -C "$state" worktree list --porcelain | grep -c '^worktree ')"
  [ "$left" -le 1 ] && pass "no worktree left" || fail "$((left - 1)) worktree(s) left: not clean or not merged into $base"
  for b in "$base" "$st1"; do
    git -C "$state" show-ref -q --verify "refs/heads/$b" && pass "evidence: $b" || fail "missing: $b"
  done
  git -C "$state" merge-base --is-ancestor "$st1" "$base" 2>/dev/null && pass "$st1 is merged into $base" ||
    fail "$st1 is not merged into $base"
  if [ -n "$repo" ]; then
    n="$(gh pr list -R "$repo" --state merged --head "selftest/$c/task-1" --base "$base" --json number --jq '.[0].number' 2>/dev/null)"
    [ -n "$n" ] && pass "PR #$n merged into $base" || fail "no merged PR from selftest/$c/task-1 into $base"
  else skip "PR flow: not checked (no --state-repo)"; fi
  if command -v claude >/dev/null 2>&1; then
    n="$(claude agents --json 2>/dev/null | grep -o '"name": *"[^"]*selftest[^"]*"' | sed 's/^"name": *//')"
    [ -z "$n" ] && pass "no self-test session left" || fail "sessions left: $(echo $n)"
  else skip "no claude: sessions not checked"; fi
  finish ;;

*) usage ;;
esac
