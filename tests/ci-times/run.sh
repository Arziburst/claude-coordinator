#!/usr/bin/env bash
# #373: the CI shards keep every step, scripts/ci-times, a failing guard case keeps its stderr. Exit 1 if any check fails.
#   tests/ci-times/run.sh sh                  # all three parts: the workflow, ci-times.sh, the guard set's fixture hook
#   tests/ci-times/run.sh ps pwsh             # ci-times.ps1 only (or: ps powershell)
# steps-main.txt: `<os> <shell> <step name>`, every step of check-core.yml on main at a4e608f but the checkout and the #need step. fixture-run-main.json:
# cut from main's run 41584645981; fixture-run-shards.json: made up, a sharded run's shape. The access points, implemented as written:
# 1. .github/workflows/check-core.yml. One list of steps: `steps: &steps` in the job shard-ubuntu, the line `steps: *steps` in shard-macos and shard-windows
#    (a YAML anchor: the steps' lines stay where they are). Each of the three: `runs-on: <os>-latest`, `fail-fast: false`, `shell: bash` under its defaults, and
#    exactly the matrix line shard: [ubuntu-1, ubuntu-2, ubuntu-3] / shard: [macos-1] / shard: [windows-1, windows-2, windows-3, windows-4]. The checkout, then the
#    step with `id: need`, have no `if:` (they run in each shard). Every other step has `- name:` and a one-line `if:`, its shards and its #need keys only (no runner.os):
#      if: matrix.shard == 'windows-2'     or     if: matrix.shard == 'ubuntu-1' || matrix.shard == 'macos-1'
#      if: (matrix.shard == 'ubuntu-1' || matrix.shard == 'macos-1') && (steps.need.outputs.guard == 'true' || steps.need.outputs.selftest == 'true')
#    (parentheses only around two or more; one key: no parentheses.) A step's shell is its `shell:`, else bash. New steps only under a name starting `ci-times`, at
#    least one on each OS (this set in CI). Each shard has a step. Jobs check-ubuntu, check-macos, check-windows: `name: check (<os>-latest)`, `needs: shard-<os>`,
#    `if: always()`, holding `needs.shard-<os>.result` and the word success (anything else fails it), `scripts/ci-times` and `::warning::`. No job named check, no
#    `continue-on-error` on a job, no `permissions:`. The `on:` block as on main. The `#need selftest` line holds ^scripts/check-contract\. ^scripts/check-core\.
#    ^scripts/check-scripts\. ^scripts/statusline\.  One concurrency, at the top level above `jobs:`, these three lines:
#      concurrency:
#        group: check-core-${{ github.event.pull_request.number || github.run_id }}
#        cancel-in-progress: ${{ github.event_name == 'pull_request' }}
# 2. scripts/ci-times.sh and .ps1: `[--baseline <file>] <run id|file>`, in either order. All digits: the JSON of `gh run view <id> --json jobs`; else the file, any line
#    ends and spacing. Output, one space between fields, in this order: `wall <seconds>` (the latest finished job's completedAt - the earliest startedAt, of all jobs);
#    `total <os> <seconds>` (the sum of its steps; no counted job: no line); `step <os> <seconds> <name>` (by first appearance, a name in several shards summed);
#    with --baseline `over <os> <seconds> <limit> <name>` in the order of the step lines. <os> ubuntu, macos, windows, in that order. A job counts when named
#    `shard-<os> (...)`, or `check (<os>-latest)` if the file has no shard-<os> job (an old run); others count for wall only. A step counts when completed and not
#    skipped. A time of 0001-01-01 (not started, not finished) is never read. Whole seconds, across midnight and a month's end. Baseline: lines `<os><TAB><seconds><TAB><name>`,
#    `#` lines ignored; limit = max(floor(b * 13 / 10), b + 60); over when seconds > limit (no float). Exit 0, also with over lines. Exit 2: no argument, an unknown flag,
#    --baseline with no value, no run, two runs. Exit 1, the one line `ci-times: cannot read <run id or file>`: a run or baseline file missing, gh failing. tests/ci-times.tsv: a baseline, a line per row of steps-main.txt.
# 3. tests/safety-guard/run.sh: SG_CASES=<file> reads that file instead of cases.txt and after the cases prints the summary line and exits (no later section runs). A failing
#    case prints the first 20 lines of the hook's stderr, in their order, in the normal and the timed: mode; a passing case none. Same verdicts, one call a case.
set -u
[ $# -gt 0 ] || { sed -n '2,4s/^# \{0,1\}//p' "$0"; exit 2; }; kind="$1"; shift; PS=("$@")
case "$kind" in sh) ;; ps) [ ${#PS[@]} -gt 0 ] || { echo "ps needs powershell or pwsh" >&2; exit 2; } ;; *) echo "unknown kind: $kind" >&2; exit 2 ;; esac
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fail=0; bad() { echo "FAIL ($1) $2"; fail=1; }; m() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
check_wf() {   # check_wf <workflow>: one line per thing wrong, none when right
  LC_ALL=C awk '
    function S() { return "matrix\\.shard == \047[a-z]+-[0-9]+\047" }; function N() { return "steps\\.need\\.outputs\\.[a-z]+ == \047true\047" }; function has(x, s, msg) { if (index(x, s) == 0) print msg }
    function endstep(   t, o, k, r) {
      if (!instep) return; instep = 0; nstep++
      if (uses != "") { if (uses ~ /^actions\/checkout@/ && nstep == 1) co = 1; else print "a step that is not named: " uses; if (cond != "") print "the checkout has an if:"; return }
      if (id == "need") { nd = (nstep == 2); if (cond != "") print "the #need step has an if:, it must run in each shard"; return }
      if (cond == "") { print "in no shard (no if:): " name; return }
      if (cond !~ ("^(" S() "|\\(" S() "( \\|\\| " S() ")+\\))( && (" N() "|\\(" N() "( \\|\\| " N() ")+\\)))?$") && cond !~ ("^" S() "( \\|\\| " S() ")+$")) { print "an if: not in a form of the header: " name ": " cond; return }
      for (t = cond; match(t, /\047[a-z]+-[0-9]+\047/); t = substr(t, RSTART + RLENGTH)) {
        k = substr(t, RSTART + 1, RLENGTH - 2)
        used[k]++; o = k; sub(/-.*/, "", o); r = o " " shell " " name; seen[r]++
        if (name ~ /^ci-times/) ci[o] = 1; else if (!(r in want)) print "not a step of main (name, OS or shell): " r
      }
    }
    { sub(/\r$/, "") }; FNR == NR { want[$0] = 1; next }
    /^jobs:/ { injobs = 1; top = top "\n"; next }; !injobs { top = top "\n" $0; next }
    /^  [A-Za-z0-9_-]+:[ ]*$/ { endstep(); job = $1; sub(/:$/, "", job); j[job] = 1; next }
    { b[job] = b[job] "\n" $0 }
    /^        shard: / && job ~ /^shard-/ { l = $0; gsub(/[][,]/, " ", l); c = split(l, f, " "); for (i = 2; i <= c; i++) valid[f[i]] = 1 }
    job != "shard-ubuntu" { next }
    /^      - / { endstep(); instep = 1; name = ""; cond = ""; id = ""; uses = ""; shell = "bash"
      if ($0 ~ /^      - name: /) { name = $0; sub(/^      - name: /, "", name) } else if ($0 ~ /^      - uses: /) uses = $3; else print "a step that is not named: " $0
      next }
    instep && /^        if: / { cond = $0; sub(/^        if: /, "", cond) }; instep && /^        shell: / { shell = $2 }; instep && /^        id: / { id = $2 }
    END { endstep()
      for (k in used) if (!(k in valid)) print "a shard no matrix holds: " k
      for (r in want) if (seen[r] == 0) print "in no shard: " r; for (r in seen) if (seen[r] > 1) print "in " seen[r] " shards: " r
      if (!co || !nd) print "the first two steps are not the checkout and the #need step (id: need)"; if ("check" in j) print "the job named check is still there"
      list["ubuntu"] = "ubuntu-1, ubuntu-2, ubuntu-3"; list["macos"] = "macos-1"; list["windows"] = "windows-1, windows-2, windows-3, windows-4"
      for (o in list) { x = b["shard-" o] "\n"; a = b["check-" o] "\n"; p = "shard-" o ": no "; q = "check-" o ": no "
        has(x, "\n        shard: [" list[o] "]\n", p "matrix line shard: [" list[o] "]"); has(x, "\n    runs-on: " o "-latest\n", p "runs-on: " o "-latest")
        has(x, "\n      fail-fast: false\n", p "fail-fast: false"); has(x, "\n        shell: bash", p "shell: bash in its defaults"); has(x, "\n    steps: " (o == "ubuntu" ? "&" : "*") "steps\n", p "steps: " (o == "ubuntu" ? "&" : "*") "steps")
        c = split(list[o], f, ", "); for (k = 1; k <= c; k++) if (used[f[k]] == 0) print "a shard with no step: " f[k]
        if (!ci[o]) print "no step named ci-times* on " o
        has(a, "\n    name: check (" o "-latest)\n", q "name: check (" o "-latest)"); has(a, "\n    if: always()\n", q "if: always()"); has(a, "needs.shard-" o ".result", q "needs.shard-" o ".result")
        has(a, "success", q "success"); has(a, "scripts/ci-times", q "scripts/ci-times"); has(a, "::warning::", q "::warning::")
        if (a !~ ("\n    needs: \\[?shard-" o "\\]?\n")) print q "needs: shard-" o
      }
      for (x in b) if (b[x] ~ /\n    continue-on-error:/) print x ": continue-on-error"; if (top ~ /\n *permissions:/) print "permissions: changed"
      has(top, "\non:\n  pull_request:\n  push:\n    branches: [main]\n  schedule:\n    - cron: \04727 2 * * *\047\n  workflow_dispatch:\n", "the on: block is not the one of main")
      has(top, "\nconcurrency:\n  group: check-core-${{ github.event.pull_request.number || github.run_id }}\n  cancel-in-progress: ${{ github.event_name == \047pull_request\047 }}\n", "no concurrency that cancels only a pull request s own runs")
      c = split("check-contract check-core check-scripts statusline", f, " "); for (k = 1; k <= c; k++) if (top !~ ("\n#need selftest [^\n]*\\^scripts/" f[k] "\\\\\\.")) print "#312: the #need selftest line lacks ^scripts/" f[k] "\\."
    }' "$here/steps-main.txt" "$1"
  LC_ALL=C grep -c '^ *concurrency:\|cancel-in-progress: true' "$1" | awk '$1 > 1 { print "more than one concurrency, or a cancel-in-progress: true" }'
}
if [ "$kind" = sh ]; then wf="$core/.github/workflows/check-core.yml"; check_wf "$wf" > "$tmp/wf.out"
  if [ -s "$tmp/wf.out" ]; then head -n 12 "$tmp/wf.out" | sed 's/^/FAIL (workflow) /'; fail=1; echo "FAIL (workflow) $(wc -l < "$tmp/wf.out") lines in all"
  else   # the check itself: each of these changes to a right workflow must be seen
    for mu in "^        if: matrix.shard == .*~        # none" "^        if: matrix.shard == .windows-1. *\$~        if: matrix.shard == 'windows-1' || matrix.shard == 'windows-2'" "^        shell: powershell~        # none" \
      "^        if: matrix.shard == .windows-1. *\$~        if: runner.os == 'Windows' || matrix.shard == 'windows-1'" "^      - name: Which bash~      - name: Which shell" "^    if: always~    # none" \
      "^  cancel-in-progress: .*~  cancel-in-progress: true" "^    name: check [(]windows-latest[)]~    name: check windows" "windows-3, windows-4~windows-3"; do
      tr -d '\r' < "$wf" | awk -v re="${mu%%~*}" -v to="${mu#*~}" '!d && sub(re, to) { d = 1 } { print }' > "$tmp/mut.yml"
      check_wf "$tmp/mut.yml" | grep -q . || bad mutant "not seen: $mu"
    done
  fi
fi
ct() { if [ "$kind" = ps ]; then "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$(m "$core")/scripts/ci-times.ps1" "$@"; else bash "$core/scripts/ci-times.sh" "$@"; fi; }
same() {   # same <what> <expected exit> <expected output, or -> <arguments>
  local what="$1" rc="$2" want="$3" out got; shift 3; out="$(ct "$@" 2>&1)"; got=$?; out="$(printf '%s' "$out" | tr -d '\r')"
  [ "$got" = "$rc" ] || bad ci-times "$what: expected exit $rc, got $got: $(printf '%s' "$out" | head -n 3)"
  [ "$want" = - ] || [ "$out" = "$want" ] || { bad ci-times "$what: the output differs:"; printf '%s\n' "--- expected" "$want" "--- got" "$out"; }
}
script="$core/scripts/ci-times.sh"; [ "$kind" = ps ] && script="$core/scripts/ci-times.ps1"
if [ ! -f "$script" ]; then bad ci-times "no $script"
else
  e() { tr -d '\r' < "$here/fixture-expected-$1.txt"; }; real="$(e real)"; shards="$(e shards)"; over="$shards"$'\n'"$(e over)"; r="$(m "$here/fixture-run-main.json")"; s="$(m "$here/fixture-run-shards.json")"; b="$(m "$here/fixture-baseline.tsv")"
  same "a real run" 0 "$real" "$r"; same "shards summed, the aggregator and what has not finished left out, a month's end" 0 "$shards" "$s"
  awk '{ gsub(/,"/, ",\r\n  \""); print }' "$here/fixture-run-main.json" > "$tmp/pretty.json"; same "other line ends and spacing" 0 "$real" "$(m "$tmp/pretty.json")"
  same "--baseline: a line per step over, none at the line, exit 0" 0 "$over" --baseline "$b" "$s"; same "the same, the run first" 0 "$over" "$s" --baseline "$b"
  mkdir "$tmp/bin"; printf '%s\n' '#!/usr/bin/env bash' '[ "$*" = "run view 123 --json jobs" ] || exit 1' 'cat "$CT_RUN"' > "$tmp/bin/gh"; chmod +x "$tmp/bin/gh"
  printf '%s\n' "& bash (Join-Path \$PSScriptRoot 'gh') @args" 'exit $LASTEXITCODE' > "$tmp/bin/gh.ps1"
  oldpath="$PATH"; export PATH="$tmp/bin:$PATH" CT_RUN="$here/fixture-run-main.json"; same "a run id, through gh" 0 "$real" 123; same "gh failing" 1 "ci-times: cannot read 999" 999; PATH="$oldpath"
  same "a missing file" 1 "ci-times: cannot read no-such-file.json" no-such-file.json; same "a missing baseline" 1 "ci-times: cannot read no-such-file.tsv" --baseline no-such-file.tsv "$s"
  same "no argument" 2 -; same "--baseline with no value" 2 - --baseline; same "--baseline and no run" 2 - --baseline "$b"; same "an unknown flag" 2 - --nope "$s"; same "two runs" 2 - "$s" "$r"
  tsv="$core/tests/ci-times.tsv"; if [ ! -f "$tsv" ]; then bad ci-times "no tests/ci-times.tsv"
  else same "the committed baseline reads" 0 - --baseline "$(m "$tsv")" "$r"
    miss="$(tr -d '\r' < "$tsv" | awk -F '\t' 'FNR == NR { if ($0 !~ /^#/ && $2 ~ /^[0-9]+$/) h[$1 " " $3] = 1; next } { sub(/\r$/, ""); o = $0; sub(/ [^ ]+ /, " ", o); if (!(o in h)) print $0 }' - "$here/steps-main.txt" | head -n 5)"
    [ -z "$miss" ] || bad ci-times "tests/ci-times.tsv has no line for: $miss"; fi
fi
[ "$kind" = sh ] && if ! grep -q SG_CASES "$core/tests/safety-guard/run.sh"; then bad guard "tests/safety-guard/run.sh has no SG_CASES (and a failing case prints no stderr)"
else
  printf '%s\n' '#!/usr/bin/env bash' 'in="$(cat)"; echo call >> "$SG_FIX_LOG"; w="$(printf "%s" "$in" | sed "s/.*\"command\":\"echo \([a-z-]*\)\".*/\1/")"' 'i=1; while [ $i -le 25 ]; do echo "fixture-stderr $w line $i" >&2; i=$((i + 1)); done' '[ "$w" = block-me ] && exit 2; exit 134' > "$tmp/hook.sh"
  printf 'block\twork\techo normal\nallow\twork\techo normal-passes\nblock\twork\techo block-me\nblock\twork\techo assistant\t-\t-\t-\tx\nblock\ttimed:work\techo timed\nallow\ttimed:work\techo timed-passes\n' > "$tmp/cases.txt"; : > "$tmp/calls"
  out="$(SG_FIX_LOG="$tmp/calls" SG_CASES="$tmp/cases.txt" SG_JOBS=2 bash "$core/tests/safety-guard/run.sh" bash "$(m "$tmp/hook.sh")" 2>&1)"; rc=$?
  [ "$rc" = 1 ] || bad guard "expected exit 1, got $rc"; [ "$(wc -l < "$tmp/calls")" -eq 6 ] || bad guard "6 cases, one call each: $(wc -l < "$tmp/calls") calls (a retry?)"
  printf '%s\n' "$out" | grep -qx "safety-guard cases: [0-9]* (cases.txt: 6 of 6, 2 in parallel), FAILURES" || bad guard "the summary line: $(printf '%s\n' "$out" | tail -n 1)"
  for c in normal assistant timed; do
    printf '%s\n' "$out" | grep -qF "expected block, got allow (exit 134): echo $c" || bad guard "the verdict of $c changed"; got="$(printf '%s\n' "$out" | sed -n "s/.*fixture-stderr $c line \([0-9]*\)\$/\1/p" | tr '\n' ' ')"
    [ "$got" = "1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 " ] || bad guard "$c failed: expected its first 20 stderr lines in order, got: [$got]"
  done
  for c in normal-passes block-me timed-passes; do printf '%s\n' "$out" | grep -q "fixture-stderr $c line\|FAIL.*echo $c\$" && bad guard "$c passes, and printed something"; done
fi
[ "$fail" = 0 ] && echo "ci-times ($kind): all pass" || echo "ci-times ($kind): FAILURES"; exit "$fail"
