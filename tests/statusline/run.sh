#!/usr/bin/env bash
# The status line cases on tests/selftest/status.json: the line, statusline.json and the session's copy
# saved and no statusline.*.tmp left - on a plain run, a config path with [ ] in it, 20 runs at once, and
# (PowerShell) statusline.json held open by a reader, which fails the move on Windows.
#   tests/statusline/run.sh sh              # scripts/statusline.sh, with the bash running this file
#   tests/statusline/run.sh ps pwsh         # scripts/statusline.ps1 (or: ps powershell)
# The .sh draws its line only with jq: without it the line is not compared. Exit 1 if any case fails.
set -u
[ $# -gt 0 ] || { sed -n '2,7s/^# \{0,1\}//p' "$0"; exit 2; }
kind="$1"; shift
[ "$kind" = sh ] || [ "$kind" = ps ] || { sed -n '2,7s/^# \{0,1\}//p' "$0"; exit 2; }
PS=("$@")
[ "$kind" = sh ] || [ ${#PS[@]} -gt 0 ] || { echo "ps needs the PowerShell command" >&2; exit 2; }
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -r "$tmp"' EXIT
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }   # Git Bash -> C:/...
fixture="$core/tests/selftest/status.json"
want='Opus 5.5 (high) · ctx 837k/1M (84%) · 5h 14% · week 92%'
line=yes; [ "$kind" = ps ] || command -v jq >/dev/null 2>&1 || line=no
bom="$(printf '\357\273\277')"

# one run with CLAUDE_CONFIG_DIR=$1 and the fixture on stdin; stdout to $tmp/out (\r removed), exit code in rc
run() {
  local cfg; cfg="$(winpath "$1")"
  if [ "$kind" = ps ]; then
    CLAUDE_CONFIG_DIR="$cfg" "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$(winpath "$core/scripts/statusline.ps1")" < "$fixture" > "$tmp/out.raw" 2> "$tmp/err"
  else
    CLAUDE_CONFIG_DIR="$cfg" bash "$core/scripts/statusline.sh" < "$fixture" > "$tmp/out.raw" 2> "$tmp/err"
  fi
  rc=$?
  tr -d '\r' < "$tmp/out.raw" > "$tmp/out"
}
# is $1 the fixture, a BOM (Windows PowerShell 5.1's utf8) aside?
same() { local c; [ -f "$1" ] || return 1; c="$(cat "$1")"; [ "${c#"$bom"}" = "$(cat "$fixture")" ]; }
# the statusline.*.tmp files left in $1/coordinator
temps() { ls "$1/coordinator" | grep '^statusline\..*\.tmp$' | tr '\n' ' '; }
fail=0; n=0
bad() { echo "FAIL $*"; fail=1; }
# check <name> <config dir> <compare statusline.json: yes | no>: the run's exit, line, files and temp files
check() {
  local name="$1" cfg="$2" json="$3" t
  n=$((n + 1))
  [ "$rc" = 0 ] || { bad "$name: exit $rc"; sed 's/^/  err: /' "$tmp/err"; return; }
  [ "$line" = no ] || [ "$(cat "$tmp/out")" = "$want" ] || { bad "$name: printed '$(cat "$tmp/out")'"; return; }
  t="$(temps "$cfg")"; [ -z "$t" ] || { bad "$name: left $t"; return; }
  [ "$json" = no ] || same "$cfg/coordinator/statusline.json" || { bad "$name: statusline.json is not the status JSON"; return; }
  same "$cfg/coordinator/sessions/selftest-fixture.json" || { bad "$name: no session copy"; return; }
  echo "ok   $name"
}

run "$tmp/one"; check "the fixture: the line, statusline.json, the session's copy, no temp file" "$tmp/one" yes
mkdir -p "$tmp/cfg[1]"; run "$tmp/cfg[1]"; check "a config path with [ ]" "$tmp/cfg[1]" yes

# 20 at once, as Claude Code draws several sessions' status lines: Move-Item -Force deletes the target,
# then moves, so another run's move in between failed this one's and left its temp file; and Set-Content
# straight on the session copy emptied it, then lost the write to another run holding it (about 1 round
# in 10 under Windows PowerShell 5.1): the copy must be whole after every round
m="$tmp/many"; mkdir -p "$m"; cm="$(winpath "$m")"; i=0
while [ $i -lt 20 ]; do
  if [ "$kind" = ps ]; then
    CLAUDE_CONFIG_DIR="$cm" "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$(winpath "$core/scripts/statusline.ps1")" < "$fixture" > /dev/null 2>&1 &
  else
    CLAUDE_CONFIG_DIR="$cm" bash "$core/scripts/statusline.sh" < "$fixture" > /dev/null 2>&1 &
  fi
  i=$((i + 1))
done
wait
rc=0; printf '%s\n' "$want" > "$tmp/out"; check "20 runs at once" "$m" yes

# statusline.json held open by a reader (FileShare.ReadWrite, no Delete): on Windows the move fails, the
# temp file goes and the old statusline.json stays for this tick; elsewhere the move succeeds
if [ "$kind" = ps ]; then
  cat > "$tmp/hold.ps1" <<'EOF'
param([string]$Target, [string]$Script, [string]$In, [string]$Out)
$h = [IO.File]::Open($Target, 'Open', 'Read', 'ReadWrite')
try {
  $exe = (Get-Process -Id $PID).Path
  $p = Start-Process -FilePath $exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $Script)) -RedirectStandardInput $In -RedirectStandardOutput $Out -NoNewWindow -PassThru
  $null = $p.Handle; $p.WaitForExit(); exit $p.ExitCode
} finally { $h.Close() }
EOF
  hd="$tmp/held"; mkdir -p "$hd/coordinator"; printf '{}' > "$hd/coordinator/statusline.json"
  CLAUDE_CONFIG_DIR="$(winpath "$hd")" "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$(winpath "$tmp/hold.ps1")" \
    -Target "$(winpath "$hd/coordinator/statusline.json")" -Script "$(winpath "$core/scripts/statusline.ps1")" \
    -In "$(winpath "$fixture")" -Out "$(winpath "$tmp/out.raw")" 2> "$tmp/err"
  rc=$?; tr -d '\r' < "$tmp/out.raw" > "$tmp/out"
  check "statusline.json held open by a reader" "$hd" no
fi
[ "$fail" = 0 ] && echo "statusline: $n cases passed" || echo "statusline: failures above ($n cases)"
exit "$fail"
# scratch: a statusline test change to measure the CI filters of #287; never merged
