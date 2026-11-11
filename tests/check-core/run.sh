#!/usr/bin/env bash
# check-core on a copy of the core that passes, then with:
#   - a FEATURES.md field wrapped onto an indented continuation line that names missing files: each one
#     reported with the continuation line's number;
#   - a script under scripts/ without its .ps1 and one under scripts/hooks/ without its .sh: each reported;
#   - a core skill naming a missing core file, outside coord-, named unlike its folder or not the coordinator's;
#   - a stale flag or case form in a "tested by" field, also one only in a sibling of the named file (#562);
#     one below a named folder found; prose and a field naming no tests/ path unchecked;
#   - a quoted case argument with a slash in a "tested by" field not read as a path, a missing unquoted
#     tests/ file still reported (#578); a path named twice in a field listed once (#584).
# The same lines from both versions.
#   tests/check-core/run.sh sh                  # check-core.sh, with the bash running this file
#   tests/check-core/run.sh ps pwsh             # check-core.ps1 (or: ps powershell)
# Exit 1 if any check fails.
set -u
[ $# -gt 0 ] || { sed -n '2,14s/^# \{0,1\}//p' "$0"; exit 2; }
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
# the core's skills (#243): a path to a missing core file; a folder without coord-, a name not its folder,
# a description that does not say it is the coordinator's
sed 's#coordinator/core/procedures/RETRO.md#coordinator/core/procedures/NORETRO.md#' "$d/skills/coord-retro/SKILL.md" > "$tmp/s" &&
  cat "$tmp/s" > "$d/skills/coord-retro/SKILL.md"
r="$(grep -n 'NORETRO' "$d/skills/coord-retro/SKILL.md" | cut -d: -f1)"
mkdir -p "$d/skills/mine" && printf -- "---\nname: other\ndescription: 'Helps with anything'\n---\n\nHello.\n" > "$d/skills/mine/SKILL.md"
run
expect "a skill naming a missing core file" 1 "skills/coord-retro/SKILL.md:$r: no such core file procedures/NORETRO.md"
expect "a core skill's folder without coord-" 1 "skills/mine/SKILL.md: a core skill's folder starts with coord-"
expect "a skill whose name is not its folder" 1 "skills/mine/SKILL.md: name 'other' is not its folder 'mine'"
expect "a skill not marked as the coordinator's" 1 "skills/mine/SKILL.md: the description does not start with 'Coordinator only'"
summary "nine errors in all" 1 9
# "tested by" tokens (#562): a flag and a case form in none of the named files are stale (built here, so this
# file does not hold them), also one only in a sibling of the named file; one below a named folder is found;
# a plain word, a token with a space, a field naming no tests/ path unchecked
g="stale$((50 + 12))"
mkdir -p "$d/tests/check-core/sub"; printf 'v8+%s\n' "$g" > "$d/tests/check-core/sibling.txt"; printf 'v7+%s\n' "$g" > "$d/tests/check-core/sub/x.txt"
G="$g" awk '{ print } !done && /^- tested by: / { g = ENVIRON["G"]
    print "  tests/check-core/run.sh, tests/check-core/sub/ (`--" g "`, `v9+" g "`, `v8+" g "`, `v7+" g "`, `" g "`, `" g " away`)"; done = 1 }
  END { print "- tested by: a CI step (`--" ENVIRON["G"] "-ci`)" }' "$d/FEATURES.md" > "$tmp/f" && cat "$tmp/f" > "$d/FEATURES.md"
t="$(grep -n "v9+$g" "$d/FEATURES.md" | cut -d: -f1)"
run
w="occurs in none of tests/check-core/run.sh, tests/check-core/sub"
expect "a stale flag in a tested-by field" 1 "FEATURES.md:$t: tested by \`--$g\` $w"
expect "a stale case form in a tested-by field" 1 "FEATURES.md:$t: tested by \`v9+$g\` $w"
expect "a token only in a sibling of the named file" 1 "FEATURES.md:$t: tested by \`v8+$g\` $w"
summary "twelve errors in all: below a named folder found; prose and a field without a test file unchecked" 1 12
# a quoted case argument with a slash is no path, an unquoted missing tests/ file is (#578); a field naming
# one path twice lists it once (#584)
printf 'host/owner/repo ../work-old/x\n' > "$d/tests/check-core/args.txt"
G="$g" awk '{ print } END { print "- tested by: tests/check-core/args.txt (`host/owner/repo`, `../work-old/x`), tests/check-core/gone.sh"
  print "- tested by: tests/check-core/run.sh, tests/check-core/run.sh (`--" ENVIRON["G"] "-twice`)" }' "$d/FEATURES.md" > "$tmp/f" &&
  cat "$tmp/f" > "$d/FEATURES.md"
a="$(grep -n 'tests/check-core/gone.sh$' "$d/FEATURES.md" | cut -d: -f1)"; u=$((a + 1))
run
expect "a missing unquoted tests/ file" 1 "FEATURES.md:$a: no such file tests/check-core/gone.sh"
expect "a path named twice listed once" 1 "FEATURES.md:$u: tested by \`--$g-twice\` occurs in none of tests/check-core/run.sh"
summary "fourteen errors in all: quoted case arguments are no paths" 1 14

echo "check-core ($kind): $n checks, $( [ $fail = 0 ] && echo all pass || echo FAILURES )"
exit $fail
