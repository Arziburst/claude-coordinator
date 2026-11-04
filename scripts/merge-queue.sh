#!/usr/bin/env bash
# Land approved PRs one at a time, in the order given (CORE §4a): parallel work, serial merging - each PR
# merges main once, when its turn comes, never after every other merge.
#   scripts/merge-queue.sh land <pr>[@<approved sha>]... [--method squash|merge|rebase] [--shared <glob>]...
#                               [--poll <seconds>] [--timeout <minutes>] [--over-bounds-ok <pr>:<the owner's words>] [--dry-run]
#   scripts/merge-queue.sh status [--shared <glob>]... [--touches <path or glob>]...
# land, per PR in order: open and not a draft; its head the approved commit (when @<sha> is given); runs of
# its branch on an older head cancelled; behind its base -> `gh pr update-branch` (GitHub merges the base
# in), and when the base brought changes to files the PR changes too (outside --shared), it stops for a
# re-review of that merge; the checks of the current head waited for (all pass or skipped); a failure
# re-runs the failed runs once, a second failure stops; then `gh pr merge --<method>
# --match-head-commit <head>` and the remote branch deleted (never the local one: the worker's worktree
# stays for cleanup-worker; a branch other open PRs are based on is kept, #229; a fork's PR deletes nothing there, #392), and every open PR that
# changes a file the merged one changed is printed
# as AFFECTED, then the AFTER MERGE lines: the merge row of CORE §4's event table, one thing a line with the PR's values, so its duties have a
# trigger (#242). The queue never resolves a conflict and never merges a commit it was not given or did
# not make itself. --shared: a file the project lets every task append to or regenerate (PROJECT.md
# *Shared files*); a glob, `*` crosses folders. status: each open PR's merge state, the CONFLICTING ones
# (CI does not run on them) and the pairs of open PRs that change the same files outside --shared; with
# --touches (a task's `touches`: a file, a folder or a glob), the open PRs changing anything under them,
# as TOUCHES - the conflict foresight before a task (CORE §4a; start-worker runs it).
# Lines (wrappers read them), each `<TAG> #<pr>: ...`: MERGED, AFFECTED, AFTER MERGE, SKIP, NOT APPROVED,
# CONFLICT, REVIEW, HEAD MOVED, FAILED, NO CHECKS, TIMEOUT, MERGE FAILED; status: CONFLICTING, OVERLAP,
# TOUCHES.
# The bounds (#381, #387), land: the contract at coordinator/briefs/<head branch, / as ->-contract.md (start-worker saves it there), else by the id its branch starts with (coordinator/briefs/<id>-contract.md),
# scripts/check-bounds on origin/<base>...<head>. OVER on a bound whose glob matches or holds an important glob (#419; check-contract's list, its --important): `OVER BOUNDS <pr> <glob> <added>/<max>`, left; any other OVER: `bounds over, not important: <pr> <glob> <added>/<max>`, it goes on. Its exit 2: `BOUNDS #<pr>: check-bounds ...`, left,
# fail-closed. No contract: `BOUNDS #<pr>: no contract ...`, no stop. --over-bounds-ok passes that PR's stopping OVER, its words printed; one per run, two PRs go in two runs.
# The folder (#387), land and --dry-run, checked before any PR merges: the cwd is a repository's root whose origin has each open PR's branch (`git ls-remote`; a fork's PR has no branch there, so only the root holds for it), else a usage error naming the folder,
# exit 1. Origin unreadable: exit 1, a line saying so, never read as a missing branch. A limit: another repository whose origin has a branch of the same name passes. status: no folder check.
# Exit codes: 0 every PR merged (status: always 0); 1 usage error or gh failed; 3 a PR was left (its line
# says why; the queue goes on with the next). gh is called, and git only to read the folder and origin and to fetch the head check-bounds reads (Windows: merge-queue.ps1).
set -uo pipefail

usage="usage: land <pr>[@<sha>]... [--method squash|merge|rebase] [--shared <glob>]... [--poll <s>] [--timeout <min>] [--over-bounds-ok <pr>:<words>] [--dry-run] | status [--shared <glob>]... [--touches <path>]..."
mode="${1:-}"; [ $# -gt 0 ] && shift
case "$mode" in land|status) ;; *) echo "$usage" >&2; exit 1 ;; esac
method=squash poll=60 timeout=120 dry=0 prs=() shared=() touches=() ook=""
need() { [ $# -ge 2 ] && [ -n "$2" ] || { echo "missing value for $1; $usage" >&2; exit 1; }; }
while [ $# -gt 0 ]; do
  case "$1" in
    --method) need "$@"; method="$2"; shift 2 ;;
    --shared) need "$@"; shared+=("$2"); shift 2 ;;
    --touches) need "$@"; touches+=("$2"); shift 2 ;;
    --poll) need "$@"; poll="$2"; shift 2 ;;
    --timeout) need "$@"; timeout="$2"; shift 2 ;;
    --over-bounds-ok) need "$@"; [ -z "$ook" ] || { echo "--over-bounds-ok: one per run, two PRs go in two runs; $usage" >&2; exit 1; }; ook="$2"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    [0-9]*) [ "$mode" = land ] || { echo "status takes no PR; $usage" >&2; exit 1; }; prs+=("$1"); shift ;;
    *) echo "unknown argument: $1; $usage" >&2; exit 1 ;;
  esac
done
case "$method" in squash|merge|rebase) ;; *) echo "--method: squash, merge or rebase; $usage" >&2; exit 1 ;; esac
case "$poll$timeout" in *[!0-9]*) echo "--poll and --timeout take whole numbers; $usage" >&2; exit 1 ;; esac
[ "$mode" = status ] || [ ${#prs[@]} -gt 0 ] || { echo "$usage" >&2; exit 1; }
okpr="${ook%%:*}" okw="${ook#*:}"
[ -z "$ook" ] || { [ "$okw" != "$ook" ] && case "$okw" in *[![:space:]]*) true ;; *) false ;; esac && case "$okpr" in ''|*[!0-9]*) false ;; *) true ;; esac; } || { echo "--over-bounds-ok takes <pr>:<the owner's words>; $usage" >&2; exit 1; }
for item in ${prs[@]+"${prs[@]}"}; do
  case "$item" in *@*) p="${item%%@*}" s="${item#*@}" ;; *) p="$item" s=0 ;; esac
  case "$p" in ''|*[!0-9]*) echo "not a PR number: $item; $usage" >&2; exit 1 ;; esac
  case "$s" in ''|*[!0-9a-fA-F]*) echo "not a commit: $item; $usage" >&2; exit 1 ;; esac
done
command -v gh >/dev/null 2>&1 || { echo "gh: command not found" >&2; exit 1; }

NL='
'; TAB='	'
# gh's --template prints plain lines (no JSON to read); a literal newline or tab, never a quoted "\n", so
# Windows PowerShell 5.1 hands gh the same template
T_PR="{{.state}} {{.isDraft}} {{.headRefOid}} {{.headRefName}} {{.baseRefName}} {{.isCrossRepository}}$NL"
T_FILES="{{range .files}}{{.path}}$NL{{end}}"
T_CMPFILES="{{range .files}}{{.filename}}$NL{{end}}"
# a check name can run more than once on one head (a pull_request run and a later workflow_dispatch run):
# only the newest of each name counts, a run not started yet being the newest (#234)
T_CHECKS="{{range .}}{{.name}}$TAB{{.startedAt}}$TAB{{.bucket}}$NL{{end}}"
T_RUNS="{{range .}}{{.url}} {{.headSha}} {{.status}} {{.conclusion}}$NL{{end}}"
T_LIST="{{range .}}{{.number}}$TAB{{.mergeable}}$TAB{{.mergeStateStatus}}$TAB{{.headRefName}}{{range .files}}$TAB{{.path}}{{end}}$NL{{end}}"
# q <gh args>: gh's output; a failed gh stops the run (exit 1), called as `x="$(q ...)" || exit 1`
q() { local out; out="$(gh "$@" 2>&1)" || { printf 'gh %s %s failed%s: %s\n' "$1" "$2" "${here:+ (folder $here)}" "$out" >&2; return 1; }; printf '%s\n' "$out"; }
pr_view() { q pr view "$1" --json state,isDraft,headRefOid,headRefName,baseRefName,isCrossRepository --template "$T_PR"; }
behind() { q api "repos/{owner}/{repo}/compare/$1...$2" --template "{{.behind_by}}"; }
open_prs() { q pr list --state open --limit 200 --json number,mergeable,mergeStateStatus,headRefName,files --template "$T_LIST"; }
is_shared() { local g; for g in ${shared[@]+"${shared[@]}"}; do case "$1" in $g) return 0 ;; esac; done; return 1; }
# meet <lines a> <lines b> [all]: the lines of a also in b (outside --shared unless "all"), joined by ", "
meet() { local f out=""; while IFS= read -r f; do [ -n "$f" ] || continue; [ -z "${3:-}" ] && is_shared "$f" && continue
           printf '%s\n' "$2" | grep -qxF -- "$f" && out="${out:+$out, }$f"; done <<< "$1"; printf '%s' "$out"; }
# under <file>: inside one of --touches - the path itself, a file below it, or a match of it as a glob
under() { local t; for t in ${touches[@]+"${touches[@]}"}; do case "$1" in "${t%/}"|"${t%/}"/*) return 0 ;; esac
            case "$1" in $t) return 0 ;; esac; done; return 1; }
pr_files() { printf '%s\n' "$1" | cut -f5- | tr '\t' '\n'; }

if [ "$mode" = status ]; then
  list="$(open_prs)" || exit 1
  n=0 nc=0 np=0
  while IFS="$TAB" read -r num mg ms br _; do
    [ -n "$num" ] || continue; n=$((n + 1)); echo "#$num $ms $br"
    [ "$mg" = CONFLICTING ] && { nc=$((nc + 1)); echo "CONFLICTING #$num: $br - its worker merges main by hand, CI does not run on it"; }
  done <<< "$list"
  i=0; while IFS= read -r a; do i=$((i + 1)); [ -n "$a" ] || continue; j=0
    while IFS= read -r b; do j=$((j + 1)); [ $j -gt $i ] && [ -n "$b" ] || continue
      both="$(meet "$(pr_files "$a")" "$(pr_files "$b")")"
      [ -n "$both" ] && { np=$((np + 1)); echo "OVERLAP #${a%%"$TAB"*} #${b%%"$TAB"*}: $both"; }
    done <<< "$list"
  done <<< "$list"
  nt=0; if [ ${#touches[@]} -gt 0 ]; then
    while IFS= read -r a; do [ -n "$a" ] || continue; hit=""
      while IFS= read -r f; do [ -n "$f" ] && under "$f" && hit="${hit:+$hit, }$f"; done <<< "$(pr_files "$a")"
      [ -n "$hit" ] && { nt=$((nt + 1)); echo "TOUCHES #${a%%"$TAB"*}: $(printf '%s\n' "$a" | cut -f4) - $hit"; }
    done <<< "$list"
  fi
  echo "merge-queue status: $n open, $nc conflicting, $np overlapping pairs${touches[0]+, $nt touching the task}"
  exit 0
fi

here="$(pwd)"; rp="$(git rev-parse --show-prefix 2>/dev/null)" && [ -z "$rp" ] || { echo "land: folder $here is not the root of a repository (a subfolder, or no repository) - land runs from the root of the repository holding the PR's branch; $usage" >&2; exit 1; }
for item in "${prs[@]}"; do pr="${item%%@*}"; v="$(pr_view "$pr")" || exit 1; read -r state _ _ branch _ fork <<< "$v"; [ "$state" = OPEN ] && [ "$fork" != true ] || continue
  e="$(git ls-remote -q --exit-code origin "refs/heads/$branch" 2>&1 >/dev/null)"; lrc=$?
  [ "$lrc" != 2 ] || { echo "land: folder $here - its origin has no branch $branch of #$pr: land runs from the root of the repository holding the PR's branch; $usage" >&2; exit 1; }
  [ "$lrc" = 0 ] || { echo "land: origin could not be read from folder $here for #$pr's branch $branch: $(printf '%s\n' "$e" | tr -d '\r' | head -n 1)" >&2; exit 1; }
done; here=""
merged=0 left=""
leave() { echo "$2 #$1: $3"; left="${left:+$left, }#$1 ($2)"; }
for item in "${prs[@]}"; do
  pr="${item%%@*}" want=""; [ "$item" != "$pr" ] && want="$(printf '%s' "${item#*@}" | tr 'A-F' 'a-f')"
  v="$(pr_view "$pr")" || exit 1; read -r state draft head branch base fork <<< "$v"
  [ "$state" = OPEN ] || { leave "$pr" SKIP "$state, not open"; continue; }
  [ "$draft" = true ] && { leave "$pr" SKIP "a draft"; continue; }
  if [ -n "$want" ]; then case "$head" in "$want"*) ;; *)
    leave "$pr" "NOT APPROVED" "its head ${head:0:7} is not the approved ${want:0:7} - verify the new commit, then queue $pr@${head:0:7}"; continue ;; esac; fi
  # the contract's bounds (#381, the header)
  bc="coordinator/briefs/$(printf '%s' "$branch" | tr / -)-contract.md"; [ -e "$bc" ] || bc="coordinator/briefs/${branch%%-*}-contract.md"
  if [ ! -e "$bc" ]; then echo "BOUNDS #$pr: no contract at $bc - not checked"
  else git fetch -q origin "$base" >/dev/null 2>&1; git fetch -q origin "$branch" >/dev/null 2>&1
    bo="$(bash "$(dirname "$0")/check-bounds.sh" "$bc" "origin/$base...$head" 2>&1 | tr -d '\r')"; brc=$?
    bover="$(printf '%s\n' "$bo" | sed -n 's/^check-bounds: OVER //p')"
    if [ "$brc" = 1 ]; then   # which OVER stops (#419, the header); the list unreadable: every OVER stops
      bimp="$(bash "$(dirname "$0")/check-contract.sh" --important | tr -d '\r')" || bimp=""; bstop=""; bnl=$'\n'
      while IFS= read -r bl; do bg="${bl% *}"; bs=""; [ -n "$bimp" ] || bs=1
        while IFS= read -r bi; do case "$bi" in $bg) bs=1 ;; esac; case "$bg" in $bi) bs=1 ;; esac; done <<<"$bimp"
        if [ -n "$bs" ]; then bstop="$bstop${bstop:+$bnl}$bl"; else echo "bounds over, not important: $pr $bl"; fi; done <<<"$bover"
      bover="$bstop"; [ -n "$bover" ] || brc=0
    fi
    if [ "$brc" = 1 ] && [ "$okpr" = "$pr" ]; then echo "BOUNDS #$pr: over its bounds ($(printf '%s\n' "$bover" | tr '\n' ' ' | sed 's/ $//')) - passed on the owner's words: $okw"
    elif [ "$brc" = 1 ]; then printf '%s\n' "$bover" | sed "s/^/OVER BOUNDS $pr /"; left="${left:+$left, }#$pr (OVER BOUNDS)"; continue
    elif [ "$brc" != 0 ]; then leave "$pr" BOUNDS "check-bounds exit $brc: $(printf '%s\n' "$bo" | head -n 1)"; continue; fi
  fi
  files="$(q pr view "$pr" --json files --template "$T_FILES")" || exit 1
  runs="$(q run list --branch "$branch" --limit 50 --json url,headSha,status,conclusion --template "$T_RUNS")" || exit 1
  # runs of this branch on an older head: superseded, they only hold the runners. A run's id is the end of
  # its url: gh's template prints the numeric databaseId as a float (3.88e+10)
  while read -r id sha st _; do
    id="${id##*/}"; [ -n "$id" ] && [ "$st" != completed ] && [ "$sha" != "$head" ] || continue
    if [ "$dry" = 1 ]; then echo "[dry-run] gh run cancel $id"; else gh run cancel "$id" >/dev/null 2>&1; echo "cancelled run $id (${sha:0:7}, superseded)"; fi
  done <<< "$runs"
  k="$(behind "$base" "$head")" || exit 1
  if [ "${k:-0}" != 0 ]; then
    [ "$dry" = 1 ] && { echo "[dry-run] gh pr update-branch $pr"; leave "$pr" SKIP "dry run - $k behind $base, would update its branch and wait for its checks"; continue; }
    out="$(gh pr update-branch "$pr" 2>&1)" ||
      { leave "$pr" CONFLICT "$branch - $base did not merge in ($(printf '%s' "$out" | tr '\n' ' ')); its worker merges $base by hand, runs its checks and pushes, then queue it again"; continue; }
    # GitHub answers before the PR shows its new head: read it again until it moves (about 90 s)
    new="$head" n=0
    while [ "$new" = "$head" ] && [ $n -lt 18 ]; do
      [ $n -gt 0 ] && sleep $(( poll < 5 ? poll : 5 )); n=$((n + 1))
      v="$(pr_view "$pr")" || exit 1; read -r _ _ new _ _ <<< "$v"
    done
    [ "$new" != "$head" ] || { leave "$pr" TIMEOUT "its branch was updated, but its head did not move within 90 s - queue it again"; continue; }
    k="$(behind "$base" "$new")" || exit 1
    if [ "${k:-0}" != 0 ]; then
      leave "$pr" CONFLICT "$branch - $base did not merge in; its worker merges $base by hand, runs its checks and pushes, then queue it again"; continue
    fi
    came="$(q api "repos/{owner}/{repo}/compare/$head...$new" --template "$T_CMPFILES")" || exit 1
    both="$(meet "$files" "$came")"
    if [ -n "$both" ]; then
      leave "$pr" REVIEW "$base changed files this PR changes too: $both - re-review the merge (git diff ${head:0:7} ${new:0:7}), then queue $pr@${new:0:7}"; continue
    fi
    echo "updated #$pr: ${head:0:7} -> ${new:0:7}, $base merged in without touching the PR's files"; head="$new"
  fi
  # the checks of the current head: all pass or skipped -> green; a failure re-runs the failed runs once;
  # after the re-run a failure counts again once a check went pending (or after three polls)
  start=$(date +%s) retried=0 seen=0 rpoll=0 empty=0 result=""
  while :; do
    v="$(pr_view "$pr")" || exit 1; read -r _ _ now _ _ <<< "$v"
    [ "$now" = "$head" ] || { result="HEAD MOVED|${head:0:7} -> ${now:0:7} while it waited - verify the new commit, then queue $pr@${now:0:7}"; break; }
    b="$(gh pr checks "$pr" --json name,startedAt,bucket --template "$T_CHECKS" 2>/dev/null | awk -F"$TAB" 'NF >= 3 { t = $2; if (t == "" || t ~ /^0001-/) t = "9999"; if (!($1 in T) || t >= T[$1]) { T[$1] = t; B[$1] = $3 } } END { for (k in B) print B[k] }')"
    if [ -z "$b" ]; then
      empty=$((empty + 1)); [ $empty -ge 5 ] && { result="NO CHECKS|no check ran on ${head:0:7}"; break; }
    elif printf '%s\n' "$b" | grep -qx pending; then seen=1
    elif printf '%s\n' "$b" | grep -qxE 'fail|cancel'; then
      if [ $retried = 0 ]; then
        r="$(q run list --commit "$head" --limit 50 --json url,headSha,status,conclusion --template "$T_RUNS")" || exit 1
        ids="$(printf '%s\n' "$r" | awk '$4 ~ /^(failure|cancelled|timed_out|startup_failure)$/ { n = split($1, p, "/"); print p[n] }')"
        [ -n "$ids" ] || { result="FAILED|a check failed on ${head:0:7} and no run of it can be re-run - classify it from its log (CORE §4 step 4), never merge over it"; break; }
        if [ "$dry" = 1 ]; then for id in $ids; do echo "[dry-run] gh run rerun $id --failed"; done
          result="SKIP|dry run - a check failed, would re-run it once"; break; fi
        for id in $ids; do gh run rerun "$id" --failed >/dev/null 2>&1; done
        echo "re-ran #$pr's failed runs once:" $ids; retried=1 seen=0 rpoll=0
      elif [ $seen = 1 ] || [ $rpoll -ge 3 ]; then
        result="FAILED|its checks failed twice on ${head:0:7} - read the log before anything else: the queue re-ran them once, so a flake is a flake bug; classify it (CORE §4 step 4), never merge over it"; break
      else rpoll=$((rpoll + 1)); fi
    else result=green; break; fi
    [ "$dry" = 1 ] && { result="SKIP|dry run - its checks are pending"; break; }
    [ $(( $(date +%s) - start )) -ge $((timeout * 60)) ] && { result="TIMEOUT|its checks still pending after $timeout min"; break; }
    sleep "$poll"
  done
  [ "$result" = green ] || { leave "$pr" "${result%%|*}" "${result#*|}"; continue; }
  if [ "$dry" = 1 ]; then echo "[dry-run] gh pr merge $pr --$method --match-head-commit $head"
    leave "$pr" SKIP "dry run - green, would merge"; continue; fi
  # no --delete-branch: gh would also delete the local branch and with it the worker's worktree, past
  # cleanup-worker's checks (CORE §8); only the remote branch goes, cleanup-worker removes the rest
  out="$(gh pr merge "$pr" "--$method" --match-head-commit "$head" 2>&1)" ||
    { leave "$pr" "MERGE FAILED" "$(printf '%s' "$out" | tr '\n' ' ')"; continue; }
  merged=$((merged + 1)); echo "MERGED #$pr: ${head:0:7}"
  # a branch other open PRs are based on stays: GitHub closes a PR whose base is deleted (#229)
  deps="$(gh pr list --state open --base "$branch" --json number --template "{{range .}}#{{.number}} {{end}}" 2>/dev/null)"
  # a fork's PR: its branch is not on origin, and that name there may be someone else's branch (#392)
  if [ "$fork" = true ]; then echo "left the fork's branch $branch: #$pr is a fork's PR, nothing deleted on origin"
  elif [ -n "$deps" ]; then echo "kept the remote branch $branch: ${deps% } use it as their base"
  else gh api -X DELETE "repos/{owner}/{repo}/git/refs/heads/$branch" >/dev/null 2>&1 && echo "deleted the remote branch $branch"; fi
  # the open PRs that change a file this one changed (shared ones too): their workers merge main now
  list="$(open_prs)" || exit 1
  while IFS= read -r l; do [ -n "$l" ] || continue
    num="${l%%"$TAB"*}"; [ "$num" = "$pr" ] && continue
    both="$(meet "$(pr_files "$l")" "$files" all)"
    [ -n "$both" ] && echo "AFFECTED #$num: $(printf '%s\n' "$l" | cut -f4) - merge $base now: $both"
  done <<< "$list"
  # the merge row of CORE §4's event table, one thing a line, filled in; printed only, nothing here runs a duty (#242, #466)
  n='<n>'; printf '%s' "$branch" | grep -qE '^[0-9]+-' && n="${branch%%-*}"
  while IFS= read -r l; do echo "AFTER MERGE #$pr: $l"; done <<EOF
cleanup-worker --worktree .claude/worktrees/$branch (CORE §8)
the run rows of task $n (branch $branch), then runs check, and the journal line (CORE §7)
close issue #$n and move it on the board, by the project's words (PROJECT.md) where it has none
the task row, from the product repository: gh pr view $pr --json statusCheckRollup,mergedAt,createdAt | run-stats coordinator/RUNS.tsv --task $n --pr-json - --append
tell each AFFECTED PR's session to merge $base (CORE §4a)
did a rule or number in the project's own files move? did a core rule or check fail us, the verifier's core_findings too (CORE §10)? an escape (CORE §12)?
the project's own after-merge duties (PROJECT.md)
EOF
done
echo "merge-queue: $merged merged${left:+, left: $left}"
[ -z "$left" ] || exit 3
