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
# The core's own role files (#362), the access point: in touches only, an item `roles/<file>` or
#   `coordinator/core/roles/<file>`, also with a leading `./`, where <file> exists in the roles/ folder of
#   the core the running check-contract belongs to (its own ../roles/, not the working directory's), is not
#   read for the word list; the other items of touches still are; title and intent as above. A project's own
#   roles/admin.md (no such core file), src/auth/roles.ts, app/models/role.rb, `roles/` alone still warn;
#   a core with no roles/ folder leaves nothing out. Checked from copies of the scripts (nocore, onlyworker).
#   tests/check-contract/run.sh sh                  # check-contract.sh, with the bash running this file
#   tests/check-contract/run.sh ps pwsh             # check-contract.ps1 (or: ps powershell)
# Exit 1 if the output or the exit code differs.
# Important components (#381), the access point: a contract one of whose `touches` items (flow or block list, quotes
# aside) a glob of the list matches - the whole path from the root, `*` crosses folders, `**/` is zero or more folders (#529) - must carry `bounds:` (lines
# `- <glob> <max added lines>`, each a whole number, at least one; the bounds' globs need not be the important one)
# and `wall:` (one non-empty line). Missing or malformed: one ERROR per missing or malformed field, its line
# `<file>: ERROR ...` holding the word `bounds` or `wall` and the important glob; the exit and summary as any ERROR.
# The list: the defaults `scripts/hooks/* .github/workflows/* tests/*/run.*` and the row *Important components* of
# the project's PROJECT.md, a space-separated list; PROJECT.md is the file two folders above the script's own
# folder (a project's core copy: coordinator/core/scripts/ reads coordinator/PROJECT.md); the row by its name as the
# retro reads Settings rows (before a "(", without ** and backticks), the value cell without its backticks; `<fill>` adds
# nothing; no file or no row: the defaults alone. A project adds, never removes. Touching none: no new line.
# A touches item that is a folder holding a glob of the list (`tests/`, `scripts/`, `scripts/hooks/`, `.github/`, the
# item with its slash the start of the glob) counts as touching it, the ERROR naming that glob; `docs/` does not.
# So does a folder under a glob's wildcard, where a file of that folder could match it: `tests/retro/` for `tests/*/run.*`.
# A bound on tests (#390), the access point: `tests_first` is `yes` (with a reason or not) and no line `- <glob> <max>` stands
# under `bounds:` (an empty key or a comment alone is no line): in every mode (plain, --field, --runs) one ERROR, this text:
#   <file>: ERROR `tests_first` is yes but `bounds` has no line (`- <glob> <max added lines>`): name the size of the tests this task adds (CONTRACT.md)
# `tests_first: no ...`: nothing new. A contract touching an important file keeps its own ERROR, beside this one; a malformed line there (`- x lots`) is a line: its own malformed ERROR alone.
set -u
[ $# -gt 0 ] || { sed -n '2,53s/^# \{0,1\}//p' "$0"; exit 2; }
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
tr -d '\r' < budget-time-ok.md | awk '{ printf "%s\r\n", $0 }' > tf-crlf.md
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
for f in tests-first-missing.md; do
  cfield "$f"
  [ "$FRC" = 1 ] || { echo "FAIL: $fopt tests_first $f: expected exit 1 (the contract fails), got $FRC"; fail=1; }
  case "$f:$FO" in tests-first-no-reason.md:*"ERROR \`tests_first\` is neither"*|tests-first-missing.md:*"ERROR missing \`tests_first\`"*|missing.md:*"cannot read"*) ;;
    *) echo "FAIL: $fopt tests_first $f: check-contract's usual error is not there:"; printf '%s\n' "$FO" | sed 's/^/    /'; fail=1 ;; esac
done
# a CRLF contract (a Windows checkout holds them): the same value as from its LF original
fval tf-crlf.md 'yes'
# usage parity (#288 item 1): the option with no key, and with an empty key, prints the usage (the header's
# first line) and exits 2 in both shells - never a binding error, never the plain check
for a in none; do
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
sed 's/^  time: 40$/  time: 90/' runs-lf.md > runs-time.md
sed -e '/^kind: /d' -e 's/^  cost: 6$/  cost: 9/' runs-lf.md > runs-nokind.md
sed -e 's/^  model: opus$/  model: claude-opus-5-5/' -e 's/^  cost: 6$/  cost: 9/' runs-lf.md > runs-full.md
sed 's/^kind: ordinary$/kind: hard/' runs-lf.md > runs-thin.md
crun() {   # crun <arguments>: check-contract's output (no CRs) in CO, its exit in CRC
  if [ "$kind" = ps ]; then
    local a=() x; for x in "$@"; do case "$x" in --runs) a+=(-Runs) ;; --kind) a+=(-Kind) ;; *) a+=("$x") ;; esac; done
    CO="$("${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "${ccore:-$core}/scripts/check-contract.ps1" "${a[@]}" 2>&1)"; CRC=$?
  else CO="$(bash "${ccore:-$core}/scripts/check-contract.sh" "$@" 2>&1)"; CRC=$?; fi
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
# full ids in the log, a short budget.model: the newest of claude-opus-4-7 (older rows, cost 18-22) and
# claude-opus-5-5 (newer rows, cost 4-8) wins
rname="full ids, short budget.model, in range"; crun runs-ordinary.md --runs runs-full.tsv
rexit 0; rplan 'runs-ordinary\.md' 'ordinary/claude-opus-5-5' '6\.00' '5\.00-7\.00' 5
rhasnt 'WARN|ERROR|thin history|cannot read|claude-opus-4-7'
# no ratio: no estimates in the log
awk -F '\t' 'BEGIN { OFS = "\t" } NR > 1 && !/^#/ && NF > 7 { $7 = "-" } { print }' runs.tsv > runs-noest.tsv
rname="no ratio yet: no estimates"; crun runs-thin.md --runs runs-noest.tsv
rexit 0; rhas 'runs-thin.md: thin history: 1 tasks'; rhas 'no ratio yet'; rhasnt '-×|ERROR'
# tests_first: no on money, roles or customer data (#334): one WARN line, never an error (the header)
tr -d '\r' < tests-first-guard.md > g-base.md
sed 's/^title: .*/title: Round the Price on the receipt/' g-base.md > g-title.md
sed 's/^  stays as it was\.$/  stays as it was, as on an invoice./' g-base.md > g-intent.md
sed 's/^touches: .*/touches: [scripts\/billing.sh, tests\/sort.sh]/' g-base.md > g-touches.md
sed 's/^tests_first: .*/tests_first: yes/' g-touches.md > g-yes.md
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
gname="two fields: the first field, the list's first word"; gwarn g-two.md title money
gname="words inside other words"; gnone g-inner.md
# the core's own role files in touches (#362): not read for the word list; a project's own and the rest still are
sed 's/^touches: .*/touches: [roles\/assistant.md, tests\/sort.sh]/' g-base.md > g-core-role.md
sed 's/^touches: .*/touches: [roles\/assistant.md, scripts\/billing.sh]/' g-base.md > g-core-billing.md
sed 's/^touches: .*/touches: [roles\/admin.md]/' g-base.md > g-proj-role.md
gname="a core role file in touches"; gnone g-core-role.md
gname="a core role file and billing in touches"; gwarn g-core-billing.md touches billing
gname="a project's own roles/admin.md"; gwarn g-proj-role.md touches role
# the core is the one check-contract runs from (its ../roles/), not the working directory: copies of the scripts
for d in nocore; do
  mkdir -p "$d/scripts"; cp "$core/scripts/check-contract.sh" "$core/scripts/check-contract.ps1" "$d/scripts/"
done
ccore="$(pwd)/nocore"; [ -n "$win" ] && ccore="$(cygpath -m "$ccore")"
gname="a core with no roles/ folder: nothing left out"; gwarn g-core-role.md touches role
ccore=""
# important components (#381): `bounds:` and `wall:` on a contract touching one (the header)
ifail() { echo "FAIL: important $iname: $1 (exit $CRC):"; printf '%s\n' "$CO" | sed 's/^/    /'; fail=1; }
ierr() {   # ierr <file> <word> <glob>: exit 1, an ERROR line holding the word and the glob, one error counted
  crun "$1"
  [ "$CRC" = 1 ] || ifail "exit $CRC, want 1"
  printf '%s\n' "$CO" | grep -F -- "$1: ERROR " | grep -F -- "$2" | grep -qF -- "$3" || ifail "no line '$1: ERROR ...$2...$3...'"
  printf '%s\n' "$CO" | grep -qxF -- "$1: FAIL (1 errors, 0 warnings)" || ifail "the summary is not '$1: FAIL (1 errors, 0 warnings)'"
}
inone() {   # inone <file>: exit 0 and only today's clean summary, byte for byte
  crun "$1"
  [ "$CRC" = 0 ] || ifail "exit $CRC, want 0"
  [ "$CO" = "$1: OK (0 errors, 0 warnings)" ] || ifail "want only '$1: OK (0 errors, 0 warnings)'"
}
imk() {   # imk <file> <touches items, empty: no touches line> <lines to add, as a printf format>
  { sed -e '$d' -e '/^bounds:/,/^  - /d' -e "s#^tests_first: .*#tests_first: ${tfv:-no - tests/sort.sh checks it}#" -e 's#^touches: .*#touches: ['"$2"']#' runs-lf.md | { [ -n "$2" ] && cat || sed '/^touches: /d'; }; printf "$3"; printf -- '---\n'; } > "$1"
}
B1='bounds:\n  - some/glob/* 10\n'; W1='wall: the guard stops it\n'
i=0; for v in 'scripts/hooks/x.sh|scripts/hooks/*'; do
  i=$((i + 1)); it="${v%%|*}"; ig="${v#*|}"
  imk "i-nob$i.md" "$it" "$W1"; iname="$it without bounds"; ierr "i-nob$i.md" bounds "$ig"
  imk "i-now$i.md" "$it" "$B1"; iname="$it without wall"; ierr "i-now$i.md" wall "$ig"
  imk "i-ok$i.md" "$it" "$B1$W1"; iname="$it with both"; inone "i-ok$i.md"
done
imk i-list.md '' 'touches:\n  - "scripts/hooks/x.sh"\n  - sort.sh\nwall: w\n'; iname="touches as a quoted list"; ierr i-list.md bounds 'scripts/hooks/*'
# a folder holding an important glob counts as touching it; a folder holding none does not
i=0; for v in 'tests/|tests/*/run.*'; do
  i=$((i + 1)); it="${v%%|*}"; ig="${v#*|}"
  imk "i-dirb$i.md" "$it" "$W1"; iname="the folder $it without bounds"; ierr "i-dirb$i.md" bounds "$ig"
  imk "i-dirw$i.md" "$it" "$B1"; iname="the folder $it without wall"; ierr "i-dirw$i.md" wall "$ig"
  imk "i-dirk$i.md" "$it" "$B1$W1"; iname="the folder $it with both"; inone "i-dirk$i.md"
done
# a folder under a glob's wildcard, neither field: the two ERRORs, each naming the glob
imk i-dir2.md 'tests/retro/' ''; iname="the folder tests/retro/ with neither field"; crun i-dir2.md
[ "$CRC" = 1 ] || ifail "exit $CRC, want 1"
for w in bounds wall; do printf '%s\n' "$CO" | grep -F -- "i-dir2.md: ERROR " | grep -F -- "$w" | grep -qF -- 'tests/*/run.*' || ifail "no line 'i-dir2.md: ERROR ...$w...tests/*/run.*...'"; done
printf '%s\n' "$CO" | grep -qxF -- "i-dir2.md: FAIL (2 errors, 0 warnings)" || ifail "the summary is not 'i-dir2.md: FAIL (2 errors, 0 warnings)'"
imk i-dirn.md 'docs/, scripts/hooksy/' ''; iname="folders holding no important glob"; inone i-dirn.md
# a malformed bound: never a whole number, no number, an empty list, a value on the key's line, a good line beside
i=0; for b in 'bounds:\n  - scripts/hooks/* lots\n' 'bounds:\n  - scripts/hooks/*\n'; do
  i=$((i + 1)); imk "i-bad$i.md" scripts/hooks/x.sh "$b$W1"; iname="a malformed bound: $b"; ierr "i-bad$i.md" bounds 'scripts/hooks/*'
done
imk i-wall1.md scripts/hooks/x.sh "${B1}wall:\n"; iname="an empty wall"; ierr i-wall1.md wall 'scripts/hooks/*'
# touching none: today's output. The glob holds from the root and a `*` needs its folder
imk i-none1.md 'sort.sh, src/x.sh' ''; iname="no important file"; inone i-none1.md
imk i-none2.md 'scripts/hooks.sh, scripts/hooksy/x.sh, tests/run.sh, docs/tests/a/run.sh, tests/a/runner.sh, .github/workflows.yml' ''; iname="near misses"; inone i-none2.md
# the project's row: PROJECT.md two folders above the script's own (the header), from copies of the scripts
for d in proj fillp; do
  mkdir -p "$d/coordinator/core/scripts"; cp "$core/scripts/check-contract.sh" "$core/scripts/check-contract.ps1" "$d/coordinator/core/scripts/"
done
printf '| Setting | Value | Source | Since | Options |\n|---|---|---|---|---|\n| Work mode | by task | owner | 2026-11-02 | - |\n| **Important components** (CONTRACT.md) | `src/pay/* lib/core/* src/i18n/**/*.test.*` | owner | 2026-11-02 | added to the default list |\n' > proj/coordinator/PROJECT.md
printf '| Setting | Value | Source | Since | Options |\n|---|---|---|---|---|\n| **Important components** (CONTRACT.md) | `<fill>` | `<fill>` | `<date>` | added to the default list |\n' > fillp/coordinator/PROJECT.md
imk i-p1.md src/pay/a.sh "$W1"; imk i-p2.md lib/core/x.sh "$B1"; imk i-p4.md scripts/hooks/x.sh "$W1"
ccore="$(pwd)/proj/coordinator/core"; [ -n "$win" ] && ccore="$(cygpath -m "$ccore")"
iname="the row adds its first glob"; ierr i-p1.md bounds 'src/pay/*'
iname="the row adds its second glob"; ierr i-p2.md wall 'lib/core/*'
iname="the row removes no default"; ierr i-p4.md bounds 'scripts/hooks/*'
# a `**/` glob of the row: zero or more folders (#529); `*` alone still needs its slash
imk i-p5.md src/i18n/x.test.ts "$W1"; imk i-p6.md src/i18n/a/b/x.test.ts "$B1"
iname="a **/ glob, a file directly in its folder"; ierr i-p5.md bounds 'src/i18n/**/*.test.*'
iname="a **/ glob, a file two folders down"; ierr i-p6.md wall 'src/i18n/**/*.test.*'
ccore="$(pwd)/fillp/coordinator/core"; [ -n "$win" ] && ccore="$(cygpath -m "$ccore")"
iname="a row still <fill>: the defaults hold"; ierr i-p4.md bounds 'scripts/hooks/*'
ccore=""
# tests_first: yes names a bound (#390, the header); `no` with none stays today's: quoted.md in expected.txt, i-none1..3 above
tfm='`tests_first` is yes but `bounds` has no line (`- <glob> <max added lines>`): name the size of the tests this task adds (CONTRACT.md)'
tfv=yes imk i-tf1.md sort.sh ''
iname="tests_first: yes and no bound"; ierr i-tf1.md "$tfm" tests_first
tfv=yes imk i-tfk.md sort.sh "$B1"; iname="tests_first: yes with a bound"; inone i-tfk.md
tfv=yes imk i-tfi.md scripts/hooks/x.sh "$W1"; iname="tests_first: yes, an important file, no bound"; crun i-tfi.md; [ "$CRC" = 1 ] || ifail "exit $CRC, want 1"
printf '%s\n' "$CO" | grep -qxF -- "i-tfi.md: ERROR $tfm" || ifail "no tests_first ERROR"
printf '%s\n' "$CO" | grep -F -- 'i-tfi.md: ERROR ' | grep -F -- 'bounds' | grep -qF -- 'scripts/hooks/*' || ifail "its own ERROR is gone"
printf '%s\n' "$CO" | grep -qxF -- 'i-tfi.md: FAIL (2 errors, 0 warnings)' || ifail "the summary is not 2 errors"
# the same output and exit codes from both versions, on every contract above at once
if [ "$kind" = ps ]; then
  set -- i-*.md
  crun "$@"; pso="$CO"; prc="$CRC"
  sho="$(bash "$core/scripts/check-contract.sh" "$@" 2>&1)"; src=$?
  [ "$prc" = "$src" ] && [ "$pso" = "$(printf '%s\n' "$sho" | tr -d '\r')" ] ||
    { echo "FAIL: important: check-contract.sh and .ps1 differ (exit $src, $prc):"; diff <(printf '%s\n' "$sho" | tr -d '\r') <(printf '%s\n' "$pso") | sed 's/^/    /'; fail=1; }
fi
echo "check-contract ($kind): $( [ $fail = 0 ] && echo all pass || echo FAILURES )"
exit $fail
