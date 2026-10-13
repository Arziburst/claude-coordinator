#!/usr/bin/env bash
# The run-stats cases: the fixture run logs against their expected lines (a task's rows summed - worker,
# tester and verifier, a lead and its sub-runs -, more than 10 tasks so only the last 10 count, old rows
# without the time columns, `-` and other non-values, fewer than 4, even counts, a header in another
# order, no header, a header only, a CRLF copy with a BOM), --per-run, one pair's line, a missing file
# (exit 1) and usage errors (exit 2); --limits on the fixtures in limits/ (a trusted window, a fresh one
# with a guess and with the previous ratio, a block that fits and one that does not, a window that has
# reset and one absent, no rate_limits, a pretty-printed JSON with CRLF and a BOM, mixed models priced
# apart with a dated id and a not-weekly one, a spend from stdin, the default status file, an unpriced
# model, a malformed price line, missing files and usage errors); the ready columns from task rows
# (ready.tsv); --task on the fixtures in task/ (the checks green after the verifier and before it, a red run
# then a green rerun, owner waits mid-task, an unmerged PR, no checks, no PR, a lead, no header and another
# order, CRLF and a BOM, stdin, not ready on a red or running check or an unapproved verifier, errors).
#   tests/run-stats/run.sh sh              # scripts/run-stats.sh, with the bash running this file
#   tests/run-stats/run.sh ps pwsh         # scripts/run-stats.ps1 (or: ps powershell)
# Exit 1 if any case fails.
set -u
[ $# -gt 0 ] || { sed -n '2,17s/^# \{0,1\}//p' "$0"; exit 2; }
kind="$1"; shift
[ "$kind" = sh ] || [ "$kind" = ps ] || { sed -n '2,17s/^# \{0,1\}//p' "$0"; exit 2; }
PS=("$@")
[ "$kind" = sh ] || [ ${#PS[@]} -gt 0 ] || { echo "ps needs the PowerShell command" >&2; exit 2; }
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -r "$tmp"' EXIT
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }   # Git Bash -> C:/...
cp "$here"/*.tsv "$tmp/"
# the same run log with CRLF line ends and a UTF-8 BOM (a file saved by a Windows editor)
{ printf '\357\273\277'; awk '{ sub(/\r$/, ""); printf "%s\r\n", $0 }' "$here/runs.tsv"; } > "$tmp/crlf.tsv"
cp "$here"/limits/*.json "$here"/limits/*.txt "$tmp/"
# the limits fixtures: a pretty-printed status JSON and a spend file with CRLF and a BOM
{ printf '\357\273\277'; awk '{ sub(/\r$/, ""); printf "%s\r\n", $0 }' "$here/limits/status-pretty.json"; } > "$tmp/status-crlf.json"
{ printf '\357\273\277'; awk '{ sub(/\r$/, ""); printf "%s\r\n", $0 }' "$here/limits/spend-week.txt"; } > "$tmp/spend-week-crlf.txt"
mkdir -p "$tmp/cfg/coordinator" && cp "$here/limits/status-trusted.json" "$tmp/cfg/coordinator/statusline.json"
# the --task fixtures (the task's runs.tsv replaces nothing: copied under its own names), and CRLF + BOM copies
cp "$here"/task/pr-*.json "$here"/task/waits*.txt "$tmp/" && cp "$here/task/runs.tsv" "$tmp/task-runs.tsv"
cp "$here/task/noheader.tsv" "$tmp/noheader-task.tsv" && cp "$here/task/reordered.tsv" "$tmp/reordered-task.tsv"
for x in task/runs.tsv:runs-crlf.tsv task/pr-rerun.json:pr-rerun-crlf.json task/waits.txt:waits-crlf.txt; do
  { printf '\357\273\277'; awk '{ sub(/\r$/, ""); printf "%s\r\n", $0 }' "$here/${x%%:*}"; } > "$tmp/${x#*:}"
done
cd "$tmp" || exit 1

# runs the script under test in $tmp; stdout to out, stderr to err, \r removed; stdin from $IN (none: empty)
run() {
  if [ "$kind" = ps ]; then
    local a=()
    for x in "$@"; do case "$x" in --kind) a+=(-Kind) ;; --model) a+=(-Model) ;; --per-run) a+=(-PerRun) ;;
      --limits) a+=(-Limits) ;; --status) a+=(-Status) ;; --spend-5h) a+=(-Spend5h) ;; --spend-week) a+=(-SpendWeek) ;;
      --prices) a+=(-Prices) ;; --prev-5h) a+=(-Prev5h) ;; --prev-week) a+=(-PrevWeek) ;; --cap-5h) a+=(-Cap5h) ;;
      --cap-week) a+=(-CapWeek) ;; --block) a+=(-Block) ;; --now) a+=(-Now) ;;
      --task) a+=(-Task) ;; --pr-json) a+=(-PrJson) ;; --waits) a+=(-Waits) ;;
      # stdin: 5.1 takes a bare - after a parameter through -File for a parameter name and fails, so -Spend5h:-
      -) case "${a[${#a[@]}-1]}" in -Spend5h | -SpendWeek | -PrJson | -Waits) a[${#a[@]}-1]="${a[${#a[@]}-1]}:-" ;; *) a+=(-) ;; esac ;;
      *) a+=("$x") ;; esac; done
    "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$(winpath "$core/scripts/run-stats.ps1")" ${a[@]+"${a[@]}"} < "${IN:-/dev/null}" > out.raw 2> err.raw
  else
    bash "$core/scripts/run-stats.sh" "$@" < "${IN:-/dev/null}" > out.raw 2> err.raw
  fi
  rc=$?
  tr -d '\r' < out.raw > out; tr -d '\r' < err.raw > err
}
fail=0; n=0
bad() { echo "FAIL $*"; fail=1; }
# expect <name> <exit code> <stdout file, - for none, * for any> <stderr text or -> -- <arguments...>
expect() {
  local name="$1" want_rc="$2" want_out="$3" want_err="$4"; shift 5
  n=$((n + 1)); run "$@"
  [ "$rc" = "$want_rc" ] || { bad "$name: exit $rc, want $want_rc"; sed 's/^/  err: /' err; return; }
  if [ "$want_out" = - ]; then [ ! -s out ] || { bad "$name: printed"; sed 's/^/  got: /' out; return; }
  elif [ "$want_out" != '*' ] && ! [ "$(cat out)" = "$(tr -d '\r' < "$want_out")" ]; then
    bad "$name: differs from ${want_out#"$here"/}"; sed 's/^/  got: /' out; return
  fi
  [ "$want_err" = - ] || [ "$(cat err)" = "$want_err" ] || { bad "$name: stderr"; sed 's/^/  got: /' err; return; }
  echo "ok   $name"
}
t="$here"
expect "a run log: the last 10 tasks, old rows, non-values, under 4, even counts" 0 "$t/expected-runs.txt" - -- runs.tsv
expect "tasks summed: worker, tester and verifier; a lead and its sub-runs" 0 "$t/expected-tasks.txt" - -- tasks.tsv
expect "--per-run: every row on its own, by kind, role and model" 0 "$t/expected-per-run.txt" - -- tasks.tsv --per-run
expect "no header: the columns in CORE 7's order" 0 "$t/expected-noheader.txt" - -- noheader.tsv
expect "a header in another order" 0 "$t/expected-reordered.txt" - -- reordered.tsv
expect "a header only" 0 "$t/expected-header-only.txt" - -- header-only.tsv
expect "CRLF line ends and a BOM" 0 "$t/expected-runs.txt" - -- crlf.tsv
expect "one kind and model (a contract's estimate)" 0 "$t/expected-one.txt" - -- runs.tsv --kind ordinary --model sonnet
expect "a kind and model with no runs" 0 "$t/expected-none.txt" - -- header-only.tsv --kind ordinary --model sonnet
expect "a missing file" 1 - "run-stats: cannot read missing.tsv" -- missing.tsv
expect "a missing file, one pair" 1 - "run-stats: cannot read missing.tsv" -- missing.tsv --kind ordinary --model sonnet
expect "--kind without --model is a usage error" 2 '*' - -- runs.tsv --kind ordinary
expect "--per-run with a kind is a usage error" 2 '*' - -- runs.tsv --per-run --kind ordinary
expect "no file is a usage error" 2 '*' - --

# --limits; the clock fixed at 2026-10-13T06:20:00Z, before both resets of the fixtures
l="$here/limits"; now=1791872400
all=(--spend-5h spend-5h.txt --spend-week spend-week.txt --prices prices.txt)
expect "limits: trusted windows, mixed models, a block that fits" 0 "$l/expected-trusted.txt" - -- \
  --limits --status status-trusted.json "${all[@]}" --cap-5h 95 --cap-week 90 --block 20 --now $now
expect "limits: a block that does not fit the 5-hour cap" 0 "$l/expected-nofit.txt" - -- \
  --limits --status status-trusted.json "${all[@]}" --cap-5h 95 --cap-week 90 --block '$80' --now $now
expect "limits: pretty-printed JSON and a spend with CRLF and a BOM" 0 "$l/expected-trusted.txt" - -- \
  --limits --status status-crlf.json --spend-5h spend-5h.txt --spend-week spend-week-crlf.txt --prices prices.txt --cap-5h 95 --cap-week 90 --block 20 --now $now
expect "limits: fresh windows, a guess and the previous ratio" 0 "$l/expected-fresh.txt" - -- \
  --limits --status status-fresh.json "${all[@]}" --prev-week 0.08 --now $now
expect "limits: a window that has reset and one absent" 0 "$l/expected-reset.txt" - -- \
  --limits --status status-reset.json "${all[@]}" --prev-5h 0.7 --prev-week 0.08 --cap-5h 95 --block 20 --now $now
expect "limits: the status only (the windows' since for session-tokens)" 0 "$l/expected-status.txt" - -- \
  --limits --status status-trusted.json --now $now
IN=spend-week.txt expect "limits: a spend from stdin" 0 "$l/expected-stdin.txt" - -- \
  --limits --status status-trusted.json --spend-week - --prices prices.txt --now $now
CLAUDE_CONFIG_DIR="$(winpath "$tmp/cfg")" expect "limits: the default status file" 0 "$l/expected-status.txt" - -- --limits --now $now
expect "limits: no rate_limits (an older Claude Code)" 1 - \
  "run-stats: no rate limits in status-old.json (an API key or an older Claude Code: budget by cost)" -- --limits --status status-old.json
expect "limits: a spend model without a price" 1 - "run-stats: no price for claude-mystery-1 in prices.txt" -- \
  --limits --status status-trusted.json --spend-5h spend-unpriced.txt --prices prices.txt
expect "limits: a malformed price line" 1 - \
  "run-stats: prices-bad.txt:2: not a price line (<model> <input> <output> <cache read> <cache write> [not-weekly])" -- \
  --limits --status status-trusted.json --spend-5h spend-5h.txt --prices prices-bad.txt
expect "limits: a missing status file" 1 - "run-stats: cannot read missing.json" -- --limits --status missing.json
expect "limits: a missing spend file" 1 - "run-stats: cannot read missing.txt" -- \
  --limits --status status-trusted.json --spend-5h missing.txt --prices prices.txt
expect "limits: a spend without prices is a usage error" 2 '*' - -- --limits --status status-trusted.json --spend-5h spend-5h.txt
expect "limits: two spends from stdin is a usage error" 2 '*' - -- --limits --spend-5h - --spend-week - --prices prices.txt
expect "limits: a cap that is no number is a usage error" 2 '*' - -- --limits --cap-5h 9x
expect "limits: a run log with --limits is a usage error" 2 '*' - -- --limits runs.tsv

# the ready columns: task rows (role task) in the forecast, never in cost or time, the last one of a task
expect "ready: task rows give ready, the last 10, the last row of a task, never cost or time" 0 "$t/expected-ready.txt" - -- ready.tsv
expect "ready: --per-run leaves task rows out" 0 "$t/expected-ready-per-run.txt" - -- ready.tsv --per-run
expect "ready: one kind and model" 0 "$t/expected-ready-one.txt" - -- ready.tsv --kind ordinary --model sonnet

# a real run log: a cost cell's leading number (`0.0648 prices`, `$0.05 status`, `$1.20`; `n/a` and `in 52` none),
# an estimate_time column ignored, a verifier's `pass` and `Done (…)` as approvals
expect "real: a cost cell read by its leading number, estimate_time ignored" 0 "$t/expected-real.txt" - -- real.tsv
expect "real: --task with a verifier's pass" 0 "$t/expected-real-pass.txt" - -- real.tsv --task 50
expect "real: --task with a verifier's Done (…)" 0 "$t/expected-real-done.txt" - -- real.tsv --task 53

# --task: one task's row from its runs, the PR's gh JSON and the journal's owner waits (fixtures in task/)
k="$here/task"
expect "task: checks green after the verifier, merged" 0 "$k/expected-late.txt" - -- task-runs.tsv --task 40 --pr-json pr-late.json
expect "task: the verifier after the checks (a neutral check, a status context), merged a day later" 0 "$k/expected-early.txt" - -- \
  task-runs.tsv --task 40 --pr-json pr-early.json
expect "task: a red run then a green rerun - the last green counts (pretty-printed JSON)" 0 "$k/expected-rerun.txt" - -- \
  task-runs.tsv --task 40 --pr-json pr-rerun.json
expect "task: owner questions mid-task subtracted (across the start, overlapping, after ready)" 0 "$k/expected-waits.txt" - -- \
  task-runs.tsv --task 40 --pr-json pr-late.json --waits waits.txt
expect "task: ready, not merged - the owner wait open" 0 "$k/expected-open.txt" - -- task-runs.tsv --task 40 --pr-json pr-open.json --waits waits.txt
expect "task: a PR without checks - the verifier alone" 0 "$k/expected-nochecks.txt" - -- task-runs.tsv --task 40 --pr-json pr-nochecks.json
expect "task: no PR - the verifier alone, not merged" 0 "$k/expected-nopr.txt" - -- task-runs.tsv --task 40
expect "task: a lead and its sub-runs, no verifier row - the checks alone" 0 "$k/expected-lead.txt" - -- task-runs.tsv --task 42 --pr-json pr-late.json
expect "task: no header - CORE 7's order and wait" 0 "$k/expected-lead.txt" - -- noheader-task.tsv --task 42 --pr-json pr-late.json
expect "task: a header in another order, with wait and a column of its own" 0 "$k/expected-reordered.txt" - -- \
  reordered-task.tsv --task 42 --pr-json pr-late.json
expect "task: CRLF line ends and a BOM in every input" 0 "$k/expected-crlf.txt" - -- \
  runs-crlf.tsv --task 40 --pr-json pr-rerun-crlf.json --waits waits-crlf.txt
IN=pr-late.json expect "task: the PR's JSON from stdin" 0 "$k/expected-late.txt" - -- task-runs.tsv --task 40 --pr-json -
expect "task: the last run of a check red - not ready" 1 - "run-stats: task 40: not ready - the check checks (windows-latest) is FAILURE" -- \
  task-runs.tsv --task 40 --pr-json pr-red.json
expect "task: a check still running - not ready" 1 - "run-stats: task 40: not ready - the check checks (macos-latest) is IN_PROGRESS" -- \
  task-runs.tsv --task 40 --pr-json pr-pending.json
expect "task: no verifier run approved it - not ready" 1 - "run-stats: task 41: not ready - no verifier run approved it" -- \
  task-runs.tsv --task 41 --pr-json pr-late.json
expect "task: no verifier and no PR - not ready" 1 - "run-stats: task 42: not ready - no approved verifier run and no green checks" -- task-runs.tsv --task 42
expect "task: no run with a start" 1 - "run-stats: task 43: no run has a start" -- task-runs.tsv --task 43
expect "task: a task with no rows" 1 - "run-stats: task 99: no rows in task-runs.tsv" -- task-runs.tsv --task 99
expect "task: a malformed wait line" 1 - "run-stats: waits-bad.txt:2: not an owner wait (<asked UTC> <answered UTC>)" -- \
  task-runs.tsv --task 40 --pr-json pr-late.json --waits waits-bad.txt
expect "task: a missing PR file" 1 - "run-stats: cannot read missing.json" -- task-runs.tsv --task 40 --pr-json missing.json
expect "task: --pr-json without --task is a usage error" 2 '*' - -- task-runs.tsv --pr-json pr-late.json
expect "task: --task with --per-run is a usage error" 2 '*' - -- task-runs.tsv --task 40 --per-run
expect "task: the waits from stdin is a usage error" 2 '*' - -- task-runs.tsv --task 40 --waits -
expect "task: --task with a kind is a usage error" 2 '*' - -- task-runs.tsv --task 40 --kind ordinary
[ "$fail" = 0 ] && echo "run-stats: $n cases passed" || echo "run-stats: failures above ($n cases)"
exit "$fail"
