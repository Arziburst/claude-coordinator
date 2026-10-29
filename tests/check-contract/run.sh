#!/usr/bin/env bash
# check-contract on the contracts in this folder, a UTF-8 BOM copy of tests/selftest/contract.md and a
# file that does not exist: the output must equal expected.txt, line for line, from either version.
# On Windows the .ps1 runs as on a Russian Windows, with the console's code page 866: the section signs
# of its warnings (CORE §7) must still come out as UTF-8, and the caller's 866 must be back afterwards,
# after a usage error (exit 2) and after a run to the end.
#   tests/check-contract/run.sh sh                  # check-contract.sh, with the bash running this file
#   tests/check-contract/run.sh ps pwsh             # check-contract.ps1 (or: ps powershell)
# Exit 1 if the output or the exit code differs.
set -u
[ $# -gt 0 ] || { sed -n '2,9s/^# \{0,1\}//p' "$0"; exit 2; }
kind="$1"; shift; PS=("$@")
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -r "$tmp"' EXIT
win=""; command -v cygpath >/dev/null 2>&1 && { win=1; core="$(cygpath -m "$core")"; }
cp "$here"/*.md "$tmp/"
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
echo "check-contract ($kind): $( [ $fail = 0 ] && echo all pass || echo FAILURES )"
exit $fail
