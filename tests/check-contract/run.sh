#!/usr/bin/env bash
# check-contract on the contracts in this folder, a UTF-8 BOM copy of tests/selftest/contract.md and a
# file that does not exist: the output must equal expected.txt, line for line, from either version.
# On Windows the .ps1 runs as on a Russian Windows, with the console's code page 866: the section signs
# of its warnings (CORE §7) must still come out as UTF-8, and the caller's 866 must be back afterwards,
# after a usage error (exit 2) and after a run to the end.
# Then --runs (#333) on runs-ordinary.md and its variants against runs.tsv: a budget inside the range, cost
# above and below, time outside, the kind from --kind, a full model name, a thin history, a missing log, a
# failing contract, and no --runs as today; round 2: the plan line, full ids in the log (runs-full.tsv) for a
# short budget.model with the newest of two winning, and a model with no ratio yet.
# --runs, the access point (#333): `check-contract.sh <contract> --runs <RUNS.tsv> [--kind <k>]` (.ps1: -Runs
# <RUNS.tsv> [-Kind <k>]; the options after the contract). The kind: the contract's top-level `kind:` field,
# else --kind. The model, matched both ways (round 2): budget.model as run-stats lists it; else a full name
# in budget.model holding a listed short name (claude-opus-5-5 is opus); else the full ids in the log holding
# a short budget.model (opus finds claude-opus-5-5) - several of them: the model of the log's newest row
# among them (runs-full.tsv: claude-opus-5-5, its rows last and latest). That resolved name is the <model> of
# every line below and the --model of the --ratio lookup. After the contract's own checks, from run-stats'
# line for that kind and model:
#   a pair with history: always exactly one plan line, a WARN after it or not (key words, in this order)
#     `<file>: run-stats <kind>/<model>: ... median <cost_median>, range <cost_low>-<cost_high> ... <n> tasks`
#   (e.g. `cost median 6.00, range 5.00-7.00, time median 40, range 30-50, 5 tasks`);
#   4 or more tasks: budget.cost outside cost_low..cost_high prints the line
#     `<file>: WARN  budget.cost <cost> is outside run-stats <kind>/<model>: median <m>, range <low>-<high>, <n> tasks`
#   and budget.time outside time_low..time_high the same with `budget.time <time>` and the time columns;
#   inside the range: no such line;
#   under 4 tasks: one line `<file>: thin history: <n> tasks; this model's runs came in at <R>× their estimates`
#   (R: cost_ratio of `run-stats <RUNS.tsv> --ratio --model <m>`), and no budget WARN line; a model with no
#   ratio (cost_ratio `-`): the line ends `... runs came in at no ratio yet` in place of `<R>× their estimates`
#   - the words `no ratio yet`, never `-×`;
#   a run log it cannot read: a line `<file>: WARN  ...` naming the log.
#   Never an ERROR from --runs: the exit code is the one without it. Without --runs the output is today's.
# The guard on tests_first: no (#334), the access point: when `tests_first` is `no ...` and the contract's
# title, intent or touches (nothing else: not inputs, outputs, non_goals or the body below the header) hold a
# word of this list, held in the script header in this order:
#   payment price billing invoice refund money role permission auth access customer "personal data" pii gdpr
# then one WARN line, counted in the summary's warnings like the others, never an ERROR, the exit unchanged:
#   `<file>: WARN  tests_first is no, but <field> names `<word>` (money, roles or customer data): tests first
#   are expected for such a change (CORE §4 step 3)` - the key words, checked: `<file>: WARN  `, `tests_first`,
#   `<field> names `<word>`` (field: title / intent / touches; the word as the list writes it, lower case),
#   `tests first are expected`. Matching: any letter case; a whole word - the letter or digit before it and
#   after it (an optional plural `s` aside: roles, permissions) is no letter or digit, so `_ - / . '` and blanks
#   bound it (auth_token.sh, billing.sh, customer's match; rolex, accessible, priceless, prepayment,
#   customers2 do not); `personal data`: one or more blanks, `-` or `_` between the two words. Several
#   matches: one line only - the first field in the order title, intent, touches, and in it the list's first
#   word it holds. `tests_first: yes ...` or no match: no such line, the output as today.
#   tests/check-contract/run.sh sh                  # check-contract.sh, with the bash running this file
#   tests/check-contract/run.sh ps pwsh             # check-contract.ps1 (or: ps powershell)
# Exit 1 if the output or the exit code differs.
set -u
[ $# -gt 0 ] || { sed -n '2,47s/^# \{0,1\}//p' "$0"; exit 2; }
kind="$1"; shift; PS=("$@")
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -r "$tmp"' EXIT
win=""; command -v cygpath >/dev/null 2>&1 && { win=1; core="$(cygpath -m "$core")"; }
cp "$here"/*.md "$here"/*.tsv "$tmp/"
# and a body line that reads like a key: below the header it is not part of the contract
{ printf '\357\273\277'; cat "$core/tests/selftest/contract.md"; printf 'acceptance: is read from the header only\n'; } > "$tmp/bom.md"
files=(how-in-text.md quoted.md empty-id-title.md misplaced.md empty-how.md commented-defaults.md budget-time.md budget-time-ok.md feature-scope.md tests-first-missing.md tests-first-bad.md tests-first-no-reason.md bom.md missing.md)
cd "$tmp" || exit 1
if [ "$kind" = ps ] && [ -n "$win" ]; then
  a=""; for f in "${files[@]}"; do a="$a '$f'"; done
  "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -Command "\$o = [Console]::OutputEncoding; try { [Console]::OutputEncoding = [Text.Encoding]::GetEncoding(866) } catch { }; & '$core/scripts/check-contract.ps1'$a; \$rc = \$LASTEXITCODE; try { [Console]::OutputEncoding = \$o } catch { }; exit \$rc" > out.txt 2>&1
elif [ "$kind" = ps ]; then "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$core/scripts/check-contract.ps1" "${files[@]}" > out.txt 2>&1
else bash "$core/scripts/check-contract.sh" "${files[@]}" > out.txt 2>&1; fi
rc=$?
fail=0
[ "$rc" = 1 ] || { echo "FAIL: expected exit 1, got $rc"; fail=1; }
tr -d '\r' < "$here/expected.txt" > want.txt   # a Windows checkout may hold it with CRLF
tr -d '\r' < out.txt | diff want.txt - || { echo "FAIL: the output differs from tests/check-contract/expected.txt (< expected, > got)"; fail=1; }
if [ "$kind" = ps ] && [ -n "$win" ]; then
  # the script switches to UTF-8 and gives the caller its own encoding back on every way out
  for a in "" " 'quoted.md'"; do
    got="$("${PS[@]}" -NoProfile -ExecutionPolicy Bypass -Command "try { [Console]::OutputEncoding = [Text.Encoding]::GetEncoding(866) } catch { 'cp=skip'; exit 0 }; \$null = & '$core/scripts/check-contract.ps1'$a; 'cp=' + [Console]::OutputEncoding.CodePage" 2>&1 | tr -d '\r' | tail -n 1)"
    case "$got" in cp=866) ;; cp=skip) echo "check-contract: no code page 866 here, the restore not checked" ;;
      *) echo "FAIL: the caller's encoding is not back after check-contract.ps1$a (expected cp=866): $got"; fail=1 ;; esac
  done
fi
# the read-only option that prints a key's value as check-contract's own extraction reads it (#276: the
# tests_first gate of start-worker takes it from here): the key's text with its continuation lines, the
# comment and quotes removed, on one line, exit 0 when the contract passes; else the usual errors and exit.
# The worker names the option: set fopt to that name (`--<fopt> tests_first <file>` / `-<fopt> ...`)
fopt=field
sed 's/^tests_first: yes$/tests_first: yes   # the oracles have no tests yet/' budget-time-ok.md > tf-comment.md
tr '\n' '\r' < budget-time-ok.md > tf-cr.md
cfield() {   # cfield <file>: the option's output (no CRs) in FO, its exit in FRC; check-contract's own exit in PRC
  if [ "$kind" = ps ]; then
    FO="$("${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$core/scripts/check-contract.ps1" "-$fopt" tests_first "$1" 2>&1)"; FRC=$?
    "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$core/scripts/check-contract.ps1" "$1" > /dev/null 2>&1; PRC=$?
  else
    FO="$(bash "$core/scripts/check-contract.sh" "--$fopt" tests_first "$1" 2>&1)"; FRC=$?
    bash "$core/scripts/check-contract.sh" "$1" > /dev/null 2>&1; PRC=$?
  fi
  FO="$(printf '%s\n' "$FO" | tr -d '\r')"
}
fval() {   # fval <file> <extended regex for the whole one line>: passes, and prints exactly that value
  cfield "$1"
  [ "$FRC" = 0 ] && [ "$(printf '%s\n' "$FO" | grep -c .)" = 1 ] && printf '%s\n' "$FO" | grep . | grep -Eq "^$2\$" ||
    { echo "FAIL: $fopt tests_first $1: expected exit 0 and one line matching '$2', got exit $FRC:"; printf '%s\n' "$FO" | sed 's/^/    /'; fail=1; }
}
fval budget-time-ok.md 'yes'
fval quoted.md 'no - tests/sort.sh and tests/empty.sh exist'
fval tf-comment.md 'yes'
fval tests-first-span.md 'yes, because[[:space:]]+it is cheap'
fval tests-first-span-single.md 'yes, because[[:space:]]+it is cheap'
for f in tests-first-no-reason.md tests-first-missing.md missing.md; do
  cfield "$f"
  [ "$FRC" = 1 ] || { echo "FAIL: $fopt tests_first $f: expected exit 1 (the contract fails), got $FRC"; fail=1; }
  case "$f:$FO" in tests-first-no-reason.md:*"ERROR \`tests_first\` is neither"*|tests-first-missing.md:*"ERROR missing \`tests_first\`"*|missing.md:*"cannot read"*) ;;
    *) echo "FAIL: $fopt tests_first $f: check-contract's usual error is not there:"; printf '%s\n' "$FO" | sed 's/^/    /'; fail=1 ;; esac
done
# whatever check-contract makes of a CR-only file, the option says the same (pass and the value, or fail)
cfield tf-cr.md
[ "$FRC" = "$PRC" ] || { echo "FAIL: $fopt tests_first tf-cr.md exits $FRC, check-contract itself $PRC"; printf '%s\n' "$FO" | sed 's/^/    /'; fail=1; }
[ "$PRC" != 0 ] || fval tf-cr.md 'yes'
# usage parity (#288 item 1): the option with no key, and with an empty key, prints the usage (the header's
# first line) and exits 2 in both shells - never a binding error, never the plain check
for a in none empty; do
  if [ "$kind" = ps ] && [ $a = none ]; then FO="$("${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$core/scripts/check-contract.ps1" "-$fopt" 2>&1)"; FRC=$?
  elif [ "$kind" = ps ]; then FO="$("${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$core/scripts/check-contract.ps1" "-$fopt" '' budget-time-ok.md 2>&1)"; FRC=$?
  elif [ $a = none ]; then FO="$(bash "$core/scripts/check-contract.sh" "--$fopt" 2>&1)"; FRC=$?
  else FO="$(bash "$core/scripts/check-contract.sh" "--$fopt" '' budget-time-ok.md 2>&1)"; FRC=$?; fi
  [ "$FRC" = 2 ] && case "$FO" in *"Check a contract"*) true ;; *) false ;; esac ||
    { echo "FAIL: $fopt with key $a: expected the usage and exit 2, got exit $FRC:"; printf '%s\n' "$FO" | tr -d '\r' | sed 's/^/    /'; fail=1; }
done
# --runs (#333): the budget against the run log's line (the header: the access point)
# the variants from an LF copy: a Windows checkout may hold runs-ordinary.md with CRLF, and sed's $ is before the \r
tr -d '\r' < runs-ordinary.md > runs-lf.md
sed 's/^  cost: 6$/  cost: 9/' runs-lf.md > runs-above.md
sed 's/^  cost: 6$/  cost: 3/' runs-lf.md > runs-below.md
sed 's/^  time: 40$/  time: 90/' runs-lf.md > runs-time.md
sed -e '/^kind: /d' -e 's/^  cost: 6$/  cost: 9/' runs-lf.md > runs-nokind.md
sed -e 's/^  model: opus$/  model: claude-opus-5-5/' -e 's/^  cost: 6$/  cost: 9/' runs-lf.md > runs-full.md
sed 's/^kind: ordinary$/kind: hard/' runs-lf.md > runs-thin.md
crun() {   # crun <arguments>: check-contract's output (no CRs) in CO, its exit in CRC
  if [ "$kind" = ps ]; then
    local a=() x; for x in "$@"; do case "$x" in --runs) a+=(-Runs) ;; --kind) a+=(-Kind) ;; *) a+=("$x") ;; esac; done
    CO="$("${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$core/scripts/check-contract.ps1" "${a[@]}" 2>&1)"; CRC=$?
  else CO="$(bash "$core/scripts/check-contract.sh" "$@" 2>&1)"; CRC=$?; fi
  CO="$(printf '%s\n' "$CO" | tr -d '\r')"
}
rfail() { echo "FAIL: runs $rname: $1 (exit $CRC):"; printf '%s\n' "$CO" | sed 's/^/    /'; fail=1; }
rexit() { [ "$CRC" = "$1" ] || rfail "exit $CRC, want $1"; }
rhas() { printf '%s\n' "$CO" | grep -qF -- "$1" || rfail "no line with: $1"; }
rhasnt() { ! printf '%s\n' "$CO" | grep -qE -- "$1" || rfail "a line matches: $1"; }
cost9='budget.cost 9 is outside run-stats ordinary/opus: median 6.00, range 5.00-7.00, 5 tasks'
rname="a budget inside the range"; crun runs-ordinary.md --runs runs.tsv
rexit 0; rhasnt 'WARN|ERROR|thin history|cannot read'
rname="cost above the range"; crun runs-above.md --runs runs.tsv
rexit 0; rhas "runs-above.md: WARN  $cost9"; rhasnt 'WARN  budget\.time|ERROR|cannot read'
rname="cost below the range"; crun runs-below.md --runs runs.tsv
rexit 0; rhas 'runs-below.md: WARN  budget.cost 3 is outside run-stats ordinary/opus: median 6.00, range 5.00-7.00, 5 tasks'
rhasnt 'ERROR|cannot read'
rname="time outside the range"; crun runs-time.md --runs runs.tsv
rexit 0; rhas 'runs-time.md: WARN  budget.time 90 is outside run-stats ordinary/opus: median 40, range 30-50, 5 tasks'
rhasnt 'WARN  budget\.cost|ERROR|cannot read'
rname="no kind field: the kind from --kind"; crun runs-nokind.md --runs runs.tsv --kind ordinary
rexit 0; rhas "runs-nokind.md: WARN  $cost9"; rhasnt 'ERROR|cannot read'
rname="budget.model as the ladder's full name"; crun runs-full.md --runs runs.tsv
rexit 0; rhas "runs-full.md: WARN  $cost9"; rhasnt 'ERROR|cannot read'
rname="under 4 tasks: the thin-history line with the model's ratio"; crun runs-thin.md --runs runs.tsv
rexit 0; rhas "runs-thin.md: thin history: 1 tasks; this model's runs came in at 0.55× their estimates"
rhasnt 'WARN  budget|ERROR|cannot read'
rname="a missing run log is a WARN"; crun runs-ordinary.md --runs missing-runs.tsv
rexit 0; printf '%s\n' "$CO" | grep -qE '^runs-ordinary\.md: WARN  .*missing-runs\.tsv' || rfail "no WARN line naming missing-runs.tsv"
rhasnt 'ERROR'
rname="a failing contract keeps its errors and exit"; crun how-in-text.md --runs runs.tsv
rexit 1; rhas 'how-in-text.md: ERROR criterion 1: oracle check without `how`'; rhasnt 'cannot read'
rname="no --runs: as today"; crun runs-above.md
rexit 0; [ "$CO" = 'runs-above.md: OK (0 errors, 0 warnings)' ] || rfail "the output is not today's"
# round 2 (#333, PR #359): the plan line, models matched both ways, no ratio yet (the header)
rplan() {   # rplan <file> <kind/model> <median> <low-high> <n>: exactly one plan line, with those key words
  local re="^$1: run-stats $2: .*median $3, range $4.*[^0-9]$5 tasks"
  [ "$(printf '%s\n' "$CO" | grep -c "^$1: run-stats ")" = 1 ] || rfail "not exactly one plan line ($1: run-stats ...)"
  printf '%s\n' "$CO" | grep -qE -- "$re" || rfail "no plan line matching: $re"
}
rname="the plan line: a budget inside the range"; crun runs-ordinary.md --runs runs.tsv
rexit 0; rplan 'runs-ordinary\.md' 'ordinary/opus' '6\.00' '5\.00-7\.00' 5; rhasnt 'WARN|ERROR|thin history'
rname="the plan line: before a WARN"; crun runs-above.md --runs runs.tsv
rexit 0; rplan 'runs-above\.md' 'ordinary/opus' '6\.00' '5\.00-7\.00' 5; rhas "runs-above.md: WARN  $cost9"
# full ids in the log, a short budget.model: the newest of claude-opus-4-7 (older rows, cost 18-22) and
# claude-opus-5-5 (newer rows, cost 4-8) wins; the swapped log makes claude-opus-4-7 the newest
sed -e 's/claude-opus-4-7/claude-opus-x-x/g' -e 's/claude-opus-5-5/claude-opus-4-7/g' -e 's/claude-opus-x-x/claude-opus-5-5/g' runs-full.tsv > runs-swap.tsv
rname="full ids, short budget.model, in range"; crun runs-ordinary.md --runs runs-full.tsv
rexit 0; rplan 'runs-ordinary\.md' 'ordinary/claude-opus-5-5' '6\.00' '5\.00-7\.00' 5
rhasnt 'WARN|ERROR|thin history|cannot read|claude-opus-4-7'
rname="full ids, short budget.model, above"; crun runs-above.md --runs runs-full.tsv
rexit 0; rhas 'runs-above.md: WARN  budget.cost 9 is outside run-stats ordinary/claude-opus-5-5: median 6.00, range 5.00-7.00, 5 tasks'
rhasnt 'WARN  budget\.time|ERROR|thin history|claude-opus-4-7'
rname="full ids, the other one newest"; crun runs-above.md --runs runs-swap.tsv
rexit 0; rplan 'runs-above\.md' 'ordinary/claude-opus-4-7' '6\.00' '5\.00-7\.00' 5
rhas 'runs-above.md: WARN  budget.cost 9 is outside run-stats ordinary/claude-opus-4-7: median 6.00, range 5.00-7.00, 5 tasks'
rhasnt 'ERROR|thin history|claude-opus-5-5'
rname="full ids, thin history: the resolved model's ratio"; crun runs-thin.md --runs runs-full.tsv
rexit 0; rhas "runs-thin.md: thin history: 1 tasks; this model's runs came in at 0.55× their estimates"
rhasnt 'WARN  budget|ERROR|-×'
# no ratio: no estimates in the log, and a model the log does not hold
awk -F '\t' 'BEGIN { OFS = "\t" } NR > 1 && !/^#/ && NF > 7 { $7 = "-" } { print }' runs.tsv > runs-noest.tsv
sed 's/^  model: opus$/  model: sonnet/' runs-lf.md > runs-sonnet.md
rname="no ratio yet: no estimates"; crun runs-thin.md --runs runs-noest.tsv
rexit 0; rhas 'runs-thin.md: thin history: 1 tasks'; rhas 'no ratio yet'; rhasnt '-×|ERROR'
rname="no ratio yet: a model not in the log"; crun runs-sonnet.md --runs runs.tsv
rexit 0; rhas 'runs-sonnet.md: thin history: 0 tasks'; rhas 'no ratio yet'; rhasnt '-×|ERROR|WARN  budget'
# tests_first: no on money, roles or customer data (#334): one WARN line, never an error (the header)
tr -d '\r' < tests-first-guard.md > g-base.md
sed 's/^title: .*/title: Round the Price on the receipt/' g-base.md > g-title.md
sed 's/^  stays as it was\.$/  stays as it was, as on an invoice./' g-base.md > g-intent.md
sed 's/^touches: .*/touches: [scripts\/billing.sh, tests\/sort.sh]/' g-base.md > g-touches.md
sed 's/^tests_first: .*/tests_first: yes/' g-touches.md > g-yes.md
sed 's/^tests_first: .*/tests_first: yes - the guard has no test yet/' g-title.md > g-yes-reason.md
sed 's/^title: .*/title: Give new users the admin ROLES/' g-base.md > g-role.md
sed -e 's/^intent: >$/intent: Permissions are read once at start-up./' -e '/^  The list is sorted/d' -e '/^  stays as it was/d' g-base.md > g-perm.md
sed "s/^  The list is sorted/  The customer's list is sorted/" g-base.md > g-customer.md
sed 's/^title: .*/title: Keep personal  data out of the log/' g-base.md > g-personal.md
sed 's/^touches: .*/touches: [scripts\/pii-export.sh]/' g-base.md > g-pii.md
sed 's/^title: .*/title: "Clean the GDPR log"/' g-base.md > g-gdpr.md
sed 's/^touches: .*/touches: [scripts\/auth_token.sh]/' g-base.md > g-auth.md
sed -e 's/^title: .*/title: Sort the access list and the money list/' -e 's/^touches: .*/touches: [scripts\/billing.sh]/' g-base.md > g-two.md
sed -e 's/^title: .*/title: Sort the rolex, accessible and priceless lists/' \
    -e 's/^  stays as it was\.$/  stays as it was: an authority, a moneyed customers2 and repayments are no words of the list./' \
    -e 's/^touches: .*/touches: [scripts\/prepayment.sh, scripts\/roleplay.sh]/' g-base.md > g-inner.md
gfail() { echo "FAIL: guard $gname: $1 (exit $CRC):"; printf '%s\n' "$CO" | sed 's/^/    /'; fail=1; }
gwarn() {   # gwarn <file> <field> <word>: exit 0, exactly one guard line naming the field and the word, counted
  crun "$1"
  [ "$CRC" = 0 ] || gfail "exit $CRC, want 0"
  [ "$(printf '%s\n' "$CO" | grep -c 'tests first are expected')" = 1 ] || gfail "not exactly one line with 'tests first are expected'"
  printf '%s\n' "$CO" | grep -F -- "$1: WARN  " | grep -F -- 'tests_first' | grep -F -- "$2 names \`$3\`" | grep -qF 'tests first are expected' ||
    gfail "no line '$1: WARN  ...tests_first...$2 names \`$3\`...tests first are expected...'"
  printf '%s\n' "$CO" | grep -qxF -- "$1: OK (0 errors, 1 warnings)" || gfail "the summary is not '$1: OK (0 errors, 1 warnings)'"
}
gnone() {   # gnone <file>: exit 0 and only the clean summary - no guard line, no warning
  crun "$1"
  [ "$CRC" = 0 ] || gfail "exit $CRC, want 0"
  [ "$CO" = "$1: OK (0 errors, 0 warnings)" ] || gfail "want only '$1: OK (0 errors, 0 warnings)'"
}
gname="an unrelated contract (words in inputs and the body)"; gnone g-base.md
gname="a money word in the title, any case"; gwarn g-title.md title price
gname="a money word in the intent's second line"; gwarn g-intent.md intent invoice
gname="a money word in touches"; gwarn g-touches.md touches billing
gname="the same with tests_first: yes"; gnone g-yes.md
gname="yes with a reason"; gnone g-yes-reason.md
gname="a role word, plural, upper case"; gwarn g-role.md title role
gname="a permission word, plural, in a one-line intent"; gwarn g-perm.md intent permission
gname="a customer word before an apostrophe"; gwarn g-customer.md intent customer
gname="personal data, two words"; gwarn g-personal.md title 'personal data'
gname="PII in a file name"; gwarn g-pii.md touches pii
gname="GDPR in a quoted title"; gwarn g-gdpr.md title gdpr
gname="auth before an underscore"; gwarn g-auth.md touches auth
gname="two fields: the first field, the list's first word"; gwarn g-two.md title money
gname="words inside other words"; gnone g-inner.md
echo "check-contract ($kind): $( [ $fail = 0 ] && echo all pass || echo FAILURES )"
exit $fail
