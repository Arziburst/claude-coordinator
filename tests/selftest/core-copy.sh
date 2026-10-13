#!/usr/bin/env bash
# The core's checks run on a copy of the core as a project holds it (coordinator/core: no .github/),
# made by `git clone` (so with .git) and carrying a nested worktree and agent worktrees under .claude/:
#   - selftest scripts fails on the copy's CLAUDE.md, .git or not;
#   - check-core counts only the copy's own Markdown files (not .claude/ or a nested worktree);
#   - check-scripts passes on the whole copy (the deliberately broken fixtures are skipped) and still
#     reports them when given their folder.
#   tests/selftest/core-copy.sh sh                  # the .sh scripts, with the bash running this file
#   tests/selftest/core-copy.sh ps pwsh             # the .ps1 scripts (or: ps powershell)
# Exit 1 if any check fails.
set -u
[ $# -gt 0 ] || { sed -n '2,10s/^# \{0,1\}//p' "$0"; exit 2; }
kind="$1"; shift; PS=("$@")
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'chmod -R u+w "$tmp"; rm -r "$tmp"' EXIT

# the copy: the core's tracked files (as in the working tree) without .github/, then git init
d="$tmp/coordinator/core"; mkdir -p "$d"
(cd "$core" && git ls-files | grep -v '^\.github/' | tar -cf - -T -) | (cd "$d" && tar -xf -)
git init -q "$d"
want="$(cd "$core" && git ls-files '*.md' | grep -vc '^\.github/')"
# agent worktrees and a nested worktree, each with a Markdown file whose link is broken
mkdir -p "$d/.claude/worktrees/agent-1" "$d/nested"
printf '[x](missing.md)\n' > "$d/.claude/worktrees/agent-1/README.md"
printf 'gitdir: /nowhere\n' > "$d/nested/.git"; printf '[x](missing.md)\n' > "$d/nested/README.md"

run() {   # run <script name> <args...>: the .sh or the .ps1 of this kind, its output in $LAST, its code in $RC
  local s="$1"; shift
  if [ "$kind" = ps ]; then "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$d/scripts/$s.ps1" "$@" > "$tmp/out" 2>&1
  else bash "$d/scripts/$s.sh" "$@" > "$tmp/out" 2>&1; fi
  RC=$?; LAST="$(tr -d '\r' < "$tmp/out")"
}
fail=0; n=0
expect() {   # expect <case> <exit code> <line>
  n=$((n + 1))
  { [ "$RC" = "$2" ] && printf '%s\n' "$LAST" | grep -qxF -- "$3"; } ||
    { echo "FAIL ($1): expected exit $2 and the line '$3', got exit $RC:"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }
}

run selftest scripts
expect "CLAUDE.md in a cloned core copy" 1 "FAIL scripts: the local core copy holds CLAUDE.md: remove it (it tells every worker it is the coordinator)"
if [ "$kind" = ps ]; then run check-core -Root "$d"; else run check-core "$d"; fi
LAST="$(printf '%s\n' "$LAST" | sed 's/, [0-9]* sections, [0-9]* hard rules, [0-9]* features//')"
expect "check-core skips .claude/ and a nested worktree" 0 "check-core: $want files, 0 errors"
cd "$d" || exit 1
clean() {   # clean <case>: exit 0, no error and nothing of the broken fixtures listed
  n=$((n + 1))
  { [ "$RC" = 0 ] && printf '%s\n' "$LAST" | grep -q '^check-scripts: [0-9]* files, 0 errors$' && ! printf '%s\n' "$LAST" | grep -q 'broken'; } ||
    { echo "FAIL ($1): expected exit 0, 0 errors and no broken fixture, got exit $RC:"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }
}
run check-scripts .
clean "check-scripts on the whole copy"
run check-scripts tests/check-scripts
clean "check-scripts on a folder above the broken fixtures"
run check-scripts tests/check-scripts/broken
expect "check-scripts on the broken fixtures" 1 "check-scripts: 3 files, 2 errors"

echo "core copy ($kind): $n checks, $( [ $fail = 0 ] && echo all pass || echo FAILURES )"
exit $fail
