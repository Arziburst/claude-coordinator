#!/usr/bin/env bash
# check-bounds (#381) on a throwaway git repository: the exact lines and exit codes, from either version.
#   tests/check-bounds/run.sh sh                    # check-bounds.sh, with the bash running this file
#   tests/check-bounds/run.sh ps pwsh               # check-bounds.ps1 (or: ps powershell)
# Exit 1 if any case fails.
# The access points:
#   scripts/check-bounds.sh <contract> <base>...<head>   (.ps1: the same two arguments, by position), run from
#   inside the repository; the bounds are the lines `- <glob> <max added lines>` under `bounds:` of the
#   contract's header (the front matter; a `bounds:` in the body below it is no bound; a CRLF file reads the same).
#   A glob matches the whole path from the repository's root, `*` crosses folders, letter case counts.
#   In this order:
#     one line per bound in the contract's order, `<glob> <added>/<max>`; a binary file a bound matches counts as 0
#     and is named by one line `binary: <path> counts as 0` right before that bound's line (a binary file no
#     bound matches is not named); then `check-bounds: OK`, or one `check-bounds: OVER <glob> <added>/<max>` per
#     bound over its maximum, in the contract's order.
#   No bound in the header: the one line `check-bounds: no bounds`, exit 0.
#   Exit 0 OK, 1 OVER, 2 a usage error: an argument missing, a second argument without `...`, a contract that
#   cannot be read, a range git cannot read (never `check-bounds: OK`).
# A file in two globs counts in both; a file no bound matches is not limited; removed lines do not count.
set -u
[ $# -gt 0 ] || { sed -n '2,5s/^# \{0,1\}//p' "$0"; exit 2; }
kind="$1"; shift; PS=("$@")
case "$kind" in sh) ;; ps) [ ${#PS[@]} -gt 0 ] || { echo "ps needs powershell or pwsh" >&2; exit 2; } ;; *) echo "unknown kind: $kind" >&2; exit 2 ;; esac
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
command -v cygpath >/dev/null 2>&1 && core="$(cygpath -m "$core")"

g() { git -C "$tmp/repo" -c user.email=t@t -c user.name=t "$@"; }
lines() { i=1; while [ "$i" -le "$2" ]; do echo "line $i"; i=$((i + 1)); done > "$tmp/repo/$1"; }
git init -q -b main "$tmp/repo"; g config core.autocrlf false
mkdir -p "$tmp/repo/src/sub" "$tmp/repo/lib" "$tmp/repo/docs" "$tmp/repo/bin" "$tmp/c"
lines lib/old.txt 4; g add -A; g commit -q -m base
g checkout -q -b work
lines src/three.txt 3; lines src/sub/two.txt 2      # src/*: 5 added, 2 of them in a subfolder
sed -n 1p "$tmp/repo/lib/old.txt" > "$tmp/lib-old"; printf 'new line\n' >> "$tmp/lib-old"; cp "$tmp/lib-old" "$tmp/repo/lib/old.txt"   # lib/*: 1 added, 3 removed
lines docs/free.txt 50                              # no bound of these cases names it
printf 'a\000b\001\n' > "$tmp/repo/bin/blob.bin"; lines bin/note.txt 1   # bin/*: a binary file and 1 added
g add -A; g commit -q -m work
R='main...work'
# the fixture itself, so a red case never means a wrong repository
got="$(g diff --numstat --no-renames "$R" | tr '\t' ' ' | sort -k3)"
want="$(printf '%s\n' '- - bin/blob.bin' '1 0 bin/note.txt' '50 0 docs/free.txt' '1 3 lib/old.txt' '2 0 src/sub/two.txt' '3 0 src/three.txt')"
[ "$got" = "$want" ] || { echo "FAIL: the fixture repository's numstat is not the one the cases count:"; printf '%s\n' "$got" | sed 's/^/    /'; exit 1; }

# mk <name> <bound line>...: a contract with these bounds
mk() { local f="$tmp/c/$1.md" b; shift
  { printf -- '---\nid: 1\ntitle: t\nbounds:\n'; for b in "$@"; do printf '  - %s\n' "$b"; done; printf 'wall: only a test\n---\n'; } > "$f"; }
cb() { (cd "$tmp/repo" || exit 9
  if [ "$kind" = ps ]; then "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$core/scripts/check-bounds.ps1" "$@"
  else bash "$core/scripts/check-bounds.sh" "$@"; fi) 2>&1; }
fail=0; n=0
# t <case> <contract> <exit> <line>...: exactly these lines and this exit code on main...work
t() { local what="$1" c="$2" want="$3" out rc w; shift 3; n=$((n + 1))
  out="$(cb "../c/$c.md" "$R")"; rc=$?; out="$(printf '%s\n' "$out" | tr -d '\r')"
  w="$(printf '%s\n' "$@")"
  [ "$rc" = "$want" ] && [ "$out" = "$w" ] ||
    { echo "FAIL ($what): want exit $want and:"; printf '%s\n' "$w" | sed 's/^/    /'; echo "  got exit $rc and:"; printf '%s\n' "$out" | sed 's/^/    /'; fail=1; }
}
# u <case> <argument>...: a usage error, exit 2 and never an OK
u() { local what="$1" out rc; shift; n=$((n + 1))
  out="$(cb "$@")"; rc=$?
  { [ "$rc" = 2 ] && ! printf '%s\n' "$out" | grep -q 'check-bounds: OK'; } ||
    { echo "FAIL (usage, $what): want exit 2 and no OK, got exit $rc:"; printf '%s\n' "$out" | sed 's/^/    /'; fail=1; }
}

mk within 'src/* 6';  t "within a bound" within 0 'src/* 5/6' 'check-bounds: OK'
mk exact 'src/* 5';   t "exactly at the bound" exact 0 'src/* 5/5' 'check-bounds: OK'
mk over 'src/* 4';    t "one over" over 1 'src/* 5/4' 'check-bounds: OVER src/* 5/4'
sed 's/$/\r/' "$tmp/c/over.md" > "$tmp/c/crlf.md"
                      t "a CRLF contract reads the same" crlf 1 'src/* 5/4' 'check-bounds: OVER src/* 5/4'
mk nomatch 'nowhere/* 0'; t "files no bound matches are not limited" nomatch 0 'nowhere/* 0/0' 'check-bounds: OK'
mk anchored 'three.txt 0'; t "a glob holds from the root" anchored 0 'three.txt 0/0' 'check-bounds: OK'
mk casey 'SRC/* 0';   t "letter case counts" casey 0 'SRC/* 0/0' 'check-bounds: OK'
mk removed 'lib/* 1'; t "removed lines do not count" removed 0 'lib/* 1/1' 'check-bounds: OK'
mk binary 'bin/* 1';  t "a binary file counts as 0 and is named" binary 0 'binary: bin/blob.bin counts as 0' 'bin/* 1/1' 'check-bounds: OK'
mk binover 'bin/* 0'; t "a binary file beside an overrun" binover 1 'binary: bin/blob.bin counts as 0' 'bin/* 1/0' 'check-bounds: OVER bin/* 1/0'
mk binonly 'bin/blob.bin 0'; t "a binary file alone is within 0" binonly 0 'binary: bin/blob.bin counts as 0' 'bin/blob.bin 0/0' 'check-bounds: OK'
mk two 'src/* 5' 'lib/* 1'; t "two globs within" two 0 'src/* 5/5' 'lib/* 1/1' 'check-bounds: OK'
mk twoone 'lib/* 0' 'src/* 5'; t "two globs, one over: the contract's order" twoone 1 'lib/* 1/0' 'src/* 5/5' 'check-bounds: OVER lib/* 1/0'
mk twoover 'src/* 4' 'lib/* 0'; t "two globs, both over" twoover 1 'src/* 5/4' 'lib/* 1/0' 'check-bounds: OVER src/* 5/4' 'check-bounds: OVER lib/* 1/0'
mk both 'src/three.txt 2' 'src/* 5'; t "a file in two globs counts in both" both 1 'src/three.txt 3/2' 'src/* 5/5' 'check-bounds: OVER src/three.txt 3/2'
printf -- '---\nid: 1\ntitle: t\n---\n' > "$tmp/c/nob.md"
                      t "no bounds" nob 0 'check-bounds: no bounds'
printf -- '---\nid: 1\ntitle: t\n---\nbounds:\n  - src/* 0\n' > "$tmp/c/body.md"
                      t "bounds in the body are no bounds" body 0 'check-bounds: no bounds'
u "no argument"
u "no range" ../c/within.md
u "a range without three dots" ../c/within.md main
u "a contract that cannot be read" ../c/absent.md "$R"
u "a range git cannot read" ../c/within.md main...no-such-branch

echo "check-bounds ($kind): $n cases, $( [ $fail = 0 ] && echo all pass || echo FAILURES )"
exit $fail
