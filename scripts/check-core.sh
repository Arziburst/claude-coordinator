#!/usr/bin/env bash
# Check the coordinator core's own references (macOS / Linux, no dependencies; Windows: check-core.ps1).
#   scripts/check-core.sh [repo-root]
# Fails (exit 1) on:
#   - a relative Markdown link to a file that does not exist;
#   - a section reference (§4b, CORE §12a, §1.16) to a section that does not exist — sections are the
#     `## <id>. ` headings of CORE.md and procedures/*.md, and §1.N must name an existing hard rule;
#   - FEATURES.md out of sync: a file a block names is missing, a script, procedure, role or one-time
#     step is in no feature, an ID repeats, a block lacks a field, the table and the blocks disagree.
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
      cur = ""; for (k = 1; k <= 5; k++) f[k] = 0
    }
    BEGIN { fname[1] = "defined"; fname[2] = "entry"; fname[3] = "promises"; fname[4] = "tested by"; fname[5] = "not covered" }
    { sub(/\r$/, "") }
    /^[ \t]*```/ { code = !code; next }
    code { next }
    /^\| *F-[A-Z]+-[0-9]+ *\|/ { s = $0; sub(/^\| */, "", s); sub(/ *\|.*$/, "", s)
      if (!(s in row)) { row[s] = NR; nr++; rord[nr] = s }; next }
    /^### / { endblk()
      if ($2 ~ /^F-[A-Z]+-[0-9]+$/) { cur = $2; curn = NR
        if (cur in blk) print "E", NR, "duplicate feature id " cur
        else { blk[cur] = NR; nb++; bord[nb] = cur } }
      next }
    /^## / { endblk(); next }
    cur != "" && /^- [a-z ]+:/ {
      kk = 0
      for (k = 1; k <= 5; k++) if (index($0, "- " fname[k] ":") == 1) { f[k] = 1; kk = k }
      if (kk == 1 || kk == 2 || kk == 4) {
        s = $0; sub(/^- [a-z ]+:/, "", s); gsub(/[`,;()]/, " ", s)
        n = split(s, t, " ")
        for (i = 1; i <= n; i++) {
          p = t[i]; sub(/#.*$/, "", p); sub(/[.:]+$/, "", p); sub(/\/$/, "", p)
          if (p !~ /^[A-Za-z0-9_.-]+(\/[A-Za-z0-9_.-]+)*$/) continue
          if (p ~ /\// || (p ~ /\.(md|sh|ps1|json|yml|txt)$/ && p !~ /^\./)) print "P", NR, p
        }
      }
    }
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
fi

nsec=$(echo $sections | wc -w | tr -d ' ')
echo "check-core: $files files, $nsec sections, $rules hard rules, $nfeat features, $errors errors"
[ "$errors" -eq 0 ]
