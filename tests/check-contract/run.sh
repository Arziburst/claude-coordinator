#!/usr/bin/env bash
# check-contract on the contracts in this folder, a UTF-8 BOM copy of tests/selftest/contract.md and a
# file that does not exist: the output must equal expected.txt, line for line, from either version.
#   tests/check-contract/run.sh sh                  # check-contract.sh, with the bash running this file
#   tests/check-contract/run.sh ps pwsh             # check-contract.ps1 (or: ps powershell)
# Exit 1 if the output or the exit code differs.
set -u
[ $# -gt 0 ] || { sed -n '2,6s/^# \{0,1\}//p' "$0"; exit 2; }
kind="$1"; shift; PS=("$@")
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -r "$tmp"' EXIT
command -v cygpath >/dev/null 2>&1 && core="$(cygpath -m "$core")"
cp "$here"/*.md "$tmp/"
# and a body line that reads like a key: below the header it is not part of the contract
{ printf '\357\273\277'; cat "$core/tests/selftest/contract.md"; printf 'acceptance: is read from the header only\n'; } > "$tmp/bom.md"
files=(how-in-text.md quoted.md empty-id-title.md misplaced.md bom.md missing.md)
cd "$tmp" || exit 1
if [ "$kind" = ps ]; then "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$core/scripts/check-contract.ps1" "${files[@]}" > out.txt 2>&1
else bash "$core/scripts/check-contract.sh" "${files[@]}" > out.txt 2>&1; fi
rc=$?
fail=0
[ "$rc" = 1 ] || { echo "FAIL: expected exit 1, got $rc"; fail=1; }
tr -d '\r' < "$here/expected.txt" > want.txt   # a Windows checkout may hold it with CRLF
tr -d '\r' < out.txt | diff want.txt - || { echo "FAIL: the output differs from tests/check-contract/expected.txt (< expected, > got)"; fail=1; }
echo "check-contract ($kind): $( [ $fail = 0 ] && echo all pass || echo FAILURES )"
exit $fail
