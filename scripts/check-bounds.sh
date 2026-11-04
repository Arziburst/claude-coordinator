#!/usr/bin/env bash
# A contract's bounds against the real diff (#381; macOS / Linux; Windows: check-bounds.ps1 - the same lines and codes).
#   scripts/check-bounds.sh <contract> <base>...<head>      run from inside the repository
# The bounds: the lines `- <glob> <max added lines>` under `bounds:` of the contract's block (its front matter, a
# top-level `contract:`, else the file, as check-contract reads it). A glob holds the whole path from the root, `*`
# crosses folders, letter case counts. Per bound the added lines of `git diff --numstat --no-renames` of the files it
# matches (a file in two globs counts in both; a rename by its new path, all its lines added; a file no bound matches
# is not limited): `<glob> <added>/<max>`, a binary file it matches named before it, `binary: <path> counts as 0`.
# Then `check-bounds: OK`, or one `check-bounds: OVER <glob> <added>/<max>` per bound over. No bound: the one line
# `check-bounds: no bounds`. Exit 0 OK or no bounds, 1 OVER, 2 usage, an unreadable contract or range, a malformed bound
# (also a max too large for a long, or a `[` not closed: refused before the diff is read, the line naming the bound).
usage() { sed -n '2,3s/^# \{0,1\}//p' "$0" >&2; exit 2; }
[ $# -eq 2 ] || usage
c="$1" range="$2"; case "$range" in *...*) ;; *) usage ;; esac
{ [ -f "$c" ] && [ -r "$c" ]; } || { echo "check-bounds: cannot read $c"; exit 2; }
# the bounds as `<glob> <max>`, a malformed line with a leading blank
b="$(LC_ALL=C awk '
  { sub(/\r$/, ""); if (NR == 1 && substr($0, 1, 3) == "\357\273\277") $0 = substr($0, 4); L[++n] = $0 }
  END { s = 1; e = n
    if (L[1] ~ /^---[ \t]*$/) { s = 2; for (i = 2; i <= n; i++) if (L[i] ~ /^---[ \t]*$/) { e = i - 1; break } }
    else for (i = 1; i <= n; i++) if (L[i] ~ /^contract:[ \t]*$/) { s = i + 1
      for (j = s; j <= n; j++) if (L[j] ~ /^[^ \t]/) { e = j - 1; break }
      for (j = s; j <= e; j++) sub(/^[ \t]+/, "", L[j]); break }
    for (i = s; i <= e; i++) { l = L[i]
      if (l ~ /^[a-z_]+:/) { on = 0; if (l ~ /^bounds:/) { on = 1; sub(/^bounds:[ \t]*/, "", l); if (l !~ /^(#.*)?$/) print " " L[i] }; continue }
      if (!on || l ~ /^[ \t]*(#.*)?$/) continue
      if (l !~ /^[ \t]*-[ \t]+[^ \t]+[ \t]+[0-9]+([ \t]+#.*)?[ \t]*$/) { print " " l; continue }
      sub(/^[ \t]*-[ \t]+/, "", l); split(l, a, /[ \t]+/); x = a[2]; sub(/^0+/, "", x); y = a[1]; gsub(/\[[^]]+\]/, "", y)
      if (length(x) > 19 || (length(x) == 19 && x > "9223372036854775807") || index(y, "[")) { print " " L[i]; continue }
      print a[1] " " a[2] } }' "$c")"
bad="$(printf '%s\n' "$b" | sed -n 's/^ //p' | head -n 1)"
[ -z "$bad" ] || { echo "check-bounds: a malformed bound (- <glob> <max added lines>): $bad"; exit 2; }
[ -n "$b" ] || { echo "check-bounds: no bounds"; exit 0; }
nums="$(git -c core.quotePath=false diff --numstat --no-renames "$range" 2>&1)" || { echo "check-bounds: cannot read $range in the repository $(git rev-parse --show-toplevel 2>/dev/null || echo '(none)'): $(printf '%s' "$nums" | head -n 1); run it from the project's root"; exit 2; }
over=""
while read -r g m; do
  a=0
  while IFS="$(printf '\t')" read -r x _ p; do
    case "$p" in $g) [ -n "$p" ] || continue; if [ "$x" = - ]; then echo "binary: $p counts as 0"; else a=$((a + x)); fi ;; esac
  done <<IN
$nums
IN
  echo "$g $a/$m"; [ "$a" -le "$m" ] || over="$over
check-bounds: OVER $g $a/$m"
done <<IN
$b
IN
if [ -n "$over" ]; then printf '%s\n' "${over#?}"; exit 1; fi
echo "check-bounds: OK"
