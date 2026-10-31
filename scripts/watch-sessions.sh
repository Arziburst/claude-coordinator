#!/usr/bin/env bash
# Watch the sessions a report is awaited from, in place of subscribing to their idle notices (#342): run
# as one background command, it polls `claude agents --json --all` and ends - waking its caller once -
# only when a listed session stopped, vanished or went quiet without its report.
#   scripts/watch-sessions.sh --list <file> [--interval <s>] [--quiet-minutes <m>] [--quiet-seconds <s>]
#                             [--agents-timeout <s>] [--once]
# The list file: one awaited session per line, its short id (`id` in claude agents --json) or its whole
# name; blank lines and comments ignored - a comment is a line whose first non-blank `#` is followed by a
# blank or the line's end (`#12 worker: Fix` is a name); a UTF-8 BOM at its start is not part of the
# first line. A line may end with its own quiet limit, ` @<n>` minutes (` @<n>s`: seconds), in place of
# the global one (e.g. a lead waiting for its workers: `<id> @120`); the entry is the line without that
# end (a name may hold blanks). An entry matches a session by the whole id or the whole name, never a
# part of it; a name several sessions have: the one at work, else a quiet one, else a stopped one. The
# file is read again on every poll (it is edited while the watcher runs).
# States, as measured: the listing gives `state`, and `status` (busy / idle) only while the session's
# process lives - a live session between turns is `done` + `idle`, an exited one `done` with no status.
# State working or status busy = at work, nothing printed; state stopped / failed (any status), or done
# with no status = STOPPED; done + idle and any other state (idle, blocked, waiting - a permission
# prompt or a limit), with or without a status = quiet: QUIET once it stayed quiet for its limit
# (--quiet-minutes, default 20; --quiet-seconds in its place, for tests; or the line's own), counted by
# the watcher from the first poll that saw it quiet and started again after a poll that saw it at work.
# Output (stdout): the findings of one poll, one line each, then the end -
#   STOPPED <id> <name> | GONE <entry> (claude does not list it) | QUIET <id> <name> <minutes>
#   EMPTY: the list file is missing or holds no session (nothing to watch: it does not run)
#   ERROR <first line of claude's stderr, or the timeout>: claude agents failed on two polls in a row
#   (one failure is retried on the next poll; with --once there is no next poll)
# --interval: seconds between polls (default 120). --agents-timeout: seconds one claude agents call may
# take (default 60); past it the one claude process the watcher started is killed - nothing under it,
# nothing else - and the poll failed. --once: one poll, then the end (tests, a manual check).
# Exit codes: 0 a finding, EMPTY, or --once with nothing found (nothing printed); 1 ERROR; 2 usage error.
# The only file it touches: one temp folder per call (mktemp -d) holding claude's stdout and stderr - read
# from files, not a pipe, so a process left under a killed claude cannot hang the watcher - removed as
# soon as it is read and on every way out. It never stops, messages or changes a session (Windows:
# watch-sessions.ps1, the same output and exit codes).
set -u

list="" interval=120 qmin=20 qsec="" atimeout=60 once=0
usage="usage: --list <file> [--interval <s>] [--quiet-minutes <m>] [--quiet-seconds <s>] [--agents-timeout <s>] [--once]"
need() { [ $# -ge 2 ] && [ -n "$2" ] || { echo "missing value for $1; $usage" >&2; exit 2; }
         case "$2" in -*) echo "missing value for $1 (got the flag $2); $usage" >&2; exit 2 ;; esac; }
num() { need "$@"; case "$2" in *[!0-9]*) echo "$1 takes a whole number (got $2); $usage" >&2; exit 2 ;; esac; }
while [ $# -gt 0 ]; do
  case "$1" in
    --list) need "$@"; list="$2"; shift 2 ;;
    --interval) num "$@"; interval="$2"; shift 2 ;;
    --quiet-minutes) num "$@"; qmin="$2"; shift 2 ;;
    --quiet-seconds) num "$@"; qsec="$2"; shift 2 ;;
    --agents-timeout) num "$@"; atimeout="$2"; shift 2 ;;
    --once) once=1; shift ;;
    -h|--help) sed -n '2,34s/^# \{0,1\}//p' "$0"; exit 2 ;;
    *) echo "unknown argument: $1; $usage" >&2; exit 2 ;;
  esac
done
[ -n "$list" ] || { echo "$usage" >&2; exit 2; }
[ "$atimeout" -gt 0 ] || { echo "--agents-timeout must be above 0; $usage" >&2; exit 2; }
limit=$((qmin * 60)); [ -n "$qsec" ] && limit=$qsec
tab="$(printf '\t')" nl='
'

# entries: the list file's sessions, one a line as `<own limit in seconds, or empty> TAB <entry>`, the
# blanks around each trimmed (bytes as they are: C locale, so a BOM is three bytes)
entries() {
  [ -f "$list" ] || return 0
  LC_ALL=C awk 'NR == 1 && substr($0, 1, 3) == "\357\273\277" { $0 = substr($0, 4) }
    { sub(/\r$/, ""); sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "") }
    $0 == "" || /^#([ \t]|$)/ { next }
    { l = ""
      if (match($0, /[ \t]+@[0-9]+s?$/)) {
        t = substr($0, RSTART); $0 = substr($0, 1, RSTART - 1); sub(/^[ \t]+@/, "", t)
        if (t ~ /s$/) l = substr(t, 1, length(t) - 1) + 0; else l = t * 60 }
      print l "\t" $0 }' "$list"
}
# The one place the watcher writes: a fresh temp folder per call, for claude's stdout and stderr (a pipe
# would stay open while anything under a killed claude still holds it, and the watcher would hang on it);
# read once the call ends or is killed, and removed at once - on every way out too (the trap)
tdir=""
cleanup() { [ -n "$tdir" ] || return 0; rm -f "$tdir/out" "$tdir/err"; rmdir "$tdir" 2>/dev/null; tdir=""; }
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
# agents: one poll; sets rc, json (claude's stdout) and err (the first line of its stderr, or the
# timeout). Past --agents-timeout only the claude process the watcher started ($!) is killed - nothing
# under it, nothing looked up by name or id.
agents() {
  local p t=0 timed=0
  json="" err="" rc=0
  tdir="$(mktemp -d "${TMPDIR:-/tmp}/watch-sessions.XXXXXX")" || { rc=1; err="no temp folder for claude's output"; return; }
  claude agents --json --all > "$tdir/out" 2> "$tdir/err" < /dev/null &
  p=$!
  while kill -0 "$p" 2>/dev/null; do
    if [ "$t" -ge $((atimeout * 10)) ]; then kill -9 "$p" 2>/dev/null; timed=1; break; fi
    sleep 0.1; t=$((t + 1))
  done
  wait "$p"; rc=$?
  json="$(cat "$tdir/out" 2>/dev/null)"
  err="$(sed -n '/./{p;q;}' "$tdir/err" 2>/dev/null)"
  cleanup
  if [ "$timed" = 1 ]; then
    rc=124; err="claude agents --json --all did not answer in $atimeout s"
  elif [ "$rc" = 0 ] && ! printf '%s' "$json" | grep -q '\['; then
    rc=1; err="claude agents --json --all printed no JSON list"
  fi
  [ -n "$err" ] || err="claude agents --json --all exited with $rc"
}
# sessions <json>: `<id> TAB <work|stop|quiet> TAB <name>` per session object of the list (string values
# unescaped; the class from state and status, as the header says)
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
        if (d == 2 && c == "}" && v["id"] != "") {
          st = v["state"]; su = v["status"]
          if (st == "working" || su == "busy") cl = "work"
          else if (st == "stopped" || st == "failed" || (st == "done" && su == "")) cl = "stop"
          else cl = "quiet"
          print v["id"] "\t" cl "\t" v["name"]
        }
        if (d == 2) delete v
        d--
      }
    } }'
}
# pick <sessions> <entry>: the session the entry names (by the whole id or the whole name), at work first
pick() {
  printf '%s\n' "$1" | E="$2" awk '{ i = index($0, "\t"); id = substr($0, 1, i - 1); r = substr($0, i + 1)
      j = index(r, "\t"); cl = substr(r, 1, j - 1); nm = substr(r, j + 1)
      if (id != ENVIRON["E"] && nm != ENVIRON["E"]) next
      p = (cl == "work") ? 3 : (cl == "stop") ? 1 : 2
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
  while IFS= read -r x; do
    lim="${x%%$tab*}"; e="${x#*$tab}"; [ -n "$lim" ] || lim=$limit
    m="$(pick "$sess" "$e")"
    if [ -z "$m" ]; then found="${found}GONE $e$nl"; continue; fi
    id="${m%%$tab*}"; r="${m#*$tab}"; cl="${r%%$tab*}"; nm="${r#*$tab}"
    case "$cl" in
      work) ;;
      stop) found="${found}STOPPED $id $nm$nl" ;;
      *) t0="$(since "$e")"; [ -n "$t0" ] || t0=$now
         quiet="$quiet$t0$tab$e$nl"
         [ $((now - t0)) -ge "$lim" ] && found="${found}QUIET $id $nm $(((now - t0) / 60))$nl" ;;
    esac
  done <<EOF
$ents
EOF
  timers="$quiet"
  [ -n "$found" ] && { printf '%s' "$found"; exit 0; }
  [ "$once" = 1 ] && exit 0
  sleep "$interval"
done
