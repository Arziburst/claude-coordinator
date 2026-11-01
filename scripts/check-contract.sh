#!/usr/bin/env bash
# Check a contract against CONTRACT.md before it is delegated (macOS / Linux, no dependencies;
# Windows: check-contract.ps1).
#   scripts/check-contract.sh <contract.md|contract.yaml> ...
# The contract is the YAML header between `---` lines, or a top-level `contract:` block.
# ERROR (exit 1) — the contract must not go out:
#   - id, title, intent, acceptance, non_goals or do_not_decide missing; id, title or intent empty;
#   - an acceptance item not led by `criterion:`; a criterion without `check`, with a check other than
#     oracle / review / owner, or an `oracle` check without `how` (a criterion with no nameable check is
#     a planning gap, CONTRACT.md); an empty, blank or null `how` is none;
#   - non_goals without the two default lines (no changes beyond … — this contract's acceptance, or "the fix" in an older contract —, do not weaken … tests …;
#     a line commented out does not count).
#   - `tests_first` missing, or neither `yes` nor `no` with its reason (`no - <why>`; CORE §4 step 3);
#   - a file that cannot be read: `<file>: cannot read`.
# WARN — allowed, but say why in the brief:
#   - budget.model, budget.escalate_to, budget.cost or touches missing; no criterion with an oracle check;
#   - budget.time (optional, never missed) present but not minutes or a range of them (25, 18-40).
# Reads the structure line by line (no YAML parser), so keep the CONTRACT.md layout; values may be quoted.
#   scripts/check-contract.sh --field <key> <contract> - read-only: the same checks, and when the contract
#   passes only the key's value as they read it (its text with continuation lines, comment and quotes
#   removed) on one line, exit 0; else the usual ERROR and FAIL lines and exit 1 (start-worker's
#   tests_first gate, #276)
#   scripts/check-contract.sh <contract> ... --runs <RUNS.tsv> [--kind <k>] - after its own checks, the
#   budget against the run log (CORE §7a, #333): the kind is the contract's top-level `kind:` field (it wins
#   over --kind), else --kind. The model, matched both ways (letter case aside), among the models run-stats
#   lists: budget.model itself; else the longest listed name budget.model holds (claude-opus-5-5 is opus);
#   else the listed names that hold budget.model (opus finds claude-opus-5-5), of several the model of the
#   log's newest (last-written) row among them; none: budget.model as written. That resolved <model> is in
#   every line below and is the --model of the --ratio lookup. From `run-stats <RUNS.tsv>`'s line for the pair:
#   a pair with history (a task with a cost or a time): one plan line, for the coordinator to copy into the
#   plan next to the budget (not a WARN, not counted)
#     `run-stats <kind>/<model>: cost median <m>, range <low>-<high>, time median <m>, range <low>-<high>, <n> tasks`
#   with 4 or more tasks with a cost, budget.cost outside cost_low..cost_high is a WARN
#     `budget.cost <cost> is outside run-stats <kind>/<model>: median <m>, range <low>-<high>, <n> tasks`
#   with fewer, one line (not a WARN) `thin history: <n> tasks; this model's runs came in at <R>× their
#   estimates`, R the cost_ratio of `run-stats <RUNS.tsv> --ratio --model <model>`; when it has none:
#   `thin history: <n> tasks; this model has no ratio yet (no task with an estimate and a cost)`;
#   with 4 or more tasks with a time, budget.time (a range by its middle) outside time_low..time_high is the
#   same WARN with `budget.time <time>` and the time columns. A run log it cannot read, or no kind, is a WARN.
#   These WARN lines count in the summary's warnings like the others; never an ERROR, the exit code is the
#   one without --runs. Not with --field.
# The guard on tests_first: no (#334): when `tests_first` is `no ...` and the contract's title, intent or
# touches (nothing else) hold a word of this list (money, roles or customer data), in this order:
#   payment price billing invoice refund money role permission auth access customer "personal data" pii gdpr
# a WARN `tests_first is no, but <field> names `<word>` (money, roles or customer data): tests first are
# expected for such a change (CORE §4 step 3)`, counted with the warnings, never an ERROR, the exit unchanged.
# Any letter case; a whole word: no letter a-z or digit right before it or after it (an optional plural `s`
# aside), so blanks, `_ - / . '` bound it (auth_token.sh, customer's match; rolex, accessible do not);
# "personal data" with one or more blanks (a folded line break too), `-` or `_` between. One line per contract:
# the first field in the order title, intent, touches, and in it the list's first word it holds; comments
# (# ...) are not read. It prints for a failing contract too (a warning beside its errors); not with --field.
usage() { sed -n '2,51s/^# \{0,1\}//p' "$0"; exit 2; }
guard_words='payment|price|billing|invoice|refund|money|role|permission|auth|access|customer|personal data|pii|gdpr'
[ $# -gt 0 ] || usage
field=""
if [ "$1" = --field ]; then
  [ $# -ge 3 ] && [ -n "$2" ] || usage
  field="$2"; shift 2
fi
runs=""; rkind=""; hasruns=""; files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --runs) [ $# -ge 2 ] && [ -n "$2" ] || usage; runs="$2"; hasruns=1; shift 2 ;;
    --kind) [ $# -ge 2 ] && [ -n "$2" ] || usage; rkind="$2"; shift 2 ;;
    *) files+=("$1"); shift ;;
  esac
done
[ ${#files[@]} -gt 0 ] || usage
[ -z "$rkind" ] || [ -n "$hasruns" ] || usage   # --kind only with --runs
[ -z "$hasruns" ] || [ -z "$field" ] || usage
here="$(cd "$(dirname "$0")" && pwd)"
# the budget against the run log: lines `W<tab><warning>` and `I<tab><line>` (the header: --runs)
forecast() {   # <kind> <budget.model> <budget.cost> <budget.time>
  local k="$1" bm="$2" tbl m ln n r
  { [ -f "$runs" ] && [ -r "$runs" ]; } || { printf 'W\tcannot read the run log %s: the budget is not checked against run-stats (CORE §7a)\n' "$runs"; return 0; }
  [ -n "$k" ] || { printf 'W\t--runs without a kind (no `kind:` field, no --kind): the budget is not checked against run-stats\n'; return 0; }
  [ -n "$bm" ] || return 0   # budget.model missing: warned above
  tbl="$(bash "$here/run-stats.sh" "$runs" 2>&1)" || { printf 'W\trun-stats failed on %s: %s\n' "$runs" "$(printf '%s' "$tbl" | head -n 1)"; return 0; }
  # the model as run-stats lists it: the same name (`=`), else the longest listed name budget.model holds
  # (`=`), else the listed names holding budget.model (`?`, one per line)
  m="$(printf '%s\n' "$tbl" | BM="$bm" awk -F '\t' 'NR > 1 && $2 != "" { x = tolower($2); y = tolower(ENVIRON["BM"])
      if (x == y) e = $2; else if (index(y, x)) { if (length($2) > length(s)) s = $2 } else if (index(x, y)) c[$2] = 1 }
    END { if (e != "") print "=" e; else if (s != "") print "=" s; else for (k in c) print "?" k }')"
  case "$m" in
    =*) m="${m#=}" ;;
    "?"*) # several full ids holding a short budget.model: the model of the log's last row among them
      m="$(C="$(printf '%s\n' "$m" | sed 's/^?//')" B="$(printf '\357\273\277')" awk -F '\t' '
        BEGIN { n = split(ENVIRON["C"], a, "\n"); for (i = 1; i <= n; i++) C[a[i]] = 1; cm = 5 }
        { sub(/\r$/, ""); if (NR == 1 && index($0, ENVIRON["B"]) == 1) $0 = substr($0, length(ENVIRON["B"]) + 1) }
        /^[ \t]*$/ || /^#/ { next }
        $1 == "date" { for (i = NF; i >= 1; i--) if ($i == "model") cm = i; next }
        ($cm in C) { last = $cm }
        END { print last }' "$runs")" ;;
    *) m="$bm" ;;
  esac
  [ -n "$m" ] || m="$bm"
  ln="$(printf '%s\n' "$tbl" | K="$k" M="$m" awk -F '\t' 'NR > 1 && $1 == ENVIRON["K"] && $2 == ENVIRON["M"] { print; exit }')"
  # the plan line: a pair with history
  printf '%s\n' "$ln" | K="$k" M="$m" awk -F '\t' 'NF >= 10 && $3 + $7 > 0 {
    print "I\trun-stats " ENVIRON["K"] "/" ENVIRON["M"] ": cost median " $4 ", range " $5 "-" $6 ", time median " $8 ", range " $9 "-" $10 ", " $3 " tasks" }'
  n="$(printf '%s\n' "$ln" | awk -F '\t' '{ print $3 + 0 }')"
  if [ "${n:-0}" -lt 4 ]; then
    r="$(bash "$here/run-stats.sh" "$runs" --ratio --model "$m" 2>/dev/null | awk -F '\t' '{ print $3 }')"
    case "$r" in
      ''|-) printf 'I\tthin history: %s tasks; this model has no ratio yet (no task with an estimate and a cost)\n' "${n:-0}" ;;
      *) printf "I\tthin history: %s tasks; this model's runs came in at %s× their estimates\n" "${n:-0}" "$r" ;;
    esac
  fi
  # the WARN lines from the pair's line (cost from 4 tasks on; the time likewise)
  printf '%s\n' "$ln" | K="$k" M="$m" C="$3" T="$4" awk -F '\t' '
    function num(v) { sub(/^[$]/, "", v); return v ~ /^[0-9]+([.][0-9]+)?$/ }
    NF >= 10 { c = ENVIRON["C"]; t = ENVIRON["T"]; p = ENVIRON["K"] "/" ENVIRON["M"]
      v = c; sub(/^[$]/, "", v)
      if ($3 >= 4 && num(c) && (v + 0 < $5 + 0 || v + 0 > $6 + 0))
        print "W\tbudget.cost " c " is outside run-stats " p ": median " $4 ", range " $5 "-" $6 ", " $3 " tasks"
      v = t; gsub(/[ \t]/, "", v)
      if (match(v, /^[0-9]+([.][0-9]+)?-[0-9]+([.][0-9]+)?$/)) { split(v, a, "-"); v = (a[1] + a[2]) / 2 } else if (!num(v)) v = ""
      if ($7 >= 4 && v != "" && (v + 0 < $9 + 0 || v + 0 > $10 + 0))
        print "W\tbudget.time " t " is outside run-stats " p ": median " $8 ", range " $9 "-" $10 ", " $7 " tasks" }'
}
prog='
    BEGIN { F = ENVIRON["F"]; K = ENVIRON["K"]; B = ENVIRON["B"]; q = sprintf("%c", 39) }
    # a value without its comment, blanks and surrounding quotes (double or single)
    function val(s,   a) { sub(/[ \t]+#.*$/, "", s); gsub(/^[ \t]+|[ \t]+$/, "", s); a = substr(s, 1, 1)
      if (length(s) >= 2 && (a == "\"" || a == q) && substr(s, length(s), 1) == a) s = substr(s, 2, length(s) - 2); return s }
    # a value that says something: not empty, not blanks inside quotes, not null (~)
    function filled(s) { s = val(s); gsub(/^[ \t]+|[ \t]+$/, "", s); return s != "" && s != "~" && tolower(s) != "null" }
    # a top-level value that holds nothing: comments, block markers, blanks or empty quotes only
    function blank(k,   t) { t = txt[k]; gsub(/#[^\n]*/, "", t); gsub(/[>|\n \t]/, "", t); return t == "" || t == "\"\"" || t == q q }
    function err(m) { print F ": ERROR " m; ne++ }
    function warn(m) { if (K == "") print F ": WARN  " m; nw++ }
    # the value of a budget key; the fixed model names in order of strength (0: a name not on this list)
    function bval(t, k,   v) { if (!match(t, "\n[ \t]+" k ":[ \t]*[^ \t\n#]+")) return ""
                              v = substr(t, RSTART, RLENGTH); sub(/^[^:]*:[ \t]*/, "", v); return v }
    function brank(m) { m = tolower(m); return m ~ /fable/ ? 4 : m ~ /opus/ ? 3 : m ~ /sonnet/ ? 2 : m ~ /haiku/ ? 1 : 0 }
    # CRLF files read like LF ones, and a UTF-8 BOM is dropped (as in check-contract.ps1)
    { sub(/\r$/, ""); if (NR == 1 && index($0, B) == 1) $0 = substr($0, length(B) + 1); L[++n] = $0 }
    END {
      # the contract block: front matter, or the body of a top-level "contract:", else the whole file
      s = 1; e = n
      if (L[1] ~ /^---[ \t]*$/) { s = 2; for (i = 2; i <= n; i++) if (L[i] ~ /^---[ \t]*$/) { e = i - 1; break } }
      else for (i = 1; i <= n; i++) if (L[i] ~ /^contract:[ \t]*$/) {
        s = i + 1; e = n; ind = 1000
        for (j = s; j <= n; j++) {
          if (L[j] ~ /^[^ \t]/) { e = j - 1; break }
          if (L[j] ~ /[^ \t]/) { match(L[j], /^[ \t]*/); if (RLENGTH < ind) ind = RLENGTH }
        }
        for (j = s; j <= e; j++) L[j] = substr(L[j], ind + 1)
        break
      }
      # top-level keys and the text of each
      for (i = s; i <= e; i++) {
        if (match(L[i], /^[a-z_]+:/)) { key = substr(L[i], 1, RLENGTH - 1); has[key] = 1; txt[key] = substr(L[i], RLENGTH + 1); first[key] = i }
        else if (key != "") { txt[key] = txt[key] "\n" L[i]; last[key] = i }
      }
      # --runs, first pass: the kind (its first line), budget.model, budget.cost and budget.time, nothing else
      if (ENVIRON["X"] != "") { b = "\n" txt["budget"]; t = ""; k = txt["kind"]; sub(/\n.*/, "", k)
        if (match(b, /\n[ \t]+time:[^\n]*/)) { t = substr(b, RSTART, RLENGTH); sub(/^\n[ \t]+time:/, "", t); t = val(t) }
        u = sprintf("%c", 31); print val(k) u bval(b, "model") u bval(b, "cost") u t; exit 0 }   # a tab in IFS would merge empty fields
      split("id title intent acceptance non_goals do_not_decide", req, " ")
      for (k = 1; k <= 6; k++) if (!(req[k] in has)) err("missing `" req[k] "`")
      split("id title intent", req, " ")
      for (k = 1; k <= 3; k++) if ((req[k] in has) && blank(req[k])) err("`" req[k] "` is empty")
      # tests first (CORE §4 step 3): yes, or no with its reason - never left undecided
      if (!("tests_first" in has)) err("missing `tests_first` (yes, or no with the reason: CORE §4 step 3)")
      else { tf = tolower(val(txt["tests_first"])); if (tf !~ /^yes([ \t,:;(]|$)/ && tf !~ /^no[ \t]*(—|-|:|,|[(])[ \t]*[^ \t)]/)
        err("`tests_first` is neither yes nor no with its reason (" val(txt["tests_first"]) "): write `tests_first: yes` or `tests_first: no - <why>`") }

      # acceptance criteria; each item starts with `- criterion:` (the first `-` line sets the items indent)
      c = 0; ok_oracle = 0; ii = -1; mis = 0
      if ("acceptance" in has) {
        m = split(txt["acceptance"], A, "\n")
        for (i = 1; i <= m; i++) {
          line = A[i]
          if (line ~ /^[ \t]*-([ \t]|$)/) {
            match(line, /^[ \t]*/); if (ii < 0) ii = RLENGTH
            if (RLENGTH == ii && line !~ /^[ \t]*-[ \t]*[{]?[ \t]*criterion:/) mis = 1
          }
          if (line ~ /^[ \t]*criterion:/) mis = 1
          if (line ~ /^[ \t]*-[ \t]*[{]?[ \t]*criterion:/) {
            c++; crit[c] = line; sub(/^[ \t]*-[ \t]*[{]?[ \t]*criterion:[ \t]*/, "", crit[c]); chk[c] = ""; how[c] = ""
            # check: and how: on the same line only in a flow item - { criterion: ..., check: ..., how: ... } -
            # each key after the brace or a comma, so a criterion whose text holds "how:" names no how
            if (line ~ /^[ \t]*-[ \t]*[{]/) {
              if (match(line, /[{,][ \t]*check:[ \t]*[^ \t,}]+/)) { t = substr(line, RSTART, RLENGTH); sub(/^[{,][ \t]*check:[ \t]*/, "", t); chk[c] = val(t) }
              if (match(line, /[{,][ \t]*how:[^,}]*/)) { t = substr(line, RSTART, RLENGTH); sub(/^[{,][ \t]*how:/, "", t); if (filled(t)) how[c] = "y" }
            }
          } else if (c > 0 && match(line, /^[ \t]+check:/)) { chk[c] = val(substr(line, RLENGTH + 1)) }
          else if (c > 0 && match(line, /^[ \t]+how:/)) {
            hi = RLENGTH - 4; t = val(substr(line, RLENGTH + 1))
            # a block scalar (how: > or how: |) holds the lines below that are indented deeper than the key
            if (t ~ /^[>|][-+0-9]*$/) {
              for (j = i + 1; j <= m; j++) {
                if (A[j] ~ /^[ \t]*(#.*)?$/) continue
                match(A[j], /^[ \t]*/); if (RLENGTH > hi) how[c] = "y"; break
              }
            } else if (filled(t)) how[c] = "y"
          }
        }
        if (mis) err("criterion must be the first key of each acceptance item")
        else if (c == 0) err("`acceptance` has no criteria")
        for (i = 1; i <= c; i++) {
          if (chk[i] == "") err("criterion " i " has no `check` (" substr(crit[i], 1, 60) ")")
          else if (chk[i] !~ /^(oracle|review|owner)$/) err("criterion " i ": check `" chk[i] "` is not oracle / review / owner")
          else if (chk[i] == "oracle" && how[i] == "") err("criterion " i ": oracle check without `how`")
          if (chk[i] == "oracle") ok_oracle = 1
        }
        if (c > 0 && !ok_oracle) warn("no criterion has an oracle check: everything rests on opinion")
      }
      if ("non_goals" in has) {
        # its text without comments: a default line commented out (# - no changes ...) is missing
        ng = ""; gm = split(txt["non_goals"], G, "\n")
        for (k = 1; k <= gm; k++) { t = G[k]; if (t ~ /^[ \t]*#/) continue; sub(/[ \t]+#.*$/, "", t); ng = ng "\n" t }
        ng = tolower(ng)
        if (index(ng, "no changes beyond") == 0) err("non_goals lacks the default (no changes beyond this contract\047s acceptance, its diagnostics and its tests)")
        if (index(ng, "weaken") == 0) err("non_goals lacks the default (do not weaken or loosen tests, timeouts or tolerances)")
      }
      b = "\n" txt["budget"]
      if (b !~ /\n[ \t]+model:[ \t]*[^ \t\n]/) warn("budget.model missing (CORE §7)")
      if (b !~ /\n[ \t]+escalate_to:[ \t]*[^ \t\n]/) warn("budget.escalate_to missing (no stronger model to retry on)")
      else if (brank(bval(b, "model")) && brank(bval(b, "escalate_to")) && brank(bval(b, "escalate_to")) <= brank(bval(b, "model")))
        warn("budget.escalate_to (" bval(b, "escalate_to") ") is not stronger than budget.model (" bval(b, "model") "): its one retry gains nothing")
      if (b !~ /\n[ \t]+cost:[ \t]*[0-9]/) {
        if (b ~ /\n[ \t]+tokens:[ \t]*[0-9]/) warn("budget.tokens is now budget.cost, in USD at list price (CORE §7a)")
        else warn("budget.cost missing (no spend forecast, CORE §7a)")
      }
      # the time estimate is optional: checked only when it is there
      if (match(b, /\n[ \t]+time:[^\n]*/)) {
        t = substr(b, RSTART, RLENGTH); sub(/^\n[ \t]+time:/, "", t); t = val(t)
        if (t !~ /^[0-9]+([.][0-9]+)?([ \t]*-[ \t]*[0-9]+([.][0-9]+)?)?$/)
          warn("budget.time (" t ") is not minutes or a range of minutes (25 or 18-40, CORE §7a)")
      }
      tc = txt["touches"]; gsub(/#[^\n]*/, "", tc); gsub(/[ \t\n-]/, "", tc); gsub(/\[|\]/, "", tc)
      if (tc == "") warn("touches missing or empty (no conflict foresight, CORE §4a)")
      # the guard on tests_first: no (#334, the header): the first field, then the first word of the list in it
      if (("tests_first" in has) && tf ~ /^no([^a-z0-9]|$)/) {
        nwd = split(ENVIRON["GW"], GW, "|"); split("title intent touches", GF, " "); gm = ""
        for (k = 1; k <= 3 && gm == ""; k++) {
          t = tolower(txt[GF[k]]); gsub(/(^|[ \t\n])#[^\n]*/, " ", t)
          for (j = 1; j <= nwd && gm == ""; j++) { w = GW[j]; gsub(/ /, "[ \t\n_-]+", w)
            if (t ~ ("(^|[^a-z0-9])" w "s?([^a-z0-9]|$)")) gm = GF[k] " names `" GW[j] "`" }
        }
        if (gm != "") warn("tests_first is no, but " gm " (money, roles or customer data): tests first are expected for such a change (CORE §4 step 3)")
      }
      # --runs: the budget against the run log, after the checks above
      nr = split(ENVIRON["R"], RL, "\n")
      for (i = 1; i <= nr; i++) { t = RL[i]; if (substr(t, 1, 2) == "W\t") warn(substr(t, 3)); else if (substr(t, 1, 2) == "I\t" && K == "") print F ": " substr(t, 3) }
      # --field: the value of the key as read above, its lines joined into one
      if (K != "" && !ne) { v = val(txt[K]); gsub(/[ \t]*\n[ \t]*/, " ", v); gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit 0 }
      print F ": " (ne ? "FAIL" : "OK") " (" ne+0 " errors, " nw+0 " warnings)"
      exit (ne ? 1 : 0)
    }'
failed=0
B="$(printf '\357\273\277')"
for f in "${files[@]}"; do
  { [ -f "$f" ] && [ -r "$f" ]; } || { echo "$f: cannot read"; failed=1; continue; }
  R=""
  if [ -n "$hasruns" ]; then
    # the contract's kind, budget.model, budget.cost and budget.time, as the checks read them; a `kind:` field wins
    IFS=$'\037' read -r ck cm cc ct <<EOF
$(F="$f" X=1 B="$B" awk "$prog" "$f")
EOF
    R="$(forecast "${ck:-$rkind}" "$cm" "$cc" "$ct")"
  fi
  # the name via the environment: awk -v would read C:\Users as escapes (Git Bash)
  F="$f" K="$field" R="$R" B="$B" GW="$guard_words" awk "$prog" "$f" || failed=1
done
exit $failed
