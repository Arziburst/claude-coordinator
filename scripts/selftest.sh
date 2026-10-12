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
usage() { sed -n '2,22s/^# \{0,1\}//p' "$0"; exit 2; }
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
