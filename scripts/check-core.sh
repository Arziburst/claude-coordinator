#!/usr/bin/env bash
# Check the coordinator core's own references (macOS / Linux, no dependencies; Windows: check-core.ps1).
#   scripts/check-core.sh [repo-root]
# Fails (exit 1) on:
#   - a relative Markdown link to a file that does not exist;
#   - a section reference (§4b, CORE §12a, §1.16) to a section that does not exist — sections are the
#     `## <id>. ` headings of CORE.md and procedures/*.md, and §1.N must name an existing hard rule;
#   - FEATURES.md out of sync: a file a block names is missing, a script, procedure, role or one-time
#     step is in no feature, an ID repeats, a block lacks a field, the table and the blocks disagree
#     (a field's indented continuation lines are read as part of it);
#   - a script under scripts/ without its other half: every script is a .sh + .ps1 pair; the hooks exception
#     (#564): hooks/safety-guard.ps1 is only a shim (it names safety-guard.sh, at most 80 lines), never a second guard;
#   - a core skill (skills/*/SKILL.md) outside `coord-`, named unlike its folder, not marked as the
#     coordinator's, or naming a `coordinator/core/<path>` this core does not have.
# Run in CI on every pull request and before proposing a core change (CORE §10).
set -u
root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$root" || exit 2

sections=" $(cat CORE.md procedures/*.md 2>/dev/null | sed -n 's/^## \([0-9][0-9]*[a-z]\{0,1\}\)\. .*/\1/p' | sort -u | tr '\n' ' ')"
rules="$(awk '/^## 1\. /{on=1; next} /^## /{on=0} on && /^[0-9]+\. \*\*/{n++} END{print n+0}' CORE.md)"

errors=0; files=0
while IFS= read -r f; do
  files=$((files + 1))
  dir="$(dirname "$f")"
  # one record per link or § reference outside fenced code: "<line> L <target>" / "<line> S <sec> <sub>"
  while read -r n kind a b; do
    if [ "$kind" = L ]; then
      path="${a%%#*}"
      [ -z "$path" ] || [ -e "$dir/$path" ] || { echo "${f#./}:$n: broken link $a"; errors=$((errors + 1)); }
    else
      case "$sections" in
        *" $a "*) if [ "$a" = 1 ] && [ -n "$b" ] && { [ "$b" -lt 1 ] || [ "$b" -gt "$rules" ]; }; then
                    echo "${f#./}:$n: §1.$b does not exist (CORE §1 has $rules hard rules)"; errors=$((errors + 1)); fi ;;
        *) echo "${f#./}:$n: §$a does not exist"; errors=$((errors + 1)) ;;
      esac
    fi
  done < <(awk '
    { sub(/\r$/, "") }
    /^[ \t]*```/ { code = !code; next }
    code { next }
    {
      s = $0
      while (match(s, /\]\([^) \t]+\)/)) {
        t = substr(s, RSTART + 2, RLENGTH - 3); s = substr(s, RSTART + RLENGTH)
        if (t !~ /^[a-z]+:/ && t !~ /^#/) print NR, "L", t
      }
      s = $0
      while (match(s, /§[0-9]+[a-z]?(\.[0-9]+)?/)) {
        r = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
        sub(/^§/, "", r); sec = r; subn = ""
        if (index(r, ".")) { sec = substr(r, 1, index(r, ".") - 1); subn = substr(r, index(r, ".") + 1) }
        print NR, "S", sec, subn
      }
    }' "$f")
done < <(find . \( -name .git -o -name .claude \) -prune -o -type d ! -path . -exec test -e {}/.git \; -prune -o -name '*.md' -print | LC_ALL=C sort)
# (not .git, not .claude/ - agent worktrees of a checkout - and not a nested repository or worktree)

# FEATURES.md, the feature map: every file a block names exists; every script, procedure, role and
# one-time step is in some feature; IDs are unique; every block has its five fields; the summary table
# and the blocks list the same IDs. One record per finding: "E <line> <message>", "P <line> <path>",
# "N <count>".
nfeat=0
if [ ! -f FEATURES.md ]; then echo "FEATURES.md: missing"; errors=$((errors + 1)); else
  while read -r kind n rest; do
    case "$kind" in
      E) echo "FEATURES.md:$n: $rest"; errors=$((errors + 1)) ;;
      # a project's local core copy has no .github/ (CORE §2): its paths are checked only where it exists
      P) case "$rest" in .github/*) [ -d .github ] || continue ;; esac
         [ -e "$rest" ] || { echo "FEATURES.md:$n: no such file $rest"; errors=$((errors + 1)); } ;;
      N) nfeat="$n" ;;
    esac
  done < <(awk '
    function endblk(   k) {
      if (cur != "") for (k = 1; k <= 5; k++) if (!f[k]) print "E", curn, cur " lacks \"- " fname[k] ":\""
      cur = ""; cont = 0; for (k = 1; k <= 5; k++) f[k] = 0
    }
    # the file paths a field names: words with a slash, or a file name with a known extension; in a
    # "tested by" field (q) a backtick-quoted token is a case argument, no path (#578)
    function paths(s, q,   n, t, i, p) {
      if (q) gsub(/`[^`]*`/, " ", s)
      gsub(/[`,;()]/, " ", s); n = split(s, t, " ")
      for (i = 1; i <= n; i++) {
        p = t[i]; sub(/#.*$/, "", p); sub(/[.:]+$/, "", p); sub(/\/$/, "", p)
        if (p !~ /^[A-Za-z0-9_.-]+(\/[A-Za-z0-9_.-]+)*$/) continue
        if (p ~ /\// || (p ~ /\.(md|sh|ps1|json|yml|txt)$/ && p !~ /^\./)) print "P", NR, p
      }
    }
    BEGIN { fname[1] = "defined"; fname[2] = "entry"; fname[3] = "promises"; fname[4] = "tested by"; fname[5] = "not covered" }
    { sub(/\r$/, "") }
    /^[ \t]*```/ { code = !code; cont = 0; next }
    code { next }
    /^\| *F-[A-Z]+-[0-9]+ *\|/ { s = $0; sub(/^\| */, "", s); sub(/ *\|.*$/, "", s)
      if (!(s in row)) { row[s] = NR; nr++; rord[nr] = s }; cont = 0; next }
    /^### / { endblk()
      if ($2 ~ /^F-[A-Z]+-[0-9]+$/) { cur = $2; curn = NR
        if (cur in blk) print "E", NR, "duplicate feature id " cur
        else { blk[cur] = NR; nb++; bord[nb] = cur } }
      next }
    /^## / { endblk(); next }
    cur != "" && /^- [a-z ]+:/ {
      kk = 0
      for (k = 1; k <= 5; k++) if (index($0, "- " fname[k] ":") == 1) { f[k] = 1; kk = k }
      cont = kk
      if (kk == 1 || kk == 2 || kk == 4) { s = $0; sub(/^- [a-z ]+:/, "", s); paths(s, kk == 4) }
      next
    }
    # an indented line right after a field (or after another such line) continues it
    cur != "" && cont && /^[ \t]+[^ \t]/ { if (cont == 1 || cont == 2 || cont == 4) paths($0, cont == 4); next }
    { cont = 0 }
    END { endblk()
      for (i = 1; i <= nb; i++) if (!(bord[i] in row)) print "E", blk[bord[i]], bord[i] " is not in the summary table"
      for (i = 1; i <= nr; i++) if (!(rord[i] in blk)) print "E", row[rord[i]], rord[i] " has no block"
      print "N", nb }' FEATURES.md)
  for f in $(find scripts -maxdepth 2 -name '*.sh' | LC_ALL=C sort) $(find procedures roles -maxdepth 1 -name '*.md' | LC_ALL=C sort); do
    grep -qF "${f%.sh}" FEATURES.md || { echo "FEATURES.md: $f is in no feature"; errors=$((errors + 1)); }
  done
  for id in $(sed -n 's/^| `\([a-z0-9-]*\)` |.*/\1/p' ONE-TIME.md); do
    grep -qF "\`$id\`" FEATURES.md || { echo "FEATURES.md: one-time step $id is in no feature"; errors=$((errors + 1)); }
  done
  # a "tested by" field's backtick token that looks like a flag, a path or a case form (not a plain word,
  # no space, no <placeholder>, * or …) occurs in a tests/ file the field names or in a file below a tests/
  # folder it names, or a tests trim left it stale (#562, #548). A field naming no tests/ path is not
  # checked. Records: "<line> TAB <token> TAB <path> ...", each path once.
  tb="$(awk '
    function flush(   i) { if (nd) for (i = 1; i <= nt; i++) print tl[i] "\t" tt[i] "\t" dirs; nt = 0; nd = 0; dirs = ""; on = 0; split("", seen) }
    function scan(s,   t, n, i, p, w) {
      while (match(s, /`[^`]*`/)) { t = substr(s, RSTART + 1, RLENGTH - 2); s = substr(s, 1, RSTART - 1) " " substr(s, RSTART + RLENGTH)
        if (t !~ /^[A-Za-z0-9_]+$/ && t !~ /[ \t<>*]|…/) { nt++; tl[nt] = NR; tt[nt] = t } }
      gsub(/[,;()]/, " ", s); n = split(s, w, " ")
      for (i = 1; i <= n; i++) { p = w[i]; sub(/[.:]+$/, "", p)
        if (p !~ /^tests\/[A-Za-z0-9_.\/-]+$/) continue
        sub(/\/$/, "", p); if (!(p in seen)) { seen[p] = 1; nd++; dirs = dirs (nd > 1 ? "\t" : "") p } }
    }
    { sub(/\r$/, "") }
    /^[ \t]*```/ { code = !code; flush(); next }
    code { next }
    /^- tested by:/ { flush(); on = 1; scan($0); next }
    on && /^[ \t]+[^ \t]/ { scan($0); next }
    { flush() }
    END { flush() }' FEATURES.md)"
  while IFS= read -r m; do [ -n "$m" ] && { echo "$m"; errors=$((errors + 1)); }; done < <([ -n "$tb" ] &&
    printf '%s\n' "$tb" | cut -f3- | tr '\t' '\n' | LC_ALL=C sort -u | while IFS= read -r d; do if [ -d "$d" ]; then find "$d" -type f; elif [ -f "$d" ]; then echo "$d"; fi; done |
    LC_ALL=C sort -u | TB="$tb" awk 'BEGIN { n = split(ENVIRON["TB"], r, "\n")
        for (i = 1; i <= n; i++) { nd[i] = split(r[i], x, "\t") - 2; ln[i] = x[1]; tk[i] = x[2]; for (j = 1; j <= nd[i]; j++) d[i, j] = x[j + 2] } }
      { m = 0; for (i = 1; i <= n; i++) if (!ok[i]) for (j = 1; j <= nd[i]; j++) if ($0 == d[i, j] || index($0, d[i, j] "/") == 1) { s[++m] = i; break }
        while (m && (getline l < $0) > 0) for (k = 1; k <= m; k++) if (!ok[s[k]] && index(l, tk[s[k]])) ok[s[k]] = 1
        close($0) }
      END { for (i = 1; i <= n; i++) if (!ok[i]) { w = d[i, 1]; for (j = 2; j <= nd[i]; j++) w = w ", " d[i, j]
        print "FEATURES.md:" ln[i] ": tested by `" tk[i] "` occurs in none of " w } }')
fi

# every script under scripts/ is a .sh + .ps1 pair (TOOLKIT Scripts): a half without the other is an error
while IFS= read -r f; do
  case "$f" in *.sh) o="${f%.sh}.ps1" ;; *) o="${f%.ps1}.sh" ;; esac
  [ -e "$o" ] || { echo "$f: no $o - every script is a .sh + .ps1 pair (TOOLKIT Scripts)"; errors=$((errors + 1)); }
done < <([ -d scripts ] && find scripts -type f \( -name '*.sh' -o -name '*.ps1' \) | LC_ALL=C sort)
# the hooks exception (TOOLKIT Scripts, #564): the guard is safety-guard.sh on every OS; its .ps1 half only hands each call to it
g=scripts/hooks/safety-guard.ps1
if [ -f "$g" ] && ! { grep -q 'safety-guard\.sh' "$g" && [ "$(wc -l < "$g")" -le 80 ]; }; then
  echo "$g: not the shim that hands each call to safety-guard.sh (at most 80 lines): a guard rule goes into safety-guard.sh (TOOLKIT Scripts)"; errors=$((errors + 1))
fi

# the core's skills (CORE §12b, #243): skills/coord-*/SKILL.md, its frontmatter name its folder, its description
# saying it is the coordinator's, every `coordinator/core/<path>` it names a file of this core
while IFS= read -r f; do
  [ -n "$f" ] || continue
  d="$(basename "$(dirname "$f")")"
  case "$d" in coord-*) ;; *) echo "$f: a core skill's folder starts with coord-"; errors=$((errors + 1)) ;; esac
  nm="$(tr -d '\r' < "$f" | sed -n '2,6s/^name: *//p' | head -n 1)"
  [ "$nm" = "$d" ] || { echo "$f: name '$nm' is not its folder '$d'"; errors=$((errors + 1)); }
  tr -d '\r' < "$f" | sed -n '2,6p' | grep -q "^description: '\{0,1\}Coordinator only" ||
    { echo "$f: the description does not start with 'Coordinator only'"; errors=$((errors + 1)); }
  while read -r n p; do [ -e "$p" ] || { echo "$f:$n: no such core file $p"; errors=$((errors + 1)); }
  done < <(tr -d '\r' < "$f" | awk '{ s = $0
    while (match(s, /coordinator\/core\/[A-Za-z0-9._\/-]+/)) { p = substr(s, RSTART + 17, RLENGTH - 17); s = substr(s, RSTART + RLENGTH)
      sub(/[.\/]+$/, "", p); print NR, p } }')
done < <([ -d skills ] && find skills -mindepth 2 -maxdepth 2 -name SKILL.md | LC_ALL=C sort)

# the start-read texts' sizes (#600): the words of CORE.md, its section 1 (from `## 1. ` to the next `## `), its event
# table (from `| Event |` to `**Where the topics live`) and each roles/*.md - a word is a run of characters between
# spaces, tabs and line ends (a CR is a line end), the same in check-core.ps1 - against tests/check-core-sizes.txt.
# Over its record by more than the margin, or no record: a WARN, never an error (TOOLKIT check-core)
sz=tests/check-core-sizes.txt
words() { LC_ALL=C awk -v m="${2:-}" '{ gsub(/\r/, " ") }
  m == "s1" { if (/^## 1\. /) on = 1; else if (/^## /) on = 0 }
  m == "ev" { if (/^\| Event \|/) on = 1; else if (/^\*\*Where the topics live/) on = 0 }
  m == "" || on { n += NF } END { print n + 0 }' "$1"; }
mg="$(tr -d '\r' 2>/dev/null < "$sz" | sed -n 's/^margin \([0-9][0-9]*%\{0,1\}\)$/\1/p' | head -n 1)"; mg="${mg:-0}"
for t in CORE.md CORE.md#section-1 CORE.md#event-table $([ -d roles ] && find roles -maxdepth 1 -name '*.md' | LC_ALL=C sort); do
  case "$t" in *#section-1) w=$(words CORE.md s1) ;; *#event-table) w=$(words CORE.md ev) ;; *) w=$(words "$t") ;; esac
  r="$(tr -d '\r' 2>/dev/null < "$sz" | awk -v t="$t" '$1 == t && NF == 2 && $2 ~ /^[0-9]+$/ { print $2; exit }')"
  if [ -z "$r" ]; then echo "WARN: $t has $w words and no record in $sz"; continue; fi
  case "$mg" in *%) x=$((r * ${mg%\%} / 100)) ;; *) x=$mg ;; esac
  [ "$w" -le $((r + x)) ] || echo "WARN: $t has $w words, over its record $r by more than the margin $mg ($sz)"
done

nsec=$(echo $sections | wc -w | tr -d ' ')
echo "check-core: $files files, $nsec sections, $rules hard rules, $nfeat features, $errors errors"
[ "$errors" -eq 0 ]
