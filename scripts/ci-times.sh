#!/usr/bin/env bash
# Seconds per step per OS of a check-core run (#373; macOS / Linux; Windows: ci-times.ps1 - the same lines and codes).
#   scripts/ci-times.sh [--baseline <file>] [--jobs <regex>] <run id | file>     the JSON of `gh run view <id> --json jobs`, or a file holding it
# Lines: `wall <s>` (the latest job's end - the earliest job's start), `total <os> <s>` (the sum of its counted steps), `shard <name> <s>` (#555:
# a `shard-<os> (<name>)` job's end - its start, by OS, then by appearance; none for a job not finished),
# `step <os> <s> <name>` (a step completed and not skipped; the shards of an OS summed, by first appearance); with
# --baseline `over <os> <s> <limit> <name>` for a step over max(floor(b * 1.3), b + 60) of its line `<os><TAB><b><TAB><name>`
# (# lines ignored). A job counts when named `shard-<os> (...)`, or `check (<os>-latest)` when the run has no shard-<os>
# job; every job counts for wall. Exit 0 (also with over lines), 2 usage, 1 `ci-times: cannot read <what>` (a missing
# run or baseline, gh failing). --jobs <regex> (#580; ERE, case-sensitive, no lookaround or backreferences): a job counts when
# its name matches, its group (where <os> stands, also in the baseline) the name with each space made _, groups by first
# appearance, no shard lines; none matching: the wall line and `ci-times: no job matches <regex>`, exit 0.
set -u
usage() { sed -n '2,3s/^# \{0,1\}//p' "$0" >&2; exit 2; }
base=""; run=""; jset=""; CT_JOBS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --baseline) [ $# -ge 2 ] || usage; base="$2"; shift 2 ;;
    --jobs) [ $# -ge 2 ] && [ -z "$jset" ] || usage; jset=1; CT_JOBS="$2"; shift 2 ;;
    -*) usage ;;
    *) [ -z "$run" ] || usage; run="$1"; shift ;;
  esac
done
[ -n "$run" ] || usage
case "$run" in
  *[!0-9]*) { [ -f "$run" ] && [ -r "$run" ] && json="$(cat "$run")"; } || { echo "ci-times: cannot read $run"; exit 1; } ;;
  *) json="$(gh run view "$run" --json jobs 2>/dev/null)" || { echo "ci-times: cannot read $run"; exit 1; } ;;
esac
if [ -n "$base" ] && ! { [ -f "$base" ] && [ -r "$base" ]; }; then echo "ci-times: cannot read $base"; exit 1; fi
export CT_JOBS; printf '%s\n' "$json" | LC_ALL=C awk -v base="$base" -v jset="$jset" '
  function epoch(t,   y, m, d, e, yoe, doy) {   # "YYYY-MM-DDTHH:MM:SS..." as UTC seconds; "" when not set (0001-01-01) or short
    if (length(t) < 19 || substr(t, 1, 4) == "0001") return ""
    y = substr(t, 1, 4) + 0; m = substr(t, 6, 2) + 0; d = substr(t, 9, 2) + 0; if (m <= 2) y--
    e = int(y / 400); yoe = y - e * 400; doy = int((153 * (m > 2 ? m - 3 : m + 9) + 2) / 5) + d - 1
    return (e * 146097 + yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy - 719468) * 86400 + substr(t, 12, 2) * 3600 + substr(t, 15, 2) * 60 + substr(t, 18, 2)
  }
  function value(v) { if (depth == 3) J[nj, key] = v; else if (depth == 5) S[ns, key] = v }   # a value under the current key: a job (depth 3) or a step (depth 5)
  { sub(/\r$/, ""); s = s $0 }
  END {
    n = length(s)
    for (i = 1; i <= n; i++) { c = substr(s, i, 1)
      if (c == "\"") { v = ""
        for (i++; i <= n && (c = substr(s, i, 1)) != "\""; i++) { if (c == "\\") { i++; c = substr(s, i, 1); if (c != "\"" && c != "\\" && c != "/") c = "\\" c }; v = v c }
        for (j = i + 1; substr(s, j, 1) == " "; j++) ; if (substr(s, j, 1) == ":") { key = v; i = j } else value(v)
      } else if (c == "{" || c == "[") { depth++; if (c == "{" && depth == 3) nj++; else if (c == "{" && depth == 5) { ns++; S[ns, "job"] = nj } }
      else if (c == "}" || c == "]") depth--
      else if (c ~ /[-0-9tfn]/) { for (j = i; j <= n && substr(s, j, 1) !~ /[,}\]]/; j++) ; value(substr(s, i, j - i)); i = j - 1 }
    }
    for (j = 1; j <= nj; j++) { nm = J[j, "name"]; o = ""
      if (jset != "") { if (nm ~ ENVIRON["CT_JOBS"]) { o = nm; gsub(/ /, "_", o); J[j, "kind"] = "job"; if (!(o in gi)) G[gi[o] = ++ng] = o } }
      else if (match(nm, /^shard-(ubuntu|macos|windows) /)) { o = substr(nm, 7, RLENGTH - 7); J[j, "kind"] = "shard"; shard[o] = 1 }
      else if (match(nm, /^check \((ubuntu|macos|windows)-latest\)$/)) { o = substr(nm, 8, RLENGTH - 15); J[j, "kind"] = "check" }
      J[j, "os"] = o; a = epoch(J[j, "startedAt"]); b = epoch(J[j, "completedAt"])
      if (a != "" && (first == "" || a < first)) first = a; if (b != "" && (last == "" || b > last)) last = b
    }
    for (j = 1; j <= nj; j++) if (J[j, "os"] != "" && !(J[j, "kind"] == "check" && (J[j, "os"] in shard))) counted[J[j, "os"]] = 1
    for (k = 1; k <= ns; k++) { j = S[k, "job"]; o = J[j, "os"]; nm = S[k, "name"]
      if (!(o in counted) || (J[j, "kind"] == "check" && (o in shard)) || S[k, "status"] != "completed" || S[k, "conclusion"] == "skipped") continue
      a = epoch(S[k, "startedAt"]); b = epoch(S[k, "completedAt"]); if (a == "" || b == "") continue
      if (!((o, nm) in sum)) { sum[o, nm] = 0; ord[o, ++cnt[o]] = nm }; sum[o, nm] += b - a; tot[o] += b - a
    }
    while (base != "" && (getline l < base) > 0) { sub(/\r$/, "", l); if (l ~ /^#/) continue; split(l, f, "\t"); if (f[2] ~ /^[0-9]+$/) bl[f[1], f[3]] = f[2] + 0 }
    nL = split("ubuntu macos windows", L, " "); if (jset != "") { nL = ng; for (x = 1; x <= ng; x++) L[x] = G[x] }
    if (first != "" && last != "") print "wall", last - first
    if (jset != "" && ng == 0) print "ci-times: no job matches " ENVIRON["CT_JOBS"]
    for (x = 1; x <= nL; x++) if (L[x] in counted) print "total", L[x], tot[L[x]] + 0
    for (x = 1; x <= nL; x++) for (j = 1; j <= nj; j++) if (J[j, "kind"] == "shard" && J[j, "os"] == L[x]) { a = epoch(J[j, "startedAt"]); b = epoch(J[j, "completedAt"])
      nm = J[j, "name"]; sub(/^[^(]*\(/, "", nm); sub(/\)$/, "", nm); if (a != "" && b != "") print "shard", nm, b - a }
    for (x = 1; x <= nL; x++) for (k = 1; k <= cnt[L[x]]; k++) print "step", L[x], sum[L[x], ord[L[x], k]], ord[L[x], k]
    for (x = 1; x <= nL; x++) for (k = 1; k <= cnt[L[x]]; k++) { o = L[x]; nm = ord[o, k]
      if ((o, nm) in bl) { b = bl[o, nm]; lim = int(b * 13 / 10); if (b + 60 > lim) lim = b + 60; if (sum[o, nm] > lim) print "over", o, sum[o, nm], lim, nm } }
  }'
