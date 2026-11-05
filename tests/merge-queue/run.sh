#!/usr/bin/env bash
# Checks of merge-queue against a stub `gh` on PATH (GitHub is never called): the stub answers from the
# files of a state folder and logs every call.
#   tests/merge-queue/run.sh sh                    # merge-queue.sh, with the bash running this file
#   tests/merge-queue/run.sh ps pwsh               # merge-queue.ps1 (or: ps powershell)
# Exit 1 if any check fails.
# Access points of the bounds (#381, #387): land reads the PR's contract at coordinator/briefs/<head branch, / as ->-contract.md, then by the id
# its branch starts with (`<id>-...`: coordinator/briefs/<id>-contract.md) and runs check-bounds on it and
# <base>...<head>. An OVER: the line of its own `OVER BOUNDS <pr> <glob> <added>/<max>`, no merge, in the summary as
# `left: #<pr> (OVER BOUNDS)`, the queue goes on, exit 3. No contract, or a branch with no id: one line
# `BOUNDS #<pr>: no contract ...` (nothing at that path), no stop. check-bounds exiting 2 (a folder at that path, a
# malformed bound, a head git cannot read) stops that PR, fail-closed: the line `BOUNDS #<pr>: check-bounds ...`, no
# merge, in the summary as `left: #<pr> (BOUNDS)`, the queue goes on, exit 3. --over-bounds-ok <pr>:<the owner's words> (.ps1: -OverBoundsOk): that PR
# passes and one line holds the words; another PR's stays stopped; no words, blank words, or no number before the colon: a usage
# error, exit 1. The folder (#387): land's cwd must be a repository's root (`git rev-parse --show-prefix` empty) whose origin has each open PR's
# branch (`git ls-remote origin <branch>`), checked before any PR merges: else exit 1, one line naming the cwd's folder, --dry-run too. status: anywhere.
# Access point (#392): land, a PR whose isCrossRepository is true (the sixth word of the stub's pr-<n>): no `gh api -X DELETE`, whatever is based on its branch,
# and in place of the deleted/kept line this one: `left the fork's branch <branch>: #<pr> is a fork's PR, nothing deleted on origin`. A PR from this repository: as before.
# Access point (#419): land stops as above only on an OVER whose glob matches or holds an important glob (check-contract's list: its defaults and the row *Important components* of the PROJECT.md
# two folders above the scripts). Any other OVER, instead of `OVER BOUNDS`: exactly the line `bounds over, not important: <pr> <glob> <added>/<max>`, and if no OVER stops it the PR goes on.
# Access point (#466): after each MERGED and its AFFECTED lines, in place of the one AFTER MERGE line, exactly these `AFTER MERGE #<pr>: ` lines in this order (the case "after a merge" holds them word by word). <n> is the
# number the branch starts with (`<n>-...`), else the literal `<n>`. The .ps1 prints its own flags (-Worktree, -Task <n> -PrJson:- -Append). Printed only: gh sees no call beyond today's.
set -u
[ $# -gt 0 ] || { sed -n '2,6s/^# \{0,1\}//p' "$0"; exit 2; }
kind="$1"; shift
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'cd /; rm -rf "$tmp"' EXIT
command -v cygpath >/dev/null 2>&1 && core="$(cygpath -m "$core")"

# The stub's state folder $STUB_D:
#   pr-<n>         `<state> <isDraft> <head> <branch> <base>`        files-<n>  the PR's files, one a line
#   behind-<sha>   how far <sha> is behind the base (none: 0)          cmp-<a>-<b> files the base brought
#   update-<n>     the pr-<n> line after `gh pr update-branch` (none: the update changes nothing);
#                  update-<n>.lag  that many `pr view` reads still show the old head (GitHub lags);
#                  update-<n>.fail the update refused with this text                delete-fail  the
#                  remote branch cannot be deleted
#   checks-<sha>   one poll a line, the buckets of that poll (the last line repeats); `MOVE <sha>` moves
#                  the PR's head to <sha> and answers pending
#   runs-commit-<sha>, runs-branch-<branch>  `<id> <sha> <status> <conclusion>` lines
#   merge-<n>.fail a merge refused with this text                      fail-view  every `pr view` fails
#   prlist         `<n>\t<mergeable>\t<mergeStateStatus>\t<branch>\t<file>...` lines
mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
D="$STUB_D"; a="$*"
printf '%s\n' "$a" | tr '\n\t' '  ' >> "$D/log"; echo >> "$D/log"
case "$1 $2" in
  "pr view")
    [ -f "$D/fail-view" ] && { echo "GraphQL: Could not resolve to a PullRequest" >&2; exit 1; }
    case " $a " in *" files "*) cat "$D/files-$3" 2>/dev/null ;;
      *) if [ -f "$D/lag-$3" ]; then k=$(cat "$D/lag-$3")
           if [ "$k" -gt 0 ]; then echo $((k - 1)) > "$D/lag-$3"; else cp "$D/update-$3" "$D/pr-$3"; rm "$D/lag-$3"; fi; fi
         cat "$D/pr-$3" ;; esac ;;
  "pr update-branch")
    [ -f "$D/update-$3.fail" ] && { cat "$D/update-$3.fail" >&2; exit 1; }
    if [ -f "$D/update-$3.lag" ]; then cp "$D/update-$3.lag" "$D/lag-$3"; elif [ -f "$D/update-$3" ]; then cp "$D/update-$3" "$D/pr-$3"; fi
    echo "updated" ;;
  "api -X") [ -f "$D/delete-fail" ] && { echo "Reference does not exist" >&2; exit 1; } ;;
  "pr checks")
    read -r _ _ h _ < "$D/pr-$3"; f="$D/checks-$h"; [ -f "$f" ] || exit 0
    n=$(cat "$f.n" 2>/dev/null || echo 0); n=$((n + 1)); echo $n > "$f.n"
    l="$(sed -n "${n}p" "$f")"; [ -n "$l" ] || l="$(tail -n 1 "$f")"
    case "$l" in MOVE\ *) p="$3"; set -- $l; read -r s d _ b c < "$D/pr-$p"; echo "$s $d $2 $b $c" > "$D/pr-$p"; printf 'c1\t2026-01-01T00:00:01Z\tpending\n'; exit 8 ;; esac
    # each word a check: `<bucket>` (its own name), or `<name>@<second>=<bucket>` (`@-` not started yet)
    i=0; for k in $l; do i=$((i + 1))
      case "$k" in *@*=*) nm="${k%%@*}"; s="${k#*@}"; s="${s%%=*}"; bk="${k#*=}"
                          [ "$s" = - ] && t="" || t="2026-01-01T00:00:$(printf '%02d' "$s")Z" ;;
                   *) nm="c$i"; t="2026-01-01T00:00:00Z"; bk="$k" ;; esac
      printf '%s\t%s\t%s\n' "$nm" "$t" "$bk"; done ;;
  "pr merge") [ -f "$D/merge-$3.fail" ] && { cat "$D/merge-$3.fail" >&2; exit 1; }; echo "merged" ;;
  "pr list")   # --base <branch>: the open PRs based on it (base-<branch>), else the open PRs (prlist)
    b=""; p=""; for x in "$@"; do [ "$p" = --base ] && b="$x"; p="$x"; done
    if [ -n "$b" ]; then cat "$D/base-$b" 2>/dev/null; else cat "$D/prlist" 2>/dev/null; fi ;;
  "run list")
    case "$3" in --commit) cat "$D/runs-commit-$4" 2>/dev/null ;; --branch) cat "$D/runs-branch-$4" 2>/dev/null ;; esac ;;
  "run rerun"|"run cancel") ;;
  api\ *)
    p="${2##*/compare/}"; x="${p%%...*}"; y="${p#*...}"
    case "$a" in *behind_by*) cat "$D/behind-$y" 2>/dev/null || echo 0 ;; *) cat "$D/cmp-$x-$y" 2>/dev/null ;; esac ;;
esac
exit 0
EOF
# PowerShell finds gh.ps1 first; it hands the arguments to the bash stub as a native process, as gh.exe
# gets them
cat > "$tmp/bin/gh.ps1" <<'EOF'
& bash (Join-Path $PSScriptRoot 'gh') @args
exit $LASTEXITCODE
EOF
# a stub `claude` (#493): `agents --json --all` prints $STUB_D/agents (none: an empty list), or fails when $STUB_D/agents-fail exists
cat > "$tmp/bin/claude" <<'EOF'
#!/usr/bin/env bash
[ "$1" = agents ] || exit 1
[ -f "$STUB_D/agents-fail" ] && { echo "claude: listing failed" >&2; exit 1; }
cat "$STUB_D/agents" 2>/dev/null || echo '[]'
EOF
cat > "$tmp/bin/claude.ps1" <<'EOF'
& bash (Join-Path $PSScriptRoot 'claude') @args
exit $LASTEXITCODE
EOF
chmod +x "$tmp/bin/gh" "$tmp/bin/claude"
export PATH="$tmp/bin:$PATH"

case "$kind" in
  sh) mq() { bash "$core/scripts/merge-queue.sh" "$@"; } ;;
  ps) ps="${1:-pwsh}"
      # the .sh's flags as the .ps1's parameters: land/status stay, --x y -> -X y, the PRs as -Pr a,b
      mq() { local a=() prs="" sh="" tc="" nx=""
        for x in "$@"; do
          [ "$nx" = shared ] && { sh="${sh:+$sh,}$x"; nx=""; continue; }
          [ "$nx" = touches ] && { tc="${tc:+$tc,}$x"; nx=""; continue; }
          [ "$nx" = value ] && { a+=("$x"); nx=""; continue; }
          case "$x" in
          land|status) a+=("$x") ;; --method) a+=(-Method); nx=value ;; --shared) nx=shared ;; --touches) nx=touches ;;
          --poll) a+=(-Poll); nx=value ;; --timeout) a+=(-Timeout); nx=value ;; --dry-run) a+=(-DryRun) ;;
          --over-bounds-ok) a+=(-OverBoundsOk); nx=value ;; --*) a+=("$x") ;;
          [0-9]*) prs="${prs:+$prs,}$x" ;; *) a+=("$x") ;; esac; done
        [ -n "$prs" ] && a+=(-Pr "$prs"); [ -n "$sh" ] && a+=(-Shared "$sh"); [ -n "$tc" ] && a+=(-Touches "$tc")
        "$ps" -NoProfile -ExecutionPolicy Bypass -File "$core/scripts/merge-queue.ps1" "${a[@]}"; } ;;
  *) echo "unknown kind: $kind" >&2; exit 2 ;;
esac

pass=0 fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL [$name] $*"; printf '%s\n' "$out" | sed 's/^/    | /'; }
# fresh <name>: a new state folder; run <args>: merge-queue's output and exit code
fresh() { name="$1"; export STUB_D="$tmp/s$((pass + fail))-$RANDOM"; mkdir -p "$STUB_D"; : > "$STUB_D/log"; }
run() { out="$(mq "$@" 2>&1)"; rc=$?; out="$(printf '%s\n' "$out" | tr -d '\r')"; }
has() { printf '%s\n' "$out" | grep -qF -- "$1" && ok || bad "expected the line: $1"; }
hasnt() { printf '%s\n' "$out" | grep -qF -- "$1" && bad "unexpected: $1" || ok; }
called() { grep -qF -- "$1" "$STUB_D/log" && ok || { bad "gh not called with: $1"; sed 's/^/    log: /' "$STUB_D/log"; }; }
notcalled() { grep -qF -- "$1" "$STUB_D/log" && { bad "gh called with: $1"; sed 's/^/    log: /' "$STUB_D/log"; } || ok; }
code() { [ "$rc" = "$1" ] && ok || bad "expected exit $1, got $rc"; }
pr() { echo "OPEN false $2 $3 main" > "$STUB_D/pr-$1"; }
H11=a111111111111111111111111111111111111111 H13=c131313131313131313131313131313131313131 N13=d131313131313131313131313131313131313131
# the cases below run from a repository's root whose origin has their open PRs' branches (#387); 1-a is off it: a merged PR's branch is gone
git init -q --bare "$tmp/r.git"; git init -q -b main "$tmp/r"; cd "$tmp/r" || exit 1; git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
for b in 11-fix 13-x 14-y 15-z 16-a 17-b 18-c 2-b 3-c 4-d 466-feat hotfix-x; do git branch "$b"; done; git remote add origin "$tmp/r.git"; git push -q origin --all 2>/dev/null

fresh "up to date, green: merged; an open PR changing the same file is AFFECTED"
pr 11 $H11 11-fix; printf 'src/x.ts\ndocs/LOG.md\n' > "$STUB_D/files-11"; echo "pass skipping" > "$STUB_D/checks-$H11"
printf '11\tMERGEABLE\tCLEAN\t11-fix\tsrc/x.ts\n12\tMERGEABLE\tBEHIND\t12-feat\tsrc/x.ts\tdocs/LOG.md\n19\tMERGEABLE\tBEHIND\t19-other\tsrc/q.ts\n' > "$STUB_D/prlist"
run land 11 --poll 0
code 0; has "MERGED #11: a111111"; has "AFFECTED #12: 12-feat - merge main now: src/x.ts, docs/LOG.md"; hasnt "AFFECTED #19"
# the event table's merge row, printed line by line so its duties have a trigger (#242, #466)
wtflag=-Worktree; [ "$kind" = sh ] && wtflag=--worktree
has "AFTER MERGE #11: cleanup-worker $wtflag .claude/worktrees/11-fix (CORE §8)"; hasnt "the event table (CORE §4) -"
has "merge-queue: 1 merged"; called "pr merge 11 --squash --match-head-commit $H11"; notcalled "--delete-branch"
called "api -X DELETE repos/"; called "/git/refs/heads/11-fix"; has "deleted the remote branch 11-fix"

fresh "after a merge: the AFTER MERGE lines in order, filled in, the issue from the branch or <n>; printed only"
H77=7777777777777777777777777777777777777777 H78=7878787878787878787878787878787878787878
pr 77 $H77 466-feat; pr 78 $H78 hotfix-x; echo src/x.ts > "$STUB_D/files-77"; echo src/y.ts > "$STUB_D/files-78"; echo pass > "$STUB_D/checks-$H77"; echo pass > "$STUB_D/checks-$H78"
printf '79\tMERGEABLE\tBEHIND\t79-other\tsrc/x.ts\n' > "$STUB_D/prlist"
case "$kind" in sh) amw=--worktree amt='--task 466 --pr-json - --append' ;; *) amw=-Worktree amt='-Task 466 -PrJson:- -Append' ;; esac
am77="AFTER MERGE #77: cleanup-worker $amw .claude/worktrees/466-feat (CORE §8)
AFTER MERGE #77: the run rows of task 466 (branch 466-feat), then runs check, and the journal line (CORE §7)
AFTER MERGE #77: close issue #466 and move it on the board, by the project's words (PROJECT.md) where it has none
AFTER MERGE #77: the task row, from the product repository: gh pr view 77 --json statusCheckRollup,mergedAt,createdAt | run-stats coordinator/RUNS.tsv $amt
AFTER MERGE #77: tell each AFFECTED PR's session to merge main (CORE §4a)
AFTER MERGE #77: did a rule or number in the project's own files move? did a core rule or check fail us, the verifier's core_findings too (CORE §10)? an escape (CORE §12)?
AFTER MERGE #77: the project's own after-merge duties (PROJECT.md)"
am78="$(printf '%s\n' "$am77" | sed 's/#77/#78/; s/pr view 77/pr view 78/; s/466-feat/hotfix-x/g; s/466/<n>/g')"
run land 77 78 --poll 0; code 0
got="$(printf '%s\n' "$out" | sed -n '/^MERGED #77:/,/^MERGED #78:/p' | grep -E '^(AFFECTED|AFTER MERGE)')"
[ "$got" = "AFFECTED #79: 79-other - merge main now: src/x.ts
$am77" ] && ok || bad "after MERGED #77 expected AFFECTED #79 as today, then exactly:
$am77"
got="$(printf '%s\n' "$out" | sed -n '/^MERGED #78:/,$p' | grep '^AFTER MERGE')"
[ "$got" = "$am78" ] && ok || bad "after MERGED #78 (no number in its branch) expected exactly:
$am78"
fresh "after a merge: the task's other finished sessions of this project are named with their rm (#493)"
qroot="$(pwd -W 2>/dev/null || pwd -P)"   # the folder as the listing gives it (Windows: C:/...)
pr 77 $H77 466-feat; echo src/x.ts > "$STUB_D/files-77"; echo pass > "$STUB_D/checks-$H77"
sess() { printf '  {\n    "id": "%s",\n    "sessionId": "5e550000-0000-4000-8000-0000000000%s",\n    "name": "%s",\n    "state": "%s"%s\n  }' "$1" "${1#a}" "$2" "$3" "${4:+,
    \"cwd\": \"$4\"}"; }
{ echo '['; sess a1 "#466 tester: x" done "$qroot/.claude/worktrees/466-feat"; echo ,; sess a2 "#466.1 worker: y" stopped "$qroot"; echo ,
  sess a3 "#466 worker: still going" working "$qroot"; echo ,; sess a4 "#4660 another task" done "$qroot"; echo ,
  sess a5 "#466 other folder" done "$qroot-other"; echo ,; sess a6 "#466 no folder" done; echo ,; sess a7 "#466 fix round" failed "$qroot"; echo; echo ']'; } > "$STUB_D/agents"
run land 77 --poll 0; code 0; has "MERGED #77:"
got="$(printf '%s\n' "$out" | grep 'other finished sessions')"
[ "$got" = "AFTER MERGE #77: other finished sessions of task 466 are still listed: claude rm a1 (#466 tester: x); claude rm a2 (#466.1 worker: y); claude rm a7 (#466 fix round)" ] && ok || bad "expected exactly the sessions a1, a2, a7 in one line, got: $got"
hasnt "claude rm a3"; hasnt "claude rm a4"; hasnt "claude rm a5"; hasnt "claude rm a6"; has "AFTER MERGE #77: cleanup-worker"
fresh "after a merge: a failing listing or no matching session: no line, the merge stands (#493)"
pr 77 $H77 466-feat; echo src/x.ts > "$STUB_D/files-77"; echo pass > "$STUB_D/checks-$H77"; touch "$STUB_D/agents-fail"
run land 77 --poll 0; code 0; has "MERGED #77:"; hasnt "other finished sessions"; has "AFTER MERGE #77: the project's own after-merge duties"
rm "$STUB_D/agents-fail"; sess a9 "#999 another task" done "$qroot" > "$STUB_D/agents.one"; { echo '['; cat "$STUB_D/agents.one"; echo ']'; } > "$STUB_D/agents"
pr 77 $H77 466-feat; run land 77 --poll 0; code 0; has "MERGED #77:"; hasnt "other finished sessions"
# no duty is run: every call of the stub is one the queue makes today, none to an issue, a board or a tracker
x="$(grep -vE '^(pr (view|checks|merge|list) |api -X DELETE repos/[^ ]*/git/refs/heads/|api repos/[^ ]*/compare/|run list )' "$STUB_D/log")"; [ -z "$x" ] && ok || bad "gh called beyond today's: $x"

fresh "a PR from this repository (isCrossRepository false): deletes, no fork line"; echo "OPEN false $H11 11-fix main false" > "$STUB_D/pr-11"; echo pass > "$STUB_D/checks-$H11"
run land 11 --poll 0; code 0; called "api -X DELETE repos/"; called "/git/refs/heads/11-fix"; has "deleted the remote branch 11-fix"; hasnt "left the fork's branch"; own="$out"
fresh "a fork's PR, a branch of that name on origin: no DELETE, its one line, every other line as for a PR from this repository"; echo "OPEN false $H11 11-fix main true" > "$STUB_D/pr-11"; echo pass > "$STUB_D/checks-$H11"
run land 11 --poll 0; code 0; notcalled "api -X DELETE"; hasnt "deleted the remote branch"; FORKL="left the fork's branch 11-fix: #11 is a fork's PR, nothing deleted on origin"
[ "$(printf '%s\n' "$out" | grep -cxF -- "$FORKL")" = 1 ] && ok || bad "expected exactly one line: $FORKL"
[ "$(printf '%s\n' "$out" | grep -vxF -- "$FORKL")" = "$(printf '%s\n' "$own" | grep -vxF "deleted the remote branch 11-fix")" ] && ok || bad "other lines differ from the same-repository run"
fresh "a fork's PR with an open PR based on a same-named branch: the fork's line, not the kept one"; echo "OPEN false $H11 11-fix main true" > "$STUB_D/pr-11"; echo pass > "$STUB_D/checks-$H11"; echo "#40 " > "$STUB_D/base-11-fix"
run land 11 --poll 0; code 0; notcalled "api -X DELETE"; has "$FORKL"; hasnt "kept the remote branch"
fresh "a fork's PR, then a PR from this repository, in one land: each by its own field"; echo "OPEN false $H11 11-fix main true" > "$STUB_D/pr-11"; echo "OPEN false $H13 13-x main false" > "$STUB_D/pr-13"; echo pass > "$STUB_D/checks-$H11"; echo pass > "$STUB_D/checks-$H13"
run land 11 13 --poll 0; code 0; notcalled "/git/refs/heads/11-fix"; called "/git/refs/heads/13-x"; has "$FORKL"; has "deleted the remote branch 13-x"

fresh "the method is passed on"
pr 11 $H11 11-fix; echo pass > "$STUB_D/checks-$H11"
run land 11 --poll 0 --method merge
code 0; called "pr merge 11 --merge --match-head-commit $H11"

fresh "behind: updated (the base touched none of its files), then green: merged on the new head"
pr 13 $H13 13-x; echo 2 > "$STUB_D/behind-$H13"; echo "OPEN false $N13 13-x main" > "$STUB_D/update-13"
echo src/y.ts > "$STUB_D/files-13"; echo docs/other.md > "$STUB_D/cmp-$H13-$N13"; printf 'pending\npass\n' > "$STUB_D/checks-$N13"
run land 13 --poll 0
code 0; has "updated #13: c131313 -> d131313, main merged in without touching the PR's files"; has "MERGED #13: d131313"
called "pr update-branch 13"; called "pr merge 13 --squash --match-head-commit $N13"

fresh "behind and the update refused: CONFLICT with gh's words, the next PR still merges, exit 3"
pr 14 e141414 14-y; echo 1 > "$STUB_D/behind-e141414"; pr 11 $H11 11-fix; echo pass > "$STUB_D/checks-$H11"
echo "merge conflict between base and head" > "$STUB_D/update-14.fail"
run land 14 11 --poll 0
code 3; has "CONFLICT #14: 14-y - main did not merge in (merge conflict between base and head)"; has "MERGED #11"
has "merge-queue: 1 merged, left: #14 (CONFLICT)"; notcalled "pr merge 14"

fresh "the update landed but GitHub shows the new head only a few reads later: waited for, then merged"
pr 13 $H13 13-x; echo 2 > "$STUB_D/behind-$H13"; echo "OPEN false $N13 13-x main" > "$STUB_D/update-13"; echo 3 > "$STUB_D/update-13.lag"
echo src/y.ts > "$STUB_D/files-13"; echo docs/other.md > "$STUB_D/cmp-$H13-$N13"; echo pass > "$STUB_D/checks-$N13"
run land 13 --poll 0
code 0; has "updated #13: c131313 -> d131313"; has "MERGED #13: d131313"; hasnt "CONFLICT"

fresh "the update answered but the head never moved: TIMEOUT, no merge"
pr 14 e141414 14-y; echo 1 > "$STUB_D/behind-e141414"
run land 14 --poll 0
code 3; has "TIMEOUT #14: its branch was updated, but its head did not move within 90 s - queue it again"; notcalled "pr merge"

fresh "a branch other open PRs are based on is kept: GitHub would close them (#229)"
pr 11 $H11 11-fix; echo pass > "$STUB_D/checks-$H11"; printf '#40 #41 ' > "$STUB_D/base-11-fix"
run land 11 --poll 0
code 0; has "MERGED #11"; has "kept the remote branch 11-fix: #40 #41 use it as their base"; notcalled "api -X DELETE"

fresh "the remote branch already gone (the repository deletes it on merge): still merged, exit 0"
pr 11 $H11 11-fix; echo pass > "$STUB_D/checks-$H11"; touch "$STUB_D/delete-fail"
run land 11 --poll 0
code 0; has "MERGED #11"; hasnt "deleted the remote branch"

fresh "the base changed a file the PR changes: REVIEW, no merge"
pr 15 f151515 15-z; echo 1 > "$STUB_D/behind-f151515"; echo "OPEN false 9151515 15-z main" > "$STUB_D/update-15"
printf 'src/z.ts\nmessages/en.json\n' > "$STUB_D/files-15"; printf 'messages/en.json\nsrc/z.ts\n' > "$STUB_D/cmp-f151515-9151515"; echo pass > "$STUB_D/checks-9151515"
run land 15 --poll 0
code 3; has "REVIEW #15: main changed files this PR changes too: src/z.ts, messages/en.json - re-review the merge (git diff f151515 9151515), then queue 15@9151515"
notcalled "pr merge 15"

fresh "the same with the shared files given: only the others count"
pr 15 f151515 15-z; echo 1 > "$STUB_D/behind-f151515"; echo "OPEN false 9151515 15-z main" > "$STUB_D/update-15"
printf 'src/z.ts\nmessages/en.json\n' > "$STUB_D/files-15"; echo messages/en.json > "$STUB_D/cmp-f151515-9151515"; echo pass > "$STUB_D/checks-9151515"
run land 15 --poll 0 --shared 'messages/*' --shared 'docs/*.md'
code 0; has "MERGED #15: 9151515"

fresh "a failed check re-runs once; green then: merged"
pr 16 b161616 16-a; printf 'fail pass\npending\npass\n' > "$STUB_D/checks-b161616"
printf 'https://github.com/o/r/actions/runs/901 b161616 completed failure\nhttps://github.com/o/r/actions/runs/902 b161616 completed success\n' > "$STUB_D/runs-commit-b161616"
run land 16 --poll 0
code 0; has "re-ran #16's failed runs once: 901"; has "MERGED #16"; called "run rerun 901 --failed"; notcalled "run rerun 902"

fresh "failed twice: FAILED, no merge"
pr 16 b161616 16-a; printf 'fail\npending\nfail\n' > "$STUB_D/checks-b161616"; echo '901 b161616 completed failure' > "$STUB_D/runs-commit-b161616"
run land 16 --poll 0
code 3; has "FAILED #16: its checks failed twice on b161616"; notcalled "pr merge 16"
has "the queue re-ran them once, so a flake is a flake bug; classify it (CORE §4 step 4), never merge over it"; hasnt "AFTER MERGE #16"

fresh "a failure right after the re-run (no pending seen yet) is the old result: waited for"
pr 16 b161616 16-a; printf 'fail\nfail\npending\npass\n' > "$STUB_D/checks-b161616"; echo '901 b161616 completed failure' > "$STUB_D/runs-commit-b161616"
run land 16 --poll 0
code 0; has "MERGED #16"

fresh "the same check name twice on the head: the newest run counts, an older failure is no failure (#234)"
pr 16 b161616 16-a; echo 'ci@1=fail ci@5=pass other=pass' > "$STUB_D/checks-b161616"
echo 'https://github.com/o/r/actions/runs/901 b161616 completed failure' > "$STUB_D/runs-commit-b161616"
run land 16 --poll 0
code 0; has "MERGED #16"; hasnt "re-ran"; notcalled "run rerun"

fresh "a newer run of the same name not started yet is pending, not the old pass"
pr 16 b161616 16-a; printf 'ci@3=pass ci@-=pending\nci@3=pass ci@4=pass\n' > "$STUB_D/checks-b161616"
run land 16 --poll 0
code 0; has "MERGED #16"; called "pr checks 16"

fresh "a failed check with no run to re-run: FAILED"
pr 16 b161616 16-a; echo fail > "$STUB_D/checks-b161616"
run land 16 --poll 0
code 3; has "FAILED #16: a check failed on b161616 and no run of it can be re-run - classify it from its log (CORE §4 step 4), never merge over it"

fresh "the approved commit: another head is NOT APPROVED, the approved one (upper case, short) merges"
pr 17 a171717aaaa 17-b; echo pass > "$STUB_D/checks-a171717aaaa"
run land 17@deadbee --poll 0
code 3; has "NOT APPROVED #17: its head a171717 is not the approved deadbee - verify the new commit, then queue 17@a171717"; notcalled "pr merge"
run land 17@A171717 --poll 0
code 0; has "MERGED #17"

fresh "a push while it waits: HEAD MOVED, no merge"
pr 18 c181818 18-c; printf 'pending\nMOVE e181818\n' > "$STUB_D/checks-c181818"
run land 18 --poll 0
code 3; has "HEAD MOVED #18: c181818 -> e181818 while it waited"; notcalled "pr merge"

fresh "runs of the branch on an older head are cancelled, the current head's are not"
pr 11 $H11 11-fix; echo pass > "$STUB_D/checks-$H11"
printf 'https://github.com/o/r/actions/runs/777 0ld0ld0 in_progress \nhttps://github.com/o/r/actions/runs/778 %s in_progress \n779 0ld0ld1 completed success\n' $H11 > "$STUB_D/runs-branch-11-fix"
run land 11 --poll 0
code 0; has "cancelled run 777 (0ld0ld0, superseded)"; called "run cancel 777"; notcalled "run cancel 778"; notcalled "run cancel 779"

fresh "closed, draft, no checks, a refused merge: each left, the queue goes on"
echo "MERGED false a1 1-a main" > "$STUB_D/pr-21"; echo "OPEN true a2 2-b main" > "$STUB_D/pr-22"; pr 23 a3 3-c; pr 24 a4 4-d
echo pass > "$STUB_D/checks-a4"; echo "Pull request is not mergeable: required review missing" > "$STUB_D/merge-24.fail"
run land 21 22 23 24 --poll 0
code 3; has "SKIP #21: MERGED, not open"; has "SKIP #22: a draft"; has "NO CHECKS #23: no check ran on a3"
has "MERGE FAILED #24: Pull request is not mergeable: required review missing"
has "merge-queue: 0 merged, left: #21 (SKIP), #22 (SKIP), #23 (NO CHECKS), #24 (MERGE FAILED)"

fresh "dry run: nothing is changed"
pr 13 $H13 13-x; echo 2 > "$STUB_D/behind-$H13"; pr 11 $H11 11-fix; echo pass > "$STUB_D/checks-$H11"
printf '777 0ld0ld0 in_progress \n' > "$STUB_D/runs-branch-11-fix"
run land 13 11 --poll 0 --dry-run
code 3; has "[dry-run] gh pr update-branch 13"; has "[dry-run] gh run cancel 777"
has "[dry-run] gh pr merge 11 --squash --match-head-commit $H11"
notcalled "pr update-branch"; notcalled "pr merge"; notcalled "run cancel"

fresh "status: merge states, the conflicting PRs and the pairs changing the same files"
printf '31\tMERGEABLE\tCLEAN\t31-a\tsrc/a.ts\tmessages/en.json\n32\tCONFLICTING\tDIRTY\t32-b\tsrc/a.ts\tsrc/b.ts\n33\tMERGEABLE\tBEHIND\t33-c\tmessages/en.json\n' > "$STUB_D/prlist"
run status --shared 'messages/*'
code 0; has "#31 CLEAN 31-a"; has "CONFLICTING #32: 32-b - its worker merges main by hand, CI does not run on it"
has "OVERLAP #31 #32: src/a.ts"; hasnt "OVERLAP #31 #33"; has "merge-queue status: 3 open, 1 conflicting, 1 overlapping pairs"
hasnt "TOUCHES"; hasnt "touching the task"
# --touches: the conflict foresight before a task (CORE §4a) - a file, a folder (with or without its
# slash) or a glob; shared files count too, the task may touch them
run status --touches src/b.ts --touches messages/
code 0; has "TOUCHES #31: 31-a - messages/en.json"; has "TOUCHES #32: 32-b - src/b.ts"; has "TOUCHES #33: 33-c - messages/en.json"
hasnt "src/a.ts, messages"; has ", 3 touching the task"
run status --touches 'src/*.ts'
code 0; has "TOUCHES #31: 31-a - src/a.ts"; has "TOUCHES #32: 32-b - src/a.ts, src/b.ts"; hasnt "TOUCHES #33"; has ", 2 touching the task"
run status --touches messages --touches src/c.ts
code 0; has "TOUCHES #31: 31-a - messages/en.json"; hasnt "TOUCHES #32"; has ", 2 touching the task"
run status --touches src/a
code 0; hasnt "TOUCHES"; has ", 0 touching the task"

# the bounds (#381, the header): a real repository beside the stub - the PR's head is a real commit, the contract a file
qg() { git -C "$tmp/q" -c user.email=t@t -c user.name=t "$@"; }
git init -q --bare "$tmp/q.git"; git init -q -b main "$tmp/q"; qg config core.autocrlf false
mkdir -p "$tmp/q/src" "$tmp/q/coordinator/briefs"; echo base > "$tmp/q/README"
qg add README; qg commit -q -m base; qg remote add origin "$tmp/q.git"; qg push -q origin main 2>/dev/null
qbranch() {   # qbranch <branch> <lines>: a pushed branch of main adding that many lines to src/, its head in QH
  local i=0; qg checkout -q -b "$1" main; mkdir -p "$(dirname "$tmp/q/src/$1.txt")"
  while [ $i -lt "$2" ]; do echo "line $i"; i=$((i + 1)); done > "$tmp/q/src/$1.txt"
  qg add src; qg commit -q -m "$1"; QH="$(qg rev-parse HEAD)"; qg push -q origin "$1" 2>/dev/null; qg checkout -q main; }
qbranch 15-over 5; H15=$QH; qbranch 16-fine 2; H16=$QH; qbranch 17-none 2; H17=$QH; qbranch nameless 1; H18=$QH
# the fixture itself, so a red case never means a wrong repository
[ "$(qg diff --numstat "main...$H15" | tr '\t' ' ')$(qg diff --numstat "main...$H16" | tr '\t' ' ')" = "5 0 src/15-over.txt2 0 src/16-fine.txt" ] ||
  { echo "FAIL: the fixture repository's branches do not add the lines the cases count"; exit 1; }
for id in 15 16; do printf -- '---\nid: %s\ntitle: t\nbounds:\n  - src/* 3\nwall: only a test\n---\n' "$id" > "$tmp/q/coordinator/briefs/$id-contract.md"; done
qpr() { pr "$1" "$2" "$3"; echo pass > "$STUB_D/checks-$2"; }
hasline() { printf '%s\n' "$out" | grep -qxF -- "$1" && ok || bad "expected exactly the line: $1"; }
oneline() { [ "$(printf '%s\n' "$out" | grep -c -- "$1")" = 1 ] && ok || bad "expected exactly one line matching: $1"; }
qback="$(pwd)"; cd "$tmp/q" || exit 1
# a copy of the scripts under a project whose row makes src/* important (#419): the cases below that stop on src/* stop through that row; it goes before the #419 cases
mkdir -p "$tmp/p/c"; cp -R "$core/scripts" "$tmp/p/c/"; printf '| Field | Value |\n|---|---|\n| **Important components** (#381) | `docs/*` `src/*` |\n' > "$tmp/p/PROJECT.md"
core="$tmp/p/c"; command -v cygpath >/dev/null 2>&1 && core="$(cygpath -m "$core")"

fresh "over its bound: stopped with a line of its own, the next PR, within its bound, still lands, exit 3"
qpr 15 "$H15" 15-over; qpr 16 "$H16" 16-fine
run land 15 16 --poll 0
code 3; hasline "OVER BOUNDS 15 src/* 5/3"; notcalled "pr merge 15"; hasnt "MERGED #15"; hasnt "OVER BOUNDS 16"
has "MERGED #16"; called "pr merge 16 --squash --match-head-commit $H16"; has "merge-queue: 1 merged, left: #15 (OVER BOUNDS)"

fresh "no contract for the branch's id: one line, no stop"
qpr 17 "$H17" 17-none
run land 17 --poll 0
code 0; oneline "no contract"; has "BOUNDS #17: no contract"; has "MERGED #17"; hasnt "OVER BOUNDS"

fresh "a branch with no id: one line, no stop"
qpr 18 "$H18" nameless
run land 18 --poll 0
code 0; oneline "no contract"; has "BOUNDS #18: no contract"; has "MERGED #18"

fresh "check-bounds cannot read it: each PR stopped with its own line, fail-closed, the next still lands, exit 3"
qbranch 20-dir 1; H20=$QH; qbranch 21-bad 1; H21=$QH; qbranch 19-gone 1; H19=f191919191919191919191919191919191919191   # its branch is there, a head git does not have
mkdir -p coordinator/briefs/20-contract.md
sed 's/^  - src.*/  - src\/* lots/' coordinator/briefs/16-contract.md > coordinator/briefs/21-contract.md
cp coordinator/briefs/16-contract.md coordinator/briefs/19-contract.md
qpr 19 "$H19" 19-gone; qpr 20 "$H20" 20-dir; qpr 21 "$H21" 21-bad; qpr 16 "$H16" 16-fine
run land 19 20 21 16 --poll 0
code 3; has "BOUNDS #19: check-bounds"; has "BOUNDS #20: check-bounds"; has "BOUNDS #21: check-bounds"
notcalled "pr merge 19"; notcalled "pr merge 20"; notcalled "pr merge 21"; hasnt "no contract"
has "MERGED #16"; has "merge-queue: 1 merged, left: #19 (BOUNDS), #20 (BOUNDS), #21 (BOUNDS)"

fresh "--over-bounds-ok: that PR passes, the owner's words printed"
qpr 15 "$H15" 15-over
run land 15 --poll 0 --over-bounds-ok "15:the owner said yes, merge it"
code 0; has "the owner said yes, merge it"; has "MERGED #15"; called "pr merge 15 --squash"; has "merge-queue: 1 merged"

fresh "--over-bounds-ok for another PR passes nothing"
qpr 15 "$H15" 15-over
run land 15 --poll 0 --over-bounds-ok "16:the owner said yes"
code 3; hasline "OVER BOUNDS 15 src/* 5/3"; notcalled "pr merge 15"

fresh "--over-bounds-ok without its words or its PR: a usage error"
qpr 15 "$H15" 15-over
for v in 15 "15:" "15: " "15:   " $'15:\t' "x:the owner said yes" ":the owner said yes"; do
  run land 15 --poll 0 --over-bounds-ok "$v"; code 1; notcalled "pr merge 15"
done

fresh "the branch-named contract before the id-named: a part suffix, a / in the branch, both copies with different bounds"
qbranch 30a-part 5; H30=$QH; qbranch 31/slash-name 5; H31=$QH; qbranch 32-both 5; H32=$QH; qc() { sed "s/src\/\* 3/src\/* $2/" coordinator/briefs/16-contract.md > "coordinator/briefs/$1-contract.md"; }
qc 30a-part 3; qc 31-slash-name 3; qc 32-both 3; qc 32 100; qpr 30 "$H30" 30a-part; qpr 31 "$H31" 31/slash-name; qpr 32 "$H32" 32-both
run land 30 31 32 --poll 0
code 3; hasline "OVER BOUNDS 30 src/* 5/3"; hasline "OVER BOUNDS 31 src/* 5/3"; hasline "OVER BOUNDS 32 src/* 5/3"; notcalled "pr merge"; hasnt "no contract"

# which OVER stops (#419, the header), the row gone: the core's default list alone. qo <id> <file> [<bound>...]: a pushed branch adding 5 lines to <file>, its contract, its PR landed
rm -f "$tmp/p/PROJECT.md"; qo() { local n="$1" f="$2"; shift 2; qg checkout -q -b "$n-o" main; mkdir -p "$(dirname "$f")"; printf '%s\n' 1 2 3 4 5 > "$f"; qg add "$f"; qg commit -q -m "$n"; QH="$(qg rev-parse HEAD)"; qg push -q origin "$n-o" 2>/dev/null; qg checkout -q main
  { printf -- '---\nid: %s\ntitle: t\n' "$n"; [ $# = 0 ] || { echo 'bounds:'; printf '  - %s\n' "$@"; }; printf 'wall: w\n---\n'; } > "coordinator/briefs/$n-contract.md"; qpr "$n" "$QH" "$n-o"; run land "$n" --poll 0; }
fresh "an OVER on an ordinary glob: the one line, the PR lands"; qo 40 src/40.txt 'src/* 3'; code 0; hasline "bounds over, not important: 40 src/* 5/3"; oneline "not important"; hasnt "OVER BOUNDS"; has "MERGED #40"; called "pr merge 40 --squash --match-head-commit $QH"; has "merge-queue: 1 merged"
fresh "a glob beside an important one, holding none: ordinary"; qo 41 scripts/merge-queue.sh 'scripts/merge-queue.* 3'; code 0; hasline "bounds over, not important: 41 scripts/merge-queue.* 5/3"; hasnt "OVER BOUNDS"; has "MERGED #41"
fresh "a glob matching an important one on the default list: stops, --over-bounds-ok passes it"; qo 42 tests/q/run.sh 'tests/q/run.sh 3'; code 3; hasline "OVER BOUNDS 42 tests/q/run.sh 5/3"; notcalled "pr merge 42"; has "left: #42 (OVER BOUNDS)"; hasnt "not important"
run land 42 --poll 0 --over-bounds-ok "42:the owner said yes"; code 0; has "the owner said yes"; has "MERGED #42"
fresh "a glob holding an important one, on a file that is not: stops"; qo 43 scripts/tool.sh 'scripts/* 3'; code 3; hasline "OVER BOUNDS 43 scripts/* 5/3"; notcalled "pr merge 43"; hasnt "not important"
fresh "ordinary bounds around an important one, all OVER: stops, each its own line"; qo 44 scripts/mix.sh 'scripts/mix.* 3' 'scripts/* 3' 'scripts/mix.sh 3'; code 3; notcalled "pr merge 44"; has "left: #44 (OVER BOUNDS)"; hasline "OVER BOUNDS 44 scripts/* 5/3"; hasline "bounds over, not important: 44 scripts/mix.* 5/3"; hasline "bounds over, not important: 44 scripts/mix.sh 5/3"
fresh "check-bounds exit 2 on an ordinary glob still stops"; qpr 19 "$H19" 19-gone; qpr 20 "$H20" 20-dir; qpr 21 "$H21" 21-bad; run land 19 20 21 --poll 0; code 3; notcalled "pr merge"; has "left: #19 (BOUNDS), #20 (BOUNDS), #21 (BOUNDS)"; hasnt "not important"
fresh "a contract with no bounds: as today"; qo 45 src/45.txt; code 0; has "MERGED #45"; hasnt "OVER BOUNDS"; hasnt "not important"

# the wrong folder: a subfolder, another repository (its origin lacks the branch), no repository at all
mkdir -p "$tmp/q/wrong-sub" "$tmp/wrong-none"; git init -q --bare "$tmp/w.git"; git init -q -b main "$tmp/wrong-repo"; git -C "$tmp/wrong-repo" remote add origin "$tmp/w.git"
for d in q/wrong-sub wrong-repo wrong-none; do for x in "" --dry-run; do
  fresh "the wrong folder: $d $x"; qpr 16 "$H16" 16-fine; cd "$tmp/$d" || exit 1; run land 16 --poll 0 $x; cd "$tmp/q" || exit 1
  code 1; has "${d##*/}"; notcalled "pr merge"; hasnt "MERGED #16"; hasnt "[dry-run] gh pr merge"; hasnt "no contract"
done; done
for x in "" --dry-run; do fresh "gh cannot read the PR from another repository: the refusal names the folder $x"; touch "$STUB_D/fail-view"; cd "$tmp/wrong-repo" || exit 1; run land 16 --poll 0 $x; cd "$tmp/q" || exit 1
  code 1; has "wrong-repo"; has "Could not resolve to a PullRequest"; notcalled "pr merge"; hasnt "[dry-run] gh pr merge"; done
fresh "one PR's branch is not in this repository: nothing merged, the first PR neither"
qpr 16 "$H16" 16-fine; qpr 34 "$H19" 34-elsewhere; run land 16 34 --poll 0; code 1; notcalled "pr merge"; hasnt "MERGED #16"
fresh "status runs anywhere"; cd "$tmp/wrong-none" || exit 1; run status; cd "$qback" || exit 1; code 0; has "merge-queue status: 0 open"

fresh "usage errors and a failing gh: exit 1"
run land; code 1
run land 11 --method fast; code 1
run land 11x; code 1
run land 11@xyz; code 1
run status 11; code 1
run frobnicate; code 1
pr 11 $H11 11-fix; touch "$STUB_D/fail-view"
run land 11 --poll 0; code 1; has "Could not resolve to a PullRequest"; notcalled "pr merge"

echo "merge-queue ($kind): $((pass + fail)) checks, $([ $fail = 0 ] && echo "all pass" || echo "$fail FAILED")"
[ $fail = 0 ]
