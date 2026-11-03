#!/usr/bin/env bash
# #373: the CI shards keep every step, scripts/ci-times, a failing guard case keeps its stderr. Exit 1 if any check fails.
#   tests/ci-times/run.sh sh                  # all three parts: the workflow, ci-times.sh, the guard set's fixture hook
#   tests/ci-times/run.sh ps pwsh             # ci-times.ps1 only (or: ps powershell)
# steps-main.txt: `<os> <shell> <step name>`, every step of check-core.yml on main at a4e608f but the checkout and the #need step. fixture-run-main.json:
# cut from main's run 41584645981; fixture-run-shards.json: made up, a sharded run's shape. The access points, implemented as written:
# 1. .github/workflows/check-core.yml. One list of steps: `steps: &steps` in the job shard-ubuntu, the line `steps: *steps` in shard-macos and shard-windows
#    (a YAML anchor: the steps' lines stay where they are). Each of the three: `runs-on: <os>-latest`, `fail-fast: false`, `shell: bash` under its defaults, and
#    exactly the matrix line shard: [<os>-1, <os>-2, ... <os>-N] (#405: at most 20 jobs of shards in all, at most 5 macos, at least 4 windows). The checkout, then the
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
# 4. #405, a split set: SG_PART=<k>/<n> (1 <= k <= n) on tests/safety-guard/run.sh; WK_PART on tests/workers/run.sh and RI_PART on tests/report-issue/run.sh the same, if the numbers pay.
#    In the workflow a part is a step named `<its name in steps-main.txt> - part <k>/<n>`, in one shard, every part 1..n there, each `bash <that run.sh>` of its body written `<VAR>=<k>/<n> bash <that run.sh>`,
#    the body otherwise the same in all parts. Split into 2 or more, always: windows' and ubuntu's guard step, with a whole line (after `run: ` or alone) `SG_PART=<k>/<n> bash tests/safety-guard/run.sh`
#    + ` powershell -NoProfile -ExecutionPolicy Bypass -File scripts/hooks/safety-guard.ps1` / ` pwsh -NoProfile -File scripts/hooks/safety-guard.ps1`. tests/ci-times.tsv may hold the parts' names for a split row.
#    SG_PART: only that part's cases run, the timed: ones too; a case's part follows from the file alone (not SG_JOBS, no clock); every part holds a case, none over 2 * cases / n + 1. What follows the cases
#    (sessions, the self-test, no-push.sh) runs in exactly one part, never under SG_CASES. A part passes when its own cases pass. Its summary: `safety-guard cases: <count> (<the file's name or path> part <k>/<n>:
#    <its cases run> of <the file's cases>, <jobs> in parallel), all pass|FAILURES`. SG_PART malformed (not <digits>/<digits>, k 0, k > n, n 0): exit 2, no hook started, no summary. Empty or unset: the whole set.
#    SG_LIST=1, before the runner's set-up and not a bash read loop (it is called some 30 times; a loop with a fork a line took 54 s a list, measured): no hook started, one line per case of that part (no SG_PART: of the file), its line number in the file (SG_CASES honoured), exit 0. WK_LIST=1, RI_LIST=1 (`bash <that run.sh> sh`): nothing run, a case's id per line.
set -u
[ $# -gt 0 ] || { sed -n '2,4s/^# \{0,1\}//p' "$0"; exit 2; }; kind="$1"; shift; PS=("$@")
case "$kind" in sh) ;; ps) [ ${#PS[@]} -gt 0 ] || { echo "ps needs powershell or pwsh" >&2; exit 2; } ;; *) echo "unknown kind: $kind" >&2; exit 2 ;; esac
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fail=0; bad() { echo "FAIL ($1) $2"; fail=1; }; m() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
check_wf() {   # check_wf <workflow>: one line per thing wrong, none when right
  LC_ALL=C awk '
    function S() { return "matrix\\.shard == \047[a-z]+-[0-9]+\047" }; function N() { return "steps\\.need\\.outputs\\.[a-z]+ == \047true\047" }; function has(x, s, msg) { if (index(x, s) == 0) print msg }
    function count(s, t,   a) { return split(s, a, t) - 1 }
    function part(r, pk,   a, x, y, t) { split(pk, a, "/"); if (a[1] + 0 < 1 || a[1] + 0 > a[2] + 0) print "a part out of range: " r " " pk; if ((r in pn) && pn[r] != a[2]) print "parts of different counts: " r; pn[r] = a[2]; pc[r, a[1] + 0]++
      x = count(body, "bash tests/safety-guard/run\\.sh") + count(body, "bash tests/workers/run\\.sh") + count(body, "bash tests/report-issue/run\\.sh"); y = count(body, "SG_PART=" pk " bash tests/safety-guard/run\\.sh") + count(body, "WK_PART=" pk " bash tests/workers/run\\.sh") + count(body, "RI_PART=" pk " bash tests/report-issue/run\\.sh")
      if (y == 0 || x != y) print "a part whose run: does not hold <VAR>=" pk " on its run.sh: " r; t = body; gsub("[A-Z][A-Z]_PART=" pk " ", "", t); if ((r in pt) && pt[r] != t) print "parts whose run: is not the same text: " r; pt[r] = t }
    function endstep(   t, o, k, r, pk, b0) {
      if (!instep) return; instep = 0; nstep++
      if (uses != "") { if (uses ~ /^actions\/checkout@/ && nstep == 1) co = 1; else print "a step that is not named: " uses; if (cond != "") print "the checkout has an if:"; return }
      if (id == "need") { nd = (nstep == 2); if (cond != "") print "the #need step has an if:, it must run in each shard"; return }
      if (cond == "") { print "in no shard (no if:): " name; return }
      if (cond !~ ("^(" S() "|\\(" S() "( \\|\\| " S() ")+\\))( && (" N() "|\\(" N() "( \\|\\| " N() ")+\\)))?$") && cond !~ ("^" S() "( \\|\\| " S() ")+$")) { print "an if: not in a form of the header: " name ": " cond; return }
      pk = ""; b0 = name; if (match(name, / - part [0-9]+\/[0-9]+$/)) { pk = substr(name, RSTART + 8); b0 = substr(name, 1, RSTART - 1) }
      for (t = cond; match(t, /\047[a-z]+-[0-9]+\047/); t = substr(t, RSTART + RLENGTH)) {
        k = substr(t, RSTART + 1, RLENGTH - 2)
        used[k]++; o = k; sub(/-.*/, "", o); r = o " " shell " " b0; if (pk == "" || !(r in pn)) seen[r]++; if (pk != "") part(r, pk)
        if (name ~ /^ci-times/) ci[o] = 1; else if (!(r in want)) print "not a step of main (name, OS or shell): " r
      }
    }
    { sub(/\r$/, "") }; FNR == NR { want[$0] = 1; next }
    /^jobs:/ { injobs = 1; top = top "\n"; next }; !injobs { top = top "\n" $0; next }
    /^  [A-Za-z0-9_-]+:[ ]*$/ { endstep(); job = $1; sub(/:$/, "", job); j[job] = 1; next }
    { b[job] = b[job] "\n" $0 }
    /^        shard: / && job ~ /^shard-/ { l = $0; gsub(/[][,]/, " ", l); c = split(l, f, " "); for (i = 2; i <= c; i++) { valid[f[i]] = 1; o = f[i]; sub(/-.*/, "", o); cnt[o]++; jobs++ } }
    job != "shard-ubuntu" { next }
    /^      - / { endstep(); instep = 1; name = ""; cond = ""; id = ""; uses = ""; shell = "bash"; body = ""
      if ($0 ~ /^      - name: /) { name = $0; sub(/^      - name: /, "", name) } else if ($0 ~ /^      - uses: /) uses = $3; else print "a step that is not named: " $0
      next }
    instep && !/^        if: / { body = body "\n" $0 }
    instep && /^        if: / { cond = $0; sub(/^        if: /, "", cond) }; instep && /^        shell: / { shell = $2 }; instep && /^        id: / { id = $2 }
    END { endstep()
      for (k in used) if (!(k in valid)) print "a shard no matrix holds: " k
      for (r in want) if (seen[r] == 0) print "in no shard: " r; for (r in seen) if (seen[r] > 1) print "in " seen[r] " shards: " r
      if (!co || !nd) print "the first two steps are not the checkout and the #need step (id: need)"; if ("check" in j) print "the job named check is still there"
      for (r in pn) for (k = 1; k <= pn[r]; k++) if (pc[r, k] != 1) print "part " k "/" pn[r] " in " pc[r, k] + 0 " shards: " r
      g["windows bash safety-guard blocks and allows the shared cases (Windows PowerShell 5.1)"] = "powershell -NoProfile -ExecutionPolicy Bypass -File scripts/hooks/safety-guard.ps1"; g["ubuntu bash safety-guard.ps1 under PowerShell 7 too (Linux)"] = "pwsh -NoProfile -File scripts/hooks/safety-guard.ps1"
      for (r in g) { t = "bash tests/safety-guard/run.sh " g[r] "\n"; if (pn[r] + 0 < 2) print "the guard set is not split: " r; else if (index(pt[r] "\n", "\n          " t) == 0 && index(pt[r] "\n", "\n        run: " t) == 0) print "not the command of main: " r }
      if (jobs > 20) print "more than 20 jobs of shards: " jobs; if (cnt["macos"] > 5) print "more than 5 macos shards: " cnt["macos"]; if (cnt["windows"] < 4) print "fewer than 4 windows shards: " cnt["windows"] + 0
      c = split("ubuntu macos windows", f, " "); for (i = 1; i <= c; i++) { o = f[i]; list[o] = ""; for (k = 1; k <= cnt[o]; k++) list[o] = list[o] (k > 1 ? ", " : "") o "-" k }
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
    wm() { tr -d '\r' < "$wf" | awk "$2" > "$tmp/mut.yml"; check_wf "$tmp/mut.yml" | grep -qF "$1" || bad split "a workflow not refused for: $1"; }   # wm <what check_wf must print> <awk>: its own reason (#405)
    wm " in 0 shards: " '/^      - name: .* - part 2\// && !d { d = 1; s = 1; next } s && /^      - / { s = 0 } !s'
    wm " in 2 shards: " '/^      - name: .*Windows PowerShell 5\.1\) - part 2\// { p = 1 } p && /^        if: / { sub(/matrix\.shard == \047[^\047]*\047/, "(& || matrix.shard == \047windows-1\047)"); p = 0 } 1'
    wm "is not the same text" '/^      - name: .*Windows PowerShell 5\.1\) - part 2\// { p = 1 } p && /run\.sh powershell/ { sub(/run\.sh powershell/, "run.sh pwsh"); p = 0 } 1'
    wm "does not hold <VAR>" '!d && /^ +(run: )?SG_PART=2\// { sub(/SG_PART=2\//, "SG_PART=1/"); d = 1 } 1'
    wm "not the command of main" '/run\.sh pwsh/ { sub(/SG_PART=/, "SG_CASES=x SG_PART=") } 1'
    wm "more than 20 jobs" '/^        shard: \[windows-1/ { sub(/\]/, ", w-a, w-b, w-c, w-d, w-e, w-f, w-g, w-h, w-i, w-j, w-k, w-l, w-m, w-n, w-o, w-p, w-q, w-r, w-s, w-t]") } 1'
    wm "more than 5 macos" '/^        shard: \[macos-1/ { $0 = "        shard: [macos-1, macos-2, macos-3, macos-4, macos-5, macos-6]" } 1'
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
    miss="$(tr -d '\r' < "$tsv" | awk -F '\t' 'FNR == NR { if ($0 !~ /^#/ && $2 ~ /^[0-9]+$/) { x = $3; sub(/ - part [0-9]+\/[0-9]+$/, "", x); h[$1 " " x] = 1 }; next } { sub(/\r$/, ""); o = $0; sub(/ [^ ]+ /, " ", o); if (!(o in h)) print $0 }' - "$here/steps-main.txt" | head -n 5)"
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
if [ "$kind" = sh ]; then   # #405: the split guard set, through a fixture hook that logs its case's word and blocks block-*; `wrong` fails its verdict, in one part only
  d="$tmp/split"; mkdir -p "$d/t"; sg="$core/tests/safety-guard/run.sh"; h="$(m "$d/hook.sh")"; wf="$core/.github/workflows/check-core.yml"
  printf '%s\n' '#!/usr/bin/env bash' 'in="$(cat)"; printf "%s\n" "$in" | sed "s/.*\"command\":\"echo \([a-z-]*\)\".*/\1/" >> "$SG_FIX_LOG"; case "$in" in *block-*) exit 2 ;; esac; exit 0' > "$d/hook.sh"
  printf 'block\twork\techo block-a\nallow\twork\techo a\n# a comment\tx\n\nallow\twork\techo a\nallow\twork\techo b\t-\t-\t-\tx\nblock\ttimed:work\techo block-t\nallow\ttimed:work\techo t\nallow\twork\techo c\nblock\twork\techo block-d\nblock\twork\techo wrong\nallow\twork\techo e\n' > "$d/cases.txt"
  printf '%s\n' a a b block-a block-d block-t c e t wrong | sort > "$d/want"; sum=0; okp=0
  rp() { : > "$1"; out="$(SG_FIX_LOG="$1" SG_CASES="$2" SG_PART="$3" SG_JOBS="${4:-2}" bash "$sg" bash "$h" </dev/null 2>&1)"; rc=$?; }   # rp <log> <cases> <SG_PART> [SG_JOBS]: $out, $rc
  for k in 1 2 3; do rp "$d/l.$k" "$d/cases.txt" "$k/3"
    line="$(printf '%s\n' "$out" | grep -E "^safety-guard cases: [0-9]+ \(.*cases\.txt part $k/3: [0-9]+ of 10, 2 in parallel\), (all pass|FAILURES)$")" || bad split "the summary of part $k/3 names no part: $(printf '%s\n' "$out" | tail -n 1)"
    r="$(printf '%s' "$line" | sed -n 's/.* part [0-9]*\/3: \([0-9]*\) of .*/\1/p')"; sum=$((sum + ${r:-0}))
    if grep -qx wrong "$d/l.$k"; then { [ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q "expected block, got allow.*echo wrong"; } || bad split "part $k/3 holds the wrong verdict: exit $rc and no FAIL line"
    elif [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q 'all pass$'; then okp=$((okp + 1)); else bad split "part $k/3 holds only passing cases: exit $rc: $(printf '%s\n' "$out" | tail -n 1)"; fi; done
  [ "$okp" = 2 ] || bad split "of 3 parts one holds the wrong verdict and 2 must pass: $okp passed"; [ "$sum" = 10 ] || bad split "the parts' summaries sum to $sum, the file holds 10 cases"; cat "$d"/l.[123] | sort > "$d/got"; x="$(comm -23 "$d/want" "$d/got" | tr '\n' ' ')"; [ -z "$x" ] || bad split "a case in no part: $x"; x="$(comm -13 "$d/want" "$d/got" | sort -u | tr '\n' ' ')"; [ -z "$x" ] || bad split "a case in two parts: $x"
  for p in 0/3 4/3 3 a/b 2/0 1/3/5; do rp "$d/bad" "$d/cases.txt" "$p"; { [ "$rc" = 2 ] && [ ! -s "$d/bad" ] && ! printf '%s\n' "$out" | grep -q '^safety-guard cases:'; } || bad split "SG_PART=$p: expected exit 2 and no hook, got exit $rc, $(wc -l < "$d/bad") calls"; done
  tr -d '\r' < "$sg" > "$d/t/run.sh"; printf 'allow\twork\techo a\nallow\twork\techo b\nallow\twork\techo c\n' > "$d/t/cases.txt"; printf '%s\n' '#!/usr/bin/env bash' 'echo run >> "$SG_FIX_NP"' > "$d/t/no-push.sh"; : > "$d/np"; c=0   # what follows the cases, in a copy of the runner with its own cases: in exactly one part
  for k in 1 2; do : > "$d/l.t"; SG_FIX_NP="$d/np" SG_FIX_LOG="$d/l.t" SG_PART="$k/2" SG_JOBS=2 bash "$d/t/run.sh" bash "$h" </dev/null >/dev/null 2>&1; [ "$(grep -c tool_name "$d/l.t")" -gt 0 ] && c=$((c + 1)); done
  [ "$(wc -l < "$d/np")" -eq 1 ] || bad split "no-push.sh ran in $(wc -l < "$d/np") parts of 2"; [ "$c" = 1 ] || bad split "the sections after the cases ran in $c parts of 2"
  lp() { env "$1_PART=$3" "$1_LIST=1" SG_FIX_LOG="$d/ln" bash "$2" bash "$h" </dev/null 2>/dev/null | tr -d '\r'; }   # the real lists, data only: the guard set at n = 3, 20 and each n of the workflow; any other set the workflow splits, at its n
  : > "$d/ln"; x="$(SG_CASES="$d/cases.txt" lp SG "$sg" 1/3)"; if [ -s "$d/ln" ] || ! printf '%s\n' "$x" | grep -qE '^[0-9]+$' || printf '%s\n' "$x" | grep -qvE '^[0-9]+$'; then bad split "no SG_LIST=1: line numbers and no hook started, as in the header"
  else for k in 1 2 3; do SG_CASES="$d/cases.txt" lp SG "$sg" "$k/3" > "$d/p"; awk -F '\t' 'FNR == NR { w[$1]; next } FNR in w { sub(/^echo /, "", $3); print $3 }' "$d/p" "$d/cases.txt" | sort > "$d/pw"; sort "$d/l.$k" | cmp -s - "$d/pw" || bad split "part $k/3: what SG_LIST lists is not what ran"; done
    { cat "$d/cases.txt"; printf 'allow\twork\techo new-end\n'; } > "$d/more.txt"; e="$(wc -l < "$d/more.txt" | tr -d ' ')"; c=0; for k in 1 2 3; do SG_CASES="$d/more.txt" lp SG "$sg" "$k/3" | grep -qx "$e" && c=$((c + 1)); done; [ "$c" = 1 ] || bad split "a case added at the end is in $c parts of 3"
    SG_JOBS=1 lp SG "$sg" 2/3 | sort > "$d/s1"; SG_JOBS=3 lp SG "$sg" 2/3 | sort > "$d/s2"; cmp -s "$d/s1" "$d/s2" || bad split "part 2/3 holds other cases on a second run (SG_JOBS 1, then 3)"
    awk -F '\t' '{ sub(/\r$/, "") } $1 != "" && $1 !~ /^#/ { print FNR }' "$core/tests/safety-guard/cases.txt" | sort > "$d/SG.all"
    for e in SG:tests/safety-guard WK:tests/workers RI:tests/report-issue; do v="${e%%:*}"; rs="$core/${e#*:}/run.sh"; ns="$(tr -d '\r' < "$wf" | sed -n "s/.*${v}_PART=[0-9]*\/\([0-9]*\) .*/\1/p" | sort -un | tr '\n' ' ')"
      if [ "$v" = SG ]; then ns="3 20 $ns"; else [ -n "$ns" ] || continue; lp "$v" "$rs" "" | sort > "$d/$v.all"; [ -s "$d/$v.all" ] || bad split "${v}_LIST=1 lists nothing"; fi; N="$(wc -l < "$d/$v.all")"
      for n in $ns; do : > "$d/u"; k=1; while [ "$k" -le "$n" ]; do lp "$v" "$rs" "$k/$n" > "$d/p"; c="$(grep -c . "$d/p")"; [ "$c" -gt 0 ] || bad split "$v part $k/$n holds no case"; [ "$c" -le $((2 * N / n + 1)) ] || bad split "$v part $k/$n holds $c of $N cases"; cat "$d/p" >> "$d/u"; k=$((k + 1)); done
        sort "$d/u" > "$d/us"; x="$(uniq -d "$d/us" | head -n 3 | tr '\n' ' ')"; [ -z "$x" ] || bad split "$v at n=$n: a case in two parts: $x"; x="$(comm -23 "$d/$v.all" "$d/us" | head -n 3 | tr '\n' ' ')"; [ -z "$x" ] || bad split "$v at n=$n: a case in no part: $x"; x="$(comm -13 "$d/$v.all" "$d/us" | sort -u | head -n 3 | tr '\n' ' ')"; [ -z "$x" ] || bad split "$v at n=$n: not a case: $x"; done; done; fi
fi
[ "$fail" = 0 ] && echo "ci-times ($kind): all pass" || echo "ci-times ($kind): FAILURES"; exit "$fail"
