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
#   scripts/retro.sh <RUNS.tsv> --core-report --id <anonymous id> [--since <YYYY-MM-DD>] [--project <folder>]
#                    [--no-insights] [--features <FEATURES.md>]          the retro report for the core (Markdown)
#   scripts/retro.sh --check-core-report <file> [--features <FEATURES.md>] [--project <folder>]
#                                                                         a core report body against its template
# The week: Monday 00:00 to Sunday 24:00 UTC, the one holding --week (default: the last complete week, the one
# holding today minus 7 days); the previous week is the 7 days before it. --project: the project root (default:
# the folder above the run log's folder); --journal / --escapes: default LOG.md / ESCAPES.tsv next to the run log.
# Next to the run log too: ROUTING.md (its "## Kinds" section, `<own kind> -> <core kind>` per line: the public
# body's kinds) and PROJECT.md (its Settings row "Worktree roots": folders, relative to the root, whose sessions
# are the project's as well as <root>/.claude/worktrees).
# The run log (CORE 7, columns by its header, else in CORE 7's order): a task is its rows before the first dot
# (37, 37.1, 37.2), as run-stats; it belongs to the week of its latest row date. Left out: rows of a probe or a
# self-test (task st<n> or 0, or a kind or role naming probe / selftest / self-test); a task-less row (- or empty)
# is the coordinator's own spend; a row whose role or kind is `assistant` (#281) is an assistant's, never a task's
# or the coordinator's (the local report's assistants only). A cost cell counts by its leading number (`0.0648 prices` is 0.0648). Results
# read by their first word: rework / escalated / failed; done and pass are approved; another word in the week is
# listed as "unknown result: <value> ×<n>" (local only).
# The transcripts: session-insights --since <week> --until <week end> --skip-tests --project <root>|<worktree
# roots>|<root>/.claude/worktrees for each week (no probe or self-test session, only this project's).
# Prints tab-separated: "retro", the weeks; "axis measure week previous" and a line per measure:
#   cost            tasks, merged, median_per_task (USD), total (the tasks' cost and the coordinator's own),
#                   coordinator, assistants (their own spend, apart from total; the local report only),
#                   per_merged_task (total / merged)
#   speed           ready_median, work_median, owner_wait_median (minutes, from the task rows; the owner wait
#                   is shown apart, never in the others), owner_wait_open (tasks ready, not merged)
#   quality         rework_rate, escalated_rate, failed_rate (of the tasks with runs), escapes (ESCAPES.tsv rows
#                   dated in the week), escapes_per_10_merged
#   predictability  per measure cost / work / ready: _forecasts (tasks with a forecast), for cost and work
#                   _logged (the estimate the task's lead row, else first worker row logged: estimate for cost,
#                   estimate_time for work; lo-hi: in range inside it, its midpoint for the ratio; one number n:
#                   in range from 2n/3 to 3n/2) and _rebuilt (no logged estimate: 3 or more earlier tasks of the
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
# --core-report prints instead the retro report for the core (procedures/RETRO.md), a fixed Markdown template over a
# period: from --since, else the day after the end of PROJECT.md's Settings row "Last core report" (<from>..<to>),
# else the first CHECKLIST.md line's date; to today (UTC). It holds the core commits (CHECKLIST.md's commit in use
# on the period's first day, then those of its lines in the period; none: PROJECT.md's Core row), the profile
# (of PROJECT.md's Strictness, Spend level and Work mode only the vocabulary word the Value starts with, else <fill>;
# the machine's os), the five axes over the period computed as
# the week's, the run log's rows of the period by role (no task rows, probes, self-tests or assistant rows), the guard reasons and
# refusal sources of the period's transcripts, CORE-FINDINGS.md's rows dated in the period by their status's first
# word ("fixed upstream" counts as fixed), the count after "local edits:" in PROJECT.md's Core row, and a row per
# feature id of the "## Summary" table of --features (default: the core's FEATURES.md). Every cell the coordinator
# writes is <fill>. CHECKLIST.md, PROJECT.md and CORE-FINDINGS.md are read next to the run log.
# --check-core-report checks a filled body: the template's lines in their order (a blank line anywhere), a feature
# row per id of --features in its order, at most 3 proposals, no <fill> left, no <!-- after line 1, every Profile
# cell a word of its vocabulary (VOCAB), Used and Trusted yes, no or unknown, and in a free-text cell no link (also
# a Markdown ](), e-mail (also [at] / (at)), @handle, \, IP address, IPv6 address (:: next to a hex group, or 6 or
# more colon-separated groups of 1-4 hex digits), HTML character reference (&#<digits>;, &#x<hex>;, &<letters>;),
# word with a / that is not a path of the core, dotted name anywhere in a word (a host, a file) that is not a core
# file's name, hex token of 7 or more digits (all decimal: named a long number or a commit id),
# the --project folder's name as a whole word (any case), and at most 160 characters; it prints nothing on a pass,
# the line on a refusal.
# Exit 1 when a file cannot be read or a check fails, 2 on a usage error.
set -u
usage() { sed -n '2,/^# Exit 1/s/^# \{0,1\}//p' "$0"; exit 2; }
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
# the retro report for the core: its template, a line per line - a cell {<type>} filled by the script or, where it
# has no value, by the coordinator (<fill>); {axes}, {guard}, {refusal}, {features}, {proposals} the rows of a group
CSPEC="<!-- core retro report, format 1 -->
**Retro report for the core.** How one project used the core since its last report: numbers made by the core's retro script and short anonymous lines; no names, paths, links, code, file names or task text leave the project.

## Report
| Field | Value |
|---|---|
| project | {id} |
| period | {period} |
| core commits | {commits} |
| format | 1 |

## Profile
| Field | Value |
|---|---|
| stack class | {stack} |
| solo or team | {solo} |
| strictness | {strict} |
| spend level | {spend} |
| work mode | {mode} |
| os | {os} |

## Five axes
| Axis | Measure | Period |
|---|---|---|
{axes}

$DASH too little data: under 3 tasks, merged tasks or forecasts, under 100 tool calls, or no transcripts, journal or escapes file.

## Runs by role
| Role | Runs |
|---|---|
| coordinator | {num} |
| lead | {num} |
| worker | {num} |
| tester | {num} |
| verifier | {num} |
| scout | {num} |
| researcher | {num} |
| other | {num} |

## Guard and refusals
| Guard reason | Blocks | Retried | Around | Changed | Stopped |
|---|---|---|---|---|---|
{guard}

| Refusal | Count | Retried | Around | Changed | Stopped |
|---|---|---|---|---|---|
{refusal}

## Core findings
| Status | Findings |
|---|---|
| new | {val} |
| sent | {val} |
| discussed | {val} |
| fixed | {val} |
| dropped | {val} |
| not core | {val} |
| local core edits | {val} |

## Features
| Feature | Used | How often | Trusted | Decision changed | Friction |
|---|---|---|---|---|---|
{features}

## Helped and hindered
| Rank | Helped most | Got in the way most |
|---|---|---|
| 1 | {text} | {text} |
| 2 | {text} | {text} |
| 3 | {text} | {text} |

## Proposals
| Proposal |
|---|
{proposals}

Data for the core's retro, not a bug report: the maintainer acts on it only after the owner's discussion and yes."
ROLES="coordinator lead worker tester verifier scout researcher other"
# the Profile's vocabularies, per cell type: the only words a Profile cell holds
VOCAB="strict=swarm:standard:strict;spend=lean:balanced:thorough;mode=by task:batch;os=windows:macos:linux;solo=solo:team;stack=game engine:web:mobile:CLI:library:data:other"
# the shared awk functions: whole words, a path's folder name, a value cell, the vocabulary, days and dates
common='function idiv(a, b) { return (a - a % b) / b }
  function days(y, m, d,   e, yoe, doy) { y -= (m <= 2); e = idiv(y, 400); yoe = y - e * 400
    doy = idiv(153 * (m > 2 ? m - 3 : m + 9) + 2, 5) + d - 1
    return e * 146097 + yoe * 365 + idiv(yoe, 4) - idiv(yoe, 100) + doy - 719468 }
  function civil(n,   z, e, doe, yoe, doy, mp, d, m, y) { z = n + 719468; e = idiv(z, 146097); doe = z - e * 146097
    yoe = idiv(doe - idiv(doe, 1460) + idiv(doe, 36524) - idiv(doe, 146096), 365)
    doy = doe - (365 * yoe + idiv(yoe, 4) - idiv(yoe, 100)); mp = idiv(5 * doy + 2, 153)
    d = doy - idiv(153 * mp + 2, 5) + 1; m = mp < 10 ? mp + 3 : mp - 9; y = yoe + e * 400 + (m <= 2)
    return sprintf("%04d-%02d-%02d", y, m, d) }
  function vocabs(   n, i, A) { n = split(ENVIRON["VOCAB"], A, ";"); for (i = 1; i <= n; i++) VW[substr(A[i], 1, index(A[i], "=") - 1)] = substr(A[i], index(A[i], "=") + 1) }
  function invocab(k, c,   n, i, W) { n = split(VW[k], W, ":"); for (i = 1; i <= n; i++) if (W[i] == c) return 1; return 0 }
  # the vocabulary word a Settings Value starts with (any case; a letter, digit, _ or - right after it is no end), else ""
  function vlead(k, v,   n, i, W) { v = tolower(v); n = split(VW[k], W, ":")
    for (i = 1; i <= n; i++) if (substr(v, 1, length(W[i])) == W[i] && substr(v, length(W[i]) + 1, 1) !~ /[a-z0-9_-]/) return W[i]
    return "" }
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
export DASH FIXED AXES MEAS KINDS GUARD REFUSAL FIELDS B CSPEC ROLES VOCAB

# the core's own files and folders (not .git, not .claude), as paths relative to the core
corefiles() { (cd "$here/.." && find . \( -name .git -o -name .claude \) -prune -o -print | sed 's|^\./||' | grep -v '^\.$') }
# the feature ids of a FEATURES.md, in the order of its "## Summary" table
features() {
  { [ -f "$1" ] && [ -r "$1" ]; } || { echo "retro: cannot read $1" >&2; return 1; }
  LC_ALL=C awk '{ sub(/\r$/, "") }
    /^## / { on = $0 ~ /^## +Summary[ \t]*$/; next }
    on && /^[|] *F-[A-Z]+-[0-9]+ *[|]/ { s = $0; sub(/^[|] */, "", s); sub(/ *[|].*$/, "", s); print s }' "$1"
}

# check <summary|proposal> <file> <project folder>: the body against its template and allowlist
check() {
  local kind="$1" f="$2" p="$3"
  { [ -f "$f" ] && [ -r "$f" ]; } || { echo "retro: cannot read $f" >&2; return 1; }
  # the core's own files and folders, for a proposal's core file and the paths its text names
  CORE="$( [ "$kind" = proposal ] && corefiles)" \
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

# checkcore <file> <FEATURES.md> <project folder>: a retro report for the core against its template (CSPEC) and the
# rules of its free-text cells; the first refusal names its line
checkcore() {
  local f="$1" feat
  { [ -f "$f" ] && [ -r "$f" ]; } || { echo "retro: cannot read $f" >&2; return 1; }
  feat="$(features "$2")" || return 1
  CORE="$(corefiles)" FEAT="$feat" PROJ="$3" LC_ALL=C awk "$common"'
    function fail(m) { if (!bad) print "retro: the core report fails its check: line " ln ": " m > "/dev/stderr"; bad = 1 }
    function step(l, r, f, x) { S[++ns] = l; REP[ns] = r; FE[ns] = f; MAX[ns] = x }
    function row(s, A) { return split(substr(s, 3, length(s) - 4), A, / [|] /) }
    # characters, not bytes: a UTF-8 continuation byte is no character of its own
    function chars(s,   x) { x = s; return length(s) - gsub(/[\200-\277]/, "", x) }
    # a cell of a {type} other than text: "" when it is one
    function vtype(p, c,   n, i, K, x, y) {
      if (p == "{id}") return (length(c) == 12 && c ~ /^[0-9a-f]+$/) ? "" : "a project id that is not 12 hex digits"
      if (p == "{period}") return c ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][.][.][0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ ? "" : "a period that is not <from>..<to>"
      if (p == "{commits}") { n = split(c, K, ", ")
        for (i = 1; i <= n; i++) if (K[i] !~ /^[0-9a-f]+$/ || length(K[i]) < 7 || length(K[i]) > 40) n = 0
        return n ? "" : "core commits that are not commit ids, split by a comma" }
      if (p == "{num}") return c ~ /^[0-9]+$/ ? "" : "a count that is not a number"
      if (p == "{val}") return isval(c) ? "" : "a value that is not a number or " ENVIRON["DASH"]
      if (p == "{yn}") return (c == "yes" || c == "no" || c == "unknown") ? "" : "a Used or Trusted cell other than yes, no or unknown"
      if (p == "{gkey}") return (c in GKS) ? "" : "a guard reason outside the template"
      if (p == "{rkey}") return (c in RKS) ? "" : "a refusal source outside the template"
      x = substr(p, 2, length(p) - 2)
      if (x in VW) { if (invocab(x, c)) return ""; y = VW[x]; gsub(/:/, ", ", y); return "a Profile cell outside its vocabulary (" y ")" }
      return "" }
    # a free-text cell: short, and nothing that could name a project or a person
    function text(c,   n, i, W, w, t, x, s) {
      if (c ~ /^[ \t]*$/) return "an empty cell"
      if (chars(c) > 160) return "a free-text cell over 160 characters"
      if (index(c, "://") || index(tolower(c), "www.") || index(c, "](")) return "a link"
      if (c ~ /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]/ || tolower(c) ~ /[a-z0-9._%+-] *(\[at\]|\(at\)) *[a-z0-9]/) return "an e-mail address"
      if (index(c, "@")) return "an @handle"
      if (index(c, "\\")) return "a path"
      if (c ~ /[0-9]+[.][0-9]+[.][0-9]+[.][0-9]+/) return "an IP address"
      # an IPv6 address: :: next to a hex group of 1-4 digits, or 6 or more colon-separated such groups
      t = " " c " "; x = "[0-9A-Fa-f][0-9A-Fa-f]?[0-9A-Fa-f]?[0-9A-Fa-f]?"
      if (t ~ ("[^A-Za-z0-9_]" x "::") || t ~ ("::" x "[^A-Za-z0-9_]") || t ~ ("[^A-Za-z0-9_]" x ":" x ":" x ":" x ":" x ":" x "[^A-Za-z0-9_]")) return "an IPv6 address"
      # an HTML character reference: GitHub renders &#64; as @ and &period; as .
      if (c ~ /&#[0-9]+;|&#[xX][0-9A-Fa-f]+;|&[A-Za-z]+;/) return "an HTML character reference"
      n = split(c, W, " ")
      for (i = 1; i <= n; i++) { w = W[i]; gsub(/^[(`"'"'"']+|[)`"'"'"'.,;:!?]+$/, "", w)
        if (w in CF) continue
        if (index(w, "/")) return "a path that is not the core'"'"'s" }
      # a dotted name anywhere in a word (a host, a file), its last part starting with a letter: only a core file s
      t = c
      while (match(t, /[A-Za-z0-9_-]+([.][A-Za-z0-9_-]+)+/)) { w = substr(t, RSTART, RLENGTH); t = substr(t, RSTART + RLENGTH)
        x = w; sub(/.*[.]/, "", x); if (x ~ /^[A-Za-z]/ && !(w in CB)) return "a host or a file name that is not one of the core'"'"'s" }
      # a commit id: a hex token of 7 or more digits (any case) with a decimal digit, no letter, digit or _ around it
      t = " " c " "
      while (match(t, /[^A-Za-z0-9_][0-9A-Fa-f]+[^A-Za-z0-9_]/)) { w = substr(t, RSTART + 1, RLENGTH - 2); t = substr(t, RSTART + RLENGTH - 1)
        if (length(w) >= 7 && w ~ /[0-9]/) return w ~ /^[0-9]+$/ ? "a long number or a commit id" : "a commit id" }
      if (name != "" && word(tolower(c), name)) return "the project folder'"'"'s name"
      return "" }
    # a table row against a template row: "S" when it is not that row (its cells, their fixed text and, for a group
    # row, its typed cells), "" when it passes, else the reason
    function match_row(l, p, grp,   n, m, i, C, P, r) {
      if (l !~ /^[|] .* [|]$/) return "S"
      n = row(l, C); m = row(p, P); if (n != m) return "S"
      for (i = 1; i <= m; i++) if (P[i] !~ /^[{][a-z]+[}]$/ && P[i] != C[i]) return "S"
      for (i = 1; i <= m; i++) if (P[i] ~ /^[{][a-z]+[}]$/ && P[i] != "{text}" && (r = vtype(P[i], C[i])) != "") return grp ? "S" : r
      for (i = 1; i <= m; i++) if (P[i] == "{text}" && (r = text(C[i])) != "") return r
      return "" }
    BEGIN { n = split(ENVIRON["CORE"], A, "\n"); for (i = 1; i <= n; i++) { CF[A[i]] = 1; x = A[i]; sub(/.*\//, "", x); CB[x] = 1 }
      vocabs(); name = ENVIRON["PROJ"] == "" ? "" : basename(ENVIRON["PROJ"]); if (name !~ /[a-z]/) name = ""
      nf = split(ENVIRON["FEAT"], F, "\n"); for (i = 1; i <= nf; i++) FT[F[i]] = 1
      n = split(ENVIRON["GUARD"], A, " "); for (i = 1; i <= n; i++) GKS[A[i]] = 1
      n = split(ENVIRON["REFUSAL"], A, " "); for (i = 1; i <= n; i++) RKS[A[i]] = 1
      nm = split(ENVIRON["MEAS"], M, " "); n = split(ENVIRON["CSPEC"], A, "\n")
      for (i = 1; i <= n; i++) { l = A[i]
        if (l == "") continue
        if (l == "{axes}") { for (j = 1; j <= nm; j++) step("| " substr(M[j], 1, index(M[j], ":") - 1) " | " substr(M[j], index(M[j], ":") + 1) " | {val} |", "1", 0) }
        else if (l == "{features}") { for (j = 1; j <= nf; j++) if (F[j] != "") step("| " F[j] " | {yn} | {text} | {yn} | {text} | {text} |", "1", 1) }
        else if (l == "{guard}") step("| {gkey} | {num} | {num} | {num} | {num} | {num} |", "*", 0)
        else if (l == "{refusal}") step("| {rkey} | {num} | {num} | {num} | {num} | {num} |", "*", 0)
        else if (l == "{proposals}") step("| {text} |", "+", 0, 3)
        else step(l, "1", 0) }
      s = 1 }
    { sub(/\r$/, ""); if (FNR == 1 && index($0, ENVIRON["B"]) == 1) $0 = substr($0, length(ENVIRON["B"]) + 1); ln = FNR }
    bad || /^[ \t]*$/ { next }
    index($0, "<fill>") { fail("a <fill> left"); next }
    FNR > 1 && index($0, "<!--") { fail("an HTML comment"); next }
    { while (1) {
        if (s > ns) { fail("a line after the template'"'"'s end"); break }
        p = S[s]
        if (!index(p, "{")) { if ($0 == p) s++; else fail("where the template has \"" p "\""); break }
        if (REP[s] == "1") { r = match_row($0, p, 0)
          if (r == "S") { x = $0; sub(/^[|] /, "", x); sub(/ [|].*$/, "", x)
            if (FE[s] && x ~ /^F-[A-Z]+-[0-9]+$/ && !(x in FT)) fail("a feature row not in FEATURES.md")
            else fail("where the template has \"" p "\"") }
          else if (r != "") fail(r)
          else s++
          break }
        r = match_row($0, p, 1)
        if (r == "") { GOT[s]++; if (MAX[s] && GOT[s] > MAX[s]) fail("more rows than the template allows (" MAX[s] ")"); break }
        if (r != "S") { fail(r); break }
        if (REP[s] == "+" && !GOT[s]) { fail("where the template has \"" p "\""); break }
        s++ } }
    END { if (!bad) { while (s <= ns && (REP[s] == "*" || (REP[s] == "+" && GOT[s]))) s++
        if (s <= ns) { ln++; fail("the body ends where the template has \"" S[s] "\"") } }
      exit bad }' "$f"
}

case "${1:-}" in
  --new-id) [ $# = 1 ] || usage; od -An -N6 -tx1 /dev/urandom | tr -d ' \n'; echo; exit 0 ;;
  --check-core-report)
    [ $# -ge 2 ] && [ -n "$2" ] || usage
    f="$2"; fe="$here/../FEATURES.md"; p=""; shift 2
    while [ $# -gt 0 ]; do
      [ $# -ge 2 ] && [ -n "$2" ] || usage
      case "$1" in --features) fe="$2" ;; --project) p="$2" ;; *) usage ;; esac
      shift 2
    done
    checkcore "$f" "$fe" "$p"; exit $? ;;
  --check-public | --check-proposal)
    k=summary; [ "$1" = --check-proposal ] && k=proposal
    case $# in 2) p="" ;; 4) [ "$3" = --project ] && [ -n "$4" ] || usage; p="$4" ;; *) usage ;; esac
    [ -n "$2" ] || usage
    check "$k" "$2" "$p"; exit $? ;;
  '' | -*) usage ;;
esac
runs="$1"; shift
week=""; proj=""; journal=""; escapes=""; noins=0; public=0; id=""; jset=0; eset=0
core=0; since=""; feats="$here/../FEATURES.md"; fset=0
while [ $# -gt 0 ]; do
  case "$1" in
    --no-insights) noins=1; shift; continue ;;
    --public) public=1; shift; continue ;;
    --core-report) core=1; shift; continue ;;
  esac
  [ $# -ge 2 ] && [ -n "$2" ] || usage
  case "$1" in
    --week) week="$2" ;; --project) proj="$2" ;; --journal) journal="$2"; jset=1 ;; --escapes) escapes="$2"; eset=1 ;;
    --id) id="$2" ;; --since) since="$2" ;; --features) feats="$2"; fset=1 ;; *) usage ;;
  esac
  shift 2
done
[ "$public" = 1 ] && { [ -n "$id" ] || usage; }
[ "$public" = 0 ] && [ "$core" = 0 ] && { [ -z "$id" ] || usage; }
# the core report: an id, no week and no summary; --since and --features only with it
[ "$core" = 1 ] && { { [ -n "$id" ] && [ "$public" = 0 ] && [ -z "$week" ]; } || usage; }
[ "$core" = 0 ] && { { [ -z "$since" ] && [ "$fset" = 0 ]; } || usage; }
re='^[0-9a-f]{12}$'; [ -z "$id" ] || [[ $id =~ $re ]] || usage
re='^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'; [ -z "$week" ] || [[ $week =~ $re ]] || usage
[ -z "$since" ] || [[ $since =~ $re ]] || usage
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
  BEGIN { split(ENVIRON["D"], p, "-"); n = days(p[1] + 0, p[2] + 0, p[3] + 0); if (ENVIRON["DEF"] != "") n -= 7
    s = n - (n + 3) % 7
    print civil(s), civil(s + 6), civil(s - 7), civil(s - 1), civil(s + 7) }')
WS="$1" WE="$2" PS="$3" PE="$4" WN="$5"
# the core report: the period, the core commits, the profile and the core findings from PROJECT.md, CHECKLIST.md
# and CORE-FINDINGS.md next to the run log ("<key><tab><value>" lines); the period stands for the week, and no
# date falls in the previous one
META=""; FEAT=""; OS=""
if [ "$core" = 1 ]; then
  FEAT="$(features "$feats")" || exit 1
  case "$(uname -s)" in Darwin) OS=macos ;; Linux) OS=linux ;; *) OS=windows ;; esac
  pmd=""; ckl=""; cfd=""; mf=(/dev/null)
  [ -f "$dir/PROJECT.md" ] && pmd="$dir/PROJECT.md" && mf+=("$pmd")
  [ -f "$dir/CHECKLIST.md" ] && ckl="$dir/CHECKLIST.md" && mf+=("$ckl")
  [ -f "$dir/CORE-FINDINGS.md" ] && cfd="$dir/CORE-FINDINGS.md" && mf+=("$cfd")
  META="$(SINCE="$since" TODAY="$(date -u +%Y-%m-%d)" PMD="$pmd" CKL="$ckl" CFD="$cfd" LC_ALL=C awk "$common"'
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function isdate(s) { return s ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ }
    function commit(s) { return s ~ /^[0-9a-f]+$/ && length(s) >= 7 && length(s) <= 40 }
    BEGIN { vocabs(); PT["strictness"] = "strict"; PT["spend level"] = "spend"; PT["work mode"] = "mode" }
    { sub(/\r$/, ""); if (FNR == 1 && index($0, ENVIRON["B"]) == 1) $0 = substr($0, length(ENVIRON["B"]) + 1)
      n = split($0, C, "|"); if (n < 4) next }
    # PROJECT.md: the Settings rows by their name (before a "(", without ** and `); of a Profile setting only the
    # vocabulary word its Value starts with, never the rest of it
    FILENAME == ENVIRON["PMD"] { k = C[2]; gsub(/[*`]/, "", k); sub(/[ \t]*[(].*$/, "", k); k = tolower(trim(k))
      v = C[3]; gsub(/[*`]/, "", v); v = trim(v)
      if (k in PT) { v = vlead(PT[k], v); if (v != "") P[k] = v }
      else if (k == "last core report") { if (match(v, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][.][.][0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) LAST = substr(v, RSTART + 12, 10) }
      else if (k == "core") {
        if (match(v, /commit [0-9a-f]+/)) { x = substr(v, RSTART + 7, RLENGTH - 7); if (commit(x)) CC = x }
        if (i = index(v, "local edits:")) { m = split(substr(v, i + 12), E, /[,;]/); ED = 0
          for (j = 1; j <= m; j++) { x = trim(E[j]); y = tolower(x); if (x != "" && x != "-" && y !~ /^none/ && x !~ /^<.*>$/) ED++ } } }
      next }
    # CHECKLIST.md and CORE-FINDINGS.md: columns by the header (date, core; date, status)
    FILENAME == ENVIRON["CKL"] { for (i = 2; i < n; i++) { x = tolower(trim(C[i])); if (x == "date") hd = i; if (x == "core") hc = i }
      if (hd && hc) { kd = hd; kc = hc; hd = hc = 0; next }; hd = hc = 0
      d = trim(C[kd ? kd : 3]); x = trim(C[kc ? kc : 4]); if (!isdate(d)) next
      K++; KD[K] = d; KC[K] = commit(x) ? x : ""; next }
    FILENAME == ENVIRON["CFD"] { for (i = 2; i < n; i++) { x = tolower(trim(C[i])); if (x == "date") hd = i; if (x == "status") hs = i }
      if (hd && hs) { fd = hd; fs = hs; hd = hs = 0; next }; hd = hs = 0
      d = trim(C[fd ? fd : 3]); if (!isdate(d)) next
      F++; FD[F] = d; FST[F] = tolower(trim(C[fs ? fs : (trim(C[n]) == "" ? n - 1 : n)])); next }
    END { to = ENVIRON["TODAY"]
      if (ENVIRON["SINCE"] != "") from = ENVIRON["SINCE"]
      else if (LAST != "") { split(LAST, p, "-"); from = civil(days(p[1] + 0, p[2] + 0, p[3] + 0) + 1) }
      else if (K) from = KD[1]
      else exit
      # the commit in use on the first day (the last line on or before it), then those of the lines in the period
      for (i = 1; i <= K; i++) if (KC[i] != "" && KD[i] <= from && KD[i] >= ud) { ud = KD[i]; uc = KC[i] }
      out = uc; if (uc != "") SEEN[uc] = 1
      for (i = 1; i <= K; i++) if (KC[i] != "" && KD[i] >= from && KD[i] <= to && !(KC[i] in SEEN)) { SEEN[KC[i]] = 1; out = out (out == "" ? "" : ", ") KC[i] }
      if (out == "") out = CC
      print "from\t" from; print "to\t" to; print "period\t" from ".." to
      if (out != "") print "core commits\t" out
      for (k in P) print k "\t" P[k]
      if (ED != "") print "local core edits\t" ED
      if (ENVIRON["CFD"] != "") { split("new sent discussed fixed dropped", A, " "); for (i = 1; i <= 5; i++) N[A[i]] = 0; N["not core"] = 0
        for (i = 1; i <= F; i++) if (FD[i] >= from && FD[i] <= to) { w = FST[i]; sub(/[^a-z].*$/, "", w); if (w == "not") w = "not core"; if (w in N) N[w]++ }
        for (w in N) print w "\t" N[w] } }' "${mf[@]}")"
  WS="$(printf '%s\n' "$META" | awk -F '\t' '$1 == "from" { print $2 }')"
  WE="$(printf '%s\n' "$META" | awk -F '\t' '$1 == "to" { print $2 }')"
  [ -n "$WS" ] || { echo "retro: no start of the period (no Last core report in PROJECT.md, no CHECKLIST.md line): give --since" >&2; exit 1; }
  PS=9999-99-99; PE=0000-00-00
fi
# the transcripts of each week (the core report: of its period), or "none" (no insights asked, no transcripts on
# this machine)
IW=none; IP=none
if [ "$noins" = 0 ] && [ "$core" = 1 ]; then
  IW="$(bash "$here/session-insights.sh" --since "${WS}T00:00:00Z" --skip-tests --project "$roots" 2>/dev/null)" || IW=none
elif [ "$noins" = 0 ]; then
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
  WS="$WS" WE="$WE" PS="$PS" PE="$PE" IW="$IW" IP="$IP" JC="$JC" EC="$EC" PUB="$([ "$core" = 1 ] && echo 2 || echo "$public")" \
  ID="$id" KMAP="$KMAP" META="$META" FEAT="$FEAT" OS="$OS" TIMES="$(printf '\303\227')" LC_ALL=C awk -F '\t' "$common"'
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
    if (r == "push to a protected branch" || substr(r, 1, 28) == "push to a protected branch (") return "push-protected"
    if (substr(r, 1, 14) == "push while on ") return "push-while-on-protected"
    if (r == "deleting a protected branch" || substr(r, 1, 29) == "deleting a protected branch (") return "delete-protected"
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
  # estimate, work: estimate_time; a range lo-hi, its midpoint for the ratio; a single number n: in range from 2n/3
  # to 3n/2, 3 val >= 2 n and 2 val <= 3 n) where there is one, else rebuilt from the earlier tasks of its kind and model as run-stats gave it before
  # the task: 3 or more of them, the last 10, by their last row before t s first row
  function fcast(t, w, ms,   i, u, n, v, val, o, j, k, s, m2, lo, hi, a, x) {
    if (ms == "c") { if (!(t in hc)) return; val = tc[t] }
    else if (ms == "a") { if (!(t in ha)) return; val = ta[t] }
    else { if (!(t in tr) || trw[t] < 0) return; val = trw[t] }
    if (ms != "r" && est(ms == "c" ? te[t] : tt[t])) {
      FC[w, ms]++; LG[w, ms]++
      if (ESGL ? (3 * val >= 2 * ELO && 2 * val <= 3 * ELO) : (val >= ELO && val <= EHI)) IN[w, ms]++
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
    if (r == "assistant" || k == "assistant") { if (w != "" && c >= 0) asst[w] += c; next }   # an assistant s run (#281)
    if (w == "W" && r != "task") RN[index(" " ENVIRON["ROLES"] " ", " " r " ") && r != "" ? r : "other"]++   # the runs by role
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
      V[w, "assistants"] = cents(idiv(2 * asst[w] + 100, 200))
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
    if (ENVIRON["PUB"] == "2") { core(); exit }
    print "retro\tweek of " WS "\tprevious week of " PS
    print "axis\tmeasure\tweek\tprevious"
    for (i = 1; i <= nm; i++) { ax = substr(M[i], 1, index(M[i], ":") - 1); me = substr(M[i], index(M[i], ":") + 1)
      print ax "\t" me "\t" V["W", me] "\t" V["P", me]
      if (me == "coordinator") print "cost\tassistants\t" V["W", "assistants"] "\t" V["P", "assistants"] }   # local only
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
    print ""; print FL[12]; print FL[13] }
  # the retro report for the core: the template (CSPEC), its cells from the period s numbers and META; a cell the
  # script has no value for is <fill> (a count: the em dash)
  function core(   n, i, j, m, A, B, C, G, l, p, out) {
    n = split(ENVIRON["META"], A, "\n"); for (i = 1; i <= n; i++) if (index(A[i], "\t")) G[substr(A[i], 1, index(A[i], "\t") - 1)] = substr(A[i], index(A[i], "\t") + 1)
    n = split(ENVIRON["ROLES"], A, " "); for (i = 1; i <= n; i++) G[A[i]] = RN[A[i]] + 0
    G["os"] = ENVIRON["OS"]
    n = split(ENVIRON["CSPEC"], A, "\n")
    for (i = 1; i <= n; i++) { l = A[i]
      if (l == "{axes}") { for (j = 1; j <= nm; j++) print "| " substr(M[j], 1, index(M[j], ":") - 1) " | " substr(M[j], index(M[j], ":") + 1) " | " V["W", substr(M[j], index(M[j], ":") + 1)] " |" }
      else if (l == "{guard}") { m = split(ENVIRON["GUARD"], B, " "); for (j = 1; j <= m; j++) if (B[j] in GK) print "| " B[j] " | " GC[B[j]] " | " GR[B[j]] " | " GA[B[j]] " | " GH[B[j]] " | " GS[B[j]] " |" }
      else if (l == "{refusal}") { m = split(ENVIRON["REFUSAL"], B, " "); for (j = 1; j <= m; j++) if (B[j] in QK) print "| " B[j] " | " QC[B[j]] " | " QR[B[j]] " | " QA[B[j]] " | " QH[B[j]] " | " QS[B[j]] " |" }
      else if (l == "{features}") { m = split(ENVIRON["FEAT"], B, "\n"); for (j = 1; j <= m; j++) if (B[j] != "") print "| " B[j] " | <fill> | <fill> | <fill> | <fill> | <fill> |" }
      else if (l == "{proposals}") print "| <fill> |"
      else if (index(l, "{")) { m = split(substr(l, 3, length(l) - 4), C, / [|] /); out = "|"
        for (j = 1; j <= m; j++) { p = C[j]
          if (p == "{id}") p = ENVIRON["ID"]
          else if (p ~ /^[{][a-z]+[}]$/) p = (C[1] in G) ? G[C[1]] : (p == "{num}" || p == "{val}") ? ENVIRON["DASH"] : "<fill>"
          out = out " " p " |" }
        print out }
      else print l } }' "$runs"
}
if [ "$public" = 0 ]; then report; exit $?; fi
# the anonymous body: built, then checked as --check-public does, and printed only when it passes
tmp="$(mktemp)" || exit 1
trap 'rm -f "$tmp"' EXIT
report > "$tmp" || exit 1
check summary "$tmp" "$proj" || exit 1
cat "$tmp"
