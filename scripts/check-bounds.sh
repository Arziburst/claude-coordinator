#!/usr/bin/env bash
# A contract's bounds against the real diff (#381; macOS / Linux; Windows: check-bounds.ps1 - the same lines and codes).
#   scripts/check-bounds.sh <contract> <base>...<head>      run from inside the repository
# The bounds: the lines `- <glob> <max added lines>` under `bounds:` of the contract's block (its front matter, a
# top-level `contract:`, else the file, as check-contract reads it). A glob holds the whole path from the root, `*`
# crosses folders, `**/` is zero or more folders (#529), letter case counts. Per bound the added lines of
# `git diff --numstat --no-renames` of the files it matches (a file in two globs counts in both; a rename by its new path, all its lines added; a file no bound matches
# is not limited): `<glob> <added>/<max>`, a binary file it matches named before it, `binary: <path> counts as 0`, and
# `check-bounds: WARN <glob> matches no file` before it for a glob matching no path of the diff (either side) nor a file
# tracked at the head (#586). One pair of matching surrounding quotes (`"..."`, `'...'`) is dropped from a glob (#586).
# Then `check-bounds: OK`, or one `check-bounds: OVER <glob> <added>/<max>` per bound over. No bound: the one line
# `check-bounds: no bounds`. Exit 0 OK or no bounds, 1 OVER, 2 usage, an unreadable contract or range, a malformed bound
# (also a max too large for a long, or a `[` not closed: refused before the diff is read, the line naming the bound),
# the #615 refusal (touches found nowhere, or another repository's origin; with touches found nowhere an OVER is still reported, exit 1).
usage() { sed -n '2,3s/^# \{0,1\}//p' "$0" >&2; exit 2; }
# globmatch <path> <glob> [<from>]: the glob matches the path; each `**/` from <from> on: none, or `*/` (one or more folders)
globmatch() { local f="${3:-0}" r a; r="${2:$f}"; case "$r" in *'**/'*) a="${2:0:$f}${r%%'**/'*}"; r="${r#*'**/'}"
  globmatch "$1" "$a$r" ${#a} || globmatch "$1" "$a*/$r" $((${#a} + 2)) ;; *) case "$1" in $2) return 0 ;; esac; return 1 ;; esac; }
[ $# -eq 2 ] || usage
c="$1" range="$2"; case "$range" in *...*) ;; *) usage ;; esac
{ [ -f "$c" ] && [ -r "$c" ]; } || { echo "check-bounds: cannot read $c"; exit 2; }
# the bounds as `<glob> <max>`, a malformed line with a leading blank
b="$(LC_ALL=C awk '
  # the items of touches (inline or a block list) as `//t <item>`, one with `**/` also without it; repository as `//r <value>`
  function tks(v,   a, k, m) { sub(/[ \t]#.*$/, "", v); gsub(/[][,"\047]/, " ", v); sub(/^[ \t]*-[ \t]/, " ", v); m = split(v, a, /[ \t]+/)
    for (k = 1; k <= m; k++) if (a[k] != "") { print "//t " a[k]; if (index(a[k], "**/")) { gsub(/\*\*\//, "", a[k]); print "//t " a[k] } } }
  { sub(/\r$/, ""); if (NR == 1 && substr($0, 1, 3) == "\357\273\277") $0 = substr($0, 4); L[++n] = $0 }
  END { s = 1; e = n
    if (L[1] ~ /^---[ \t]*$/) { s = 2; for (i = 2; i <= n; i++) if (L[i] ~ /^---[ \t]*$/) { e = i - 1; break } }
    else for (i = 1; i <= n; i++) if (L[i] ~ /^contract:[ \t]*$/) { s = i + 1
      for (j = s; j <= n; j++) if (L[j] ~ /^[^ \t]/) { e = j - 1; break }
      for (j = s; j <= e; j++) sub(/^[ \t]+/, "", L[j]); break }
    for (i = s; i <= e; i++) { l = L[i]
      if (l ~ /^[a-z_]+:/) { on = 0; tk = (l ~ /^touches:/); if (tk) tks(substr(l, 9))
        if (l ~ /^repository:/) { v = substr(l, 12); sub(/[ \t]#.*$/, "", v); gsub(/[ \t"\047]/, "", v); if (v != "") print "//r " v } }
      if (tk) { if (l !~ /^[a-z_]+:/) tks(l); continue }
      if (l ~ /^[a-z_]+:/) { if (l ~ /^bounds:/) { on = 1; sub(/^bounds:[ \t]*/, "", l); if (l !~ /^(#.*)?$/) print " " L[i] }; continue }
      if (!on || l ~ /^[ \t]*(#.*)?$/) continue
      if (l !~ /^[ \t]*-[ \t]+[^ \t]+[ \t]+[0-9]+([ \t]+#.*)?[ \t]*$/) { print " " l; continue }
      sub(/^[ \t]*-[ \t]+/, "", l); split(l, a, /[ \t]+/); x = a[2]; q = substr(a[1], 1, 1)
      if (length(a[1]) > 2 && (q == "\"" || q == "\047") && substr(a[1], length(a[1])) == q) a[1] = substr(a[1], 2, length(a[1]) - 2)   # #586
sub(/^0+/, "", x); y = a[1]; gsub(/\[[^]]+\]/, "", y)
      if (length(x) > 19 || (length(x) == 19 && x > "9223372036854775807") || index(y, "[")) { print " " L[i]; continue }
      print a[1] " " a[2] } }' "$c")"
tch="$(printf '%s\n' "$b" | sed -n 's#^//t ##p')"; repo="$(printf '%s\n' "$b" | sed -n 's#^//r ##p' | head -n 1)"; b="$(printf '%s\n' "$b" | grep -v '^//')"
bad="$(printf '%s\n' "$b" | sed -n 's/^ //p' | head -n 1)"
[ -z "$bad" ] || { echo "check-bounds: a malformed bound (- <glob> <max added lines>): $bad"; exit 2; }
[ -n "$b" ] || { echo "check-bounds: no bounds"; exit 0; }
nums="$(git -c core.quotePath=false diff --numstat --no-renames "$range" 2>&1)" || { echo "check-bounds: cannot read $range in the repository $(git rev-parse --show-toplevel 2>/dev/null || echo '(none)'): $(printf '%s' "$nums" | head -n 1); run it from the project's root"; exit 2; }
# #615: a folder that is not the contract's repository counts 0 for every bound: its OK is refused (an OVER is still said)
top="$(git rev-parse --show-toplevel 2>/dev/null)"; lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }; wrong=""
if [ -n "$repo" ]; then o="$(git remote get-url origin 2>/dev/null)"; u="${o%/}"
  case "$(lc "/${u%.git}")" in *[/:]"$(lc "${repo%.git}")") ;; *) echo "check-bounds: the origin of the repository $top (${o:-none}) is not the contract's repository $repo: run it inside that repository"; exit 2 ;; esac; fi
if [ -n "$tch" ]; then P=(); while IFS= read -r x; do P+=("$x"); done <<IN
$tch
IN
  [ -n "$(git -C "$top" ls-files -- "${P[@]}" 2>/dev/null | head -n 1)$(git -C "$top" diff --name-only --no-renames "$range" -- "${P[@]}" 2>/dev/null | head -n 1)" ] || wrong="check-bounds: none of the contract's touches ($(printf '%s' "$tch" | tr '\n' ' ' | sed 's/ $//')) is in the repository $top or in $range: run it inside the contract's repository"
fi
over="" outl="" nl=$'\n' hd="${range#*...}" trk="" tl=0
while read -r g m; do
  a=0 hit=0
  while IFS="$(printf '\t')" read -r x _ p; do
    [ -n "$p" ] && globmatch "$p" "$g" || continue; hit=1; if [ "$x" = - ]; then outl="${outl}binary: $p counts as 0$nl"; else a=$((a + x)); fi
  done <<IN
$nums
IN
  # #586: a glob matching no path of the diff nor a file tracked at the head (an empty head: HEAD) is named
  if [ $hit = 0 ]; then [ $tl = 1 ] || { trk="$(git -c core.quotePath=false ls-tree -r --full-tree --name-only "${hd:-HEAD}" 2>/dev/null)"; tl=1; }
    while IFS= read -r p; do [ -n "$p" ] && globmatch "$p" "$g" && { hit=1; break; }; done <<IN
$trk
IN
    [ $hit = 1 ] || outl="${outl}check-bounds: WARN $g matches no file$nl"; fi
  outl="$outl$g $a/$m$nl"; [ "$a" -le "$m" ] || over="$over
check-bounds: OVER $g $a/$m"
done <<IN
$b
IN
[ -n "$over" ] || [ -z "$wrong" ] || { echo "$wrong"; exit 2; }; printf '%s' "$outl"
if [ -n "$over" ]; then printf '%s\n' "${over#?}"; exit 1; fi
echo "check-bounds: OK"
