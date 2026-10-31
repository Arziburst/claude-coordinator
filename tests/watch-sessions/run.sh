#!/usr/bin/env bash
# Checks of watch-sessions against a stub `claude` on PATH (the real claude is never called): the stub
# answers `agents --json --all` from a scripted sequence and logs every call.
#   tests/watch-sessions/run.sh sh                 # watch-sessions.sh, with the bash running this file
#   tests/watch-sessions/run.sh ps pwsh            # watch-sessions.ps1 (or: ps powershell)
# Exit 1 if any check fails.
#
# Access points the script implements as written here (#342):
#   watch-sessions.sh  --list <file> [--interval <s>] [--quiet-minutes <m>] [--quiet-seconds <s>] [--once]
#   watch-sessions.ps1 -List <file>  [-Interval <s>]  [-QuietMinutes <m>]  [-QuietSeconds <s>]  [-Once]
#   --quiet-seconds: the quiet limit in seconds, in place of --quiet-minutes (for tests: minutes are too
#   coarse); the QUIET line's <minutes> are then the whole minutes idle (0 here).
#   Output lines (stdout, one per finding): `STOPPED <id> <name>`, `GONE <id or name as listed>`,
#   `QUIET <id> <name> <minutes>`, `EMPTY`, `ERROR <first line of claude's failure>`.
#   Exit codes: 0 for a finding, EMPTY, or --once with nothing found (nothing printed); 1 for ERROR.
#   States: working / busy = at work; idle = quiet (measured from the first poll that saw it idle);
#   stopped / failed / done = STOPPED.
#   The list file: a comment is a line whose first non-blank `#` is followed by a blank or the line's
#   end (`# text`, `#`); `#12 worker: Fix` is a session name (start-worker names begin with `#<n>`).
#   A line matches a session by the whole short id or the whole name, never a part of it.
set -u
[ $# -gt 0 ] || { sed -n '2,6s/^# \{0,1\}//p' "$0"; exit 2; }
kind="$1"; shift
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
bin="$tmp/bin"   # PATH takes this form; the paths handed to the script take the Windows form below
command -v cygpath >/dev/null 2>&1 && { core="$(cygpath -m "$core")"; tmp="$(cygpath -m "$tmp")"; }

# The stub's state folder $STUB_D:
#   list-<n>    the sessions call <n> lists, `<id> <state> <name...>` per line (an empty file: none);
#               past the last list-<n> the last one repeats
#   fail-<n>    call <n> fails (exit 1) with this text on stderr
#   after-<n>   a shell script run after call <n> answered (the coordinator editing the list between
#               two polls)
#   log         every call's arguments, one call a line;  n  the number of calls so far
mkdir -p "$bin"
cat > "$bin/claude" <<'EOF'
#!/usr/bin/env bash
D="$STUB_D"
printf '%s\n' "$*" >> "$D/log"
k=$(cat "$D/n" 2>/dev/null || echo 0); k=$((k + 1)); echo $k > "$D/n"
[ -f "$D/after-$k" ] && trap 'sh "$D/after-$k"' EXIT
[ -f "$D/fail-$k" ] && { cat "$D/fail-$k" >&2; exit 1; }
f="$D/list-$k"
if [ ! -f "$f" ]; then f=""; for x in "$D"/list-*; do [ -f "$x" ] || continue
  i="${x##*-}"; [ "$i" -lt "$k" ] && { [ -z "$f" ] || [ "$i" -gt "${f##*-}" ]; } && f="$x"; done; fi
[ -n "$f" ] || { echo "[]"; exit 0; }
awk '{ n = $0; sub(/^[^ ]+ [^ ]+ /, "", n); gsub(/\\/, "\\\\", n); gsub(/"/, "\\\"", n)
  printf "%s{\n    \"id\": \"%s\",\n    \"sessionId\": \"5e550000-0000-4000-8000-%012d\",\n    \"name\": \"%s\",\n    \"state\": \"%s\"\n  }", (m++ ? ",\n  " : "[\n  "), $1, NR, n, $2 }
  END { print (m ? "\n]" : "[]") }' "$f"
exit 0
EOF
# PowerShell finds claude.ps1 first on Windows; it hands the arguments to the bash stub as a native
# process, as claude.exe gets them
cat > "$bin/claude.ps1" <<'EOF'
& bash (Join-Path $PSScriptRoot 'claude') @args
exit $LASTEXITCODE
EOF
chmod +x "$bin/claude"
export PATH="$bin:$PATH"
[ "$(command -v claude)" = "$bin/claude" ] || { echo "FAIL: the stub claude is not first on PATH ($(command -v claude))"; exit 1; }

case "$kind" in
  sh) ws() { bash "$core/scripts/watch-sessions.sh" "$@"; } ;;
  ps) ps="${1:-pwsh}"
      # the .sh's flags as the .ps1's parameters
      ws() { local a=()
        while [ $# -gt 0 ]; do
          case "$1" in
            --list) a+=(-List "$2"); shift 2 ;; --interval) a+=(-Interval "$2"); shift 2 ;;
            --quiet-minutes) a+=(-QuietMinutes "$2"); shift 2 ;; --quiet-seconds) a+=(-QuietSeconds "$2"); shift 2 ;;
            --once) a+=(-Once); shift ;; *) a+=("$1"); shift ;;
          esac
        done
        "$ps" -NoProfile -ExecutionPolicy Bypass -File "$core/scripts/watch-sessions.ps1" "${a[@]}"; } ;;
  *) echo "unknown kind: $kind" >&2; exit 2 ;;
esac

pass=0 fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL [$name] $*"; printf '%s\n' "$out" | sed 's/^/    | /'; }
# fresh <name>: a new state folder and an empty working folder; the list file is $L (not created)
fresh() { name="$1"; export STUB_D="$tmp/s$((pass + fail))-$RANDOM"; mkdir -p "$STUB_D" "$STUB_D.cwd"
  : > "$STUB_D/log"; L="$STUB_D.cwd/watch.txt"; }
# run <args>: the watcher's output and exit code, run from the working folder, killed after 60 s (exit 124)
run() { ( cd "$STUB_D.cwd" && ws "$@" ) > "$STUB_D.out" 2>&1 & local p=$! t=0
  while kill -0 $p 2>/dev/null && [ $t -lt 600 ]; do sleep 0.1; t=$((t + 1)); done
  if kill -0 $p 2>/dev/null; then kill $p 2>/dev/null; wait $p 2>/dev/null; rc=124; else wait $p; rc=$?; fi
  out="$(tr -d '\r' < "$STUB_D.out")"; rm -f "$STUB_D.out"; }
has() { printf '%s\n' "$out" | grep -qE -- "$1" && ok || bad "expected a line matching: $1"; }
hasnt() { printf '%s\n' "$out" | grep -qE -- "$1" && bad "unexpected: $1" || ok; }
silent() { [ -z "$out" ] && ok || bad "expected no output"; }
code() { [ "$rc" = "$1" ] && ok || bad "expected exit $1, got $rc"; }
calls() { local c; c=$(cat "$STUB_D/n" 2>/dev/null || echo 0); [ "$c" "$1" "$2" ] && ok || bad "claude called $c times, expected $1 $2"; }
A=a1b2c3d4 B=b2c3d4e5 C=c3d4e5f6

fresh "all working, --once: nothing printed, exit 0"
printf '%s\n%s\n' $A $B > "$L"; printf '%s working w-a\n%s busy w-b\n' $A $B > "$STUB_D/list-1"
run --list "$L" --once
code 0; silent; calls -eq 1

for st in stopped done failed; do
  fresh "a listed session $st: STOPPED with its id and name"
  printf '%s\n%s\n' $A $B > "$L"; printf '%s working w-a\n%s %s #12 worker: Fix\n' $A $B $st > "$STUB_D/list-1"
  run --list "$L" --interval 1
  code 0; has "^STOPPED $B #12 worker: Fix\$"; hasnt "^STOPPED $A"
done

fresh "stopped on the second poll: nothing on the first, STOPPED after it"
echo $A > "$L"; echo "$A working w-a" > "$STUB_D/list-1"; echo "$A done w-a" > "$STUB_D/list-2"
run --list "$L" --interval 1
code 0; has "^STOPPED $A w-a\$"; calls -eq 2

fresh "a listed session claude does not list: GONE"
printf '%s\n%s\n' $A $C > "$L"; echo "$A working w-a" > "$STUB_D/list-1"
run --list "$L" --interval 1
code 0; has "^GONE $C\$"; hasnt "^(STOPPED|GONE|QUIET) $A"

fresh "a listed name claude does not list: GONE with the name as listed"
printf '%s\n' "#13 worker: Gone away" > "$L"; echo "$A working w-a" > "$STUB_D/list-1"
run --list "$L" --interval 1
code 0; has "^GONE #13 worker: Gone away\$"

fresh "idle past the limit: QUIET with its id, name and minutes"
echo $A > "$L"; echo "$A idle w-a" > "$STUB_D/list-1"
run --list "$L" --interval 1 --quiet-seconds 2
code 0; has "^QUIET $A w-a [0-9]+\$"; calls -ge 2

fresh "the quiet time counts from the first poll that saw it idle, not from the watcher's start"
echo $A > "$L"; echo "$A working w-a" > "$STUB_D/list-1"; echo "$A idle w-a" > "$STUB_D/list-3"
run --list "$L" --interval 1 --quiet-seconds 2
code 0; has "^QUIET $A w-a [0-9]+\$"; calls -ge 4

fresh "idle under the limit, --once: nothing"
echo $A > "$L"; echo "$A idle w-a" > "$STUB_D/list-1"
run --list "$L" --once --quiet-seconds 600
code 0; silent

fresh "idle under the default limit (20 minutes), --once: nothing"
echo $A > "$L"; echo "$A idle w-a" > "$STUB_D/list-1"
run --list "$L" --once
code 0; silent

fresh "idle, working, idle again: the quiet time starts again, no QUIET under the limit"
printf '%s\n%s\n' $A $B > "$L"; printf '%s idle w-a\n%s working w-b\n' $A $B > "$STUB_D/list-1"
printf '%s working w-a\n%s working w-b\n' $A $B > "$STUB_D/list-2"; printf '%s idle w-a\n%s working w-b\n' $A $B > "$STUB_D/list-3"
printf '%s idle w-a\n%s done w-b\n' $A $B > "$STUB_D/list-4"
run --list "$L" --interval 1 --quiet-seconds 3
code 0; has "^STOPPED $B w-b\$"; hasnt "^QUIET"; calls -eq 4

fresh "the list file missing: EMPTY, claude not called"
run --list "$L" --interval 1
code 0; has "^EMPTY\$"; calls -eq 0

fresh "the list file empty: EMPTY"
: > "$L"; run --list "$L" --interval 1
code 0; has "^EMPTY\$"

fresh "the list file only comments and blank lines: EMPTY"
printf '# awaited reports\n\n   \n# %s\n#\n  #\tindented\n' $A > "$L"; echo "$A done w-a" > "$STUB_D/list-1"
run --list "$L" --interval 1
code 0; has "^EMPTY\$"; hasnt "^STOPPED"

fresh "comments and blank lines around sessions are ignored; a name with spaces matches the full name"
printf '# awaited\n\n#12 worker: Fix the thing\n  \n%s\n' $B > "$L"
printf '%s working #12 worker: Fix the thing\n%s working w-b\n' $A $B > "$STUB_D/list-1"
printf '%s done #12 worker: Fix the thing\n%s working w-b\n' $A $B > "$STUB_D/list-2"
run --list "$L" --interval 1
code 0; has "^STOPPED $A #12 worker: Fix the thing\$"; hasnt "GONE"; hasnt "^STOPPED $B"

fresh "a name that is only a prefix of a listed name is not that session: GONE"
printf '#12 worker\n' > "$L"; printf '%s working #12 worker: Fix the thing\n' $A > "$STUB_D/list-1"
run --list "$L" --interval 1
code 0; has "^GONE #12 worker\$"

fresh "the list read again on every poll: a session removed after its report gets no finding"
printf '%s\n%s\n' $A $B > "$L"; printf '%s working w-a\n%s working w-b\n' $A $B > "$STUB_D/list-1"
printf 'grep -v "^%s$" "%s" > "%s.x"; cat "%s.x" > "%s"; rm -f "%s.x"\n' $A "$L" "$STUB_D" "$STUB_D" "$L" "$STUB_D" > "$STUB_D/after-1"
printf '%s done w-a\n%s done w-b\n' $A $B > "$STUB_D/list-2"
run --list "$L" --interval 1
code 0; has "^STOPPED $B w-b\$"; hasnt "^STOPPED $A"

fresh "the list read again on every poll: a session added meanwhile is watched"
echo $A > "$L"; echo "$A working w-a" > "$STUB_D/list-1"
printf 'echo %s >> "%s"\n' $C "$L" > "$STUB_D/after-1"
echo "$A working w-a" > "$STUB_D/list-2"
run --list "$L" --interval 1
code 0; has "^GONE $C\$"; hasnt "^(STOPPED|GONE|QUIET) $A"

fresh "the list emptied while watching: EMPTY"
echo $A > "$L"; echo "$A working w-a" > "$STUB_D/list-1"
printf ': > "%s"\n' "$L" > "$STUB_D/after-1"
run --list "$L" --interval 1
code 0; has "^EMPTY\$"; hasnt "^STOPPED"

fresh "several findings at once: one line each, exit 0"
printf '%s\n%s\n%s\n' $A $B $C > "$L"; printf '%s done w-a\n%s failed w-b\n' $A $B > "$STUB_D/list-1"
run --list "$L" --interval 1
code 0; has "^STOPPED $A w-a\$"; has "^STOPPED $B w-b\$"; has "^GONE $C\$"

fresh "claude agents failing once, then working: no ERROR, the next finding"
echo $A > "$L"; echo "connection reset" > "$STUB_D/fail-1"; echo "$A done w-a" > "$STUB_D/list-2"
run --list "$L" --interval 1
code 0; hasnt "^ERROR"; has "^STOPPED $A w-a\$"; calls -eq 2

fresh "claude agents failing twice in a row: ERROR with the first line, exit 1"
echo $A > "$L"; printf 'agents: backend unavailable\nsecond line\n' > "$STUB_D/fail-1"; cp "$STUB_D/fail-1" "$STUB_D/fail-2"
echo "$A done w-a" > "$STUB_D/list-3"
run --list "$L" --interval 1
code 1; has "^ERROR .*backend unavailable"; hasnt "second line"; hasnt "^STOPPED"; calls -eq 2

fresh "failures that are not in a row: no ERROR"
echo $A > "$L"; echo "x" > "$STUB_D/fail-1"; echo "$A working w-a" > "$STUB_D/list-2"; echo "x" > "$STUB_D/fail-3"
echo "$A done w-a" > "$STUB_D/list-4"
run --list "$L" --interval 1
code 0; hasnt "^ERROR"; has "^STOPPED $A w-a\$"

fresh "the watcher writes nothing and calls nothing but claude agents --json --all"
printf '# keep\n%s\n%s\n' $A $B > "$L"; cp "$L" "$STUB_D/list.orig"
printf '%s working w-a\n%s idle w-b\n' $A $B > "$STUB_D/list-1"; printf '%s working w-a\n%s working w-b\n' $A $B > "$STUB_D/list-2"
printf '%s done w-a\n%s working w-b\n' $A $B > "$STUB_D/list-3"
before="$(ls -A "$STUB_D.cwd")"
run --list "$L" --interval 1 --quiet-seconds 600
code 0; has "^STOPPED $A w-a\$"
cmp -s "$L" "$STUB_D/list.orig" && ok || bad "the list file changed"
[ "$(ls -A "$STUB_D.cwd")" = "$before" ] && ok || bad "new files in the working folder: $(ls -A "$STUB_D.cwd" | tr '\n' ' ')"
calls -eq 3
others="$(grep -v -- '^agents ' "$STUB_D/log")"
[ -z "$others" ] && ok || bad "claude called with: $others"
grep -- '^agents ' "$STUB_D/log" | grep -v -- '--json' >/dev/null && bad "a call without --json" || ok
grep -- '^agents ' "$STUB_D/log" | grep -v -- '--all' >/dev/null && bad "a call without --all" || ok

fresh "the interval is kept: three polls take at least two seconds"
echo $A > "$L"; echo "$A working w-a" > "$STUB_D/list-1"; echo "$A done w-a" > "$STUB_D/list-3"
t0=$(date +%s); run --list "$L" --interval 1; t1=$(date +%s)
code 0; has "^STOPPED $A w-a\$"; calls -eq 3; [ $((t1 - t0)) -ge 2 ] && ok || bad "3 polls in $((t1 - t0)) s"

echo "watch-sessions ($kind${1:+ $1}): $pass passed, $fail failed"
[ "$fail" -eq 0 ]
