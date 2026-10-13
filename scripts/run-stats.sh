#!/usr/bin/env bash
# The forecast numbers from a run log (CORE §7a; macOS / Linux, no dependencies; Windows: run-stats.ps1).
#   scripts/run-stats.sh <RUNS.tsv>                                 per kind and model, over TASKS
#   scripts/run-stats.sh <RUNS.tsv> --kind <kind> --model <model>   that pair's line only (a contract's estimate)
#   scripts/run-stats.sh <RUNS.tsv> --per-run                       per kind, role and model, over single rows
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
# Exit 1 when the file cannot be read, 2 on a usage error.
usage() { sed -n '2,26s/^# \{0,1\}//p' "$0"; exit 2; }
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
