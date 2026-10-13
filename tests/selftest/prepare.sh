#!/usr/bin/env bash
# The CORE-FINDINGS.md check of `selftest prepare` against a temporary project and state repository:
# the same verdict and message from both versions for an empty status, a capitalised status, a UTF-16
# file (Windows PowerShell 5.1's Out-File), and a UTF-8 BOM with CRLF line ends (which pass).
#   tests/selftest/prepare.sh sh                  # selftest.sh, with the bash running this file
#   tests/selftest/prepare.sh ps pwsh             # selftest.ps1 (or: ps powershell)
# Exit 1 if any check fails.
set -u
[ $# -gt 0 ] || { sed -n '2,7s/^# \{0,1\}//p' "$0"; exit 2; }
kind="$1"; shift; PS=("$@")
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'chmod -R u+w "$tmp"; rm -r "$tmp"' EXIT
command -v cygpath >/dev/null 2>&1 && core="$(cygpath -m "$core")"

g() { git -c user.email=t@t -c user.name=t "$@"; }
p="$tmp/project"; s="$p/coordinator"
git init -q -b main "$p" && g -C "$p" commit -q --allow-empty -m p
git init -q -b state "$s" && g -C "$s" commit -q --allow-empty -m s
printf 'coordinator/\n' >> "$p/.git/info/exclude"
tpl="$(tr -d '\r' < "$core/CORE-FINDINGS.template.md")"

prepare() {   # prepare <core commit>: one run, its output in $LAST, its exit code in $RC
  if [ "$kind" = ps ]; then
    "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$core/scripts/selftest.ps1" prepare -Project "$p" -State "$s" -Core "$1" > "$tmp/out" 2>&1
  else bash "$core/scripts/selftest.sh" prepare --project "$p" --state "$s" --core "$1" > "$tmp/out" 2>&1; fi
  RC=$?; LAST="$(tr -d '\r' < "$tmp/out")"
}
fail=0; n=0
expect() {   # expect <case> <exit code> <line>
  n=$((n + 1))
  { [ "$RC" = "$2" ] && printf '%s\n' "$LAST" | grep -qxF -- "$3"; } ||
    { echo "FAIL ($1): expected exit $2 and the line '$3', got exit $RC:"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }
}
row() { printf '| CF-1 | 2026-10-13 | abc1234 | a check | what happened | none | %s |\n' "$1"; }
f="$s/CORE-FINDINGS.md"

{ printf '%s\n' "$tpl"; row ''; } > "$f"
prepare c1; expect "an empty status cell" 1 "FAIL prepare: CORE-FINDINGS.md: unknown status '<empty>'"
{ printf '%s\n' "$tpl"; row 'Sent #12'; } > "$f"
prepare c2; expect "a capitalised status" 1 "FAIL prepare: CORE-FINDINGS.md: unknown status 'Sent #12'"
{ printf '\377\376'; { printf '%s\n' "$tpl"; row 'sent #12'; } | iconv -f UTF-8 -t UTF-16LE; } > "$f"
prepare c3; expect "a UTF-16 LE file" 1 "FAIL prepare: CORE-FINDINGS.md is not UTF-8 (re-save it as UTF-8)"
{ printf '\357\273\277'; { printf '%s\n' "$tpl"; row 'sent #12'; row 'new'; } | awk '{ printf "%s\r\n", $0 }'; } > "$f"
prepare c4; expect "a UTF-8 BOM and CRLF" 0 "PASS prepare: CORE-FINDINGS.md in the template's format"

echo "selftest prepare ($kind): $n checks, $( [ $fail = 0 ] && echo all pass || echo FAILURES )"
exit $fail
