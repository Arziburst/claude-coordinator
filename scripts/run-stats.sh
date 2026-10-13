#!/usr/bin/env bash
# The forecast numbers from a run log (CORE §7a; macOS / Linux, no dependencies; Windows: run-stats.ps1).
#   scripts/run-stats.sh <RUNS.tsv>                                 per kind and model, over TASKS
#   scripts/run-stats.sh <RUNS.tsv> --kind <kind> --model <model>   that pair's line only (a contract's estimate)
#   scripts/run-stats.sh <RUNS.tsv> --per-run                       per kind, role and model, over single rows
#   scripts/run-stats.sh --limits [options]                         the limits: percent per dollar, dollars left
#                                                                   and a block's fit (below)
# RUNS.tsv (CORE §7): tab-separated, columns by the header line when there is one (its first field `date`;
# names task, role, kind, model, cost, active), else in CORE §7's order (task 2, role 3, kind 4, model 5,
# cost 9, active 13). Blank lines and lines starting with # are skipped; CRLF and a UTF-8 BOM read as plain.
# Values: cost in USD (a number, `$` allowed), active in minutes (a number, a trailing `m` allowed); any
# other value (empty, `-`, `n/a`, `in <parent>`) has none, and a row without the time columns has no time.
# A TASK is the rows whose task number agrees before its first dot (37, 37.1 and 37.2 are task 37; an
# empty or `-` task is no task): its cost and its time are the sums of the values its rows have (a
# subagent's row, cost `in <parent>`, adds no time: it is inside its parent's); a task none of whose rows
# has a value for a measure is left out of that measure only. Its kind and model are its lead row's, else
# its first worker row's (the model it was planned on), else its first row's; tasks are ordered by their
# last row. Per kind and model and per measure, the LAST 10 tasks that have a value for it count.
# --per-run: every row on its own, grouped by kind, role and model, the last 10 rows with a value.
# Prints a header, then tab-separated (sorted; --per-run adds role after kind):
#   kind model cost_n cost_median cost_low cost_high time_n time_median time_low time_high
#   median: the middle value, the mean of the two middle ones for an even count;
#   low / high: the 25th and 75th percentile by nearest rank (the value at rank ceil(p * n / 100) of the
#   sorted values, 1-based) from 4 values on, min and max under 4;
#   cost to the cent, time to the minute, each rounded half up once; no values: n 0 and `-`.
# --limits (CORE §7a: limit percent per dollar, the block forecast), every option optional:
#   --status <file>        the status JSON (default <config>/coordinator/statusline.json, <config> being
#                          $CLAUDE_CONFIG_DIR or ~/.claude): rate_limits.five_hour and .seven_day
#   --spend-5h <file|->    the account's spend in that window: what `session-tokens --since <since>` prints
#   --spend-week <file|->  (its per-model token lines; - reads stdin, for one of the two)
#   --prices <file>        needed with a spend: per line `<model id> <input> <output> <cache read> <cache write>`
#                          in USD per million tokens (cache write at the 1-hour price; `$` and ` / ` allowed,
#                          # comments), then `not-weekly` for a model with its own limit whose spend does not
#                          count toward the weekly one (BINDINGS Models); a spend model takes the line of its own
#                          id, else of the longest id it starts with (a dated id); none: exit 1
#   --prev-5h, --prev-week <% per $>   the last window's ratio      --cap-5h, --cap-week <%>   the caps (§9)
#   --block <USD>          the block's estimate                     --now <Unix seconds>       instead of the clock
# Prints a header, then a line for five_hour and one for seven_day, tab-separated:
#   window used since resets cost ratio basis left left_cap block fit
#   used: used_percentage, one decimal; since: the window's start, resets_at minus 5 hours / 7 days (UTC, the
#   argument for session-tokens --since); resets: resets_at (UTC); cost: the spend at list price, USD to the
#   cent (seven_day without not-weekly models); ratio: percent per dollar, four decimals; basis: `trusted`
#   (used / cost, the window rose >= 10 points), `previous` (under 10: --prev-*), `guess` (under 10, no
#   --prev-*: used / cost), `-` (none); left / left_cap: USD before 100% / the cap at the ratio, rounded down;
#   block: the block's percent at the ratio; fit: `fits` when used + block stays within the cap (100 without
#   one), else `does not fit`. Fixed-point throughout, rounded half up once unless said; no value: `-`.
#   A window absent from the JSON: all `-`. resets_at passed: the window has reset - used 0, since, resets
#   and cost `-` (its spend is the old window's), the ratio only from --prev-*.
# Exit 1 when a file cannot be read, the JSON has no rate limits (an API key, an older Claude Code), a price
# line is malformed or a spend model has no price; 2 on a usage error.
usage() { sed -n '2,50s/^# \{0,1\}//p' "$0"; exit 2; }
B="$(printf '\357\273\277')"   # a UTF-8 BOM, read as nothing
# a value in units of 1/10000 (four decimals, the rest dropped), `$` first allowed; -1 when it is no number
units='function units(v,   i, d) { sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); sub(/^[$]/, "", v)
    if (v !~ /^[0-9]+([.][0-9]+)?$/) return -1
    i = v; d = ""; if (index(v, ".")) { i = substr(v, 1, index(v, ".") - 1); d = substr(v, index(v, ".") + 1) }
    return (i + 0) * 10000 + substr(d "0000", 1, 4) }
  function idiv(a, b) { return (a - a % b) / b }   # whole numbers: exact, no float rounding
  function bom() { sub(/\r$/, ""); if (FNR == 1 && index($0, ENVIRON["B"]) == 1) $0 = substr($0, length(ENVIRON["B"]) + 1) }'
limits() {
  local st="" s5="" sw="" pr="" p5="" pw="" c5="" cw="" bl="" now="" v x num='^[$]?[0-9]+([.][0-9]+)?$'
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || usage
    case "$1" in
      --status) st="$2" ;; --spend-5h) s5="$2" ;; --spend-week) sw="$2" ;; --prices) pr="$2" ;;
      --prev-5h) p5="$2" ;; --prev-week) pw="$2" ;; --cap-5h) c5="$2" ;; --cap-week) cw="$2" ;;
      --block) bl="$2" ;; --now) now="$2" ;; *) usage ;;
    esac; shift 2
  done
  for v in "$p5" "$pw" "$c5" "$cw" "$bl"; do [ -z "$v" ] || [[ $v =~ $num ]] || usage; done
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
  # the prices as `model in out read write flag`, each in 1/10000 USD per million tokens
  if [ -n "$pr" ]; then
    P="$(F="$pr" B="$B" LC_ALL=C awk "$units"'
      { bom() }
      /^[ \t]*(#|$)/ { next }
      { gsub(/\//, " "); $0 = $0; ok = (NF == 5 || (NF == 6 && $6 == "not-weekly"))
        for (i = 2; i <= 5 && ok; i++) if ((u[i] = units($i)) < 0) ok = 0
        if (!ok) { print "run-stats: " ENVIRON["F"] ":" FNR ": not a price line (<model> <input> <output> <cache read> <cache write> [not-weekly])" > "/dev/stderr"; exit 1 }
        print $1, u[2], u[3], u[4], u[5], (NF == 6 ? "w" : "-") }' "$pr")" || return 1
  fi
  # a spend in micro-USD: tokens times the price of the model's line; the week leaves not-weekly out
  spend() {
    local f="$1"; [ "$f" = - ] && f=""
    P="$P" WIN="$2" F="$pr" B="$B" LC_ALL=C awk "$units"'
      BEGIN { n = split(ENVIRON["P"], L, "\n"); for (i = 1; i <= n; i++) { split(L[i], a, " "); id[i] = a[1]
                pi[i] = a[2]; po[i] = a[3]; prd[i] = a[4]; pw[i] = a[5]; nw[i] = (a[6] == "w") } }
      function tok(k,   t) { if (!match($0, "(^|[ \t])" k "[0-9]+")) return 0
        t = substr($0, RSTART, RLENGTH); sub(/^.*=/, "", t); return t + 0 }
      { bom() }
      /^[ \t]*(#|$)/ || $1 == "total" || $1 == "cost" || $1 == "time" || $0 !~ /[ \t]in=[0-9]/ { next }
      { m = $1; b = 0
        for (i = 1; i <= n; i++) if (id[i] == m || (index(m, id[i]) == 1 && (b == 0 || length(id[i]) > length(id[b])))) { b = i; if (id[i] == m) break }
        if (!b) { print "run-stats: no price for " m " in " ENVIRON["F"] > "/dev/stderr"; exit 1 }
        if (ENVIRON["WIN"] == "week" && nw[b]) next
        T += tok("in=") * pi[b] + tok("out>=") * po[b] + tok("cache_read=") * prd[b] + tok("cache_write=") * pw[b] }
      END { printf "%.0f\n", idiv(T, 10000) }' ${f:+"$f"}
  }
  if [ -n "$s5" ]; then c5u="$(spend "$s5" 5h)" || return 1; fi
  if [ -n "$sw" ]; then cwu="$(spend "$sw" week)" || return 1; fi
  W="$W" C5="$c5u" CW="$cwu" P5="$p5" PW="$pw" CAP5="$c5" CAPW="$cw" BL="$bl" NOW="$now" LC_ALL=C awk "$units"'
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
      print "window\tused\tsince\tresets\tcost\tratio\tbasis\tleft\tleft_cap\tblock\tfit"
      line("five_hour", 18000, ENVIRON["C5"], ENVIRON["P5"], ENVIRON["CAP5"])
      line("seven_day", 604800, ENVIRON["CW"], ENVIRON["PW"], ENVIRON["CAPW"]) }
    # used in 1/10000 percent, cost c in micro-USD, the ratio r in 1/10000 percent per dollar
    function line(w, len, c, prev, cap,   u, since, res, r, basis, cost, left, lc, blk, fit, L4, bc, p) {
      if (!(w in U) || U[w] == "-") { print w "\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-"; return }
      u = units(U[w]); since = res = "-"
      if (R[w] != "-" && R[w] + 0 <= now) { u = 0; c = "" }   # the window has reset since the JSON was written
      else if (R[w] != "-") { res = iso(int(R[w])); since = iso(int(R[w]) - len) }
      cost = (c == "") ? "-" : usd(rdiv(c, 10000)); c = (c == "") ? 0 : c + 0
      r = -1; basis = "-"
      if (u >= 100000 && c > 0) { r = rdiv(u * 1000000, c); basis = "trusted" }
      else if (prev != "") { r = units(prev); basis = "previous" }
      else if (u > 0 && c > 0) { r = rdiv(u * 1000000, c); basis = "guess" }
      left = lc = blk = fit = "-"
      L4 = (cap != "") ? units(cap) : 1000000
      if (r > 0) { left = usd(idiv((u < 1000000 ? 1000000 - u : 0) * 100, r))
        if (cap != "") lc = usd(idiv((u < L4 ? L4 - u : 0) * 100, r)) }
      if (ENVIRON["BL"] != "" && r > 0) { bc = rdiv(units(ENVIRON["BL"]), 100); p = bc * r   # in 1/1000000 percent
        blk = one(rdiv(p, 100000)); fit = (100 * u + p <= 100 * L4) ? "fits" : "does not fit" }
      print w "\t" one(rdiv(u, 1000)) "\t" since "\t" res "\t" cost "\t" (r < 0 ? "-" : sprintf("%d.%04d", idiv(r, 10000), r % 10000)) "\t" basis "\t" left "\t" lc "\t" blk "\t" fit }'
}
[ "${1:-}" = --limits ] && { shift; limits "$@"; exit $?; }
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
  BEGIN { B = ENVIRON["B"]; mode = ENVIRON["MODE"]; ct = 2; cr = 3; ck = 4; cm = 5; cc = 9; ca = 13 }
  # a value in units of 1/10000 (four decimals, the rest dropped); -1 when it is no number
  function units(v, unit,   i, d) { sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
    if (unit == "$") sub(/^[$]/, "", v); else sub(/m$/, "", v)
    if (v !~ /^[0-9]+([.][0-9]+)?$/) return -1
    i = v; d = ""; if (index(v, ".")) { i = substr(v, 1, index(v, ".") - 1); d = substr(v, index(v, ".") + 1) }
    return (i + 0) * 10000 + substr(d "0000", 1, 4) }
  function col(c) { return c ? $c : "" }
  { sub(/\r$/, ""); if (NR == 1 && index($0, B) == 1) $0 = substr($0, length(B) + 1) }
  /^[ \t]*$/ || /^#/ { next }
  $1 == "date" { ct = cr = ck = cm = cc = ca = 0
    for (i = NF; i >= 1; i--) { if ($i == "task") ct = i; if ($i == "role") cr = i; if ($i == "kind") ck = i
      if ($i == "model") cm = i; if ($i == "cost") cc = i; if ($i == "active") ca = i }   # the first of a name
    next }
  { k = col(ck); m = col(cm); r = col(cr); c = units(col(cc), "$"); a = units(col(ca), "m")
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
    }
    if (mode == "one") { g = ENVIRON["K"] "\t" ENVIRON["M"]; print g "\t" stats(g, "c", 100) "\t" stats(g, "t", 10000); exit }
    print (mode == "run" ? "kind\trole\tmodel" : "kind\tmodel") "\tcost_n\tcost_median\tcost_low\tcost_high\ttime_n\ttime_median\ttime_low\ttime_high"
    for (g in seen) print g "\t" stats(g, "c", 100) "\t" stats(g, "t", 10000) | "LC_ALL=C sort"
    close("LC_ALL=C sort") }' "$f"
