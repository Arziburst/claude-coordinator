#!/usr/bin/env bash
# The forecast numbers from a run log (CORE §7a; macOS / Linux, no dependencies; Windows: run-stats.ps1).
#   scripts/run-stats.sh <RUNS.tsv>                                 per kind and model, over TASKS
#   scripts/run-stats.sh <RUNS.tsv> --kind <kind> --model <model>   that pair's line only (a contract's estimate)
#   scripts/run-stats.sh <RUNS.tsv> --per-run                       per kind, role and model, over single rows
#   scripts/run-stats.sh <RUNS.tsv> --task <n> [--pr-json <file|->] [--waits <file>] [--append]
#                                                                   one task's `task` row: time to ready (below);
#                                                                   --append also writes it to RUNS.tsv (#242)
#   scripts/run-stats.sh --limits [options]                         the limits: percent per dollar, dollars left
#                                                                   and a block's fit (below)
# RUNS.tsv (CORE §7): tab-separated, columns by the header line when there is one (its first field `date`;
# names task, role, kind, model, cost, result, start, wall, active), else in CORE §7's order (task 2, role 3,
# kind 4, model 5, cost 9, result 10, start 11, wall 12, active 13, wait 14; estimate and estimate_time, the last, are not read). Blank lines and lines starting
# with # are skipped; CRLF and a UTF-8 BOM read as plain. A row with role `task` is a finished task's own row
# (CORE §7: wall = its time to ready); it counts only toward ready below, never toward cost or time. A row whose
# role or kind is `assistant` (#281) is never part of a task: --per-run counts it under kind and role `assistant`.
# Values: cost in USD (the cell's leading number, `$` allowed: `0.0648 prices` is 0.0648), active in minutes (a
# number, a trailing `m` allowed); any
# other value (empty, `-`, `n/a`, `in <parent>`) has none, and a row without the time columns has no time.
# A TASK is the rows whose task number agrees before its first dot (37, 37.1 and 37.2 are task 37; an
# empty or `-` task is no task): its cost and its time are the sums of the values its rows have (a
# subagent's row, cost `in <parent>`, adds no time: it is inside its parent's); a task none of whose rows
# has a value for a measure is left out of that measure only. Its kind and model are its lead row's, else
# its first worker row's (the model it was planned on), else its first row's; tasks are ordered by their
# last row. Ready: per task its last `task` row's wall, under that row's kind and model, tasks ordered by
# that row. Per kind and model and per measure, the LAST 10 tasks that have a value for it count.
# --per-run: every row on its own (no `task` rows), grouped by kind, role and model, the last 10 rows with a
# value, without the ready columns.
# Prints a header, then tab-separated (sorted; --per-run adds role after kind):
#   kind model cost_n cost_median cost_low cost_high time_n time_median time_low time_high
#   ready_n ready_median ready_low ready_high
#   median: the middle value, the mean of the two middle ones for an even count;
#   low / high: the 25th and 75th percentile by nearest rank (the value at rank ceil(p * n / 100) of the
#   sorted values, 1-based) from 4 values on, min and max under 4;
#   cost to the cent, time to the minute, each rounded half up once; no values: n 0 and `-`.
# --task <n> (CORE §7a: time to ready, owner wait): prints the task's `task` row to append to RUNS.tsv, in the
#   header's order (a column it does not name stays empty), then the names it lacks in CORE §7's order, `wait`
#   last: date (UTC: the merge, else ready) task role(`task`) kind model effort(-) estimate(-) tokens(-) cost(-)
#   result(`merged` / `ready`) start wall active wait. The task's rows (before the first dot; `task` rows
#   aside): start = the earliest start; active = the work, its rows' active summed (a subagent's, `in
#   <parent>`, aside); kind and model as above. Ready = the later of the last approval of a verifier row
#   (result `approved…`, or `done` / `pass`: its start + wall) and the checks all green; a task with verifier rows none of which
#   approved is not ready. --pr-json: `gh pr view <n> --json statusCheckRollup,mergedAt,createdAt` (- reads
#   stdin), read as text: per check (its type, workflow and name) the run started last counts - a rerun
#   replaces a red run -, green = a CheckRun COMPLETED with SUCCESS / NEUTRAL / SKIPPED or a StatusContext
#   SUCCESS, the checks' time the last completedAt (else startedAt); one not green: not ready; no checks: the
#   verifier alone. --waits: the journal's owner decisions for the task, `<asked> <answered>` per line
#   (YYYY-MM-DDTHH:MM:SS[.f]Z; # comments); the part of each inside start .. ready, overlaps once, is the
#   mid-task wait. wall = ready - start - that wait; wait = merge - ready (never below 0) + that wait;
#   unmerged (mergedAt null or no --pr-json): result `ready`, wait `<mid-task wait>+` (still open). Seconds
#   exact, each minute value rounded half up once.
# --limits (CORE §7a: limit percent per dollar, the block forecast), every option optional:
#   --status <file>        the status JSON (default <config>/coordinator/statusline.json, <config> being
#                          $CLAUDE_CONFIG_DIR or ~/.claude): rate_limits.five_hour and .seven_day
#   --spend-5h <file|->    the account's spend in that window: what `session-tokens --since <since>` prints
#   --spend-week <file|->  (its per-model token lines; - reads stdin, for one of the two)
#   --prices <file>        needed with a spend: per line `<model id> <input> <output> <cache read> <cache write>`
#                          in USD per million tokens (cache write at the 1-hour price; `$` and ` / ` allowed,
#                          # comments), then, in any order, `top` for the top rung's model when it stands above
#                          the strong one (Fable, CORE §7) and `not-weekly` for a model with its own limit whose
#                          spend does not count toward the weekly one (none known; never Fable); a spend model
#                          takes the line of its own id, else of the longest id it starts with (a dated id); none:
#                          exit 1. Assumed: every model spends the 5-hour window: five_hour sums them all
#   --prev-5h, --prev-week <% per $>   the last window's ratio      --cap-5h, --cap-week <%>   the caps (§9)
#   --block <USD>          the block's estimate without its top-rung runs
#   --block-top <USD>      the estimate of the block's top-rung runs, counted at 2.5 times (CORE §7: the top
#                          rung burns the limits faster)            --now <Unix seconds>       instead of the clock
# Prints a header, then a line for five_hour and one for seven_day, tab-separated:
#   window used since resets cost ratio basis left left_cap block fit top
#   used: used_percentage, one decimal; since: the window's start, resets_at minus 5 hours / 7 days (UTC, the
#   argument for session-tokens --since); resets: resets_at (UTC); cost: the spend at list price, USD to the
#   cent (seven_day without not-weekly models); ratio: percent per dollar, four decimals; basis: `trusted`
#   (used / cost, the window rose >= 10 points), `previous` (under 10: --prev-*), `guess` (under 10, no
#   --prev-*: used / cost), `-` (none); left / left_cap: USD before 100% / the cap at the ratio, rounded down;
#   block: the block's percent at the ratio (--block plus 2.5 times --block-top); fit: `fits` when used + block
#   stays within the cap (100 without one), else `does not fit`; top: the `top` models' share of the window's
#   cost in percent, one decimal (`-` without a cost or a `top` line). Fixed-point throughout, rounded half up once unless said; no value: `-`.
#   A window absent from the JSON: all `-`. resets_at passed: the window has reset - used 0, since, resets
#   and cost `-` (its spend is the old window's), the ratio only from --prev-*.
# Exit 1 when a file cannot be read, the JSON has no rate limits (an API key, an older Claude Code), a price
# line is malformed or a spend model has no price; in --task when the task has no rows or no start, is not
# ready or a wait line is malformed; 2 on a usage error.
usage() { sed -n '2,82s/^# \{0,1\}//p' "$0"; exit 2; }
B="$(printf '\357\273\277')"   # a UTF-8 BOM, read as nothing
# a value in units of 1/10000 (four decimals, the rest dropped), `$` first allowed; -1 when it is no number
units='function units(v,   i, d) { sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); sub(/^[$]/, "", v)
    if (v !~ /^[0-9]+([.][0-9]+)?$/) return -1
    i = v; d = ""; if (index(v, ".")) { i = substr(v, 1, index(v, ".") - 1); d = substr(v, index(v, ".") + 1) }
    return (i + 0) * 10000 + substr(d "0000", 1, 4) }
  function idiv(a, b) { return (a - a % b) / b }   # whole numbers: exact, no float rounding
  function bom() { sub(/\r$/, ""); if (FNR == 1 && index($0, ENVIRON["B"]) == 1) $0 = substr($0, length(ENVIRON["B"]) + 1) }'
limits() {
  local st="" s5="" sw="" pr="" p5="" pw="" c5="" cw="" bl="" bt="" now="" v x num='^[$]?[0-9]+([.][0-9]+)?$'
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || usage
    case "$1" in
      --status) st="$2" ;; --spend-5h) s5="$2" ;; --spend-week) sw="$2" ;; --prices) pr="$2" ;;
      --prev-5h) p5="$2" ;; --prev-week) pw="$2" ;; --cap-5h) c5="$2" ;; --cap-week) cw="$2" ;;
      --block) bl="$2" ;; --block-top) bt="$2" ;; --now) now="$2" ;; *) usage ;;
    esac; shift 2
  done
  for v in "$p5" "$pw" "$c5" "$cw" "$bl" "$bt"; do [ -z "$v" ] || [[ $v =~ $num ]] || usage; done
  case "$now" in '') now="$(date +%s)" ;; *[!0-9]*) usage ;; esac
  [ "$s5" != - ] || [ "$sw" != - ] || usage                          # one stdin
  { [ -z "$s5" ] && [ -z "$sw" ]; } || [ -n "$pr" ] || usage         # a spend needs its prices
  [ -n "$st" ] || st="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/coordinator/statusline.json"
  for x in "$st" "$pr" "$s5" "$sw"; do
    [ -z "$x" ] || [ "$x" = - ] || { [ -f "$x" ] && [ -r "$x" ]; } || { echo "run-stats: cannot read $x" >&2; return 1; }
  done
  # the windows: name, used_percentage and resets_at as written (- when absent or not a plain number);
  # the JSON as one line, read as text; each window a flat object after "rate_limits"
  local W P="" c5u="" cwu=""
  W="$(B="$B" LC_ALL=C awk "$units"'
    { bom(); s = s " " $0 }
    function val(o, k,   v) { if (!match(o, "\"" k "\"[ \t]*:[ \t]*[0-9]+([.][0-9]+)?[ \t]*[,}]")) return "-"
      v = substr(o, RSTART, RLENGTH); sub(/^[^:]*:[ \t]*/, "", v); sub(/[ \t]*[,}]$/, "", v); return v }
    END { p = index(s, "\"rate_limits\""); if (!p) exit; s = substr(s, p + 13)
      for (i = 1; i <= 2; i++) { w = (i == 1) ? "five_hour" : "seven_day"
        if (match(s, "\"" w "\"[ \t]*:[ \t]*[{][^}]*[}]")) { o = substr(s, RSTART, RLENGTH); print w, val(o, "used_percentage"), val(o, "resets_at") } } }' "$st")"
  [ -n "$W" ] || { echo "run-stats: no rate limits in $st (an API key or an older Claude Code: budget by cost)" >&2; return 1; }
  # the prices as `model in out read write weekly top`, each in 1/10000 USD per million tokens
  if [ -n "$pr" ]; then
    P="$(F="$pr" B="$B" LC_ALL=C awk "$units"'
      { bom() }
      /^[ \t]*(#|$)/ { next }
      { gsub(/\//, " "); $0 = $0; ok = (NF >= 5 && NF <= 7); nw = tp = 0
        for (i = 6; i <= NF && ok; i++) { if ($i == "not-weekly" && !nw) nw = 1; else if ($i == "top" && !tp) tp = 1; else ok = 0 }
        for (i = 2; i <= 5 && ok; i++) if ((u[i] = units($i)) < 0) ok = 0
        if (!ok) { print "run-stats: " ENVIRON["F"] ":" FNR ": not a price line (<model> <input> <output> <cache read> <cache write> [not-weekly] [top])" > "/dev/stderr"; exit 1 }
        print $1, u[2], u[3], u[4], u[5], (nw ? "w" : "-"), (tp ? "t" : "-") }' "$pr")" || return 1
  fi
  # a spend in micro-USD, then the `top` models' part of it: tokens times the price of the model's line; the
  # week leaves not-weekly out
  spend() {
    local f="$1"; [ "$f" = - ] && f=""
    P="$P" WIN="$2" F="$pr" B="$B" LC_ALL=C awk "$units"'
      BEGIN { n = split(ENVIRON["P"], L, "\n"); for (i = 1; i <= n; i++) { split(L[i], a, " "); id[i] = a[1]
                pi[i] = a[2]; po[i] = a[3]; prd[i] = a[4]; pw[i] = a[5]; nw[i] = (a[6] == "w"); tp[i] = (a[7] == "t") } }
      function tok(k,   t) { if (!match($0, "(^|[ \t])" k "[0-9]+")) return 0
        t = substr($0, RSTART, RLENGTH); sub(/^.*=/, "", t); return t + 0 }
      { bom() }
      /^[ \t]*(#|$)/ || $1 == "total" || $1 == "cost" || $1 == "time" || $0 !~ /[ \t]in=[0-9]/ { next }
      { m = $1; b = 0
        for (i = 1; i <= n; i++) if (id[i] == m || (index(m, id[i]) == 1 && (b == 0 || length(id[i]) > length(id[b])))) { b = i; if (id[i] == m) break }
        if (!b) { print "run-stats: no price for " m " in " ENVIRON["F"] > "/dev/stderr"; exit 1 }
        if (ENVIRON["WIN"] == "week" && nw[b]) next
        c = tok("in=") * pi[b] + tok("out>=") * po[b] + tok("cache_read=") * prd[b] + tok("cache_write=") * pw[b]
        T += c; if (tp[b]) TT += c }
      END { printf "%.0f %.0f\n", idiv(T, 10000), idiv(TT, 10000) }' ${f:+"$f"}
  }
  if [ -n "$s5" ]; then c5u="$(spend "$s5" 5h)" || return 1; fi
  if [ -n "$sw" ]; then cwu="$(spend "$sw" week)" || return 1; fi
  local ht=0; case "$P" in *" t"*) ht=1 ;; esac   # a `top` line in the prices
  W="$W" C5="${c5u% *}" T5="${c5u#* }" CW="${cwu% *}" TW="${cwu#* }" HT="$ht" P5="$p5" PW="$pw" CAP5="$c5" CAPW="$cw" \
    BL="$bl" BT="$bt" NOW="$now" LC_ALL=C awk "$units"'
    # Unix seconds as YYYY-MM-DDTHH:MM:SSZ (the civil calendar; no strftime in the BSD awk)
    function iso(t,   s, z, e, doe, yoe, doy, mp, d, m, y) { s = t % 86400; z = idiv(t - s, 86400) + 719468
      e = idiv(z, 146097); doe = z - e * 146097
      yoe = idiv(doe - idiv(doe, 1460) + idiv(doe, 36524) - idiv(doe, 146096), 365)
      doy = doe - (365 * yoe + idiv(yoe, 4) - idiv(yoe, 100)); mp = idiv(5 * doy + 2, 153)
      d = doy - idiv(153 * mp + 2, 5) + 1; m = mp < 10 ? mp + 3 : mp - 9; y = yoe + e * 400 + (m <= 2)
      return sprintf("%04d-%02d-%02dT%02d:%02d:%02dZ", y, m, d, idiv(s, 3600), idiv(s % 3600, 60), s % 60) }
    function rdiv(a, b) { return idiv(2 * a + b, 2 * b) }   # a / b rounded half up
    function usd(c) { return sprintf("%d.%02d", idiv(c, 100), c % 100) }   # cents
    function one(x) { return sprintf("%d.%d", idiv(x, 10), x % 10) }       # tenths
    BEGIN { n = split(ENVIRON["W"], L, "\n"); for (i = 1; i <= n; i++) { split(L[i], a, " "); U[a[1]] = a[2]; R[a[1]] = a[3] }
      now = ENVIRON["NOW"] + 0
      print "window\tused\tsince\tresets\tcost\tratio\tbasis\tleft\tleft_cap\tblock\tfit\ttop"
      line("five_hour", 18000, ENVIRON["C5"], ENVIRON["T5"], ENVIRON["P5"], ENVIRON["CAP5"])
      line("seven_day", 604800, ENVIRON["CW"], ENVIRON["TW"], ENVIRON["PW"], ENVIRON["CAPW"]) }
    # used in 1/10000 percent, cost c and its top part t in micro-USD, the ratio r in 1/10000 percent per dollar
    function line(w, len, c, t, prev, cap,   u, since, res, r, basis, cost, left, lc, blk, fit, L4, bc, p, top) {
      if (!(w in U) || U[w] == "-") { print w "\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-"; return }
      u = units(U[w]); since = res = "-"
      if (R[w] != "-" && R[w] + 0 <= now) { u = 0; c = "" }   # the window has reset since the JSON was written
      else if (R[w] != "-") { res = iso(int(R[w])); since = iso(int(R[w]) - len) }
      top = (c == "" || c + 0 == 0 || !ENVIRON["HT"]) ? "-" : one(rdiv(t * 1000, c + 0))   # tenths of a percent
      cost = (c == "") ? "-" : usd(rdiv(c, 10000)); c = (c == "") ? 0 : c + 0
      r = -1; basis = "-"
      if (u >= 100000 && c > 0) { r = rdiv(u * 1000000, c); basis = "trusted" }
      else if (prev != "") { r = units(prev); basis = "previous" }
      else if (u > 0 && c > 0) { r = rdiv(u * 1000000, c); basis = "guess" }
      left = lc = blk = fit = "-"
      L4 = (cap != "") ? units(cap) : 1000000
      if (r > 0) { left = usd(idiv((u < 1000000 ? 1000000 - u : 0) * 100, r))
        if (cap != "") lc = usd(idiv((u < L4 ? L4 - u : 0) * 100, r)) }
      if ((ENVIRON["BL"] != "" || ENVIRON["BT"] != "") && r > 0) {   # the block in cents, its top-rung runs at 2.5 times
        bc = rdiv((ENVIRON["BL"] == "" ? 0 : units(ENVIRON["BL"])) * 10 + (ENVIRON["BT"] == "" ? 0 : units(ENVIRON["BT"])) * 25, 1000)
        p = bc * r   # in 1/1000000 percent
        blk = one(rdiv(p, 100000)); fit = (100 * u + p <= 100 * L4) ? "fits" : "does not fit" }
      print w "\t" one(rdiv(u, 1000)) "\t" since "\t" res "\t" cost "\t" (r < 0 ? "-" : sprintf("%d.%04d", idiv(r, 10000), r % 10000)) "\t" basis "\t" left "\t" lc "\t" blk "\t" fit "\t" top }'
}
# YYYY-MM-DDTHH:MM:SS[.fraction]Z as Unix seconds (the civil calendar: no mktime in the BSD awk), -1 when it is
# none; and back to YYYY-MM-DDTHH:MM:SSZ
tfn='function epoch(v,   y, m, d, h, mi, s, e, yoe, doe) { sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
    if (v !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]([.][0-9]+)?Z$/) return -1
    y = substr(v, 1, 4) + 0; m = substr(v, 6, 2) + 0; d = substr(v, 9, 2) + 0
    h = substr(v, 12, 2) + 0; mi = substr(v, 15, 2) + 0; s = substr(v, 18, 2) + 0
    if (m < 1 || m > 12 || d < 1 || d > 31 || h > 23 || mi > 59 || s > 60) return -1
    y -= (m <= 2); e = idiv(y, 400); yoe = y - e * 400
    doe = yoe * 365 + idiv(yoe, 4) - idiv(yoe, 100) + idiv(153 * (m > 2 ? m - 3 : m + 9) + 2, 5) + d - 1
    return (e * 146097 + doe - 719468) * 86400 + h * 3600 + mi * 60 + s }
  function iso(t,   s, z, e, doe, yoe, doy, mp, d, m, y) { s = t % 86400; z = idiv(t - s, 86400) + 719468
    e = idiv(z, 146097); doe = z - e * 146097
    yoe = idiv(doe - idiv(doe, 1460) + idiv(doe, 36524) - idiv(doe, 146096), 365)
    doy = doe - (365 * yoe + idiv(yoe, 4) - idiv(yoe, 100)); mp = idiv(5 * doy + 2, 153)
    d = doy - idiv(153 * mp + 2, 5) + 1; m = mp < 10 ? mp + 3 : mp - 9; y = yoe + e * 400 + (m <= 2)
    return sprintf("%04d-%02d-%02dT%02d:%02d:%02dZ", y, m, d, idiv(s, 3600), idiv(s % 3600, 60), s % 60) }'
# --task: one task's `task` row - its time to ready and owner wait (CORE 7a)
taskrow() {
  local f="$1" id="$2" pj="" wf="" x C="checks none" G="-" W="" ap=0 row nl
  shift 2
  while [ $# -gt 0 ]; do
    [ "$1" = --append ] && { ap=1; shift; continue; }
    [ $# -ge 2 ] || usage
    case "$1" in --pr-json) pj="$2" ;; --waits) wf="$2" ;; *) usage ;; esac; shift 2
  done
  [ "$wf" != - ] || usage                                             # stdin is for the PR's JSON only
  for x in "$f" "$pj" "$wf"; do
    [ -z "$x" ] || [ "$x" = - ] || { [ -f "$x" ] && [ -r "$x" ]; } || { echo "run-stats: cannot read $x" >&2; return 1; }
  done
  # the PR: `merged <seconds|->`, then `checks none`, `checks green <seconds>` (the last completion of the
  # checks' latest runs) or `checks red <state> <name>`; the JSON as one line, read as text, each check a flat object
  if [ -n "$pj" ]; then
    x="$pj"; [ "$x" = - ] && x=""
    x="$(B="$B" LC_ALL=C awk "$units$tfn"'
      { bom(); s = s " " $0 }
      function str(o, k,   v) { if (!match(o, "\"" k "\"[ \t]*:[ \t]*\"[^\"]*\"")) return ""
        v = substr(o, RSTART, RLENGTH); sub(/^[^:]*:[ \t]*"/, "", v); sub(/"$/, "", v); return v }
      END { m = epoch(str(s, "mergedAt")); print "merged", (m < 0 ? "-" : m)
        p = index(s, "\"statusCheckRollup\""); r = substr(s, p + 19)
        if (!p || !match(r, /^[ \t]*:[ \t]*\[/)) { print "checks none"; exit }
        r = substr(r, RLENGTH + 1); n = 0
        # per check (its type, workflow and name) the run started last; a tie: the later one in the list
        while (match(r, /^[ \t,]*[{][^{}]*[}]/)) { o = substr(r, RSTART, RLENGTH); r = substr(r, RLENGTH + 1)
          k = str(o, "__typename") "\t" str(o, "workflowName") "\t" str(o, "name") str(o, "context"); t = epoch(str(o, "startedAt"))
          if ((k in at) && t < at[k]) continue
          if (!(k in at)) key[++n] = k
          at[k] = t; nm[k] = str(o, "name") str(o, "context"); e = epoch(str(o, "completedAt")); fin[k] = (e < 0) ? t : e
          if (str(o, "__typename") == "StatusContext") { st[k] = str(o, "state"); ok[k] = (st[k] == "SUCCESS") }
          else { st[k] = (str(o, "status") == "COMPLETED") ? str(o, "conclusion") : str(o, "status")
            ok[k] = (st[k] == "SUCCESS" || st[k] == "NEUTRAL" || st[k] == "SKIPPED") } }
        g = -1
        for (i = 1; i <= n; i++) { k = key[i]; if (!ok[k]) { print "checks red", (st[k] == "" ? "unknown" : st[k]), nm[k]; exit }
          if (fin[k] > g) g = fin[k] }
        print (g < 0 ? "checks none" : "checks green " g) }' ${x:+"$x"})" || return 1
    G="${x%%
*}"; G="${G#merged }"; C="${x#*
}"
  fi
  # the owner-decision intervals: `<asked> <answered>` per line, UTC
  if [ -n "$wf" ]; then
    W="$(F="$wf" B="$B" LC_ALL=C awk "$units$tfn"'
      { bom() }
      /^[ \t]*(#|$)/ { next }
      { a = epoch($1); b = epoch($2)
        if (NF != 2 || a < 0 || b < a) { print "run-stats: " ENVIRON["F"] ":" FNR ": not an owner wait (<asked UTC> <answered UTC>)" > "/dev/stderr"; exit 1 }
        print a, b }' "$wf")" || return 1
  fi
  row="$(F="$f" T="$id" C="$C" G="$G" W="$W" B="$B" LC_ALL=C awk -F '\t' "$units$tfn"'
    BEGIN { T = ENVIRON["T"]; sub(/[.].*$/, "", T); ct = 2; cr = 3; ck = 4; cm = 5; cc = 9; cs = 10; cb = 11; cw = 12; ca = 13
      first = -1; ver = -1 }
    function col(c) { return c ? $c : "" }
    function minutes(v) { sub(/m[ \t]*$/, "", v); return units(v) }   # in 1/10000 minute
    function fail(m) { print "run-stats: task " T ": " m > "/dev/stderr"; bad = 1; exit 1 }
    { bom() }
    /^[ \t]*$/ || /^#/ { next }
    $1 == "date" { nh = NF; ct = cr = ck = cm = cc = cs = cb = cw = ca = 0
      for (i = NF; i >= 1; i--) { hd[i] = $i; if ($i == "task") ct = i; if ($i == "role") cr = i; if ($i == "kind") ck = i
        if ($i == "model") cm = i; if ($i == "cost") cc = i; if ($i == "result") cs = i; if ($i == "start") cb = i
        if ($i == "wall") cw = i; if ($i == "active") ca = i }
      next }
    { t = col(ct); sub(/[.].*$/, "", t); r = col(cr); if (t != T || r == "task" || r == "assistant" || col(ck) == "assistant") next
      n++; a = minutes(col(ca)); s = epoch(col(cb))
      if (a >= 0 && col(cc) !~ /^[ \t]*in[ \t]/) { act += a; ha = 1 }   # a subagent: in its parent
      p = (r == "lead") ? 3 : ((r == "worker") ? 2 : 1)
      if (p > pr) { pr = p; k = col(ck); m = col(cm) }
      if (s >= 0 && (first < 0 || s < first)) first = s
      # the verifier approved at its run'"'"'s start + wall; the last approval counts
      if (r == "verifier") { hv = 1; w = minutes(col(cw))
        if (tolower(col(cs)) ~ /^[ \t]*(approved|done([^a-z]|$)|pass([^a-z]|$))/ && s >= 0 && w >= 0 && s + idiv(w * 6, 1000) > ver) ver = s + idiv(w * 6, 1000) } }
    END { if (bad) exit 1
      if (!n) fail("no rows in " ENVIRON["F"])
      if (first < 0) fail("no run has a start")
      if (hv && ver < 0) fail("not ready - no verifier run approved it")
      split(ENVIRON["C"], c, " "); g = -1
      if (c[2] == "red") { x = ENVIRON["C"]; sub(/^checks red [^ ]* /, "", x); fail("not ready - the check " x " is " c[3]) }
      if (c[2] == "green") g = c[3] + 0
      ready = ver > g ? ver : g
      if (ready < 0) fail("not ready - no approved verifier run and no green checks")
      if (ready < first) ready = first
      # the owner waits inside first start .. ready, overlaps once
      nw = split(ENVIRON["W"], L, "\n"); q = 0
      for (i = 1; i <= nw; i++) { if (split(L[i], iv, " ") < 2) continue
        lo = iv[1] + 0; hi = iv[2] + 0; if (lo < first) lo = first; if (hi > ready) hi = ready; if (hi <= lo) continue
        q++; for (j = q; j > 1 && A[j - 1] > lo; j--) { A[j] = A[j - 1]; Z[j] = Z[j - 1] }; A[j] = lo; Z[j] = hi }
      wait = 0; e = -1
      for (i = 1; i <= q; i++) { lo = A[i] > e ? A[i] : e; if (Z[i] > lo) wait += Z[i] - lo; if (Z[i] > e) e = Z[i] }
      mg = ENVIRON["G"]
      if (mg != "-") { o = mg - ready; if (o < 0) o = 0; V["wait"] = idiv(o + wait + 30, 60); V["result"] = "merged"; V["date"] = substr(iso(mg + 0), 1, 10) }
      else { V["wait"] = idiv(wait + 30, 60) "+"; V["result"] = "ready"; V["date"] = substr(iso(ready), 1, 10) }
      V["task"] = T; V["role"] = "task"; V["kind"] = k; V["model"] = m; V["effort"] = V["estimate"] = V["tokens"] = V["cost"] = "-"
      V["start"] = iso(first); V["wall"] = idiv(ready - first - wait + 30, 60); V["active"] = ha ? idiv(act + 5000, 10000) : "-"
      # the header'"'"'s order (a column it does not name: empty), then the names it lacks in CORE 7'"'"'s order
      x = "date task role kind model effort estimate tokens cost result start wall active wait"; split(x, nn, " ")
      o = ""; for (i = 1; i <= nh; i++) { v = ""; if ((hd[i] in V) && !(hd[i] in u)) { v = V[hd[i]]; u[hd[i]] = 1 }; o = o (i > 1 ? "\t" : "") v }
      for (i = 1; i <= 14; i++) if (!(nn[i] in u)) o = o (o == "" && i == 1 ? "" : "\t") V[nn[i]]
      print o }' "$f")" || return 1
  printf '%s\n' "$row"
  [ "$ap" = 1 ] || return 0
  # --append: the row as the file's last line, in its line ends; a last line without its end gets one first.
  # The coordinator once took the printed row for a written one, and the task rows went missing (#242)
  nl='
'; [ "$(tr -cd '\r' < "$f" | wc -c | tr -d ' ')" = 0 ] || nl="$(printf '\r')$nl"   # not grep: Git Bash's drops CRs
  if [ -s "$f" ] && [ "$(tail -c 1 "$f" | wc -l | tr -d ' ')" = 0 ]; then printf '%s' "$nl" >> "$f"; fi
  printf '%s%s' "$row" "$nl" >> "$f" || return 1
  echo "run-stats: the task row appended to $f" >&2
}
[ "${1:-}" = --limits ] && { shift; limits "$@"; exit $?; }
[ "${2:-}" = --task ] && { [ $# -ge 3 ] && [ -n "$1" ] && [ -n "$3" ] || usage; f="$1"; id="$3"; shift 3; taskrow "$f" "$id" "$@"; exit $?; }
f="${1:-}"; kind=""; model=""; mode=task
case $# in
  1) ;;
  2) [ "$2" = --per-run ] || usage; mode=run ;;
  5) [ "$2" = --kind ] && [ "$4" = --model ] && [ -n "$3" ] && [ -n "$5" ] || usage; kind="$3"; model="$5"; mode=one ;;
  *) usage ;;
esac
[ -n "$f" ] || usage
{ [ -f "$f" ] && [ -r "$f" ]; } || { echo "run-stats: cannot read $f" >&2; exit 1; }
# the file name and the pair via the environment: awk -v would read C:\Users as escapes (Git Bash)
K="$kind" M="$model" MODE="$mode" B="$(printf '\357\273\277')" LC_ALL=C awk -F '\t' '
  BEGIN { B = ENVIRON["B"]; mode = ENVIRON["MODE"]; ct = 2; cr = 3; ck = 4; cm = 5; cc = 9; cw = 12; ca = 13 }
  # a value in units of 1/10000 (four decimals, the rest dropped); -1 when it is no number
  function units(v, unit,   i, d) { sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
    # a cost: its leading number (`0.0648 prices` is 0.0648, `$1.20` 1.20); minutes: the whole value, `m` allowed
    if (unit == "$") { sub(/^[$]/, "", v); if (!match(v, /^[0-9]+([.][0-9]+)?/)) return -1; v = substr(v, 1, RLENGTH) }
    else { sub(/m$/, "", v); if (v !~ /^[0-9]+([.][0-9]+)?$/) return -1 }
    i = v; d = ""; if (index(v, ".")) { i = substr(v, 1, index(v, ".") - 1); d = substr(v, index(v, ".") + 1) }
    return (i + 0) * 10000 + substr(d "0000", 1, 4) }
  function col(c) { return c ? $c : "" }
  { sub(/\r$/, ""); if (NR == 1 && index($0, B) == 1) $0 = substr($0, length(B) + 1) }
  /^[ \t]*$/ || /^#/ { next }
  $1 == "date" { ct = cr = ck = cm = cc = cw = ca = 0
    for (i = NF; i >= 1; i--) { if ($i == "task") ct = i; if ($i == "role") cr = i; if ($i == "kind") ck = i
      if ($i == "model") cm = i; if ($i == "cost") cc = i; if ($i == "wall") cw = i; if ($i == "active") ca = i }   # the first of a name
    next }
  { k = col(ck); m = col(cm); r = col(cr); c = units(col(cc), "$"); a = units(col(ca), "m")
    # an assistant'"'"'s run (#281): never a task'"'"'s; --per-run under kind and role assistant
    if (r == "assistant" || k == "assistant") { if (mode != "run") next; k = r = "assistant" }
    # a task row (role task): its wall is the time to ready, the forecast only; the last one of a task counts
    if (r == "task") { if (mode == "run") next
      t = col(ct); sub(/[.].*$/, "", t); if (t == "" || t == "-") next
      rl[t] = ++rrow; rk[t] = k; rm[t] = m; rw[t] = units(col(cw), "m"); next }
    if (mode == "run") { if (k == "" || m == "") next
      g = k "\t" r "\t" m; seen[g] = 1
      if (c >= 0) V[g, "c", ++N[g, "c"]] = c; if (a >= 0) V[g, "t", ++N[g, "t"]] = a; next }
    t = col(ct); sub(/[.].*$/, "", t); if (t == "" || t == "-") next
    last[t] = ++row
    if (c >= 0) { tc[t] += c; hc[t] = 1 }
    if (a >= 0 && col(cc) !~ /^[ \t]*in[ \t]/) { ta[t] += a; ha[t] = 1 }   # a subagent: in its parent
    # its kind and model: the lead row, else the first worker row, else the first row
    p = (r == "lead") ? 3 : ((r == "worker") ? 2 : 1)
    if (!(t in pr) || p > pr[t]) { pr[t] = p; tk[t] = k; tm[t] = m } }
  # the numbers of one measure: n, median, low, high; r = the units of the output step (a cent, a minute)
  function stats(g, x, r,   n, s, i, j, t, v, a) {
    n = N[g, x] + 0; if (n == 0) return "0\t-\t-\t-"
    s = n > 10 ? n - 9 : 1; t = 0
    for (i = s; i <= n; i++) { a[++t] = V[g, x, i]; for (j = t; j > 1 && a[j - 1] > a[j]; j--) { v = a[j]; a[j] = a[j - 1]; a[j - 1] = v } }
    return t "\t" out(t % 2 ? 2 * a[(t + 1) / 2] : a[t / 2] + a[t / 2 + 1], r) "\t" \
      out(2 * a[t < 4 ? 1 : rank(25, t)], r) "\t" out(2 * a[t < 4 ? t : rank(75, t)], r) }
  function rank(p, n,   q) { q = p * n / 100; return q == int(q) ? q : int(q) + 1 }
  # twice a value in units, rounded half up to the step r: cents as d.cc, minutes as a whole number
  function out(w, r,   c) { c = int((w + r) / (2 * r)); return r == 100 ? sprintf("%d.%02d", int(c / 100), c % 100) : sprintf("%d", c) }
  END {
    if (mode != "run") {
      # the tasks in the order of their last row, each under its kind and model
      for (t in last) at[last[t]] = t
      for (i = 1; i <= row; i++) { if (!(i in at)) continue; t = at[i]
        if (tk[t] == "" || tm[t] == "") continue
        g = tk[t] "\t" tm[t]; seen[g] = 1
        if (t in hc) V[g, "c", ++N[g, "c"]] = tc[t]; if (t in ha) V[g, "t", ++N[g, "t"]] = ta[t] }
      # the task rows in the order of each task'"'"'s last one, under the kind and model they name
      for (t in rl) rt[rl[t]] = t
      for (i = 1; i <= rrow; i++) { if (!(i in rt)) continue; t = rt[i]
        if (rk[t] == "" || rm[t] == "") continue
        g = rk[t] "\t" rm[t]; seen[g] = 1; if (rw[t] >= 0) V[g, "r", ++N[g, "r"]] = rw[t] }
      x = "\t"; y = "\tready_n\tready_median\tready_low\tready_high"
    }
    if (mode == "one") { g = ENVIRON["K"] "\t" ENVIRON["M"]; print g "\t" stats(g, "c", 100) "\t" stats(g, "t", 10000) x stats(g, "r", 10000); exit }
    print (mode == "run" ? "kind\trole\tmodel" : "kind\tmodel") "\tcost_n\tcost_median\tcost_low\tcost_high\ttime_n\ttime_median\ttime_low\ttime_high" y
    for (g in seen) print g "\t" stats(g, "c", 100) "\t" stats(g, "t", 10000) (x == "" ? "" : x stats(g, "r", 10000)) | "LC_ALL=C sort"
    close("LC_ALL=C sort") }' "$f"
