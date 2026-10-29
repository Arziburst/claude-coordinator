#!/usr/bin/env bash
# `selftest hooks` on every settings file in tests/selftest/hooks/ (@CORE@ in it: this core's folder): the output of each, with its exit code,
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
      --expect) x=-Expect ;;
    esac
    a+=("$x")
  done
  "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File scripts/selftest.ps1 "${a[@]}"
}
fail=0; n=0

# each fixture is read from a copy whose @CORE@ is this core's folder: an absolute path to a folder on
# any machine (env COORD_PROTECTED_ROOT)
mkdir -p "$tmp/fx"; fx="$tmp/fx"; command -v cygpath >/dev/null 2>&1 && fx="$(cygpath -m "$fx")"
for f in tests/selftest/hooks/*.json; do
  sed "s#@CORE@#$core#g" "$f" > "$fx/${f##*/}"
  st hooks --settings "$fx/${f##*/}" > "$tmp/one" 2>&1; rc=$?
  printf '== %s (exit %s)\n' "${f##*/}" "$rc"; tr -d '\r' < "$tmp/one"
done > "$tmp/out"
n=$((n + 1))
tr -d '\r' < tests/selftest/hooks/expected.txt | diff - "$tmp/out" ||
  { echo "FAIL: the output differs from tests/selftest/hooks/expected.txt (< expected, > got)"; fail=1; }

# tests/selftest/hooks/os/: a root whose verdict depends on the OS - on Windows only a drive path counts
# (C:/... or C:\..., or Git Bash's /c/..., which the guard reads as C:/...): /tmp fails there, /c/Windows
# passes; elsewhere /tmp is a folder and /c/Windows is not
osroot() {   # osroot <fixture> <expected exit> <expected line>
  n=$((n + 1))
  st hooks --settings "tests/selftest/hooks/os/$1.json" > "$tmp/one" 2>&1; rc=$?
  { [ "$rc" = "$2" ] && tr -d '\r' < "$tmp/one" | grep -qxF -- "$3"; } ||
    { echo "FAIL (hooks os/$1.json): expected exit $2 and '$3', got exit $rc:"; sed 's/^/    /' "$tmp/one"; fail=1; }
}
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    osroot posixroot 1 'FAIL hooks: COORD_PROTECTED_ROOT is not a drive path (C:/... or C:\...): /tmp - Claude Code passes C:\... file paths on Windows'
    osroot gitbashroot 0 'PASS hooks: COORD_PROTECTED_ROOT is an absolute path to a folder' ;;
  *)
    osroot posixroot 0 'PASS hooks: COORD_PROTECTED_ROOT is an absolute path to a folder'
    osroot gitbashroot 1 'FAIL hooks: COORD_PROTECTED_ROOT is not a folder on this machine: /c/Windows' ;;
esac

# the guard hook's "timeout" (#290): under a loaded CPU a guard that runs out of time blocks the call
# (onFailure "block") - a lost SendMessage - so 30 s or more passes and a shorter or missing one fails.
# tests/selftest/hooks/timeout/: good.json with timeout 10, 30, 60 and none; then both settings examples
# (their /ABSOLUTE/PATH and /ABSOLUTE/PROJECT, or C:/..., as this core's folder) pass it, with exit 0.
# The key words only: a PASS or FAIL line that names the timeout (a FAIL line also names 30)
tmo() {   # tmo <settings file> <label> <PASS|FAIL>: exit 0 / 1 and that line; never the other one
  n=$((n + 1))
  st hooks --settings "$1" > "$tmp/one" 2>&1; rc=$?
  tr -d '\r' < "$tmp/one" > "$tmp/lines"
  local want=0 other=FAIL; [ "$3" = FAIL ] && { want=1; other=PASS; }
  { [ "$rc" = "$want" ] && grep -i "^$3 hooks:.*timeout" "$tmp/lines" | { [ "$3" = PASS ] && cat || grep '30'; } | grep -q . &&
    ! grep -qi "^$other hooks:.*timeout" "$tmp/lines"; } ||
    { echo "FAIL (hooks $2): expected exit $want and a $3 line about the guard's timeout (>= 30 s), got exit $rc:"; sed 's/^/    /' "$tmp/one"; fail=1; }
}
tmo tests/selftest/hooks/timeout/t10.json timeout/t10.json FAIL
tmo tests/selftest/hooks/timeout/none.json timeout/none.json FAIL
tmo tests/selftest/hooks/timeout/t30.json timeout/t30.json PASS
tmo tests/selftest/hooks/timeout/t60.json timeout/t60.json PASS
for f in settings.example.json settings.example.windows.json; do
  sed "s#C:/ABSOLUTE/PATH#$core#g; s#C:/ABSOLUTE/PROJECT#$core#g; s#/ABSOLUTE/PATH#$core#g; s#/ABSOLUTE/PROJECT#$core#g" "$f" > "$fx/$f"
  tmo "$fx/$f" "$f" PASS
done

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
# the push probe passes only on the guard's push block, never on its working-copy block
hc editblk0 'FAIL hookcheck: no block in the transcript: the hook did not run (its path, its shell, or the settings were not loaded)'

# hookcheck --expect edit: the edit probe (a Write into COORD_PROTECTED_ROOT) passes only on the guard's
# working-copy block; a push block, a write that went through, no hook and a non-blocking error fail
hce() {   # hce <session> <expected exit> <expected line>
  n=$((n + 1))
  CLAUDE_CONFIG_DIR=tests/selftest/claude st hookcheck --session "$1" --expect edit > "$tmp/one" 2>&1; rc=$?
  { [ "$rc" = "$2" ] && tr -d '\r' < "$tmp/one" | grep -qxF -- "$3"; } ||
    { echo "FAIL (hookcheck --session $1 --expect edit): expected exit $2 and '$3', got exit $rc:"; sed 's/^/    /' "$tmp/one"; fail=1; }
}
hce editblk0 0 "PASS hookcheck: the edit tool's write into the working copy was blocked through Claude Code"
hce editok00 1 "FAIL hookcheck: the write into the working copy went through: COORD_PROTECTED_ROOT is not in the settings' env, or its matcher leaves out the edit tools"
hce editnone 1 'FAIL hookcheck: no working-copy block in the transcript: the hook did not run (its matcher, COORD_PROTECTED_ROOT, or the settings were not loaded)'
hce blocked0 1 'FAIL hookcheck: no working-copy block in the transcript: the hook did not run (its matcher, COORD_PROTECTED_ROOT, or the settings were not loaded)'
hce nonblock 1 'FAIL hookcheck: the guard blocked, but Claude Code got it as a non-blocking error: a shell wrapper turns exit 2 into 1'
usage hookcheck --session editblk0 --expect other
usage hooks --settings tests/selftest/hooks/good.json --expect edit

echo "selftest hooks ($kind): $n checks, $( [ $fail = 0 ] && echo all pass || echo FAILURES )"
exit $fail
