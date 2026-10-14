#!/usr/bin/env bash
# The session-tokens cases: the fixtures against their expected lines (the time line included, a
# stopped session's cost-state record), the error cases and their exit codes, --prune on status files
# and status-line temp files with set ages, a missing projects folder, a config path with [ ] in it.
#   tests/session-tokens/run.sh sh              # scripts/session-tokens.sh, with the bash running this file
#   tests/session-tokens/run.sh ps pwsh         # scripts/session-tokens.ps1 (or: ps powershell)
# Exit 1 if any case fails.
set -u
[ $# -gt 0 ] || { sed -n '2,7s/^# \{0,1\}//p' "$0"; exit 2; }
kind="$1"; shift
[ "$kind" = sh ] || [ "$kind" = ps ] || { sed -n '2,7s/^# \{0,1\}//p' "$0"; exit 2; }
PS=("$@")
[ "$kind" = sh ] || [ ${#PS[@]} -gt 0 ] || { echo "ps needs the PowerShell command" >&2; exit 2; }
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -r "$tmp"' EXIT
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }   # Git Bash -> C:/...

# runs the script under test with CLAUDE_CONFIG_DIR=$1; stdout to $tmp/out, stderr to $tmp/err, \r removed
run() {
  local cfg; cfg="$(winpath "$1")"; shift
  if [ "$kind" = ps ]; then
    local a=()
    for x in "$@"; do case "$x" in --since) a+=(-Since) ;; --prune) a+=(-Prune) ;; *) a+=("$x") ;; esac; done
    CLAUDE_CONFIG_DIR="$cfg" "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$(winpath "$core/scripts/session-tokens.ps1")" "${a[@]}" > "$tmp/out.raw" 2> "$tmp/err.raw"
  else
    CLAUDE_CONFIG_DIR="$cfg" bash "$core/scripts/session-tokens.sh" "$@" > "$tmp/out.raw" 2> "$tmp/err.raw"
  fi
  rc=$?
  tr -d '\r' < "$tmp/out.raw" > "$tmp/out"; tr -d '\r' < "$tmp/err.raw" > "$tmp/err"
}
fail=0; n=0
bad() { echo "FAIL $*"; fail=1; }
# expect <name> <exit code> <stdout file or -> <stderr text or -> -- <config dir> <arguments...>
expect() {
  local name="$1" want_rc="$2" want_out="$3" want_err="$4"; shift 5
  n=$((n + 1)); run "$@"
  [ "$rc" = "$want_rc" ] || { bad "$name: exit $rc, want $want_rc"; sed 's/^/  err: /' "$tmp/err"; return; }
  if [ "$want_out" = - ]; then [ ! -s "$tmp/out" ] || { bad "$name: printed"; sed 's/^/  got: /' "$tmp/out"; return; }
  elif ! [ "$(cat "$tmp/out")" = "$(tr -d '\r' < "$want_out")" ]; then
    bad "$name: differs from ${want_out#"$here"/}"; sed 's/^/  got: /' "$tmp/out"; return
  fi
  [ "$want_err" = - ] || [ "$(cat "$tmp/err")" = "$want_err" ] || { bad "$name: stderr"; sed 's/^/  got: /' "$tmp/err"; return; }
  echo "ok   $name"
}
cl="$here/claude"; t="$here"
expect "a session, its subagent, the cost line" 0 "$t/expected.txt" - -- "$cl" s1
expect "a session without subagents" 0 "$t/expected-s2.txt" - -- "$cl" s2
expect "a subagent by its agentId" 0 "$t/expected-agent.txt" - -- "$cl" x
expect "an ambiguous transcript prefix" 1 - "$(printf 'ambiguous id s:\ns1\ns2')" -- "$cl" s
expect "--since a UTC time" 0 "$t/expected-since.txt" - -- "$cl" --since 2026-10-05T17:00:00Z
expect "--since with milliseconds" 0 "$t/expected-since.txt" - -- "$cl" --since 2026-10-05T17:00:00.000Z
expect "--since without the Z" 0 "$t/expected-since.txt" - -- "$cl" --since 2026-10-05T17:00:00
expect "--since Unix seconds (the status line's resets_at)" 0 "$t/expected-since.txt" - -- "$cl" --since 1791219600
expect "--since with an offset other than Z is refused" 2 - - -- "$cl" --since 2026-10-05T17:00:00+02:00
expect "--since a date only is refused" 2 - - -- "$cl" --since 2026-10-05
expect "a usage object in a tool input before the message's own" 0 "$t/expected-tool-usage.txt" - -- "$here/edge" t1
expect "a tool input with keys differing only by case" 0 "$t/expected-case-keys.txt" - -- "$here/edge" t6
expect "--since: the record's own timestamp, before or after the message" 0 "$t/expected-order-since.txt" - -- "$here/order" --since 2026-10-05T17:00:00Z
expect "an ambiguous prefix of status files only" 1 - "$(printf 'ambiguous id ab:\nab1\nab2')" -- "$here/edge" ab
# the time line: a gap over 5 minutes left out of active, one of exactly 5 kept, a half minute rounded up,
# the record's own timestamp while a tool input carries another, a line without one skipped
tm="$here/time"
expect "time: a gap over 5 minutes is not active" 0 "$t/expected-time-gap.txt" - -- "$tm" g1
expect "time: a subagent working while the transcript is quiet is active" 0 "$t/expected-time-subagent.txt" - -- "$tm" g2
expect "time: a subagent alone, by its agentId" 0 "$t/expected-time-agent.txt" - -- "$tm" g2t
expect "time: a session with one record (wall=0m)" 0 "$t/expected-time-one.txt" - -- "$tm" g3
expect "time: no record with a timestamp, no time line" 0 "$t/expected-time-none.txt" - -- "$tm" g4
# a 12-minute tool call is work, a 12-minute gap after a result is not, two overlapping tool calls
# keep the time active until the later result
expect "time: tool calls span their gaps, a gap after a result does not" 0 "$t/expected-time-tools.txt" - -- "$tm" g5
# a 50-minute tool call gives 30 minutes of work; a question to a person (AskUserQuestion, and a tool
# whose name ends in it) gives none, whether it waits 20 minutes or 3
expect "time: a tool call's gap is capped at 30 minutes, a question to a person is idle" 0 "$t/expected-time-cap.txt" - -- "$tm" g6
# the same transcript with CRLF line ends (a checkout on Windows, a copy through another tool)
mkdir -p "$tmp/crlf/projects/-work-app"
awk '{ sub(/\r$/, ""); printf "%s\r\n", $0 }' "$tm/projects/-work-app/g1.jsonl" > "$tmp/crlf/projects/-work-app/g1.jsonl"
expect "time: CRLF line ends" 0 "$t/expected-time-gap.txt" - -- "$tmp/crlf" g1
# the cost-state record Claude Code appends at a normal stop: its numbers (exact out, thinking, its cost
# before the status file's), the last of several, none after an assistant message, two models with keys
# in another order (its subagent's messages not added again), a subagent by its agentId (no record)
st="$here/state"
expect "cost-state: a stopped session's record" 0 "$t/expected-state-one.txt" - -- "$st" c1
expect "cost-state: the last of several records counts" 0 "$t/expected-state-last.txt" - -- "$st" c2
expect "cost-state: an assistant message after the record, the sums" 0 "$t/expected-state-after.txt" - -- "$st" c3
expect "cost-state: two models, keys in another order, spaces" 0 "$t/expected-state-models.txt" - -- "$st" c4
expect "cost-state: a subagent of a stopped session, the sums" 0 "$t/expected-state-agent.txt" - -- "$st" c4s
# the same records with CRLF line ends and a UTF-8 BOM
mkdir -p "$tmp/crlf2/projects/-work-app"
awk 'NR == 1 { printf "\357\273\277" } { sub(/\r$/, ""); printf "%s\r\n", $0 }' "$st/projects/-work-app/c2.jsonl" > "$tmp/crlf2/projects/-work-app/c2.jsonl"
expect "cost-state: CRLF line ends and a BOM" 0 "$t/expected-state-last.txt" - -- "$tmp/crlf2" c2
printf 'cost\t$0.1000\n' > "$tmp/cost-ab1.txt"; printf 'cost\t$0.4182\n' > "$tmp/cost-s1.txt"
expect "a status file only, by its full id" 0 "$tmp/cost-ab1.txt" - -- "$here/edge" ab1
# no projects folder, the status file there: the cost line
mkdir -p "$tmp/noproj/coordinator/sessions"; cp "$cl/coordinator/sessions/s1.json" "$tmp/noproj/coordinator/sessions/"
expect "no projects folder, a status file" 0 "$tmp/cost-s1.txt" - -- "$tmp/noproj" s1
expect "neither a transcript nor a status file" 1 - - -- "$tmp/noproj" s9
# a config path with [ ] in it (PowerShell reads [1] as a wildcard unless the path is literal)
mkdir -p "$tmp/cfg[1]"; cp -R "$cl/." "$tmp/cfg[1]/"
expect "a config path with [ ]" 0 "$t/expected.txt" - -- "$tmp/cfg[1]" s1
expect "a config path with [ ], --since" 0 "$t/expected-since.txt" - -- "$tmp/cfg[1]" --since 2026-10-05T17:00:00Z
expect "a config path with [ ], a subagent" 0 "$t/expected-agent.txt" - -- "$tmp/cfg[1]" x
# --prune deletes status files older than exactly 7 x 24 hours: ages 30 and 7.5 days go, 6.5 days and now stay
d="$tmp/prune/coordinator/sessions"; mkdir -p "$d"
stamp() {   # the local time $1 seconds ago, for touch -t: GNU date reads @<n>, BSD date -r <n>
  local s=$(( $(date +%s) - $1 ))
  if date --version >/dev/null 2>&1; then date -d "@$s" +%Y%m%d%H%M.%S; else date -r "$s" +%Y%m%d%H%M.%S; fi
}
touch "$d/new.json"; touch -t "$(stamp 561600)" "$d/d6.json"; touch -t "$(stamp 648000)" "$d/d7.json"; touch -t "$(stamp 2592000)" "$d/old.json"
# and the status line's temp files older than an hour: 2 hours goes, 30 minutes stays; statusline.json stays at any age
c="$tmp/prune/coordinator"
touch -t "$(stamp 7200)" "$c/statusline.101.tmp"; touch -t "$(stamp 1800)" "$c/statusline.102.tmp"; touch -t "$(stamp 2592000)" "$c/statusline.json"
n=$((n + 1)); run "$tmp/prune" --prune
left="$(ls "$d" | LC_ALL=C sort | tr '\n' ' ')"
if [ "$rc" = 0 ] && [ "$left" = "d6.json new.json " ]; then echo "ok   --prune at 7 x 24 hours"; else bad "--prune: exit $rc, left $left"; fi
n=$((n + 1)); left="$(ls "$c" | LC_ALL=C sort | tr '\n' ' ')"
if [ "$left" = "sessions statusline.102.tmp statusline.json " ]; then echo "ok   --prune: the status line's temp files at 1 hour"; else bad "--prune temp files: left $left"; fi
[ "$fail" = 0 ] && echo "session-tokens: $n cases passed" || echo "session-tokens: failures above ($n cases)"
exit "$fail"
