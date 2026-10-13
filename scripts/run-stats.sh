#!/usr/bin/env bash
# The forecast numbers from a run log (CORE §7a; macOS / Linux, no dependencies; Windows: run-stats.ps1).
#   scripts/run-stats.sh <RUNS.tsv>                              every kind and model, a header line first
#   scripts/run-stats.sh <RUNS.tsv> --kind <kind> --model <model>   that pair's line only (a contract's estimate)
# Reads RUNS.tsv (CORE §7): tab-separated, columns by the header line when there is one (its first
# field `date`; names kind, model, cost, active), else in CORE §7's order (kind 4, model 5, cost 9,
# active 13). Blank lines and lines starting with # are skipped; CRLF and a UTF-8 BOM read as plain.
# Per kind and model and per measure, the LAST 10 rows (file order) that have a value for it: cost in
# USD (a number, `$` allowed) and active in minutes (a number, a trailing `m` allowed). Any other value
# (empty, `-`, `n/a`, `in <parent>`) skips the row for that measure; a row without the time columns
# counts for cost only.
# Prints, tab-separated: kind model cost_n cost_median cost_low cost_high time_n time_median time_low time_high
#   median: the middle value, the mean of the two middle ones for an even count;
#   low / high: the 25th and 75th percentile by nearest rank (the value at rank ceil(p * n / 100) of the
#   sorted values, 1-based) from 4 values on, min and max under 4;
#   cost to the cent, time to the minute, each rounded half up once; no values: n 0 and `-`.
# Exit 1 when the file cannot be read, 2 on a usage error.
[ $# -eq 1 ] || [ $# -eq 5 ] || { sed -n '2,17s/^# \{0,1\}//p' "$0"; exit 2; }
f="$1"; kind=""; model=""; one=""
if [ $# -eq 5 ]; then
  [ "$2" = --kind ] && [ "$4" = --model ] && [ -n "$3" ] && [ -n "$5" ] || { sed -n '2,17s/^# \{0,1\}//p' "$0"; exit 2; }
  kind="$3"; model="$5"; one=1
fi
{ [ -f "$f" ] && [ -r "$f" ]; } || { echo "run-stats: cannot read $f" >&2; exit 1; }
# the file name and the pair via the environment: awk -v would read C:\Users as escapes (Git Bash)
K="$kind" M="$model" ONE="$one" B="$(printf '\357\273\277')" LC_ALL=C awk -F '\t' '
  BEGIN { B = ENVIRON["B"]; ck = 4; cm = 5; cc = 9; ca = 13 }
  # a value in units of 1/10000 (four decimals, the rest dropped); -1 when it is no number
  function units(v, unit,   i, d) { sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
    if (unit == "$") sub(/^[$]/, "", v); else sub(/m$/, "", v)
    if (v !~ /^[0-9]+([.][0-9]+)?$/) return -1
    i = v; d = ""; if (index(v, ".")) { i = substr(v, 1, index(v, ".") - 1); d = substr(v, index(v, ".") + 1) }
    return (i + 0) * 10000 + substr(d "0000", 1, 4) }
  { sub(/\r$/, ""); if (NR == 1 && index($0, B) == 1) $0 = substr($0, length(B) + 1) }
  /^[ \t]*$/ || /^#/ { next }
  $1 == "date" { ck = cm = cc = ca = 0
    for (i = NF; i >= 1; i--) { if ($i == "kind") ck = i; if ($i == "model") cm = i; if ($i == "cost") cc = i; if ($i == "active") ca = i }   # the first of a name
    next }
  { k = ck ? $ck : ""; m = cm ? $cm : ""; if (k == "" || m == "") next
    g = k "\t" m; seen[g] = 1
    if (cc && (u = units($cc, "$")) >= 0) V[g, "c", ++N[g, "c"]] = u
    if (ca && (u = units($ca, "m")) >= 0) V[g, "t", ++N[g, "t"]] = u }
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
    if (ENVIRON["ONE"] != "") { g = ENVIRON["K"] "\t" ENVIRON["M"]; print g "\t" stats(g, "c", 100) "\t" stats(g, "t", 10000); exit }
    print "kind\tmodel\tcost_n\tcost_median\tcost_low\tcost_high\ttime_n\ttime_median\ttime_low\ttime_high"
    for (g in seen) print g "\t" stats(g, "c", 100) "\t" stats(g, "t", 10000) | "LC_ALL=C sort"
    close("LC_ALL=C sort") }' "$f"
