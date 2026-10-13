#!/usr/bin/env bash
# Syntax check of every script under the given folders (macOS / Linux, no dependencies; Windows:
# check-scripts.ps1). Catches a script that no longer parses before anything runs it.
#   scripts/check-scripts.sh [folder ...]      default: this core's own scripts/
# .sh files: `bash -n`. .ps1 files: PowerShell's own parser, through check-scripts.ps1 - under
# `powershell` (Windows PowerShell 5.1's rules) where it exists, else `pwsh`; without either they are
# listed as skipped, not passed. A file marked `#Requires -Version 7` is parsed by `pwsh`.
# Prints `<file>:<line>: <message>` per error, then `check-scripts: <n> files, <e> errors`.
# Exit 1 on any error, 2 on a usage error.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
only=""
if [ "${1:-}" = "--only-sh" ]; then only=sh; shift; fi   # used by check-scripts.ps1
case "${1:-}" in -h|--help) sed -n '2,10s/^# \{0,1\}//p' "$0"; exit 2 ;; esac
[ $# -gt 0 ] || set -- "$here"
for d in "$@"; do [ -d "$d" ] || { echo "not a folder: $d" >&2; exit 2; }; done

n=0; e=0
# every file as <folder>/<path below it>, sorted the same way on every system. The core's deliberately
# broken fixtures (tests/check-scripts/broken/) are left out unless the folder given is that folder or
# inside it: a whole core copy passes, and their own check still sees them fail.
list() { for d in "$@"; do d="${d%/}"; find "$d" -type f -name "*.$ext" | sed "s|^$d/||" | LC_ALL=C sort |
  A="$(cd "$d" && pwd)/" awk 'BEGIN { a = ENVIRON["A"]; p = "/tests/check-scripts/broken/" } index(a, p) || !index(a $0, p)' |
  sed "s|^|$d/|"; done; }

ext=sh
while IFS= read -r f; do
  [ -n "$f" ] || continue
  n=$((n + 1))
  out="$(bash -n "$f" 2>&1)" && continue
  e=$((e + 1))
  # "file: line 3: message" -> "file:3: message"
  printf '%s\n' "$out" | sed "s|^.*: line \([0-9][0-9]*\): |$f:\1: |"
done <<LIST
$(list "$@")
LIST

if [ "$only" = sh ]; then echo "#count $n $e"; exit 0; fi

ext=ps1
ps="$(list "$@")"
if [ -n "$ps" ]; then
  # Windows PowerShell 5.1 first, as check-scripts.ps1 is run on Windows: the same machine, the same verdict
  shell=""
  if command -v powershell >/dev/null 2>&1; then shell=powershell; elif command -v pwsh >/dev/null 2>&1; then shell=pwsh; fi
  if [ -z "$shell" ]; then
    echo "skipped $(printf '%s\n' "$ps" | grep -c .) .ps1 files: no PowerShell on this machine"
  else
    res="$("$shell" -NoProfile -ExecutionPolicy Bypass -File "$here/check-scripts.ps1" -OnlyPs1 "$@" | tr -d '\r')"
    printf '%s\n' "$res" | grep -v '^#count ' || true
    c="$(printf '%s\n' "$res" | sed -n 's/^#count //p')"
    n=$((n + ${c%% *})); e=$((e + ${c##* }))
  fi
fi
echo "check-scripts: $n files, $e errors"
[ "$e" -eq 0 ]
