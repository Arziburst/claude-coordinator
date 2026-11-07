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
    for x in "$@"; do case "$x" in --since) a+=(-Since) ;; --prune) a+=(-Prune) ;; --prices) a+=(-Prices) ;; *) a+=("$x") ;; esac; done
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
  elif ! [ "$(grep -v '^context' "$tmp/out")" = "$(tr -d '\r' < "$want_out" | grep -v '^context')" ]; then   # every older line, byte for byte; the context line (#342): below
    bad "$name: differs from ${want_out#"$here"/}"; sed 's/^/  got: /' "$tmp/out"; return
  fi
  [ "$want_err" = - ] || [ "$(cat "$tmp/err")" = "$want_err" ] || { bad "$name: stderr"; sed 's/^/  got: /' "$tmp/err"; return; }
  echo "ok   $name"
}
cl="$here/claude"; t="$here"
E="empty session id: give a session id, a prefix, an agentId or a transcript (CLAUDE_CODE_SESSION_ID may be unset in this tool)"
expect "a session, its subagent, the cost line" 0 "$t/expected.txt" - -- "$cl" s1
expect "a session without subagents" 0 "$t/expected-s2.txt" - -- "$cl" s2
expect "a subagent by its agentId" 0 "$t/expected-agent.txt" - -- "$cl" x
expect "an ambiguous transcript prefix" 1 - "$(printf 'ambiguous id s:\ns1\ns2')" -- "$cl" s
expect "an empty session id is refused, never every session (#209)" 2 - "$E" -- "$cl" ""
expect "a blank session id is refused" 2 - "$E" -- "$cl" "  "
expect "--since a UTC time" 0 "$t/expected-since.txt" - -- "$cl" --since 2026-10-05T17:00:00Z
expect "--since with milliseconds" 0 "$t/expected-since.txt" - -- "$cl" --since 2026-10-05T17:00:00.000Z
expect "--since without the Z" 0 "$t/expected-since.txt" - -- "$cl" --since 2026-10-05T17:00:00
expect "--since Unix seconds (the status line's resets_at)" 0 "$t/expected-since.txt" - -- "$cl" --since 1791219600
expect "--since with an offset other than Z is refused" 2 - - -- "$cl" --since 2026-10-05T17:00:00+02:00
expect "a usage object in a tool input before the message's own" 0 "$t/expected-tool-usage.txt" - -- "$here/edge" t1
expect "--since: the record's own timestamp, before or after the message" 0 "$t/expected-order-since.txt" - -- "$here/order" --since 2026-10-05T17:00:00Z
expect "an ambiguous prefix of status files only" 1 - "$(printf 'ambiguous id ab:\nab1\nab2')" -- "$here/edge" ab
# the time line: a gap over 5 minutes left out of active, one of exactly 5 kept, a half minute rounded up,
# the record's own timestamp while a tool input carries another, a line without one skipped
tm="$here/time"
expect "time: a gap over 5 minutes is not active" 0 "$t/expected-time-gap.txt" - -- "$tm" g1
expect "time: a subagent working while the transcript is quiet is active" 0 "$t/expected-time-subagent.txt" - -- "$tm" g2
expect "time: a session with one record (wall=0m)" 0 "$t/expected-time-one.txt" - -- "$tm" g3
expect "time: no record with a timestamp, no time line" 0 "$t/expected-time-none.txt" - -- "$tm" g4
# a 12-minute tool call is work, a 12-minute gap after a result is not, two overlapping tool calls
# keep the time active until the later result
expect "time: tool calls span their gaps, a gap after a result does not" 0 "$t/expected-time-tools.txt" - -- "$tm" g5
# a 50-minute tool call gives 30 minutes of work; a question to a person (AskUserQuestion, and a tool
# whose name ends in it) gives none, whether it waits 20 minutes or 3
expect "time: a tool call's gap is capped at 30 minutes, a question to a person is idle" 0 "$t/expected-time-cap.txt" - -- "$tm" g6
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
# a decimal-comma locale (de_DE, ru_RU: the BSD awk on macOS reads 0.0071 as 0 there): the same lines
for loc in ru_RU.UTF-8; do
  export LC_ALL="$loc"
  expect "cost-state cost under $loc" 0 "$t/expected-state-one.txt" - -- "$st" c1
  expect "a status file's cost under $loc" 0 "$t/expected-state-after.txt" - -- "$st" c3
  unset LC_ALL
done
# a cost at a rounding midpoint: half up, as the .ps1 rounds (1.89075 is 1.8907499... as a double)
mkdir -p "$tmp/mid/projects/-w" "$tmp/mid/coordinator/sessions"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"go"},"uuid":"u1","sessionId":"m1","timestamp":"2026-10-12T10:00:00.000Z"}' \
  '{"type":"cost-state","sessionId":"m1","totalCostUSD":1.89075,"modelUsage":{"claude-haiku-5-5":{"inputTokens":1,"outputTokens":2}}}' > "$tmp/mid/projects/-w/m1.jsonl"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"go"},"uuid":"u1","sessionId":"m2","timestamp":"2026-10-12T10:00:00.000Z"}' > "$tmp/mid/projects/-w/m2.jsonl"
printf '{"session_id":"m2","cost":{"total_cost_usd":0.03125}}\n' > "$tmp/mid/coordinator/sessions/m2.json"
for c in 'm1 $1.8908' 'm2 $0.0313'; do
  n=$((n + 1)); run "$tmp/mid" "${c%% *}"
  grep -qxF "cost$(printf '\t')${c#* }" "$tmp/out" || { bad "a cost at a rounding midpoint (${c%% *}): want cost ${c#* }"; sed 's/^/  got: /' "$tmp/out"; }
done
printf 'cost\t$0.1000\n' > "$tmp/cost-ab1.txt"; printf 'cost\t$0.4182\n' > "$tmp/cost-s1.txt"
expect "a status file only, by its full id" 0 "$tmp/cost-ab1.txt" - -- "$here/edge" ab1
# no projects folder, the status file there: the cost line
mkdir -p "$tmp/noproj/coordinator/sessions"; cp "$cl/coordinator/sessions/s1.json" "$tmp/noproj/coordinator/sessions/"
expect "neither a transcript nor a status file" 1 - - -- "$tmp/noproj" s9
# a config path with [ ] in it (PowerShell reads [1] as a wildcard unless the path is literal)
mkdir -p "$tmp/cfg[1]"; cp -R "$cl/." "$tmp/cfg[1]/"
expect "a config path with [ ]" 0 "$t/expected.txt" - -- "$tmp/cfg[1]" s1
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
# #342, the access point: the last line, wherever a transcript is read, `context` and a tab, each bucket <requests>/<tokens, as the total line sums them>, by input + cache read + cache write of a request (each message id once, its largest output), 100000 in 100-200k, 700000 in 400-700k.
# --prices <file> (-Prices; coordinator/prices.txt's format, as run-stats reads it; unreadable: exit 2): each bucket <requests>/<tokens>/$<cost, 4 places>, then unpriced=<n>: the requests of a model not in the file, counted, no cost.
ctx() { n=$((n + 1)); run "$2" "${@:4}"; [ "$rc" = 0 ] && [ "$(tail -n 1 "$tmp/out")" = "$(printf 'context\t%s' "$3")" ] && echo "ok   $1" || { bad "$1: want the last line context $3"; sed 's/^/  got: /' "$tmp/out"; }; }
PF="$(winpath "$here/context/prices.txt")"; K='under100k=1/100999/$0.4200 100-200k=2/299999/$0.4500 200-400k=3/799999/$0.1320 400-700k=3/1500000/$0.2600 over700k=2/1500001/$0.1400 unpriced=1'
ctx "context: each bucket's edges, requests and tokens, no price needed" "$here/context" 'under100k=1/100999 100-200k=2/299999 200-400k=3/799999 400-700k=3/1500000 over700k=2/1500001' k1
ctx "context: --prices, four models' costs, an unpriced model" "$here/context" "$K" k1 --prices "$PF"
ctx "context: a stopped session, from its transcript, not its record" "$st" 'under100k=1/1013/$0.0002 100-200k=0/0/$0.0000 200-400k=0/0/$0.0000 400-700k=0/0/$0.0000 over700k=0/0/$0.0000 unpriced=0' c1 --prices "$PF"
expect "context: --prices with no such file" 2 - - -- "$here/context" k1 --prices "$(winpath "$tmp/none.txt")"
[ "$fail" = 0 ] && echo "session-tokens: $n cases passed" || echo "session-tokens: failures above ($n cases)"
exit "$fail"
