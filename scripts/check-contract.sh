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
#   - a file that cannot be read: `<file>: cannot read`.
# WARN — allowed, but say why in the brief:
#   - budget.model, budget.escalate_to, budget.cost or touches missing; no criterion with an oracle check;
#   - budget.time (optional, never missed) present but not minutes or a range of them (25, 18-40).
# Reads the structure line by line (no YAML parser), so keep the CONTRACT.md layout; values may be quoted.
[ $# -gt 0 ] || { sed -n '2,17s/^# \{0,1\}//p' "$0"; exit 2; }
failed=0
for f in "$@"; do
  { [ -f "$f" ] && [ -r "$f" ]; } || { echo "$f: cannot read"; failed=1; continue; }
  # the name via the environment: awk -v would read C:\Users as escapes (Git Bash)
  F="$f" B="$(printf '\357\273\277')" awk '
    BEGIN { F = ENVIRON["F"]; B = ENVIRON["B"]; q = sprintf("%c", 39) }
    # a value without its comment, blanks and surrounding quotes (double or single)
    function val(s,   a) { sub(/[ \t]+#.*$/, "", s); gsub(/^[ \t]+|[ \t]+$/, "", s); a = substr(s, 1, 1)
      if (length(s) >= 2 && (a == "\"" || a == q) && substr(s, length(s), 1) == a) s = substr(s, 2, length(s) - 2); return s }
    # a value that says something: not empty, not blanks inside quotes, not null (~)
    function filled(s) { s = val(s); gsub(/^[ \t]+|[ \t]+$/, "", s); return s != "" && s != "~" && tolower(s) != "null" }
    # a top-level value that holds nothing: comments, block markers, blanks or empty quotes only
    function blank(k,   t) { t = txt[k]; gsub(/#[^\n]*/, "", t); gsub(/[>|\n \t]/, "", t); return t == "" || t == "\"\"" || t == q q }
    function err(m) { print F ": ERROR " m; ne++ }
    function warn(m) { print F ": WARN  " m; nw++ }
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
      split("id title intent acceptance non_goals do_not_decide", req, " ")
      for (k = 1; k <= 6; k++) if (!(req[k] in has)) err("missing `" req[k] "`")
      split("id title intent", req, " ")
      for (k = 1; k <= 3; k++) if ((req[k] in has) && blank(req[k])) err("`" req[k] "` is empty")

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
      print F ": " (ne ? "FAIL" : "OK") " (" ne+0 " errors, " nw+0 " warnings)"
      exit (ne ? 1 : 0)
    }' "$f" || failed=1
done
exit $failed
