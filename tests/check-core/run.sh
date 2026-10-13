#!/usr/bin/env bash
# check-core on a copy of the core that passes, then with:
#   - a FEATURES.md field wrapped onto an indented continuation line that names missing files: each one
#     reported with the continuation line's number;
#   - a script under scripts/ without its .ps1 and one under scripts/hooks/ without its .sh: each reported.
# The same lines from both versions.
#   tests/check-core/run.sh sh                  # check-core.sh, with the bash running this file
#   tests/check-core/run.sh ps pwsh             # check-core.ps1 (or: ps powershell)
# Exit 1 if any check fails.
set -u
[ $# -gt 0 ] || { sed -n '2,9s/^# \{0,1\}//p' "$0"; exit 2; }
kind="$1"; shift; PS=("$@")
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'chmod -R u+w "$tmp"; rm -r "$tmp"' EXIT

# the copy: the core's files as in the working tree (tracked, and new ones not ignored)
d="$tmp/core"; mkdir -p "$d"
(cd "$core" && git ls-files --cached --others --exclude-standard | while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done |
  tar -cf - -T -) | (cd "$d" && tar -xf -)

run() {   # check-core of this kind on the copy, its output in $LAST, its exit code in $RC
  if [ "$kind" = ps ]; then "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$d/scripts/check-core.ps1" -Root "$d" > "$tmp/out" 2>&1
  else bash "$d/scripts/check-core.sh" "$d" > "$tmp/out" 2>&1; fi
  RC=$?; LAST="$(tr -d '\r' < "$tmp/out")"
}
fail=0; n=0
expect() {   # expect <case> <exit code> <line>
  n=$((n + 1))
  { [ "$RC" = "$2" ] && printf '%s\n' "$LAST" | grep -qxF -- "$3"; } ||
    { echo "FAIL ($1): expected exit $2 and the line '$3', got exit $RC:"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }
}
summary() {   # summary <case> <exit code> <errors>: the last line ends with ", <errors> errors"
  n=$((n + 1))
  { [ "$RC" = "$2" ] && printf '%s\n' "$LAST" | tail -n 1 | grep -q "^check-core: .*, $3 errors\$"; } ||
    { echo "FAIL ($1): expected exit $2 and $3 errors, got exit $RC:"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }
}

run; summary "the copy as it is" 0 0

# a continuation line under the first "- defined:" field
awk '{ print } !done && /^- defined: / { print "  scripts/nowhere.sh, procedures/NOWHERE.md"; done = 1 }' "$d/FEATURES.md" > "$tmp/f" &&
  cat "$tmp/f" > "$d/FEATURES.md"
c="$(grep -n '^  scripts/nowhere.sh, procedures/NOWHERE.md$' "$d/FEATURES.md" | cut -d: -f1)"
# a .sh without its .ps1, a .ps1 without its .sh
printf 'echo lone\n' > "$d/scripts/lone.sh"; printf "'lone'\n" > "$d/scripts/hooks/lone.ps1"
run
expect "a continuation line names a missing script" 1 "FEATURES.md:$c: no such file scripts/nowhere.sh"
expect "a continuation line names a missing procedure" 1 "FEATURES.md:$c: no such file procedures/NOWHERE.md"
expect "a .sh without its .ps1" 1 "scripts/lone.sh: no scripts/lone.ps1 - every script is a .sh + .ps1 pair (TOOLKIT Scripts)"
expect "a .ps1 without its .sh" 1 "scripts/hooks/lone.ps1: no scripts/hooks/lone.sh - every script is a .sh + .ps1 pair (TOOLKIT Scripts)"
# and scripts/lone.sh is in no feature
summary "five errors in all" 1 5

echo "check-core ($kind): $n checks, $( [ $fail = 0 ] && echo all pass || echo FAILURES )"
exit $fail
