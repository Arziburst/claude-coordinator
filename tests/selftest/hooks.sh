#!/usr/bin/env bash
# `selftest hooks` on every settings file in tests/selftest/hooks/: the output of each, with its exit code,
# must equal tests/selftest/hooks/expected.txt line for line, from either version (selftest.sh reads the
# JSON with jq when present, else with awk: run it both ways). Then a step given a parameter of another
# step, or a stray word, is a usage error (exit 2) in both versions, and runs nothing.
#   tests/selftest/hooks.sh sh                  # selftest.sh, with the bash running this file
#   tests/selftest/hooks.sh ps pwsh             # selftest.ps1 (or: ps powershell)
# Exit 1 if any check fails.
set -u
[ $# -gt 0 ] || { sed -n '2,8s/^# \{0,1\}//p' "$0"; exit 2; }
kind="$1"; shift; PS=("$@")
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -r "$tmp"' EXIT
command -v cygpath >/dev/null 2>&1 && core="$(cygpath -m "$core")"
cd "$core" || exit 1

# st <step> <selftest.sh arguments>: the .sh, or the .ps1 with the same arguments in its own form
st() {
  if [ "$kind" = sh ]; then bash scripts/selftest.sh "$@"; return; fi
  local a=() x
  for x in "$@"; do
    case "$x" in
      --repo) x=-Repo ;; --sandbox) x=-Sandbox ;; --state-repo) x=-StateRepo ;; --in) x=-In ;;
      --project) x=-Project ;; --state) x=-State ;; --core) x=-Core ;; --settings) x=-Settings ;; --session) x=-Session ;;
    esac
    a+=("$x")
  done
  "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File scripts/selftest.ps1 "${a[@]}"
}
fail=0; n=0

for f in tests/selftest/hooks/*.json; do
  st hooks --settings "$f" > "$tmp/one" 2>&1; rc=$?
  printf '== %s (exit %s)\n' "${f##*/}" "$rc"; tr -d '\r' < "$tmp/one"
done > "$tmp/out"
n=$((n + 1))
tr -d '\r' < tests/selftest/hooks/expected.txt | diff - "$tmp/out" ||
  { echo "FAIL: the output differs from tests/selftest/hooks/expected.txt (< expected, > got)"; fail=1; }

usage() {   # usage <selftest.sh arguments>: exit 2 and no PASS / FAIL line
  n=$((n + 1))
  st "$@" > "$tmp/one" 2>&1; rc=$?
  { [ "$rc" = 2 ] && ! grep -q '^PASS \|^FAIL ' "$tmp/one"; } ||
    { echo "FAIL ($*): expected a usage error (exit 2), got exit $rc:"; sed 's/^/    /' "$tmp/one"; fail=1; }
}
usage scripts --settings tests/selftest/hooks/good.json
usage scripts extra
usage env --settings tests/selftest/hooks/good.json
usage sandbox --sandbox "$tmp/nowhere"
usage clean --sandbox "$tmp/nowhere" --settings tests/selftest/hooks/good.json
usage hooks --settings tests/selftest/hooks/good.json --session s1
usage hooks
usage hookcheck --session s1 --settings tests/selftest/hooks/good.json
usage prepare --project "$tmp" --state "$tmp" --core c1 --state-repo o/r
usage verify --project "$tmp" --state "$tmp" --core c1 --settings tests/selftest/hooks/good.json

# hookcheck: a prefix of several transcripts, and a pattern or path character, name no session
hc() {   # hc <session> <expected line>: exit 1 and that FAIL line
  n=$((n + 1))
  CLAUDE_CONFIG_DIR=tests/selftest/claude st hookcheck --session "$1" > "$tmp/one" 2>&1; rc=$?
  { [ "$rc" = 1 ] && tr -d '\r' < "$tmp/one" | grep -qxF -- "$2"; } ||
    { echo "FAIL (hookcheck --session $1): expected exit 1 and '$2', got exit $rc:"; sed 's/^/    /' "$tmp/one"; fail=1; }
}
hc n 'FAIL hookcheck: ambiguous session n: noblock0-0000-0000-0000-000000000003 nonblock-0000-0000-0000-000000000002'
hc '*' 'FAIL hookcheck: the session id * holds a pattern or path character'
hc 'blocked0/x' 'FAIL hookcheck: the session id blocked0/x holds a pattern or path character'

echo "selftest hooks ($kind): $n checks, $( [ $fail = 0 ] && echo all pass || echo FAILURES )"
exit $fail
