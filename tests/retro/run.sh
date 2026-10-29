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
      --core-report) a+=(-CoreReport) ;; --check-core-report) a+=(-CheckCoreReport) ;; --since) a+=(-Since) ;;
      --features) a+=(-Features) ;;
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
# the retro report for the core (#303): <RUNS.tsv> --core-report --id <id> [--since <date>] over the fixture project
# core-report/ (a run log over the weeks around its period, its journal and escapes, CHECKLIST.md, PROJECT.md,
# CORE-FINDINGS.md) and a small FEATURES.md. The test hook both modes take: --features <FEATURES.md> (PS: -Features;
# default the core's own FEATURES.md). The period runs to today (UTC): from --since, else the day after the end of
# PROJECT.md's Settings row "Last core report" (<from>..<to>), else the first CHECKLIST line's date; the core
# commits: the CHECKLIST commit in use on the period's first day, then those of its lines in the period; os from
# the machine (windows, macos, linux).
cr="$(winpath "$here/core-report/coordinator/RUNS.tsv")"; cf="$(winpath "$here/core-report/FEATURES.md")"
today="$(date -u +%Y-%m-%d)"
case "$(uname -s)" in Darwin) os=macos ;; Linux) os=linux ;; *) os=windows ;; esac
sed -e "s/@TODAY@/$today/" -e "s/@OS@/$os/" "$here/expected-core-report.md" > "$tmp/expected-core-report.md"
expect "--core-report: the template, the period from Last core report, the five axes, runs, findings, a row per feature" 0 "$tmp/expected-core-report.md" - -- "$cr" --core-report --id "$ID" --features "$cf" --no-insights
cp "$tmp/out" "$tmp/core.md"
expect "--core-report --since: the period and the core commit from that day" 0 any - -- "$cr" --core-report --id "$ID" --since 2026-10-05 --features "$cf" --no-insights
{ grep -qxF "| period | 2026-10-05..$today |" "$tmp/out" && grep -qxF '| core commits | 7c2d4a9 |' "$tmp/out" && grep -qxF '| cost | tasks | 2 |' "$tmp/out"; } ||
  bad "--since 2026-10-05: the period, the core commit 7c2d4a9 or the 2 tasks of the period"
mkdir -p "$tmp/first/coordinator" && cp "$here/core-report/coordinator/"* "$tmp/first/coordinator/"
grep -v '^| Last core report |' "$here/core-report/coordinator/PROJECT.md" > "$tmp/first/coordinator/PROJECT.md"
expect "--core-report, no Last core report: the period from the first CHECKLIST line" 0 any - -- "$(winpath "$tmp/first/coordinator/RUNS.tsv")" --core-report --id "$ID" --features "$cf" --no-insights
{ grep -qxF "| period | 2026-09-01..$today |" "$tmp/out" && grep -qxF '| core commits | 1ebe968, 7c2d4a9 |' "$tmp/out" && grep -qxF '| cost | tasks | 5 |' "$tmp/out"; } ||
  bad "no Last core report: the period from 2026-09-01, both core commits or the 5 tasks"
# the guard numbers from the transcripts over the period, as session-insights gives them for the project's folders
ins="$(CLAUDE_CONFIG_DIR="$cfg" bash "$core/scripts/session-insights.sh" --since 2026-09-28T00:00:00Z --skip-tests --project "$P|$P/.claude/worktrees" 2>/dev/null)"
gsum() { printf '%s\n' "$ins" | awk -F '\t' -v k="$1" -v d="$2" '$1 == "block" && (d == "all" || $2 != "deny rule") { if (match($3, "(^| )" k "=[0-9]+")) { x = substr($3, RSTART, RLENGTH); sub(/.*=/, "", x); s += x } } END { print s + 0 }'; }
gb="$(gsum count guard)"; ga="$(gsum around guard)"; gall="$(gsum count all)"
expect "--core-report with transcripts: the guard's blocks over the period" 0 any - -- "$cr" --core-report --id "$ID" --since 2026-09-28 --project "$P" --features "$cf"
gt="$(awk -F ' [|] ' '/^[|] Guard reason [|]/ { on = 1; next } on && !/^[|]/ { on = 0 } on && $2 ~ /^[0-9]+$/ { s += $2 } END { print s + 0 }' "$tmp/out")"
{ [ "$gb" -gt 0 ] && grep -qxF "| stability | guard_blocks | $gb |" "$tmp/out" && grep -qxF "| stability | guard_around | $ga |" "$tmp/out" && [ "$gt" = "$gall" ]; } ||
  bad "the guard over the period: guard_blocks $gb, guard_around $ga, the reasons' blocks $gall (got $gt)"
# the checker: the generated body is refused at its first <fill>; a filled body passes; one refusal each
expect "--check-core-report refuses the generated body: a <fill> left (line 15)" 1 - "~line 15:" -- --check-core-report "$(winpath "$tmp/core.md")" --features "$cf"
filled="$here/core-report-filled.md"
expect "--check-core-report passes a filled body (start-worker.sh and CORE.md in a cell, a cell of 160 characters)" 0 - - -- --check-core-report "$(winpath "$filled")" --features "$cf"
# repl <line> <text> <file>: the filled body with that line replaced; row <text>: F-WORKERS-01's row (line 105)
# with <text> as its "Decision changed" cell
repl() { R="$2" awk -v n="$1" 'NR == n { $0 = ENVIRON["R"] } { print }' "$filled" > "$tmp/$3"; }
row() { printf '| F-WORKERS-01 | yes | every task | yes | %s | none |' "$1"; }
repl 105 "$(row 'kept merge-queue.ps1 and ONE-TIME.md as they are')" cr-core.md
expect "--check-core-report passes core file names (merge-queue.ps1, ONE-TIME.md)" 0 - - -- --check-core-report "$(winpath "$tmp/cr-core.md")" --features "$cf"
awk 'NR < 70 || NR > 81' "$filled" > "$tmp/cr-missing.md"
expect "--check-core-report refuses a missing section" 1 - "~Runs by role" -- --check-core-report "$(winpath "$tmp/cr-missing.md")" --features "$cf"
repl 70 '## Runs per role' cr-renamed.md
expect "--check-core-report refuses a renamed section" 1 - "~line 70:" -- --check-core-report "$(winpath "$tmp/cr-renamed.md")" --features "$cf"
repl 105 '| F-WORKERS-99 | yes | every task | yes | none | none |' cr-feature.md
expect "--check-core-report refuses a feature row not in FEATURES.md" 1 - "~line 105:" -- --check-core-report "$(winpath "$tmp/cr-feature.md")" --features "$cf"
repl 105 "$(row '<fill>')" cr-fill.md
expect "--check-core-report refuses a <fill> left" 1 - "~line 105:" -- --check-core-report "$(winpath "$tmp/cr-fill.md")" --features "$cf"
repl 105 "$(row 'see https://example.com/notes for it')" cr-url.md
expect "--check-core-report refuses a URL" 1 - "~line 105:" -- --check-core-report "$(winpath "$tmp/cr-url.md")" --features "$cf"
repl 105 "$(row 'asked dev@example.org first')" cr-mail.md
expect "--check-core-report refuses an e-mail" 1 - "~line 105:" -- --check-core-report "$(winpath "$tmp/cr-mail.md")" --features "$cf"
repl 105 "$(row 'asked @someone first')" cr-handle.md
expect "--check-core-report refuses an @handle" 1 - "~line 105:" -- --check-core-report "$(winpath "$tmp/cr-handle.md")" --features "$cf"
repl 105 "$(row 'kept in D:\dev\app for a week')" cr-win.md
expect "--check-core-report refuses a Windows path" 1 - "~line 105:" -- --check-core-report "$(winpath "$tmp/cr-win.md")" --features "$cf"
repl 105 "$(row 'moved under src\cart first')" cr-back.md
expect "--check-core-report refuses a path with a backslash" 1 - "~line 105:" -- --check-core-report "$(winpath "$tmp/cr-back.md")" --features "$cf"
repl 105 "$(row 'moved under /srv/app/cart first')" cr-posix.md
expect "--check-core-report refuses a POSIX path" 1 - "~line 105:" -- --check-core-report "$(winpath "$tmp/cr-posix.md")" --features "$cf"
repl 105 "$(row 'the cart.ts check broke twice')" cr-file.md
expect "--check-core-report refuses a file name that is not the core's" 1 - "~line 105:" -- --check-core-report "$(winpath "$tmp/cr-file.md")" --features "$cf"
sed '104s/hard tasks |/hard tasks! |/' "$filled" > "$tmp/cr-long.md"
expect "--check-core-report refuses a free-text cell over 160 characters" 1 - "~line 104:" -- --check-core-report "$(winpath "$tmp/cr-long.md")" --features "$cf"
# #320: an IPv6 address (:: next to a hex group, or 6 or more colon-separated groups of 1-4 hex digits) and an HTML
# character reference (&#<digits>;, &#x<hex>;, &<letters>;) refused naming the line; a time, a ratio, a:b, a lone &
# and R&D pass; a plain number of 7 or more digits is named as a long number
i=0
for x in 'fe80::1ff:fe23:4567:890a timed out' '2001:db8::7334 down' 'bound to ::1 only' \
         'the 2001:0db8:85a3:0000:0000:8a2e:0370:7334 host' 'asked dev&#64;acme&#46;org first' 'ping &#64;handle' \
         'outage at acme&#x2E;com' 'outage at acme&period;com'; do
  i=$((i + 1)); repl 105 "$(row "$x")" "cr-ref$i.md"
  expect "--check-core-report refuses an IPv6 address or an HTML character reference: $x" 1 - "~line 105:" -- --check-core-report "$(winpath "$tmp/cr-ref$i.md")" --features "$cf"
done
i=0
for x in 'at 12:30:45 it stopped' 'a 1:2:3 split' 'a:b' 'cost & time' 'R&D work'; do
  i=$((i + 1)); repl 105 "$(row "$x")" "cr-colon$i.md"
  expect "--check-core-report passes a time, a ratio, a lone & or R&D: $x" 0 - - -- --check-core-report "$(winpath "$tmp/cr-colon$i.md")" --features "$cf"
done
repl 105 "$(row 'used 2000000 tokens')" cr-num.md
expect "--check-core-report refuses a long number naming it" 1 - "~line 105:" -- --check-core-report "$(winpath "$tmp/cr-num.md")" --features "$cf" &&
  { grep -qF 'long number' "$tmp/err" || { bad "--check-core-report refuses a long number naming it: stderr lacks long number"; sed 's/^/  got: /' "$tmp/err"; }; }
# round 2 (#303): the Profile holds only vocabulary words - strictness swarm/standard/strict, spend level
# lean/balanced/thorough, work mode by task/batch, os windows/macos/linux, solo or team solo/team, stack class
# RETRO.md §8's list (game engine, web, mobile, CLI, library, data, other); the generator prints a Settings Value's
# leading vocabulary word, else <fill>, and nothing else of it
mkdir -p "$tmp/names/coordinator" && cp "$here/core-report/coordinator/"* "$tmp/names/coordinator/"
sed -e 's/^\(| \*\*Strictness\*\* (CORE §3) | \)standard |/\1strict for Contoso Ltd client work |/' \
    -e 's/^\(| \*\*Spend level\*\* (CORE §7) | \)balanced |/\1balanced, ask Ivan |/' \
    -e 's/^\(| \*\*Work mode\*\* (CORE §4) | \)by task |/\1batch over the ACME-JIRA board |/' \
    "$here/core-report/coordinator/PROJECT.md" > "$tmp/names/coordinator/PROJECT.md"
expect "--core-report: Settings Values with names give only their vocabulary word" 0 any - -- "$(winpath "$tmp/names/coordinator/RUNS.tsv")" --core-report --id "$ID" --features "$cf" --no-insights
{ grep -qxF '| strictness | strict |' "$tmp/out" && grep -qxF '| spend level | balanced |' "$tmp/out" && grep -qxF '| work mode | batch |' "$tmp/out"; } ||
  { bad "the Profile: strict, balanced and batch only"; grep '^| \(strictness\|spend level\|work mode\) |' "$tmp/out" | sed 's/^/  got: /'; }
n=$((n + 1)); if grep -qE 'Contoso|Ivan|ACME' "$tmp/out"; then bad "a name from the Settings Values in the body"; grep -nE 'Contoso|Ivan|ACME' "$tmp/out" | sed 's/^/  got: /'; else echo "ok   no name from the Settings Values in the body"; fi
sed -e 's/^\(| \*\*Strictness\*\* (CORE §3) | \)standard |/\1as Contoso wants |/' \
    -e 's/^\(| \*\*Spend level\*\* (CORE §7) | \)balanced |/\1ask Ivan first |/' \
    -e 's/^\(| \*\*Work mode\*\* (CORE §4) | \)by task |/\1per ACME sprint |/' \
    "$here/core-report/coordinator/PROJECT.md" > "$tmp/names/coordinator/PROJECT.md"
expect "--core-report: a Settings Value with no vocabulary word gives <fill>" 0 any - -- "$(winpath "$tmp/names/coordinator/RUNS.tsv")" --core-report --id "$ID" --features "$cf" --no-insights
{ grep -qxF '| strictness | <fill> |' "$tmp/out" && grep -qxF '| spend level | <fill> |' "$tmp/out" && grep -qxF '| work mode | <fill> |' "$tmp/out" && ! grep -qE 'Contoso|Ivan|ACME' "$tmp/out"; } ||
  { bad "the Profile: <fill> for a Value with no vocabulary word"; grep '^| \(strictness\|spend level\|work mode\) |' "$tmp/out" | sed 's/^/  got: /'; }
# the checker holds the Profile cells (lines 15-20 of the filled body) to the same vocabularies
repl 19 '| work mode | batch over the ACME board |' cr-mode.md
expect "--check-core-report refuses a work mode outside its vocabulary" 1 - "~line 19:" -- --check-core-report "$(winpath "$tmp/cr-mode.md")" --features "$cf"
repl 17 '| strictness | strict for Contoso |' cr-strict.md
expect "--check-core-report refuses a strictness outside its vocabulary" 1 - "~line 17:" -- --check-core-report "$(winpath "$tmp/cr-strict.md")" --features "$cf"
repl 18 '| spend level | balanced, ask Ivan |' cr-spend.md
expect "--check-core-report refuses a spend level outside its vocabulary" 1 - "~line 18:" -- --check-core-report "$(winpath "$tmp/cr-spend.md")" --features "$cf"
repl 15 '| stack class | the Contoso shop |' cr-stack.md
expect "--check-core-report refuses a stack class outside its vocabulary" 1 - "~line 15:" -- --check-core-report "$(winpath "$tmp/cr-stack.md")" --features "$cf"
repl 16 '| solo or team | team of Ivan |' cr-team.md
expect "--check-core-report refuses a solo or team outside its vocabulary" 1 - "~line 16:" -- --check-core-report "$(winpath "$tmp/cr-team.md")" --features "$cf"
repl 20 '| os | windows on the Contoso laptop |' cr-os.md
expect "--check-core-report refuses an os outside its vocabulary" 1 - "~line 20:" -- --check-core-report "$(winpath "$tmp/cr-os.md")" --features "$cf"
repl 15 '| stack class | game engine |' cr-stack-ok.md
expect "--check-core-report passes a stack class from the list (game engine)" 0 - - -- --check-core-report "$(winpath "$tmp/cr-stack-ok.md")" --features "$cf"
# host names and addresses with ordinary punctuation around them, each refused naming its line
i=0
for x in "acme.com's API" 'outage at acme.com—twice' 'see(acme.com) for it' 'acme.com:8080 timed out' 'see [docs](acme.com) first' \
         'server 203.0.113.7 timed out' 'dev[at]example.org asked' 'dev(at)example.org'; do
  i=$((i + 1)); repl 105 "$(row "$x")" "cr-host$i.md"
  expect "--check-core-report refuses a host or an address: $x" 1 - "~line 105:" -- --check-core-report "$(winpath "$tmp/cr-host$i.md")" --features "$cf"
done
repl 105 "$(row "the start-worker.sh's output and CORE.md—§4 were clear")" cr-core-punct.md
expect "--check-core-report passes core file names with punctuation (start-worker.sh's, CORE.md—§4)" 0 - - -- --check-core-report "$(winpath "$tmp/cr-core-punct.md")" --features "$cf"
# --check-core-report <file> [--features <file>] --project <folder> (PS -Project): the folder's name as a whole
# word, in any case; without --project the name is not checked
repl 105 "$(row 'the Acme-Shop board was slow')" cr-proj.md
expect "--check-core-report --project refuses the project folder's name" 1 - "~line 105:" -- --check-core-report "$(winpath "$tmp/cr-proj.md")" --features "$cf" --project "$P"
expect "--check-core-report without --project does not check the name" 0 - - -- --check-core-report "$(winpath "$tmp/cr-proj.md")" --features "$cf"
repl 105 "$(row 'the acme-shopping board was slow')" cr-proj-part.md
expect "--check-core-report --project passes the name inside a longer word" 0 - - -- --check-core-report "$(winpath "$tmp/cr-proj-part.md")" --features "$cf" --project "$P"
expect "--check-core-report --project passes a filled body without the name" 0 - - -- --check-core-report "$(winpath "$filled")" --features "$cf" --project "$P"
# a commit id (a hex token of 7 or more digits) in free text; an HTML comment after line 1
repl 105 "$(row 'reverted 1ebe968 and moved on')" cr-hex.md
expect "--check-core-report refuses a commit id in free text" 1 - "~line 105:" -- --check-core-report "$(winpath "$tmp/cr-hex.md")" --features "$cf"
repl 105 "$(row 'a big brief <!-- the cart --> went through a file')" cr-comment.md
expect "--check-core-report refuses an HTML comment in a cell" 1 - "~line 105:" -- --check-core-report "$(winpath "$tmp/cr-comment.md")" --features "$cf"
repl 118 '| <!-- let the guard name the branch |' cr-comment2.md
expect "--check-core-report refuses <!-- in a proposal" 1 - "~line 118:" -- --check-core-report "$(winpath "$tmp/cr-comment2.md")" --features "$cf"
# at most 3 proposals
awk 'NR == 118 { print; print "| a shorter brief |"; print "| a quieter guard |"; next } { print }' "$filled" > "$tmp/cr-prop3.md"
expect "--check-core-report passes 3 proposals" 0 - - -- --check-core-report "$(winpath "$tmp/cr-prop3.md")" --features "$cf"
awk 'NR == 118 { print; print "| a shorter brief |"; print "| a quieter guard |"; print "| a fourth idea |"; next } { print }' "$filled" > "$tmp/cr-prop4.md"
expect "--check-core-report refuses a fourth proposal" 1 - "~line 121:" -- --check-core-report "$(winpath "$tmp/cr-prop4.md")" --features "$cf"
# errors
expect "--core-report without --id" 2 any - -- "$cr" --core-report --features "$cf"
expect "--core-report with a --since that is no date" 2 any - -- "$cr" --core-report --id "$ID" --since 2026-13-01 --features "$cf"
expect "--check-core-report of a missing file" 1 - "~retro: cannot read" -- --check-core-report "$(winpath "$tmp/none.md")" --features "$cf"
[ "$fail" = 0 ] && echo "retro: $n cases passed" || echo "retro: failures above ($n cases)"
exit "$fail"
