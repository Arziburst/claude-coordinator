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
#                                                       no PowerShell shell that turns its exit 2 into 1;
#                                                       env COORD_PROTECTED_ROOT: a folder, edit tools matched
#   scripts/selftest.sh hookcheck --session <id> [--expect edit]   a session told to push to main (with
#                                                       edit: to Write into the protected root): its transcript
#                                                       shows the block, not a non-blocking hook error
# For the core itself (the maintainer, CI) - a sandbox, kept between runs or removed:
#   scripts/selftest.sh sandbox [--in <folder>]      3: a repository with a local bare origin,
#                                                       at <folder>/coordinator-selftest (default: home): a fixed
#                                                       path, so the owner trusts its repo once per machine;
#                                                       a sandbox kept by clean --keep is reused
#   scripts/selftest.sh clean --sandbox <dir> [--keep] [--state-repo <owner/name>]
#                                                    6: no worktree, branch, session or selftest/* branch
#                                                       left; then the sandbox folder is removed - or, with
#                                                       --keep, kept: only main, at the sandbox's first commit
# Prints `PASS|FAIL|SKIP <step>: <what>` per check, then `selftest <step>: <p> pass, <f> fail, <s> skipped`.
# Exit 1 on any FAIL, 2 on a usage error.
set -u
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/.." && pwd)"
usage() { sed -n '2,31s/^# \{0,1\}//p' "$0"; exit 2; }
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
  # an absolute path: the repo's origin URL is stored from it, and a relative one breaks every git
  # command run from another folder (a reused sandbox's fetch)
  in="$(cd "$in" && pwd)" || { fail "cannot enter $in"; finish; }
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
    [ -n "$i" ] || { fail "no first commit recorded in $d/$marker (a sandbox from an older core): run selftest clean --sandbox $d without --keep"; finish; }
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
  if command -v claude >/dev/null 2>&1; then
    n="$(claude agents --json 2>/dev/null | grep -o '"name": *"[^"]*selftest[^"]*"' | sed 's/^"name": *"//; s/"$//')"
    [ -z "$n" ] && pass "no self-test session left" || fail "sessions left: $(printf '%s\n' "$n" | paste -sd ' ' -)"
  else skip "no claude: sessions not checked"; fi
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
    s = all; n = length(s); i = 1; ge = ""; R = ""
    ws(); if (substr(s, i, 1) != "{" || !val("")) exit 3
    ws(); if (i <= n) exit 3
    if (ge != "") { print C[ge, gh]; print S[ge, gh]; print F[ge, gh]; print M[ge]; print R }
  }'
  # a UTF-8 BOM before the JSON is dropped
  json="$(B="$(printf '\357\273\277')" awk 'NR == 1 && index($0, ENVIRON["B"]) == 1 { $0 = substr($0, length(ENVIRON["B"]) + 1) } { print }' "$file")"
  ok="" g="" root=""
  if command -v jq >/dev/null 2>&1; then
    printf '%s\n' "$json" | jq -e -s 'length == 1 and (.[0] | type == "object")' >/dev/null 2>&1 &&
      g="$(printf '%s\n' "$json" | jq -r "$hook_jq")" && ok=1
    # env.COORD_PROTECTED_ROOT: the owner's working copy, kept from edit tools (TOOLKIT Safety)
    [ -n "$ok" ] && root="$(printf '%s\n' "$json" | jq -r '.env | objects | .COORD_PROTECTED_ROOT | strings | gsub("[\n\r\t]"; " ")')"
  else g="$(printf '%s\n' "$json" | awk "$hook_awk")" && ok=1 && root="$(printf '%s\n' "$g" | sed -n 5p)"; fi
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
  case "$expect" in push|edit) ;; *) usage ;; esac
  # the id is a prefix, not a pattern; a prefix of several sessions names none of them
  case "$id" in *[][*?/\\]*) fail "the session id $id holds a pattern or path character"; finish ;; esac
  all="$(find "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects" -maxdepth 2 -name "$id*.jsonl" 2>/dev/null)"
  [ -n "$all" ] || { fail "no transcript for session $id"; finish; }
  if [ "$(printf '%s\n' "$all" | wc -l | tr -d ' ')" -gt 1 ]; then
    fail "ambiguous session $id: $(printf '%s\n' "$all" | sed 's|.*/||; s|\.jsonl$||' | LC_ALL=C sort | paste -sd ' ' -)"; finish
  fi
  tf="$all"
  if grep '"hook_non_blocking_error"' "$tf" | grep -q 'safety-guard'; then
    fail "the guard blocked, but Claude Code got it as a non-blocking error: a shell wrapper turns exit 2 into 1"
  elif [ "$expect" = edit ]; then
    # the edit probe: a Write into the root (COORD_PROTECTED_ROOT) - only the guard's working-copy
    # block counts, which it gives for Edit / Write / MultiEdit / NotebookEdit calls only
    if grep -q "Blocked by safety-guard: the owner's working copy is never edited by a worker" "$tf"; then
      pass "the edit tool's write into the working copy was blocked through Claude Code"
    elif grep -Eq 'File created successfully at|has been updated successfully' "$tf"; then
      fail "the write into the working copy went through: COORD_PROTECTED_ROOT is not in the settings' env, or its matcher leaves out the edit tools"
    else fail "no working-copy block in the transcript: the hook did not run (its matcher, COORD_PROTECTED_ROOT, or the settings were not loaded)"; fi
  elif grep 'Blocked by safety-guard' "$tf" | grep -vq "the owner's working copy is never edited"; then pass "the push to a protected branch was blocked through Claude Code"
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
    n="$(claude agents --json 2>/dev/null | grep -o '"name": *"[^"]*selftest[^"]*"' | sed 's/^"name": *"//; s/"$//')"
    [ -z "$n" ] && pass "no self-test session left" || fail "sessions left: $(printf '%s\n' "$n" | paste -sd ' ' -)"
  else skip "no claude: sessions not checked"; fi
  finish ;;

*) usage ;;
esac
