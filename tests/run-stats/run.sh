#!/usr/bin/env bash
# The run-stats cases: the fixture run logs against their expected lines (old rows without the time
# columns, `-` and other non-values, fewer than 4 runs, more than 10 so only the last 10 count, even
# counts, a header in another order, no header, a header only, a CRLF copy with a BOM), one pair's line,
# a missing file (exit 1) and usage errors (exit 2).
#   tests/run-stats/run.sh sh              # scripts/run-stats.sh, with the bash running this file
#   tests/run-stats/run.sh ps pwsh         # scripts/run-stats.ps1 (or: ps powershell)
# Exit 1 if any case fails.
set -u
[ $# -gt 0 ] || { sed -n '2,8s/^# \{0,1\}//p' "$0"; exit 2; }
kind="$1"; shift
[ "$kind" = sh ] || [ "$kind" = ps ] || { sed -n '2,8s/^# \{0,1\}//p' "$0"; exit 2; }
PS=("$@")
[ "$kind" = sh ] || [ ${#PS[@]} -gt 0 ] || { echo "ps needs the PowerShell command" >&2; exit 2; }
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -r "$tmp"' EXIT
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }   # Git Bash -> C:/...
cp "$here"/*.tsv "$tmp/"
# the same run log with CRLF line ends and a UTF-8 BOM (a file saved by a Windows editor)
{ printf '\357\273\277'; awk '{ sub(/\r$/, ""); printf "%s\r\n", $0 }' "$here/runs.tsv"; } > "$tmp/crlf.tsv"
cd "$tmp" || exit 1

# runs the script under test in $tmp; stdout to out, stderr to err, \r removed
run() {
  if [ "$kind" = ps ]; then
    local a=()
    for x in "$@"; do case "$x" in --kind) a+=(-Kind) ;; --model) a+=(-Model) ;; *) a+=("$x") ;; esac; done
    "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$(winpath "$core/scripts/run-stats.ps1")" ${a[@]+"${a[@]}"} > out.raw 2> err.raw
  else
    bash "$core/scripts/run-stats.sh" "$@" > out.raw 2> err.raw
  fi
  rc=$?
  tr -d '\r' < out.raw > out; tr -d '\r' < err.raw > err
}
fail=0; n=0
bad() { echo "FAIL $*"; fail=1; }
# expect <name> <exit code> <stdout file, - for none, * for any> <stderr text or -> -- <arguments...>
expect() {
  local name="$1" want_rc="$2" want_out="$3" want_err="$4"; shift 5
  n=$((n + 1)); run "$@"
  [ "$rc" = "$want_rc" ] || { bad "$name: exit $rc, want $want_rc"; sed 's/^/  err: /' err; return; }
  if [ "$want_out" = - ]; then [ ! -s out ] || { bad "$name: printed"; sed 's/^/  got: /' out; return; }
  elif [ "$want_out" != '*' ] && ! [ "$(cat out)" = "$(tr -d '\r' < "$want_out")" ]; then
    bad "$name: differs from ${want_out#"$here"/}"; sed 's/^/  got: /' out; return
  fi
  [ "$want_err" = - ] || [ "$(cat err)" = "$want_err" ] || { bad "$name: stderr"; sed 's/^/  got: /' err; return; }
  echo "ok   $name"
}
t="$here"
expect "a run log: old rows, non-values, under 4, over 10, even counts" 0 "$t/expected-runs.txt" - -- runs.tsv
expect "no header: the columns in CORE 7's order" 0 "$t/expected-noheader.txt" - -- noheader.tsv
expect "a header in another order" 0 "$t/expected-reordered.txt" - -- reordered.tsv
expect "a header only" 0 "$t/expected-header-only.txt" - -- header-only.tsv
expect "CRLF line ends and a BOM" 0 "$t/expected-runs.txt" - -- crlf.tsv
expect "one kind and model (a contract's estimate)" 0 "$t/expected-one.txt" - -- runs.tsv --kind ordinary --model sonnet
expect "a kind and model with no runs" 0 "$t/expected-none.txt" - -- header-only.tsv --kind ordinary --model sonnet
expect "a missing file" 1 - "run-stats: cannot read missing.tsv" -- missing.tsv
expect "a missing file, one pair" 1 - "run-stats: cannot read missing.tsv" -- missing.tsv --kind ordinary --model sonnet
expect "--kind without --model is a usage error" 2 '*' - -- runs.tsv --kind ordinary
expect "no file is a usage error" 2 '*' - --
[ "$fail" = 0 ] && echo "run-stats: $n cases passed" || echo "run-stats: failures above ($n cases)"
exit "$fail"
