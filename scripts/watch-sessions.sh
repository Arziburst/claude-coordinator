#!/usr/bin/env bash
# Watch the sessions a report is awaited from, in place of subscribing to their idle notices (#342): run
# as one background command, it polls `claude agents --json --all` and ends - waking its caller once -
# only when a listed session stopped, vanished or went quiet without its report.
#   scripts/watch-sessions.sh --list <file> [--interval <s>] [--quiet-minutes <m>] [--quiet-seconds <s>] [--once]
# The list file: one awaited session per line, its short id (`id` in claude agents --json) or its whole
# name; blank lines and comments ignored - a comment is a line whose first non-blank `#` is followed by a
# blank or the line's end (`#12 worker: Fix` is a name). A line matches a session by the whole id or the
# whole name, never a part of it; a name several sessions have: the one at work, else a quiet one, else
# a stopped one. The file is read again on every poll (it is edited while the watcher runs).
# States: working / busy = at work, nothing printed; stopped / failed / done = STOPPED; any other state
# (idle, blocked, waiting - a permission prompt or a limit) = quiet: QUIET once it stayed quiet for
# --quiet-minutes (default 20; --quiet-seconds in its place, for tests), counted by the watcher from the
# first poll that saw it quiet and started again after a poll that saw it at work.
# Output (stdout): the findings of one poll, one line each, then the end -
#   STOPPED <id> <name> | GONE <id or name as listed> (claude does not list it) | QUIET <id> <name> <minutes>
#   EMPTY: the list file is missing or holds no session (nothing to watch: it does not run)
#   ERROR <first line of claude's stderr>: claude agents failed on two polls in a row (one failure is
#   retried on the next poll; with --once there is no next poll)
# --interval: seconds between polls (default 120). --once: one poll, then the end (tests, a manual check).
# Exit codes: 0 a finding, EMPTY, or --once with nothing found (nothing printed); 1 ERROR; 2 usage error.
# It writes no file and never stops, messages or changes a session (Windows: watch-sessions.ps1, the same
# output and exit codes).
set -u

list="" interval=120 qmin=20 qsec="" once=0
usage="usage: --list <file> [--interval <s>] [--quiet-minutes <m>] [--quiet-seconds <s>] [--once]"
need() { [ $# -ge 2 ] && [ -n "$2" ] || { echo "missing value for $1; $usage" >&2; exit 2; }
         case "$2" in -*) echo "missing value for $1 (got the flag $2); $usage" >&2; exit 2 ;; esac; }
num() { need "$@"; case "$2" in *[!0-9]*) echo "$1 takes a whole number (got $2); $usage" >&2; exit 2 ;; esac; }
while [ $# -gt 0 ]; do
  case "$1" in
    --list) need "$@"; list="$2"; shift 2 ;;
    --interval) num "$@"; interval="$2"; shift 2 ;;
    --quiet-minutes) num "$@"; qmin="$2"; shift 2 ;;
    --quiet-seconds) num "$@"; qsec="$2"; shift 2 ;;
    --once) once=1; shift ;;
    -h|--help) sed -n '2,23s/^# \{0,1\}//p' "$0"; exit 2 ;;
    *) echo "unknown argument: $1; $usage" >&2; exit 2 ;;
  esac
done
[ -n "$list" ] || { echo "$usage" >&2; exit 2; }
limit=$((qmin * 60)); [ -n "$qsec" ] && limit=$qsec
tab="$(printf '\t')" nl='
'

# entries: the list file's sessions, one a line, the blanks around each trimmed
entries() {
  [ -f "$list" ] || return 0
  awk '{ sub(/\r$/, ""); sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "") } $0 == "" || /^#([ \t]|$)/ { next } { print }' "$list"
}
# agents: one call of claude agents --json --all; sets rc, json (its stdout) and err (the first line of its
# stderr), no file written: stderr comes through the pipe, stdout and the exit code through fd 3
agents() {
  local all
  all="$( { { claude agents --json --all 2>&1 1>&3 3>&-; echo "#rc $?" >&3; } | sed 's/^/#err /'; } 3>&1 )"
  rc="$(printf '%s\n' "$all" | sed -n 's/^#rc //p')"
  err="$(printf '%s\n' "$all" | sed -n 's/^#err //p' | sed -n '/./{p;q;}')"
  json="$(printf '%s\n' "$all" | grep -v -e '^#rc ' -e '^#err ')"
  if [ "$rc" = 0 ] && ! printf '%s' "$json" | grep -q '\['; then
    rc=1; err="claude agents --json --all printed no JSON list"
  fi
  [ -n "$err" ] || err="claude agents --json --all exited with $rc"
}
# sessions <json>: `<id> TAB <state> TAB <name>` per session object of the list (string values unescaped)
sessions() {
  printf '%s' "$1" | awk 'BEGIN { RS = "\001" } { s = s $0 } END {
    n = length(s); d = 0; q = 0; after = 0
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1)
      if (q) {
        if (c == "\\") { c = substr(s, ++i, 1)
          if (c == "n" || c == "r" || c == "t" || c == "b" || c == "f") c = " "; else if (c == "u") c = "\\u" }
        else if (c == "\"") { q = 0
          if (d == 2) { if (after) { v[k] = t; after = 0 } else k = t }
          continue }
        t = t c; continue
      }
      if (c == "\"") { q = 1; t = "" }
      else if (c == ":") { if (d == 2) after = 1 }
      else if (c == ",") { if (d == 2) after = 0 }
      else if (c == "{" || c == "[") { if (d == 2) after = 0; d++ }
      else if (c == "}" || c == "]") {
        if (d == 2 && c == "}" && v["id"] != "") print v["id"] "\t" v["state"] "\t" v["name"]
        if (d == 2) delete v
        d--
      }
    } }'
}
# pick <sessions> <entry>: the session the entry names (by the whole id or the whole name), at work first
pick() {
  printf '%s\n' "$1" | E="$2" awk '{ i = index($0, "\t"); id = substr($0, 1, i - 1); r = substr($0, i + 1)
      j = index(r, "\t"); st = substr(r, 1, j - 1); nm = substr(r, j + 1)
      if (id != ENVIRON["E"] && nm != ENVIRON["E"]) next
      p = (st == "working" || st == "busy") ? 3 : (st == "stopped" || st == "failed" || st == "done") ? 1 : 2
      if (p > best) { best = p; line = $0 } }
    END { if (best) print line }'
}
# since <entry>: when the watcher first saw it quiet (empty: not quiet on the last poll)
since() { printf '%s' "$timers" | E="$1" awk '{ i = index($0, "\t"); if (substr($0, i + 1) == ENVIRON["E"]) { print substr($0, 1, i - 1); exit } }'; }

fails=0 timers=""
while :; do
  ents="$(entries)"
  [ -n "$ents" ] || { echo EMPTY; exit 0; }
  agents
  if [ "$rc" != 0 ]; then
    fails=$((fails + 1))
    if [ "$fails" -ge 2 ] || [ "$once" = 1 ]; then echo "ERROR $err"; exit 1; fi
    sleep "$interval"; continue
  fi
  fails=0
  sess="$(sessions "$json")"
  now=$SECONDS found="" quiet=""
  while IFS= read -r e; do
    m="$(pick "$sess" "$e")"
    if [ -z "$m" ]; then found="${found}GONE $e$nl"; continue; fi
    id="${m%%$tab*}"; r="${m#*$tab}"; st="${r%%$tab*}"; nm="${r#*$tab}"
    case "$st" in
      working|busy) ;;
      stopped|failed|done) found="${found}STOPPED $id $nm$nl" ;;
      *) t0="$(since "$e")"; [ -n "$t0" ] || t0=$now
         quiet="$quiet$t0$tab$e$nl"
         [ $((now - t0)) -ge "$limit" ] && found="${found}QUIET $id $nm $(((now - t0) / 60))$nl" ;;
    esac
  done <<EOF
$ents
EOF
  timers="$quiet"
  [ -n "$found" ] && { printf '%s' "$found"; exit 0; }
  [ "$once" = 1 ] && exit 0
  sleep "$interval"
done
