#!/usr/bin/env bash
# Checks of merge-queue against a stub `gh` on PATH (GitHub is never called): the stub answers from the
# files of a state folder and logs every call.
#   tests/merge-queue/run.sh sh                    # merge-queue.sh, with the bash running this file
#   tests/merge-queue/run.sh ps pwsh               # merge-queue.ps1 (or: ps powershell)
# Exit 1 if any check fails.
set -u
[ $# -gt 0 ] || { sed -n '2,6s/^# \{0,1\}//p' "$0"; exit 2; }
kind="$1"; shift
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
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
    case "$l" in MOVE\ *) p="$3"; set -- $l; read -r s d _ b c < "$D/pr-$p"; echo "$s $d $2 $b $c" > "$D/pr-$p"; echo pending; exit 8 ;; esac
    for k in $l; do echo "$k"; done ;;
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
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH"

case "$kind" in
  sh) mq() { bash "$core/scripts/merge-queue.sh" "$@"; } ;;
  ps) ps="${1:-pwsh}"
      # the .sh's flags as the .ps1's parameters: land/status stay, --x y -> -X y, the PRs as -Pr a,b
      mq() { local a=() prs="" sh="" nx=""
        for x in "$@"; do
          [ "$nx" = shared ] && { sh="${sh:+$sh,}$x"; nx=""; continue; }
          [ "$nx" = value ] && { a+=("$x"); nx=""; continue; }
          case "$x" in
          land|status) a+=("$x") ;; --method) a+=(-Method); nx=value ;; --shared) nx=shared ;;
          --poll) a+=(-Poll); nx=value ;; --timeout) a+=(-Timeout); nx=value ;; --dry-run) a+=(-DryRun) ;; --*) a+=("$x") ;;
          [0-9]*) prs="${prs:+$prs,}$x" ;; *) a+=("$x") ;; esac; done
        [ -n "$prs" ] && a+=(-Pr "$prs"); [ -n "$sh" ] && a+=(-Shared "$sh")
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

fresh "up to date, green: merged; an open PR changing the same file is AFFECTED"
pr 11 $H11 11-fix; printf 'src/x.ts\ndocs/LOG.md\n' > "$STUB_D/files-11"; echo "pass skipping" > "$STUB_D/checks-$H11"
printf '11\tMERGEABLE\tCLEAN\t11-fix\tsrc/x.ts\n12\tMERGEABLE\tBEHIND\t12-feat\tsrc/x.ts\tdocs/LOG.md\n19\tMERGEABLE\tBEHIND\t19-other\tsrc/q.ts\n' > "$STUB_D/prlist"
run land 11 --poll 0
code 0; has "MERGED #11: a111111"; has "AFFECTED #12: 12-feat - merge main now: src/x.ts, docs/LOG.md"; hasnt "AFFECTED #19"
has "merge-queue: 1 merged"; called "pr merge 11 --squash --match-head-commit $H11"; notcalled "--delete-branch"
called "api -X DELETE repos/"; called "/git/refs/heads/11-fix"; has "deleted the remote branch 11-fix"

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

fresh "a failure right after the re-run (no pending seen yet) is the old result: waited for"
pr 16 b161616 16-a; printf 'fail\nfail\npending\npass\n' > "$STUB_D/checks-b161616"; echo '901 b161616 completed failure' > "$STUB_D/runs-commit-b161616"
run land 16 --poll 0
code 0; has "MERGED #16"

fresh "a failed check with no run to re-run: FAILED"
pr 16 b161616 16-a; echo fail > "$STUB_D/checks-b161616"
run land 16 --poll 0
code 3; has "FAILED #16: a check failed on b161616 and no run of it can be re-run"

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
