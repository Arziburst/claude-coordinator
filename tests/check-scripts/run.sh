#!/usr/bin/env bash
# check-scripts on temporary folders, the same verdict from both versions:
#   - a folder named `c&d [x]` with Foo.SH, Baz.PS1 (extensions in capitals count) and a broken bad.sh:
#     every file counted, the error under the folder's own name;
#   - a .ps1 using `??` without `#Requires -Version 7`: an error wherever Windows PowerShell 5.1 exists
#     (its rules, also when check-scripts.ps1 runs under pwsh), a pass where only pwsh does;
#   - (the .ps1 only) a `bash` first on PATH that checks nothing, as the WSL launcher: on Windows the bash
#     next to git is used instead; where none is found, the .sh files are listed as skipped and counted
#     as an error, never dropped from the count.
#   tests/check-scripts/run.sh sh                  # check-scripts.sh, with the bash running this file
#   tests/check-scripts/run.sh ps pwsh             # check-scripts.ps1 (or: ps powershell)
# Exit 1 if any check fails.
set -u
[ $# -gt 0 ] || { sed -n '2,12s/^# \{0,1\}//p' "$0"; exit 2; }
kind="$1"; shift; PS=("$@")
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -r "$tmp"' EXIT
win=""; command -v cygpath >/dev/null 2>&1 && { win=1; core="$(cygpath -m "$core")"; }

run() {   # run <folder>: check-scripts of this kind from $tmp, its output in $LAST, its exit code in $RC;
  # with $RUNPATH set (one folder, no spaces), the PowerShell runs with that PATH and with Program Files
  # elsewhere (set inside it: Windows hands a process its own ProgramFiles whatever the parent passes)
  if [ "$kind" = ps ] && [ -n "${RUNPATH:-}" ]; then
    (cd "$tmp" && PATH="$RUNPATH" "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -Command \
      "\$env:ProgramFiles = 'C:\\nowhere'; & '$core/scripts/check-scripts.ps1' $1; exit \$LASTEXITCODE") > "$tmp/out" 2>&1
  elif [ "$kind" = ps ]; then (cd "$tmp" && "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$core/scripts/check-scripts.ps1" "$@") > "$tmp/out" 2>&1
  else (cd "$tmp" && bash "$core/scripts/check-scripts.sh" "$@") > "$tmp/out" 2>&1; fi
  RC=$?; LAST="$(tr -d '\r' < "$tmp/out")"
}
fail=0; n=0
expect() {   # expect <case> <exit code> <line>: the exit code, and the line exactly (or, ending in *, as a prefix)
  n=$((n + 1))
  { [ "$RC" = "$2" ] && printf '%s\n' "$LAST" | P="$3" awk 'BEGIN { p = ENVIRON["P"]; s = (substr(p, length(p)) == "*") }
      (s && index($0, substr(p, 1, length(p) - 1)) == 1) || (!s && $0 == p) { f = 1 } END { exit !f }'; } ||
    { echo "FAIL ($1): expected exit $2 and the line '$3', got exit $RC:"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }
}
# the PowerShell the .sh hands the .ps1 files to (5.1 first), or this kind's own
ps1by=""
if [ "$kind" = ps ]; then ps1by=ps; command -v powershell >/dev/null 2>&1 && ps1by=powershell
elif command -v powershell >/dev/null 2>&1; then ps1by=powershell; elif command -v pwsh >/dev/null 2>&1; then ps1by=ps; fi

d="c&d [x]"; mkdir -p "$tmp/$d/sub"
printf 'echo ok\n' > "$tmp/$d/Foo.SH"
printf 'if then\n' > "$tmp/$d/sub/bad.sh"
printf '$x = 1\n' > "$tmp/$d/Baz.PS1"
run "$d"
expect "a broken .sh under a folder named c&d [x]" 1 "$d/sub/bad.sh:1: *"
if [ -n "$ps1by" ]; then expect "every file, extensions in capitals too" 1 "check-scripts: 3 files, 1 errors"
else expect "every file, extensions in capitals too" 1 "check-scripts: 2 files, 1 errors"; fi

mkdir -p "$tmp/p51"; printf '$a = $null ?? 1\n$a\n' > "$tmp/p51/coalesce.ps1"
run p51
case "$ps1by" in
  powershell) expect "?? under Windows PowerShell 5.1's rules" 1 "check-scripts: 1 files, 1 errors" ;;
  ps) expect "?? where only pwsh exists" 0 "check-scripts: 1 files, 0 errors" ;;
  *) expect "?? with no PowerShell" 0 "check-scripts: 0 files, 0 errors" ;;
esac

if [ "$kind" = ps ]; then
  mkdir -p "$tmp/two" "$tmp/fake"
  printf 'echo ok\n' > "$tmp/two/ok.sh"; printf '$x = 1\n' > "$tmp/two/ok.ps1"
  if [ -n "$win" ]; then printf '@exit /b 0\r\n' > "$tmp/fake/bash.cmd"
  else printf '#!/bin/sh\nexit 0\n' > "$tmp/fake/bash"; chmod +x "$tmp/fake/bash"; fi
  RUNPATH="$tmp/fake:$PATH" run two
  if [ -n "$win" ]; then expect "a bash on PATH that checks nothing; git's own bash is used" 0 "check-scripts: 2 files, 0 errors"
  else
    expect "a bash on PATH that checks nothing" 1 "skipped 1 .sh files: bash did not run (*"
    expect "a bash on PATH that checks nothing" 1 "check-scripts: 1 files, 1 errors"
  fi
  if [ -n "$win" ]; then
    # no git on PATH either: nothing but the fake bash and the PowerShell itself
    RUNPATH="$tmp/fake:$(dirname "$(command -v "${PS[0]}")")" run two
    expect "no git and a bash that checks nothing" 1 "skipped 1 .sh files: bash did not run (*"
    expect "no git and a bash that checks nothing" 1 "check-scripts: 1 files, 1 errors"
  fi
fi

echo "check-scripts ($kind): $n checks, $( [ $fail = 0 ] && echo all pass || echo FAILURES )"
exit $fail
