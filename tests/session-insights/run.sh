#!/usr/bin/env bash
# The session-insights cases: the fixture transcripts against their expected lines — guard blocks followed
# by a retry, a way around, a change and a stop; a deny rule; blocks on PowerShell and on Write; tool
# errors and a repeat, refusals that are no errors; waits on a person; rereads with --detail; a cache
# rewrite after a pause; a subagent counted with its session and alone; --since across two sessions;
# CRLF, a BOM and malformed lines; the error cases and their exit codes.
#   tests/session-insights/run.sh sh              # scripts/session-insights.sh, with the bash running this file
#   tests/session-insights/run.sh ps pwsh         # scripts/session-insights.ps1 (or: ps powershell)
# Exit 1 if any case fails.
set -u
[ $# -gt 0 ] || { sed -n '2,9s/^# \{0,1\}//p' "$0"; exit 2; }
kind="$1"; shift
[ "$kind" = sh ] || [ "$kind" = ps ] || { sed -n '2,9s/^# \{0,1\}//p' "$0"; exit 2; }
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
    for x in "$@"; do case "$x" in --since) a+=(-Since) ;; --detail) a+=(-Detail) ;; *) a+=("$x") ;; esac; done
    CLAUDE_CONFIG_DIR="$cfg" "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$(winpath "$core/scripts/session-insights.ps1")" ${a[@]+"${a[@]}"} > "$tmp/out.raw" 2> "$tmp/err.raw"
  else
    CLAUDE_CONFIG_DIR="$cfg" bash "$core/scripts/session-insights.sh" "$@" > "$tmp/out.raw" 2> "$tmp/err.raw"
  fi
  rc=$?
  tr -d '\r' < "$tmp/out.raw" > "$tmp/out"; tr -d '\r' < "$tmp/err.raw" > "$tmp/err"
}
fail=0; n=0
bad() { echo "FAIL $*"; fail=1; }
# expect <name> <exit code> <stdout file, - (nothing) or any> <stderr text or -> -- <config dir> <arguments...>
expect() {
  local name="$1" want_rc="$2" want_out="$3" want_err="$4"; shift 5
  n=$((n + 1)); run "$@"
  [ "$rc" = "$want_rc" ] || { bad "$name: exit $rc, want $want_rc"; sed 's/^/  err: /' "$tmp/err"; return; }
  if [ "$want_out" = any ]; then :
  elif [ "$want_out" = - ]; then [ ! -s "$tmp/out" ] || { bad "$name: printed"; sed 's/^/  got: /' "$tmp/out"; return; }
  elif ! [ "$(cat "$tmp/out")" = "$(tr -d '\r' < "$want_out")" ]; then
    bad "$name: differs from ${want_out#"$here"/}"; sed 's/^/  got: /' "$tmp/out"; return
  fi
  [ "$want_err" = - ] || [ "$(cat "$tmp/err")" = "$want_err" ] || { bad "$name: stderr"; sed 's/^/  got: /' "$tmp/err"; return; }
  echo "ok   $name"
}
cl="$here/claude"; mu="$here/multi"; t="$here"
expect "blocks: retried, around, changed, stopped; a deny rule; PowerShell and Write blocks" 0 "$t/expected-b1.txt" - -- "$cl" b1
expect "tool errors and a repeat, refusals, waits, rereads, a cache rewrite, malformed lines" 0 "$t/expected-e1.txt" - -- "$cl" e1
expect "--detail: the reread files' paths" 0 "$t/expected-e1-detail.txt" - -- "$cl" e1 --detail
expect "a session with its subagent" 0 "$t/expected-sub1.txt" - -- "$cl" sub1
expect "a subagent by its agentId" 0 "$t/expected-a1.txt" - -- "$cl" a1
expect "a transcript by its path" 0 "$t/expected-b1.txt" - -- "$cl" "$(winpath "$cl/projects/-work-app/b1.jsonl")"
expect "a session without messages prints nothing" 0 - - -- "$cl" e0
expect "an ambiguous prefix" 1 - "$(printf 'ambiguous id e:\ne0\ne1')" -- "$cl" e
expect "no such session" 1 - - -- "$cl" nope
expect "one session, also before 17:00" 0 "$t/expected-m1.txt" - -- "$mu" m1
expect "--since across two sessions" 0 "$t/expected-since.txt" - -- "$mu" --since 2026-10-05T17:00:00Z
expect "--since Unix seconds" 0 "$t/expected-since.txt" - -- "$mu" --since 1791219600
expect "--since every transcript, --detail" 0 "$t/expected-all.txt" - -- "$cl" --since 2026-01-01T00:00:00Z --detail
expect "--since with an offset other than Z is refused" 2 - - -- "$mu" --since 2026-10-05T17:00:00+02:00
expect "no session and no --since" 2 any - -- "$cl"
expect "--since and a session together are refused" 2 any - -- "$cl" b1 --since 2026-10-05T17:00:00Z
mkdir -p "$tmp/none"
expect "--since without a projects folder" 1 - - -- "$tmp/none" --since 2026-10-05T17:00:00Z
# the same transcript with CRLF line ends and a BOM (a checkout on Windows, a copy through another tool)
mkdir -p "$tmp/crlf/projects/-work-app"
{ printf '\357\273\277'; awk '{ sub(/\r$/, ""); printf "%s\r\n", $0 }' "$cl/projects/-work-app/e1.jsonl"; } > "$tmp/crlf/projects/-work-app/e1.jsonl"
expect "CRLF line ends and a BOM" 0 "$t/expected-e1.txt" - -- "$tmp/crlf" e1
# a config path with [ ] in it (PowerShell reads [1] as a wildcard unless the path is literal)
mkdir -p "$tmp/cfg[1]"; cp -R "$cl/." "$tmp/cfg[1]/"
expect "a config path with [ ]" 0 "$t/expected-sub1.txt" - -- "$tmp/cfg[1]" sub1
expect "a config path with [ ], --since" 0 "$t/expected-all.txt" - -- "$tmp/cfg[1]" --since 2026-01-01T00:00:00Z --detail
[ "$fail" = 0 ] && echo "session-insights: $n cases passed" || echo "session-insights: failures above ($n cases)"
exit "$fail"
