#!/usr/bin/env bash
# Land approved PRs one at a time, in the order given (CORE §4a): parallel work, serial merging - each PR
# merges main once, when its turn comes, never after every other merge.
#   scripts/merge-queue.sh land <pr>[@<approved sha>]... [--method squash|merge|rebase] [--shared <glob>]...
#                               [--poll <seconds>] [--timeout <minutes>] [--dry-run]
#   scripts/merge-queue.sh status [--shared <glob>]...
# land, per PR in order: open and not a draft; its head the approved commit (when @<sha> is given); runs of
# its branch on an older head cancelled; behind its base -> `gh pr update-branch` (GitHub merges the base
# in), and when the base brought changes to files the PR changes too (outside --shared), it stops for a
# re-review of that merge; the checks of the current head waited for (all pass or skipped); a failure
# re-runs the failed runs once, a second failure stops; then `gh pr merge --<method>
# --match-head-commit <head>` and the remote branch deleted (never the local one: the worker's worktree
# stays for cleanup-worker), and every open PR that changes a file the merged one changed is printed
# as AFFECTED. The queue never resolves a conflict and never merges a commit it was not given or did not
# make itself. --shared: a file the project lets every task append to or regenerate (PROJECT.md *Shared
# files*); a glob, `*` crosses folders. status: each open PR's merge state, the CONFLICTING ones (CI does
# not run on them) and the pairs of open PRs that change the same files outside --shared.
# Lines (wrappers read them), each `<TAG> #<pr>: ...`: MERGED, AFFECTED, SKIP, NOT APPROVED, CONFLICT,
# REVIEW, HEAD MOVED, FAILED, NO CHECKS, TIMEOUT, MERGE FAILED; status: CONFLICTING, OVERLAP.
# Exit codes: 0 every PR merged (status: always 0); 1 usage error or gh failed; 3 a PR was left (its line
# says why; the queue goes on with the next). Only gh is called, never git (Windows: merge-queue.ps1).
set -uo pipefail

usage="usage: land <pr>[@<sha>]... [--method squash|merge|rebase] [--shared <glob>]... [--poll <s>] [--timeout <min>] [--dry-run] | status [--shared <glob>]..."
mode="${1:-}"; [ $# -gt 0 ] && shift
case "$mode" in land|status) ;; *) echo "$usage" >&2; exit 1 ;; esac
method=squash poll=60 timeout=120 dry=0 prs=() shared=()
need() { [ $# -ge 2 ] && [ -n "$2" ] || { echo "missing value for $1; $usage" >&2; exit 1; }; }
while [ $# -gt 0 ]; do
  case "$1" in
    --method) need "$@"; method="$2"; shift 2 ;;
    --shared) need "$@"; shared+=("$2"); shift 2 ;;
    --poll) need "$@"; poll="$2"; shift 2 ;;
    --timeout) need "$@"; timeout="$2"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    [0-9]*) [ "$mode" = land ] || { echo "status takes no PR; $usage" >&2; exit 1; }; prs+=("$1"); shift ;;
    *) echo "unknown argument: $1; $usage" >&2; exit 1 ;;
  esac
done
case "$method" in squash|merge|rebase) ;; *) echo "--method: squash, merge or rebase; $usage" >&2; exit 1 ;; esac
case "$poll$timeout" in *[!0-9]*) echo "--poll and --timeout take whole numbers; $usage" >&2; exit 1 ;; esac
[ "$mode" = status ] || [ ${#prs[@]} -gt 0 ] || { echo "$usage" >&2; exit 1; }
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
T_PR="{{.state}} {{.isDraft}} {{.headRefOid}} {{.headRefName}} {{.baseRefName}}$NL"
T_FILES="{{range .files}}{{.path}}$NL{{end}}"
T_CMPFILES="{{range .files}}{{.filename}}$NL{{end}}"
T_CHECKS="{{range .}}{{.bucket}}$NL{{end}}"
T_RUNS="{{range .}}{{.url}} {{.headSha}} {{.status}} {{.conclusion}}$NL{{end}}"
T_LIST="{{range .}}{{.number}}$TAB{{.mergeable}}$TAB{{.mergeStateStatus}}$TAB{{.headRefName}}{{range .files}}$TAB{{.path}}{{end}}$NL{{end}}"
# q <gh args>: gh's output; a failed gh stops the run (exit 1), called as `x="$(q ...)" || exit 1`
q() { local out; out="$(gh "$@" 2>&1)" || { printf 'gh %s %s failed: %s\n' "$1" "$2" "$out" >&2; return 1; }; printf '%s\n' "$out"; }
pr_view() { q pr view "$1" --json state,isDraft,headRefOid,headRefName,baseRefName --template "$T_PR"; }
behind() { q api "repos/{owner}/{repo}/compare/$1...$2" --template "{{.behind_by}}"; }
open_prs() { q pr list --state open --limit 200 --json number,mergeable,mergeStateStatus,headRefName,files --template "$T_LIST"; }
is_shared() { local g; for g in ${shared[@]+"${shared[@]}"}; do case "$1" in $g) return 0 ;; esac; done; return 1; }
# meet <lines a> <lines b> [all]: the lines of a also in b (outside --shared unless "all"), joined by ", "
meet() { local f out=""; while IFS= read -r f; do [ -n "$f" ] || continue; [ -z "${3:-}" ] && is_shared "$f" && continue
           printf '%s\n' "$2" | grep -qxF -- "$f" && out="${out:+$out, }$f"; done <<< "$1"; printf '%s' "$out"; }
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
  echo "merge-queue status: $n open, $nc conflicting, $np overlapping pairs"
  exit 0
fi

merged=0 left=""
leave() { echo "$2 #$1: $3"; left="${left:+$left, }#$1 ($2)"; }
for item in "${prs[@]}"; do
  pr="${item%%@*}" want=""; [ "$item" != "$pr" ] && want="$(printf '%s' "${item#*@}" | tr 'A-F' 'a-f')"
  v="$(pr_view "$pr")" || exit 1; read -r state draft head branch base <<< "$v"
  [ "$state" = OPEN ] || { leave "$pr" SKIP "$state, not open"; continue; }
  [ "$draft" = true ] && { leave "$pr" SKIP "a draft"; continue; }
  if [ -n "$want" ]; then case "$head" in "$want"*) ;; *)
    leave "$pr" "NOT APPROVED" "its head ${head:0:7} is not the approved ${want:0:7} - verify the new commit, then queue $pr@${head:0:7}"; continue ;; esac; fi
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
    b="$(gh pr checks "$pr" --json bucket --template "$T_CHECKS" 2>/dev/null | grep -v '^$')"
    if [ -z "$b" ]; then
      empty=$((empty + 1)); [ $empty -ge 5 ] && { result="NO CHECKS|no check ran on ${head:0:7}"; break; }
    elif printf '%s\n' "$b" | grep -qx pending; then seen=1
    elif printf '%s\n' "$b" | grep -qxE 'fail|cancel'; then
      if [ $retried = 0 ]; then
        r="$(q run list --commit "$head" --limit 50 --json url,headSha,status,conclusion --template "$T_RUNS")" || exit 1
        ids="$(printf '%s\n' "$r" | awk '$4 ~ /^(failure|cancelled|timed_out|startup_failure)$/ { n = split($1, p, "/"); print p[n] }')"
        [ -n "$ids" ] || { result="FAILED|a check failed on ${head:0:7} and no run of it can be re-run"; break; }
        if [ "$dry" = 1 ]; then for id in $ids; do echo "[dry-run] gh run rerun $id --failed"; done
          result="SKIP|dry run - a check failed, would re-run it once"; break; fi
        for id in $ids; do gh run rerun "$id" --failed >/dev/null 2>&1; done
        echo "re-ran #$pr's failed runs once:" $ids; retried=1 seen=0 rpoll=0
      elif [ $seen = 1 ] || [ $rpoll -ge 3 ]; then
        result="FAILED|its checks failed twice on ${head:0:7} - read the log before anything else"; break
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
  gh api -X DELETE "repos/{owner}/{repo}/git/refs/heads/$branch" >/dev/null 2>&1 && echo "deleted the remote branch $branch"
  # the open PRs that change a file this one changed (shared ones too): their workers merge main now
  list="$(open_prs)" || exit 1
  while IFS= read -r l; do [ -n "$l" ] || continue
    num="${l%%"$TAB"*}"; [ "$num" = "$pr" ] && continue
    both="$(meet "$(pr_files "$l")" "$files" all)"
    [ -n "$both" ] && echo "AFFECTED #$num: $(printf '%s\n' "$l" | cut -f4) - merge $base now: $both"
  done <<< "$list"
done
echo "merge-queue: $merged merged${left:+, left: $left}"
[ -z "$left" ] || exit 3
