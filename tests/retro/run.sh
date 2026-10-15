#!/usr/bin/env bash
# The retro cases: the fixture run log (coordinator/RUNS.tsv - history before the weeks, a previous week with too
# little data, a week with a rework, an escalation, a failed run, a lead with sub-runs and a subagent row, a
# project-specific kind, an open owner wait, a self-test and a probe left out), its journal and escapes, and the
# fixture transcripts (claude/: a coordinator, a worker and a task about a self-test kept; a probe, a self-test lead
# with its subagent, a session in a coordinator-selftest sandbox and another project left out) against the expected
# local report and public body; the public body without the project's folder name or its kind; a week with too
# little data, no transcripts, journal or escapes; CRLF and a BOM; the allowlist self-check failing on an injected
# path, the folder's name, free text and a foreign label; the proposal check; --new-id; usage errors.
#   tests/retro/run.sh sh              # scripts/retro.sh, with the bash running this file
#   tests/retro/run.sh ps pwsh         # scripts/retro.ps1 (or: ps powershell)
# Exit 1 if any case fails.
set -u
[ $# -gt 0 ] || { sed -n '2,12s/^# \{0,1\}//p' "$0"; exit 2; }
kind="$1"; shift
[ "$kind" = sh ] || [ "$kind" = ps ] || { sed -n '2,12s/^# \{0,1\}//p' "$0"; exit 2; }
PS=("$@")
[ "$kind" = sh ] || [ ${#PS[@]} -gt 0 ] || { echo "ps needs the PowerShell command" >&2; exit 2; }
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -r "$tmp"' EXIT
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }   # Git Bash -> C:/...
cfg="$(winpath "$here/claude")"

# runs the script under test; stdout to out, stderr to err, \r removed
run() {
  if [ "$kind" = ps ]; then
    local a=()
    for x in "$@"; do case "$x" in --week) a+=(-Week) ;; --project) a+=(-Project) ;; --journal) a+=(-Journal) ;;
      --escapes) a+=(-Escapes) ;; --no-insights) a+=(-NoInsights) ;; --public) a+=(-Public) ;; --id) a+=(-Id) ;;
      --check-public) a+=(-CheckPublic) ;; --check-proposal) a+=(-CheckProposal) ;; --new-id) a+=(-NewId) ;;
      *) a+=("$x") ;; esac; done
    CLAUDE_CONFIG_DIR="$cfg" "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$(winpath "$core/scripts/retro.ps1")" ${a[@]+"${a[@]}"} > "$tmp/out.raw" 2> "$tmp/err.raw"
  else
    CLAUDE_CONFIG_DIR="$cfg" bash "$core/scripts/retro.sh" "$@" > "$tmp/out.raw" 2> "$tmp/err.raw"
  fi
  rc=$?
  tr -d '\r' < "$tmp/out.raw" > "$tmp/out"; tr -d '\r' < "$tmp/err.raw" > "$tmp/err"
}
fail=0; n=0
bad() { echo "FAIL $*"; fail=1; }
# expect <name> <exit code> <stdout file, - (nothing) or any> <stderr text, - (any), or ~text (contains)> -- <arguments...>
expect() {
  local name="$1" want_rc="$2" want_out="$3" want_err="$4"; shift 5
  n=$((n + 1)); run "$@"
  [ "$rc" = "$want_rc" ] || { bad "$name: exit $rc, want $want_rc"; sed 's/^/  err: /' "$tmp/err"; return 1; }
  if [ "$want_out" = any ]; then :
  elif [ "$want_out" = - ]; then [ ! -s "$tmp/out" ] || { bad "$name: printed"; sed 's/^/  got: /' "$tmp/out"; return 1; }
  elif ! [ "$(cat "$tmp/out")" = "$(tr -d '\r' < "$want_out")" ]; then
    bad "$name: differs from ${want_out#"$here"/}"; diff "$want_out" "$tmp/out" | sed 's/^/  /'; return 1
  fi
  case "$want_err" in
    -) ;;
    "~"*) grep -qF -- "${want_err#"~"}" "$tmp/err" || { bad "$name: stderr lacks ${want_err#"~"}"; sed 's/^/  got: /' "$tmp/err"; return 1; } ;;
    *) [ "$(cat "$tmp/err")" = "$want_err" ] || { bad "$name: stderr"; sed 's/^/  got: /' "$tmp/err"; return 1; } ;;
  esac
  echo "ok   $name"
}
t="$here"; runs="$(winpath "$here/coordinator/RUNS.tsv")"; P=C:/work/acme-shop; ID=3f9a0c1b7e42

expect "the local report: five axes, this week against the previous one" 0 "$t/expected-local.txt" - -- "$runs" --week 2026-10-07 --project "$P"
expect "--week any day of the week gives the same week" 0 "$t/expected-local.txt" - -- "$runs" --week 2026-10-11 --project "$P"
expect "the public body: the template, numbers and the allowlist only" 0 "$t/expected-public.md" - -- "$runs" --week 2026-10-07 --project "$P" --public --id "$ID"
cp "$tmp/out" "$tmp/public.md"
# the project's folder name and its own kind never leave: not in the public body, in any case
if grep -qi 'acme' "$tmp/public.md"; then bad "the public body names the project"; else echo "ok   the public body holds neither the folder's name nor the project's own kind"; fi; n=$((n + 1))
# the real run log's parts: the kinds map, an unknown result, logged and rebuilt forecasts, a sibling worktree root
n=$((n + 1)); if grep -q '^| trivial | 1 |' "$tmp/public.md" && grep -q '^| other | 1 |' "$tmp/public.md"; then echo "ok   ROUTING.md's map: mechanical counts as trivial, an unmapped kind as other"; else bad "the kinds map in the public body"; fi
n=$((n + 1)); if grep -q 'superseded' "$tmp/public.md"; then bad "an unknown result in the public body"; else echo "ok   an unknown result stays out of the public body"; fi
n=$((n + 1)); if grep -q '^| predictability | cost_logged | 4 | 2 |' "$tmp/public.md" && grep -q '^| predictability | work_rebuilt | 2 | 2 |' "$tmp/public.md"; then echo "ok   logged and rebuilt forecasts counted apart"; else bad "the logged and rebuilt counts"; fi
expect "the local report keeps the project's kinds and lists an unknown result" 0 any - -- "$runs" --week 2026-10-07 --project "$P"
grep -q '^kind	mechanical	1	' "$tmp/out" && grep -q '^unknown result: superseded by #17 ×1$' "$tmp/out" && grep -q '^block	deleting a protected branch (main)	' "$tmp/out" ||
  bad "the local report: its own kind mechanical, the unknown result and the sibling worktree's block"
# a week with too little data, no transcripts, no journal and no escapes file (a run log alone in its folder)
mkdir -p "$tmp/bare/coordinator" && cp "$here/coordinator/RUNS.tsv" "$tmp/bare/coordinator/"
expect "a week with too little data; no transcripts, journal or escapes" 0 "$t/expected-thin.txt" - -- "$(winpath "$tmp/bare/coordinator/RUNS.tsv")" --week 2026-09-28 --project "$P" --no-insights
expect "the same as a public body" 0 "$t/expected-thin-public.md" - -- "$(winpath "$tmp/bare/coordinator/RUNS.tsv")" --week 2026-09-28 --project "$P" --no-insights --public --id "$ID"
# no PROJECT.md and no ROUTING.md: the sibling worktree root is not the project's, and mechanical is other
expect "no PROJECT.md: only the root and its .claude/worktrees" 0 any - -- "$(winpath "$tmp/bare/coordinator/RUNS.tsv")" --week 2026-10-07 --project "$P"
! grep -q 'deleting a protected branch' "$tmp/out" || bad "a session under a worktree root no PROJECT.md names was counted"
expect "no ROUTING.md: a project kind is other in the public body" 0 any - -- "$(winpath "$tmp/bare/coordinator/RUNS.tsv")" --week 2026-10-07 --project "$P" --public --id "$ID"
grep -q '^| other | 2 |' "$tmp/out" || bad "without a kinds map mechanical and the project's kind are other"
# the run log, journal and escapes with CRLF line ends and a UTF-8 BOM (saved by a Windows editor)
mkdir -p "$tmp/crlf/coordinator"
for f in RUNS.tsv LOG.md ESCAPES.tsv ROUTING.md PROJECT.md; do
  { printf '\357\273\277'; awk '{ sub(/\r$/, ""); printf "%s\r\n", $0 }' "$here/coordinator/$f"; } > "$tmp/crlf/coordinator/$f"
done
expect "CRLF line ends and a BOM in the run log, the journal, the escapes, ROUTING.md and PROJECT.md" 0 "$t/expected-local.txt" - -- "$(winpath "$tmp/crlf/coordinator/RUNS.tsv")" --week 2026-10-07 --project "$P"
expect "the default week (the last complete one) and the default project" 0 any - -- "$runs"
head -n 1 "$tmp/out" | grep -q '^retro	week of [0-9-]*	previous week of [0-9-]*$' || bad "the default week's header line"
# the allowlist self-check on the public body, then on bodies with something injected
expect "--check-public passes the body" 0 - - -- --check-public "$(winpath "$tmp/public.md")" --project "$P"
{ cat "$tmp/public.md"; echo '| cost | src/cart.ts | 1 | 2 |'; } > "$tmp/inj-path.md"
expect "--check-public fails on an injected path" 1 - "retro: the summary body fails its check: line 78: a path separator" -- --check-public "$(winpath "$tmp/inj-path.md")"
{ cat "$tmp/public.md"; echo 'See C:\work\acme-shop for the details'; } > "$tmp/inj-win.md"
expect "--check-public fails on an injected Windows path" 1 - "~a path separator" -- --check-public "$(winpath "$tmp/inj-win.md")"
{ cat "$tmp/public.md"; echo '| other | 1 | acme-shop | 0 | 0 |'; } > "$tmp/inj-name.md"
expect "--check-public fails on the project folder's name" 1 - "~the project folder's name" -- --check-public "$(winpath "$tmp/inj-name.md")" --project "$P"
expect "without --project the name is still no allowlisted cell" 1 - "~a cell outside the allowlist" -- --check-public "$(winpath "$tmp/inj-name.md")"
{ cat "$tmp/public.md"; echo 'Fixed the cart total for the checkout page'; } > "$tmp/inj-text.md"
expect "--check-public fails on free text" 1 - "~not a line of the template" -- --check-public "$(winpath "$tmp/inj-text.md")"
{ cat "$tmp/public.md"; echo '| checkout | 1 | 2 | 3 | 4 |'; } > "$tmp/inj-label.md"
expect "--check-public fails on a label outside the allowlist" 1 - "~a row label outside the allowlist" -- --check-public "$(winpath "$tmp/inj-label.md")"
: > "$tmp/empty.md"
expect "--check-public fails on an empty body" 1 - "retro: the summary body is empty" -- --check-public "$(winpath "$tmp/empty.md")"
# the proposal check: the fixture passes; a project path, a path outside the core, a foreign signature, a missing line fail
expect "--check-proposal passes the fixture proposal" 0 - - -- --check-proposal "$(winpath "$here/proposal.md")" --project "$P"
sed 's|^Change: .*|Change: move the check out of src/cart.ts into the shared module|' "$here/proposal.md" > "$tmp/prop-path.md"
expect "--check-proposal fails on a path that is not the core's" 1 - "~a path that is not the core's" -- --check-proposal "$(winpath "$tmp/prop-path.md")"
sed 's|^Change: .*|Change: the guard should allow pushes in the acme-shop repository|' "$here/proposal.md" > "$tmp/prop-name.md"
expect "--check-proposal fails on the project folder's name" 1 - "~the project folder's name" -- --check-proposal "$(winpath "$tmp/prop-name.md")" --project "$P"
sed 's|^Expected gain: .*|Expected gain: fewer blocks, see #55 and /home/me/notes|' "$here/proposal.md" > "$tmp/prop-abs.md"
expect "--check-proposal fails on a task number and an absolute path" 1 - "~a path, a link, an address or a task number" -- --check-proposal "$(winpath "$tmp/prop-abs.md")"
sed 's#^| signature | .*#| signature | stability:guard_false_positives:cart.ts |#' "$here/proposal.md" > "$tmp/prop-sig.md"
expect "--check-proposal fails on a signature naming no core file" 1 - "~a signature outside" -- --check-proposal "$(winpath "$tmp/prop-sig.md")"
sed 's#^| core file | .*#| core file | src/cart.ts |#' "$here/proposal.md" > "$tmp/prop-core.md"
expect "--check-proposal fails on a core file outside the core" 1 - "~a core file that is not in the core" -- --check-proposal "$(winpath "$tmp/prop-core.md")"
grep -v '^Expected gain:' "$here/proposal.md" > "$tmp/prop-short.md"
expect "--check-proposal fails without its Expected gain line" 1 - "retro: the proposal body lacks its Change or Expected gain line" -- --check-proposal "$(winpath "$tmp/prop-short.md")"
expect "--check-public refuses a proposal" 1 - "~a cell outside the allowlist" -- --check-public "$(winpath "$here/proposal.md")"
# a new anonymous id: 12 hex digits, random
expect "--new-id" 0 any - -- --new-id
a="$(cat "$tmp/out")"; run --new-id; b="$(cat "$tmp/out")"
{ [[ $a =~ ^[0-9a-f]{12}$ ]] && [[ $b =~ ^[0-9a-f]{12}$ ]] && [ "$a" != "$b" ]; } || bad "--new-id gave '$a' and '$b'"
# errors
expect "a missing run log" 1 - "~retro: cannot read" -- "$(winpath "$tmp/none.tsv")"
expect "no arguments" 2 any - --
expect "--public without --id" 2 any - -- "$runs" --public
expect "--id without --public" 2 any - -- "$runs" --id "$ID"
expect "an id that is not 12 hex digits" 2 any - -- "$runs" --public --id ACME
expect "a week that is no date" 2 any - -- "$runs" --week 2026-13-01
[ "$fail" = 0 ] && echo "retro: $n cases passed" || echo "retro: failures above ($n cases)"
exit "$fail"
