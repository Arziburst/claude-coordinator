#!/usr/bin/env bash
# The weekly retro (procedures/RETRO.md; macOS / Linux, no dependencies; Windows: retro.ps1): the coordinator
# measured on the owner's five goals - cost, speed, quality, predictability, stability - this week against the
# previous one. Reads only; sends nothing.
#   scripts/retro.sh <RUNS.tsv> [--week <YYYY-MM-DD>] [--project <folder>] [--journal <LOG.md>]
#                    [--escapes <ESCAPES.tsv>] [--no-insights]          the local report
#   scripts/retro.sh <RUNS.tsv> ... --public --id <anonymous id>         the anonymous summary (Markdown)
#   scripts/retro.sh --check-public <file> [--project <folder>]           a summary body against its allowlist
#   scripts/retro.sh --check-proposal <file> [--project <folder>]         a proposal body against its template
#   scripts/retro.sh --new-id                                             a new random anonymous id (12 hex)
# The week: Monday 00:00 to Sunday 24:00 UTC, the one holding --week (default: the last complete week, the one
# holding today minus 7 days); the previous week is the 7 days before it. --project: the project root (default:
# the folder above the run log's folder); --journal / --escapes: default LOG.md / ESCAPES.tsv next to the run log.
# Next to the run log too: ROUTING.md (its "## Kinds" section, `<own kind> -> <core kind>` per line: the public
# body's kinds) and PROJECT.md (its Settings row "Worktree roots": folders, relative to the root, whose sessions
# are the project's as well as <root>/.claude/worktrees).
# The run log (CORE 7, columns by its header, else in CORE 7's order): a task is its rows before the first dot
# (37, 37.1, 37.2), as run-stats; it belongs to the week of its latest row date. Left out: rows of a probe or a
# self-test (task st<n> or 0, or a kind or role naming probe / selftest / self-test); a task-less row (- or empty)
# is the coordinator's own spend. A cost cell counts by its leading number (`0.0648 prices` is 0.0648). Results
# read by their first word: rework / escalated / failed; done and pass are approved; another word in the week is
# listed as "unknown result: <value> ×<n>" (local only).
# The transcripts: session-insights --since <week> --until <week end> --skip-tests --project <root>|<worktree
# roots>|<root>/.claude/worktrees for each week (no probe or self-test session, only this project's).
# Prints tab-separated: "retro", the weeks; "axis measure week previous" and a line per measure:
#   cost            tasks, merged, median_per_task (USD), total (the tasks' cost and the coordinator's own),
#                   coordinator, per_merged_task (total / merged)
#   speed           ready_median, work_median, owner_wait_median (minutes, from the task rows; the owner wait
#                   is shown apart, never in the others), owner_wait_open (tasks ready, not merged)
#   quality         rework_rate, escalated_rate, failed_rate (of the tasks with runs), escapes (ESCAPES.tsv rows
#                   dated in the week), escapes_per_10_merged
#   predictability  per measure cost / work / ready: _forecasts (tasks with a forecast), for cost and work
#                   _logged (the estimate the task's lead row, else first worker row logged: estimate for cost,
#                   estimate_time for work; lo-hi: in range inside it, its midpoint for the ratio; one number n:
#                   in range from n/2 to 2n) and _rebuilt (no logged estimate: 3 or more earlier tasks of the
#                   kind and model, the last 10 before the task's first row, their 25th-75th percentile, min-max
#                   under 4, as run-stats), _in_range, _ratio_median (actual / the forecast's midpoint, percent)
#   stability       failed_runs (rows with result failed), guard_blocks, deny_rule_blocks, guard_around (blocks
#                   whose next call named the same target - worth a look, not a finding), guard_false_positives
#                   (journal lines "guard false positive: <reason>", dated by their own date, else the last one
#                   above), guard_errors (refusals by the guard's own hook: an error or a timeout, no block),
#                   refusals (all other), tool_errors, tool_calls, tool_error_rate, cache_rewrites,
#                   cache_rewrites_per_task, waiting_minutes, rereads
# then "kind name tasks rework escalated failed" per kind of the week (the project's own kinds), the unknown
# results, and the week's block and refusal lines.
# Too little data: "—" instead of a number - under 3 values (tasks, merged tasks, forecasts) for a median, a
# rate or a ratio, under 100 tool calls for the error rate, no transcripts or no journal / escapes file.
# --public prints instead a Markdown body built only from a fixed template, numbers and the allowlist: the core's
# kinds (trivial, ordinary, hard, hardest; a project's own kind by ROUTING.md's map, else "other"), the guard's reasons and the refusal sources as
# fixed keys, the anonymous id and the dates; it is checked before it is printed (as --check-public): any line
# outside the template, a cell outside the allowlist, a / or \, or the project folder's name fails it (exit 1,
# nothing printed).
# Exit 1 when a file cannot be read or a check fails, 2 on a usage error.
set -u
usage() { sed -n '2,53s/^# \{0,1\}//p' "$0"; exit 2; }
here="$(cd "$(dirname "$0")" && pwd)"
B="$(printf '\357\273\277')"           # a UTF-8 BOM, read as nothing
DASH="$(printf '\342\200\224')"        # the em dash: too little data
# the template's fixed lines (the summary, the proposal) and the allowlist; the .ps1 holds the same
FIXED="<!-- self-improvement summary, format 1 -->
**Coordinator self-improvement: weekly summary.** Numbers only, made by the core's retro script: no code, file names, paths, branches, task text or names leave the project.
| Field | Value |
|---|---|
| Axis | Measure | Week | Previous |
|---|---|---|---|
| Kind | Tasks | Rework | Escalated | Failed |
|---|---|---|---|---|
| Guard reason | Blocks | Retried | Around | Changed | Stopped |
|---|---|---|---|---|---|
| Refusal | Count | Retried | Around | Changed | Stopped |
$DASH too little data: under 3 tasks, merged tasks or forecasts, under 100 tool calls, or no transcripts, journal or escapes file.
Data for proposals, not a bug report: the maintainer acts on it only after the owner's discussion and yes.
<!-- self-improvement proposal, format 1 -->
**Coordinator self-improvement: proposal** from one project's weekly numbers, in the core's own terms: no code, file names, paths, branches, task text or names of the project.
A proposal, not a bug report: the maintainer acts on it only after the owner's discussion and yes."
AXES="cost speed quality predictability stability"
MEAS="cost:tasks cost:merged cost:median_per_task cost:total cost:coordinator cost:per_merged_task speed:ready_median speed:work_median speed:owner_wait_median speed:owner_wait_open quality:rework_rate quality:escalated_rate quality:failed_rate quality:escapes quality:escapes_per_10_merged predictability:cost_forecasts predictability:cost_logged predictability:cost_rebuilt predictability:cost_in_range predictability:cost_ratio_median predictability:work_forecasts predictability:work_logged predictability:work_rebuilt predictability:work_in_range predictability:work_ratio_median predictability:ready_forecasts predictability:ready_in_range predictability:ready_ratio_median stability:failed_runs stability:guard_blocks stability:deny_rule_blocks stability:guard_around stability:guard_false_positives stability:guard_errors stability:refusals stability:tool_errors stability:tool_calls stability:tool_error_rate stability:cache_rewrites stability:cache_rewrites_per_task stability:waiting_minutes stability:rereads"
KINDS="trivial ordinary hard hardest other"
GUARD="unreadable-call owner-copy-edit mirror-push push-all-branches push-matching push-protected push-while-on-protected delete-protected worktree-force worktree-by-hand remove-root remove-project project-rules-unreadable project-rule-unreadable project-rule deny-rule other"
REFUSAL="guard-error other-hook classifier safety-check user other"
FIELDS="project:week of:previous week of:format:signature:axis:measure:week:previous:risk:core file:low:medium:high"
# the shared awk functions: whole words, a path's folder name, a value cell, the vocabulary
common='function idiv(a, b) { return (a - a % b) / b }
  function word(s, w,   i, p, b, a) { p = 0
    while ((i = index(substr(s, p + 1), w)) > 0) { p += i
      b = p > 1 ? substr(s, p - 1, 1) : ""; a = substr(s, p + length(w), 1)
      if (b !~ /[a-z0-9_]/ && a !~ /[a-z0-9_]/) return 1 }
    return 0 }
  function basename(p) { gsub(/\\/, "/", p); sub(/\/+$/, "", p); sub(/.*\//, "", p); return tolower(p) }
  function isval(c) { return c == ENVIRON["DASH"] || c ~ /^[0-9]+$/ || c ~ /^[0-9]+[.][0-9][0-9]?$/ || c ~ /^[0-9]+%$/ ||
      c ~ /^[0-9]+[.][0-9]%$/ || c ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ || (length(c) == 12 && c ~ /^[0-9a-f]+$/) }
  function vocab(   n, i, A) { n = split(ENVIRON["AXES"] " " ENVIRON["KINDS"] " " ENVIRON["GUARD"] " " ENVIRON["REFUSAL"], A, " ")
    for (i = 1; i <= n; i++) VOC[A[i]] = 1
    n = split(ENVIRON["MEAS"], A, " "); for (i = 1; i <= n; i++) VOC[substr(A[i], index(A[i], ":") + 1)] = 1
    n = split(ENVIRON["FIELDS"], A, ":"); for (i = 1; i <= n; i++) VOC[A[i]] = 1
    n = split(ENVIRON["FIXED"], A, "\n"); for (i = 1; i <= n; i++) { FIX[A[i]] = 1; FL[i] = A[i] } }'
export DASH FIXED AXES MEAS KINDS GUARD REFUSAL FIELDS B

# check <summary|proposal> <file> <project folder>: the body against its template and allowlist
check() {
  local kind="$1" f="$2" p="$3" core
  { [ -f "$f" ] && [ -r "$f" ]; } || { echo "retro: cannot read $f" >&2; return 1; }
  core="$(cd "$here/.." && pwd)"
  # the core's own files and folders, for a proposal's core file and the paths its text names
  CORE="$( [ "$kind" = proposal ] && cd "$core" && find . \( -name .git -o -name .claude \) -prune -o -print | sed 's|^\./||' | grep -v '^\.$')" \
  KIND="$kind" PROJ="$p" LC_ALL=C awk "$common"'
    function fail(m) { if (!bad) print "retro: the " ENVIRON["KIND"] " body fails its check: line " FNR ": " m > "/dev/stderr"; bad = 1 }
    # free text (a proposal): no \, no URL, no absolute or home path, no #<n>, no @, and a word with a / only
    # when it is a path of the core
    function free(s,   n, i, W, w) {
      if (index(s, "\\") || index(s, "://") || index(s, "~") || index(s, "@") || s ~ /#[0-9]/ || s ~ /(^|[ (`"])[A-Za-z]:\// || s ~ /(^|[ (`"])\//) return fail("a path, a link, an address or a task number in the text")
      n = split(s, W, " ")
      for (i = 1; i <= n; i++) { w = W[i]; gsub(/^[(`"]+|[)`".,;:]+$/, "", w)
        if (index(w, "/") && !(w in CF)) return fail("a path that is not the core'"'"'s") } }
    BEGIN { vocab(); n = split(ENVIRON["CORE"], A, "\n"); for (i = 1; i <= n; i++) { CF[A[i]] = 1; x = A[i]; sub(/.*\//, "", x); CB[x] = 1 }
      name = ENVIRON["PROJ"] == "" ? "" : basename(ENVIRON["PROJ"]); if (name in VOC || isval(name) || name !~ /[a-z]/) name = "" }
    { sub(/\r$/, ""); if (FNR == 1 && index($0, ENVIRON["B"]) == 1) $0 = substr($0, length(ENVIRON["B"]) + 1) }
    bad { next }
    $0 == "" { next }
    $0 in FIX { lines++; next }
    ENVIRON["KIND"] == "proposal" && /^(Change|Expected gain): ./ { lines++; k = substr($0, 1, index($0, ":") - 1); if (k in FREE) fail("a second " k " line"); FREE[k] = 1
      if (name != "" && word(tolower($0), name)) fail("the project folder'"'"'s name"); else free(substr($0, index($0, ":") + 2)); next }
    # a table row: | <label> | <cell> | ... | - every cell a word of the allowlist or a value; a proposal s core
    # file (a path of the core) is the only cell that may hold a /
    { lines++; n = 0; tbl = $0 ~ /^[|] .* [|]$/
      if (tbl) n = split(substr($0, 3, length($0) - 4), C, / [|] /)
      cf = ENVIRON["KIND"] == "proposal" && n == 2 && C[1] == "core file"
      if (!cf && (index($0, "/") || index($0, "\\"))) { fail("a path separator"); next }
      if (!tbl) { fail("not a line of the template"); next }
      if (name != "" && word(tolower($0), name)) { fail("the project folder'"'"'s name"); next }
      if (cf) { if (!(C[2] in CF)) fail("a core file that is not in the core"); next }
      if (ENVIRON["KIND"] == "proposal" && n == 2 && C[1] == "signature") {
        m = split(C[2], S, ":"); if (m != 3 || !(S[1] in VOC) || !(S[2] in VOC) || !(S[3] in CB)) fail("a signature outside <axis>:<measure>:<core file name>"); next }
      if (!(C[1] in VOC)) { fail("a row label outside the allowlist"); next }
      for (i = 2; i <= n; i++) if (!(C[i] in VOC) && !isval(C[i])) { fail("a cell outside the allowlist"); next } }
    END { if (!bad && !lines) { print "retro: the " ENVIRON["KIND"] " body is empty" > "/dev/stderr"; bad = 1 }
      if (!bad && ENVIRON["KIND"] == "proposal" && (!("Change" in FREE) || !("Expected gain" in FREE))) { print "retro: the proposal body lacks its Change or Expected gain line" > "/dev/stderr"; bad = 1 }
      exit bad }' "$f"
}

case "${1:-}" in
  --new-id) [ $# = 1 ] || usage; od -An -N6 -tx1 /dev/urandom | tr -d ' \n'; echo; exit 0 ;;
  --check-public | --check-proposal)
    k=summary; [ "$1" = --check-proposal ] && k=proposal
    case $# in 2) p="" ;; 4) [ "$3" = --project ] && [ -n "$4" ] || usage; p="$4" ;; *) usage ;; esac
    [ -n "$2" ] || usage
    check "$k" "$2" "$p"; exit $? ;;
  '' | -*) usage ;;
esac
runs="$1"; shift
week=""; proj=""; journal=""; escapes=""; noins=0; public=0; id=""; jset=0; eset=0
while [ $# -gt 0 ]; do
  case "$1" in
    --no-insights) noins=1; shift; continue ;;
    --public) public=1; shift; continue ;;
  esac
  [ $# -ge 2 ] && [ -n "$2" ] || usage
  case "$1" in
    --week) week="$2" ;; --project) proj="$2" ;; --journal) journal="$2"; jset=1 ;; --escapes) escapes="$2"; eset=1 ;;
    --id) id="$2" ;; *) usage ;;
  esac
  shift 2
done
[ "$public" = 1 ] && { [ -n "$id" ] || usage; }
[ "$public" = 0 ] && { [ -z "$id" ] || usage; }
re='^[0-9a-f]{12}$'; [ -z "$id" ] || [[ $id =~ $re ]] || usage
re='^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'; [ -z "$week" ] || [[ $week =~ $re ]] || usage
{ [ -f "$runs" ] && [ -r "$runs" ]; } || { echo "retro: cannot read $runs" >&2; exit 1; }
dir="$(cd "$(dirname "$runs")" && pwd)"
[ -n "$proj" ] || proj="$(dirname "$dir")"
case "$proj" in /* | [A-Za-z]:*) ;; *) proj="$(pwd)/$proj" ;; esac
[ "$jset" = 1 ] || { [ -f "$dir/LOG.md" ] && journal="$dir/LOG.md"; }
[ "$eset" = 1 ] || { [ -f "$dir/ESCAPES.tsv" ] && escapes="$dir/ESCAPES.tsv"; }
for x in "$journal" "$escapes"; do
  [ -z "$x" ] || { [ -f "$x" ] && [ -r "$x" ]; } || { echo "retro: cannot read $x" >&2; exit 1; }
done
# the project's own kinds mapped to the core's: ROUTING.md next to the run log, its section "## Kinds", one
# `<kind> -> <core kind>` per line (the public body only; the local report keeps the project's kinds)
KMAP=""
if [ -f "$dir/ROUTING.md" ]; then
  KMAP="$(LC_ALL=C awk '
    { sub(/\r$/, "") }
    /^#/ { on = tolower($0) ~ /^##[ \t]+kinds[ \t]*$/; next }
    on { l = tolower($0); gsub(/`/, "", l); sub(/^[ \t]*[-*][ \t]*/, "", l); sub(/[ \t]+$/, "", l)
      if (l ~ /^[a-z0-9_.-]+[ \t]*->[ \t]*(trivial|ordinary|hard|hardest)$/) {
        k = l; sub(/[ \t]*->.*$/, "", k); c = l; sub(/^.*->[ \t]*/, "", c); print k "=" c } }' "$dir/ROUTING.md")"
fi
# the folders whose sessions are the project's: the root, the worktree roots PROJECT.md names next to the run log
# (its Settings row "Worktree roots": paths split by , or ;, relative to the root; none / - / <fill> for none),
# and <root>/.claude/worktrees - joined by | for session-insights --project
base="$(printf '%s' "$proj" | tr '\\' '/')"; base="${base%/}"
roots="$base"
if [ -f "$dir/PROJECT.md" ]; then
  while IFS= read -r w; do
    [ -n "$w" ] || continue
    w="$(printf '%s' "$w" | tr '\\' '/')"
    case "$w" in
      /* | [A-Za-z]:*) ;;
      *) b="$base"
         while :; do case "$w" in ../*) b="${b%/*}"; w="${w#../}" ;; ./*) w="${w#./}" ;; ..) b="${b%/*}"; w="" ;; *) break ;; esac; done
         w="$b${w:+/$w}" ;;
    esac
    roots="$roots|$w"
  done <<EOF
$(LC_ALL=C awk -F '|' '{ sub(/\r$/, "") }
  $2 ~ /^[ \t]*[*]*Worktree roots[*]*[ \t]*$/ { v = $3; gsub(/`/, "", v); n = split(v, a, /[,;]/)
    for (i = 1; i <= n; i++) { x = a[i]; sub(/^[ \t]+/, "", x); sub(/[ \t]+$/, "", x); y = tolower(x)
      if (x != "" && x != "-" && y != "none" && y != "n/a" && x !~ /^<.*>$/) print x } }' "$dir/PROJECT.md")
EOF
fi
roots="$roots|$base/.claude/worktrees"
# the weeks: this one's Monday and Sunday, the previous one's, and the next Monday (the --until of this one)
set -- $(D="${week:-$(date -u +%Y-%m-%d)}" DEF="$([ -z "$week" ] && echo 1)" LC_ALL=C awk "$common"'
  function days(y, m, d,   e, yoe, doy) { y -= (m <= 2); e = idiv(y, 400); yoe = y - e * 400
    doy = idiv(153 * (m > 2 ? m - 3 : m + 9) + 2, 5) + d - 1
    return e * 146097 + yoe * 365 + idiv(yoe, 4) - idiv(yoe, 100) + doy - 719468 }
  function civil(n,   z, e, doe, yoe, doy, mp, d, m, y) { z = n + 719468; e = idiv(z, 146097); doe = z - e * 146097
    yoe = idiv(doe - idiv(doe, 1460) + idiv(doe, 36524) - idiv(doe, 146096), 365)
    doy = doe - (365 * yoe + idiv(yoe, 4) - idiv(yoe, 100)); mp = idiv(5 * doy + 2, 153)
    d = doy - idiv(153 * mp + 2, 5) + 1; m = mp < 10 ? mp + 3 : mp - 9; y = yoe + e * 400 + (m <= 2)
    return sprintf("%04d-%02d-%02d", y, m, d) }
  BEGIN { split(ENVIRON["D"], p, "-"); n = days(p[1] + 0, p[2] + 0, p[3] + 0); if (ENVIRON["DEF"] != "") n -= 7
    s = n - (n + 3) % 7
    print civil(s), civil(s + 6), civil(s - 7), civil(s - 1), civil(s + 7) }')
WS="$1" WE="$2" PS="$3" PE="$4" WN="$5"
# the transcripts of each week, or "none" (no insights asked, no transcripts on this machine)
IW=none; IP=none
if [ "$noins" = 0 ]; then
  IW="$(bash "$here/session-insights.sh" --since "${WS}T00:00:00Z" --until "${WN}T00:00:00Z" --skip-tests --project "$roots" 2>/dev/null)" || IW=none
  IP="$(bash "$here/session-insights.sh" --since "${PS}T00:00:00Z" --until "${WS}T00:00:00Z" --skip-tests --project "$roots" 2>/dev/null)" || IP=none
fi
# the journal's guard false positives and the escapes, per week ("-": no file)
JC=-; EC=-
if [ -n "$journal" ]; then
  JC="$(WS="$WS" WE="$WE" PS="$PS" PE="$PE" LC_ALL=C awk '
    { sub(/\r$/, ""); if (NR == 1 && index($0, ENVIRON["B"]) == 1) $0 = substr($0, length(ENVIRON["B"]) + 1)
      d = ""; if (match($0, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) d = substr($0, RSTART, RLENGTH)
      if (index(tolower($0), "guard false positive:")) { x = d != "" ? d : last
        if (x >= ENVIRON["WS"] && x <= ENVIRON["WE"]) w++; else if (x >= ENVIRON["PS"] && x <= ENVIRON["PE"]) p++ }
      if (d != "") last = d }
    END { print (w + 0) ":" (p + 0) }' "$journal")"
fi
if [ -n "$escapes" ]; then
  EC="$(WS="$WS" WE="$WE" PS="$PS" PE="$PE" LC_ALL=C awk -F '\t' '
    { sub(/\r$/, ""); if (NR == 1 && index($0, ENVIRON["B"]) == 1) $0 = substr($0, length(ENVIRON["B"]) + 1) }
    /^[ \t]*$/ || /^#/ || $1 == "date" { next }
    { d = substr($1, 1, 10); if (d >= ENVIRON["WS"] && d <= ENVIRON["WE"]) w++; else if (d >= ENVIRON["PS"] && d <= ENVIRON["PE"]) p++ }
    END { print (w + 0) ":" (p + 0) }' "$escapes")"
fi

report() {
  WS="$WS" WE="$WE" PS="$PS" PE="$PE" IW="$IW" IP="$IP" JC="$JC" EC="$EC" PUB="$public" ID="$id" KMAP="$KMAP" \
  TIMES="$(printf '\303\227')" LC_ALL=C awk -F '\t' "$common"'
  BEGIN { vocab(); D = ENVIRON["DASH"]; WS = ENVIRON["WS"]; WE = ENVIRON["WE"]; PS = ENVIRON["PS"]; PE = ENVIRON["PE"]
    cd = 1; ct = 2; cr = 3; ck = 4; cm = 5; ce = 7; cc = 9; cs = 10; cw = 12; ca = 13; cx = 14; cy = 15
    kmn = split(ENVIRON["KMAP"], A, "\n"); for (i = 1; i <= kmn; i++) if (index(A[i], "=")) KM[substr(A[i], 1, index(A[i], "=") - 1)] = substr(A[i], index(A[i], "=") + 1)
    ins(ENVIRON["IW"], "W"); ins(ENVIRON["IP"], "P")
    split(ENVIRON["JC"] == "-" ? "-:-" : ENVIRON["JC"], JJ, ":"); JN["W"] = JJ[1]; JN["P"] = JJ[2]
    split(ENVIRON["EC"] == "-" ? "-:-" : ENVIRON["EC"], JJ, ":"); EN["W"] = JJ[1]; EN["P"] = JJ[2] }
  # a value in units of 1/10000 (four decimals, the rest dropped); -1 when it is no number (as run-stats: a cost is
  # its cell s leading number, `0.0648 prices` 0.0648; minutes the whole value, a trailing m allowed)
  function units(v, unit,   i, d) { sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
    if (unit == "$") { sub(/^[$]/, "", v); if (!match(v, /^[0-9]+([.][0-9]+)?/)) return -1; v = substr(v, 1, RLENGTH) }
    else { sub(/m$/, "", v); if (v !~ /^[0-9]+([.][0-9]+)?$/) return -1 }
    i = v; d = ""; if (index(v, ".")) { i = substr(v, 1, index(v, ".") - 1); d = substr(v, index(v, ".") + 1) }
    return (i + 0) * 10000 + substr(d "0000", 1, 4) }
  # a logged estimate (estimate: budget.cost; estimate_time: budget.time): a number or a range lo-hi at the cell s
  # start (`$` allowed, the rest ignored); sets ELO and EHI in units, ESGL for a single number; 0 when none
  function est(v,   a, b) { sub(/^[ \t]+/, "", v); sub(/^[$]/, "", v)
    if (!match(v, /^[0-9]+([.][0-9]+)?/)) return 0
    a = substr(v, 1, RLENGTH); v = substr(v, RLENGTH + 1); ELO = units(a, "$"); EHI = ELO; ESGL = 1
    if (match(v, /^[ \t]*-[ \t]*[0-9]+([.][0-9]+)?/)) { b = substr(v, RSTART, RLENGTH); sub(/^[ \t]*-[ \t]*/, "", b)
      EHI = units(b, "$"); ESGL = 0; if (EHI < ELO) return 0 }
    return ELO + EHI > 0 }
  function col(c) { return c ? $c : "" }
  function wk(d) { return d == "" ? "" : (d >= WS && d <= WE) ? "W" : (d >= PS && d <= PE) ? "P" : "" }
  function add(k, v) { L[k, ++LN[k]] = v }
  function kv(s, k,   x) { if (!match(s, "(^| )" k "=[0-9]+")) return 0; x = substr(s, RSTART, RLENGTH); sub(/^.*=/, "", x); return x + 0 }
  # the guard reasons and refusal sources as the fixed keys of the public body
  function gkey(r) {
    if (r == "deny rule") return "deny-rule"
    if (r == "the tool call could not be read (not a JSON object)") return "unreadable-call"
    if (r == "the owner'"'"'s working copy is never edited by a worker (<path>); work in your worktree") return "owner-copy-edit"
    if (r == "mirror push (overwrites every branch, incl. protected ones)") return "mirror-push"
    if (r == "push of every branch (incl. protected ones)") return "push-all-branches"
    if (r == "push of all matching branches (incl. protected ones)") return "push-matching"
    if (r == "push to a protected branch") return "push-protected"
    if (substr(r, 1, 14) == "push while on ") return "push-while-on-protected"
    if (r == "deleting a protected branch") return "delete-protected"
    if (r == "removing a worktree by force (use the cleanup script)") return "worktree-force"
    if (r == "removing a worktree by hand (use the cleanup script)") return "worktree-by-hand"
    if (r == "recursive removal of /, a drive or home") return "remove-root"
    if (r == "recursive removal of the project or a folder that holds it") return "remove-project"
    if (substr(r, 1, 32) == "project rule file cannot be read") return "project-rules-unreadable"
    if (substr(r, 1, 27) == "project rule cannot be read") return "project-rule-unreadable"
    if (substr(r, 1, 14) == "project rule: ") return "project-rule"
    return "other" }
  function rkey(s) { if (substr(s, 1, 17) == "hook safety-guard") return "guard-error"
    if (s == "hook" || substr(s, 1, 5) == "hook ") return "other-hook"
    if (s == "classifier" || s == "user") return s
    if (s == "safety check") return "safety-check"
    return "other" }
  # the public kind: a core kind as it is, a project s kind by its map (ROUTING.md *Kinds*), else other
  function pkind(k) { k = tolower(k); return (k == "trivial" || k == "ordinary" || k == "hard" || k == "hardest") ? k : (k in KM) ? KM[k] : "other" }
  # one week of session-insights lines; "none": no transcripts
  function ins(s, w,   n, i, A, f, c, g) { if (s == "none") return; has[w] = 1
    n = split(s, A, "\n")
    for (i = 1; i <= n; i++) { split(A[i], f, "\t")
      if (f[1] == "block") { c = kv(f[3], "count"); if (f[2] == "deny rule") deny[w] += c; else { gb[w] += c; ga[w] += kv(f[3], "around") }
        if (w == "W") { g = gkey(f[2]); GK[g] = 1; GC[g] += c; GR[g] += kv(f[3], "retried"); GA[g] += kv(f[3], "around")
          GH[g] += kv(f[3], "changed"); GS[g] += kv(f[3], "stopped"); LOC[++nl] = A[i] } }
      else if (f[1] == "refusal") { c = kv(f[3], "count"); g = rkey(f[2]); if (g == "guard-error") gerr[w] += c; else ref[w] += c
        if (w == "W") { QK[g] = 1; QC[g] += c; QR[g] += kv(f[3], "retried"); QA[g] += kv(f[3], "around")
          QH[g] += kv(f[3], "changed"); QS[g] += kv(f[3], "stopped"); LOC[++nl] = A[i] } }
      else if (f[1] == "tool_error") te[w] += kv(f[3], "count")
      else if (f[1] == "waiting") wmin[w] = kv(f[2], "minutes")
      else if (f[1] == "cache") crw[w] = kv(f[2], "rewrites")
      else if (f[1] == "reread") rrf[w] = kv(f[2], "files")
      else if (f[1] == "turns") calls[w] = kv(f[2], "tool_calls") } }
  function rank(p, n,   q) { q = p * n / 100; return q == int(q) ? q : int(q) + 1 }
  # twice the median of a list
  function med2(k,   n, i, j, v, a) { n = LN[k]
    for (i = 1; i <= n; i++) { a[i] = L[k, i]; for (j = i; j > 1 && a[j - 1] > a[j]; j--) { v = a[j]; a[j] = a[j - 1]; a[j - 1] = v } }
    return n % 2 ? 2 * a[(n + 1) / 2] : a[n / 2] + a[n / 2 + 1] }
  function cents(c) { return sprintf("%d.%02d", idiv(c, 100), c % 100) }   # hundredths as d.dd
  function dec1(x) { return sprintf("%d.%d", idiv(x, 10), x % 10) }        # tenths as d.d
  function pct(a, b) { return idiv(200 * a + b, 2 * b) "%" }
  # the forecast of task t for a measure (c cost, a work, r ready): the estimate logged in its run log row (cost:
  # estimate, work: estimate_time; a range lo-hi, its midpoint for the ratio; a single number n: in range from n/2
  # to 2n) where there is one, else rebuilt from the earlier tasks of its kind and model as run-stats gave it before
  # the task: 3 or more of them, the last 10, by their last row before t s first row
  function fcast(t, w, ms,   i, u, n, v, val, o, j, k, s, m2, lo, hi, a, x) {
    if (ms == "c") { if (!(t in hc)) return; val = tc[t] }
    else if (ms == "a") { if (!(t in ha)) return; val = ta[t] }
    else { if (!(t in tr) || trw[t] < 0) return; val = trw[t] }
    if (ms != "r" && est(ms == "c" ? te[t] : tt[t])) {
      FC[w, ms]++; LG[w, ms]++
      if (ESGL ? (2 * val >= ELO && val <= 2 * ELO) : (val >= ELO && val <= EHI)) IN[w, ms]++
      m2 = ESGL ? 2 * ELO : ELO + EHI; add(w ms "q", idiv(400 * val + m2, 2 * m2)); return }
    n = 0
    for (i = 1; i <= nt; i++) { u = T[i]; if (u == t) continue
      if (ms == "r") { if (!(u in tr) || trw[u] < 0 || trk[u] != trk[t] || trm[u] != trm[t] || tr[u] >= fa[t]) continue; o = tr[u]; v = trw[u] }
      else { if (!(u in lr) || tk[u] != tk[t] || tm[u] != tm[t] || lr[u] >= fa[t]) continue
        if (ms == "c") { if (!(u in hc)) continue; v = tc[u] } else { if (!(u in ha)) continue; v = ta[u] }
        o = lr[u] }
      n++; O[n] = o; X[n] = v
      for (j = n; j > 1 && O[j - 1] > O[j]; j--) { x = O[j]; O[j] = O[j - 1]; O[j - 1] = x; x = X[j]; X[j] = X[j - 1]; X[j - 1] = x } }
    if (n < 3) return
    s = n > 10 ? n - 9 : 1; k = 0
    for (i = s; i <= n; i++) { a[++k] = X[i]; for (j = k; j > 1 && a[j - 1] > a[j]; j--) { x = a[j]; a[j] = a[j - 1]; a[j - 1] = x } }
    m2 = k % 2 ? 2 * a[(k + 1) / 2] : a[k / 2] + a[k / 2 + 1]
    lo = k < 4 ? a[1] : a[rank(25, k)]; hi = k < 4 ? a[k] : a[rank(75, k)]
    FC[w, ms]++; RB[w, ms]++; if (val >= lo && val <= hi) IN[w, ms]++
    if (m2 > 0) add(w ms "q", idiv(400 * val + m2, 2 * m2)) }
  { sub(/\r$/, ""); if (NR == 1 && index($0, ENVIRON["B"]) == 1) $0 = substr($0, length(ENVIRON["B"]) + 1) }
  /^[ \t]*$/ || /^#/ { next }
  $1 == "date" { cd = ct = cr = ck = cm = ce = cc = cs = cw = ca = cx = cy = 0
    for (i = NF; i >= 1; i--) { if ($i == "date") cd = i; if ($i == "task") ct = i; if ($i == "role") cr = i; if ($i == "kind") ck = i
      if ($i == "model") cm = i; if ($i == "cost") cc = i; if ($i == "result") cs = i; if ($i == "wall") cw = i
      if ($i == "active") ca = i; if ($i == "wait") cx = i; if ($i == "estimate") ce = i; if ($i == "estimate_time") cy = i }
    next }
  { row++; t = col(ct); sub(/[.].*$/, "", t); k = col(ck); m = col(cm); r = col(cr)
    x = tolower(t); y = tolower(k " " r)
    if (x ~ /^#?st[0-9]/ || x == "0" || x == "#0" || y ~ /probe|selftest|self-test/) next   # a probe or a self-test
    d = substr(col(cd), 1, 10); if (d !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) d = ""
    c = units(col(cc), "$"); w = wk(d)
    if (t == "" || t == "-") { if (w != "" && c >= 0) coord[w] += c; next }   # the coordinator s own line
    if (!(t in fa)) { fa[t] = row; T[++nt] = t }
    if (d > md[t]) md[t] = d
    if (r == "task") { tr[t] = row; trk[t] = k; trm[t] = m; trw[t] = units(col(cw), "m"); trx[t] = col(cx); trs[t] = tolower(col(cs)); next }
    lr[t] = row; nrun[t]++
    if (c >= 0) { tc[t] += c; hc[t] = 1 }
    a = units(col(ca), "m"); if (a >= 0 && col(cc) !~ /^[ \t]*in[ \t]/) { ta[t] += a; ha[t] = 1 }   # a subagent: in its parent
    p = (r == "lead") ? 3 : ((r == "worker") ? 2 : 1)
    if (!(t in pr) || p > pr[t]) { pr[t] = p; tk[t] = k; tm[t] = m; te[t] = col(ce); tt[t] = col(cy) }
    # a result is read by its first word; done and pass are approvals; any other word, in this week, is listed
    u = col(cs); sub(/^[ \t]+/, "", u); sub(/[ \t]+$/, "", u)
    if (w == "W" && u != "" && u != "-" && tolower(u) !~ /^(approved|done|pass|rework|escalated|failed|ready|merged)([^a-z]|$)/) UNK[u]++
    s = tolower(col(cs)); sub(/^[ \t]+/, "", s)
    if (s ~ /^rework/) rw[t] = 1; if (s ~ /^escalated/) es[t] = 1
    if (s ~ /^failed/) { fl[t] = 1; if (w != "") frun[w]++ } }
  END {
    for (i = 1; i <= nt; i++) { t = T[i]; if (!(t in pr)) { tk[t] = trk[t]; tm[t] = trm[t] }
      w = wk(md[t]); if (w == "") continue
      n[w]++
      if ((t in tr) && trs[t] ~ /^[ \t]*merged/) mg[w]++
      if (t in hc) { add(w "c", tc[t]); tot[w] += tc[t] }
      if (t in ha) add(w "a", ta[t])
      if ((t in tr) && trw[t] >= 0) add(w "r", trw[t])
      if (t in tr) { x = trx[t]; if (x ~ /[+][ \t]*$/) open[w]++; else if ((v = units(x, "m")) >= 0) add(w "x", v) }
      if (t in nrun) { nr[w]++; if (t in rw) nrw[w]++; if (t in es) nes[w]++; if (t in fl) nfl[w]++
        if (w == "W") { k = tk[t] == "" ? "-" : tk[t]; KN[k]++; KR[k] += (t in rw); KE[k] += (t in es); KF[k] += (t in fl)
          k = pkind(k); UN[k]++; UR[k] += (t in rw); UE[k] += (t in es); UF[k] += (t in fl) } }
      fcast(t, w, "c"); fcast(t, w, "a"); fcast(t, w, "r") }
    for (q = 1; q <= 2; q++) { w = q == 1 ? "W" : "P"
      V[w, "tasks"] = n[w] + 0; V[w, "merged"] = mg[w] + 0
      V[w, "median_per_task"] = LN[w "c"] >= 3 ? cents(idiv(med2(w "c") + 100, 200)) : D
      V[w, "total"] = cents(idiv(2 * (tot[w] + coord[w]) + 100, 200)); V[w, "coordinator"] = cents(idiv(2 * coord[w] + 100, 200))
      V[w, "per_merged_task"] = mg[w] >= 3 ? cents(idiv(2 * (tot[w] + coord[w]) + 100 * mg[w], 200 * mg[w])) : D
      V[w, "ready_median"] = LN[w "r"] >= 3 ? idiv(med2(w "r") + 10000, 20000) : D
      V[w, "work_median"] = LN[w "a"] >= 3 ? idiv(med2(w "a") + 10000, 20000) : D
      V[w, "owner_wait_median"] = LN[w "x"] >= 3 ? idiv(med2(w "x") + 10000, 20000) : D
      V[w, "owner_wait_open"] = open[w] + 0
      V[w, "rework_rate"] = nr[w] >= 3 ? pct(nrw[w], nr[w]) : D; V[w, "escalated_rate"] = nr[w] >= 3 ? pct(nes[w], nr[w]) : D
      V[w, "failed_rate"] = nr[w] >= 3 ? pct(nfl[w], nr[w]) : D
      V[w, "escapes"] = EN[w] == "-" ? D : EN[w]
      V[w, "escapes_per_10_merged"] = (EN[w] == "-" || mg[w] < 3) ? D : dec1(idiv(200 * EN[w] + mg[w], 2 * mg[w]))
      for (j = 1; j <= 3; j++) { ms = substr("car", j, 1); mn = j == 1 ? "cost" : j == 2 ? "work" : "ready"
        V[w, mn "_forecasts"] = FC[w, ms] + 0
        if (ms != "r") { V[w, mn "_logged"] = LG[w, ms] + 0; V[w, mn "_rebuilt"] = RB[w, ms] + 0 }
        V[w, mn "_in_range"] = FC[w, ms] >= 3 ? pct(IN[w, ms], FC[w, ms]) : D
        V[w, mn "_ratio_median"] = LN[w ms "q"] >= 3 ? idiv(med2(w ms "q") + 1, 2) "%" : D }
      V[w, "failed_runs"] = frun[w] + 0
      V[w, "guard_false_positives"] = JN[w] == "-" ? D : JN[w]
      if (w in has) { V[w, "guard_blocks"] = gb[w] + 0; V[w, "deny_rule_blocks"] = deny[w] + 0; V[w, "guard_around"] = ga[w] + 0
        V[w, "guard_errors"] = gerr[w] + 0; V[w, "refusals"] = ref[w] + 0; V[w, "tool_errors"] = te[w] + 0; V[w, "tool_calls"] = calls[w] + 0
        V[w, "tool_error_rate"] = calls[w] >= 100 ? dec1(idiv(2000 * te[w] + calls[w], 2 * calls[w])) "%" : D
        V[w, "cache_rewrites"] = crw[w] + 0
        V[w, "cache_rewrites_per_task"] = n[w] >= 3 ? cents(idiv(200 * crw[w] + n[w], 2 * n[w])) : D
        V[w, "waiting_minutes"] = wmin[w] + 0; V[w, "rereads"] = rrf[w] + 0 }
      else { split("guard_blocks deny_rule_blocks guard_around guard_errors refusals tool_errors tool_calls tool_error_rate cache_rewrites cache_rewrites_per_task waiting_minutes rereads", Z, " ")
        for (j = 1; j <= 12; j++) V[w, Z[j]] = D } }
    nm = split(ENVIRON["MEAS"], M, " ")
    if (ENVIRON["PUB"] == "1") { public(); exit }
    print "retro\tweek of " WS "\tprevious week of " PS
    print "axis\tmeasure\tweek\tprevious"
    for (i = 1; i <= nm; i++) { ax = substr(M[i], 1, index(M[i], ":") - 1); me = substr(M[i], index(M[i], ":") + 1)
      print ax "\t" me "\t" V["W", me] "\t" V["P", me] }
    print "kind\tname\ttasks\trework\tescalated\tfailed"
    for (k in KN) print "kind\t" k "\t" KN[k] "\t" (KN[k] >= 3 ? pct(KR[k], KN[k]) "\t" pct(KE[k], KN[k]) "\t" pct(KF[k], KN[k]) : D "\t" D "\t" D) | "LC_ALL=C sort"
    close("LC_ALL=C sort")
    for (u in UNK) print "unknown result: " u " " ENVIRON["TIMES"] UNK[u] | "LC_ALL=C sort"
    close("LC_ALL=C sort")
    for (i = 1; i <= nl; i++) print LOC[i]
    print "note\t" D " too little data: under 3 tasks, merged tasks or forecasts, under 100 tool calls, or no transcripts, journal or escapes file" }
  # the anonymous body: the template s fixed lines (FL), the allowlisted labels, the numbers
  function public(   i, k, me, ax) {
    print FL[1]; print FL[2]; print ""
    print FL[3]; print FL[4]
    print "| project | " ENVIRON["ID"] " |"; print "| week of | " WS " |"; print "| previous week of | " PS " |"; print "| format | 1 |"; print ""
    print FL[5]; print FL[6]
    for (i = 1; i <= nm; i++) { ax = substr(M[i], 1, index(M[i], ":") - 1); me = substr(M[i], index(M[i], ":") + 1)
      print "| " ax " | " me " | " V["W", me] " | " V["P", me] " |" }
    split(ENVIRON["KINDS"], A, " ")
    k = 0; for (i = 1; i <= 5; i++) if (A[i] in UN) k++
    if (k) { print ""; print FL[7]; print FL[8]
      for (i = 1; i <= 5; i++) if (A[i] in UN) print "| " A[i] " | " UN[A[i]] " | " (UN[A[i]] >= 3 ? pct(UR[A[i]], UN[A[i]]) " | " pct(UE[A[i]], UN[A[i]]) " | " pct(UF[A[i]], UN[A[i]]) : D " | " D " | " D) " |" }
    split(ENVIRON["GUARD"], A, " "); k = 0; for (i in GK) k++
    if (k) { print ""; print FL[9]; print FL[10]
      for (i = 1; i <= 17; i++) if (A[i] in GK) print "| " A[i] " | " GC[A[i]] " | " GR[A[i]] " | " GA[A[i]] " | " GH[A[i]] " | " GS[A[i]] " |" }
    split(ENVIRON["REFUSAL"], A, " "); k = 0; for (i in QK) k++
    if (k) { print ""; print FL[11]; print FL[10]
      for (i = 1; i <= 6; i++) if (A[i] in QK) print "| " A[i] " | " QC[A[i]] " | " QR[A[i]] " | " QA[A[i]] " | " QH[A[i]] " | " QS[A[i]] " |" }
    print ""; print FL[12]; print FL[13] }' "$runs"
}
if [ "$public" = 0 ]; then report; exit $?; fi
# the anonymous body: built, then checked as --check-public does, and printed only when it passes
tmp="$(mktemp)" || exit 1
trap 'rm -f "$tmp"' EXIT
report > "$tmp" || exit 1
check summary "$tmp" "$proj" || exit 1
cat "$tmp"
