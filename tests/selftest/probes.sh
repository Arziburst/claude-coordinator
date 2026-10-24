#!/usr/bin/env bash
# `selftest probes` (SELFTEST step 2a) against a stub `claude` first on PATH (the real claude is never
# called): on `--bg` it writes the probe session's transcript into a temporary CLAUDE_CONFIG_DIR - a
# token probe's `echo <token>` fed to this core's safety-guard.sh, so the block comes from the guard and
# the token file - and prints Claude Code's `claude stop <id>` line; `stop` is recorded. Each probe's
# scenario is set by its name (STUB_PUSH, STUB_OWN, STUB_EDIT). Then `hookcheck --expect probe` on
# tests/selftest/claude, and the usage errors of both steps.
#   tests/selftest/probes.sh sh                  # selftest.sh, with the bash running this file
#   tests/selftest/probes.sh ps pwsh             # selftest.ps1 (or: ps powershell)
# Exit 1 if any check fails.
set -u
[ $# -gt 0 ] || { sed -n '2,10s/^# \{0,1\}//p' "$0"; exit 2; }
kind="$1"; shift; PS=("$@")
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -r "$tmp"' EXIT
mp() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
core="$(mp "$core")"; T="$(mp "$tmp")"
cd "$core" || exit 1

mkdir -p "$tmp/bin" "$tmp/stub" "$tmp/cfg" "$tmp/proj" "$tmp/root"
cat > "$tmp/bin/claude" <<'EOF'
#!/usr/bin/env bash
# the stub claude of tests/selftest/probes.sh
D="$STUB_DIR"
if [ "${1:-}" = stop ]; then printf '%s\n' "${2:-}" >> "$D/stops"; echo "stopped ${2:-}"; exit 0; fi
[ "${1:-}" = --bg ] || exit 0
shift; name="" model="" settings="" extra="" prompt=""
while [ $# -gt 0 ]; do
  case "$1" in
    --name) name="$2"; shift 2 ;; --model) model="$2"; shift 2 ;; --settings) settings="$2"; shift 2 ;;
    --*) extra="$extra $1"; shift ;;
    *) prompt="$1"; shift ;;
  esac
done
case "$name" in
  "probe: push") scn="${STUB_PUSH:-block}" ;;
  "probe: push (own settings)") scn="${STUB_OWN:-block}" ;;
  "probe: edit") scn="${STUB_EDIT:-editblock}" ;;
  *) scn=none ;;
esac
tok=none tok2=none; [ -f .claude/coordinator-probe.txt ] && { IFS= read -r tok; IFS= read -r tok2; } < .claude/coordinator-probe.txt
inp=no; case "$prompt" in *"echo $tok"*) inp=yes ;; esac
cwd="$(pwd -P)"; command -v cygpath >/dev/null 2>&1 && cwd="$(cygpath -m "$cwd")"
printf 'launch|%s|%s|%s|%s|%s|%s|%s|%s\n' "$name" "$model" "$settings" "$extra" "$cwd" "$tok" "$inp" "$tok2" >> "$D/log"
printf '%s\n' "$prompt" >> "$D/prompts"
case "$scn" in
  noid) echo "Started."; exit 0 ;;
  refused) echo "Error: refused by policy" >&2; exit 1 ;;
esac
k=$(($(cat "$D/count" 2>/dev/null || echo 0) + 1)); echo "$k" > "$D/count"
id="$(printf 'p%07d' "$k")"; printf '%s\n' "$id" >> "$D/ids"
dir="$CLAUDE_CONFIG_DIR/projects/stub"; mkdir -p "$dir"; tf="$dir/$id-0000-4000-8000-000000000001.jsonl"
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk 'NR > 1 { printf "\\n" } { printf "%s", $0 }'; }
result() {   # result <content> [error]
  printf '{"type":"user","message":{"content":[{"type":"tool_result","content":"%s"%s}]}}\n' "$(esc "$1")" "${2:+,\"is_error\":true}"
}
# the guard's verdict on `echo <token>`, as Claude Code would run it from this project
guarded() {
  local c p err rc
  c="$(printf '%s\n' "$prompt" | sed -n 's/^Run exactly this one shell command: //p' | head -n 1)"
  p="$(pwd)"; command -v cygpath >/dev/null 2>&1 && p="$(cygpath -m "$p")"
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"%s"}}]}}\n' "$(esc "$c")"
  err="$(printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$c" "$p" |
    env -u COORD_PROTECTED_ROOT -u COORD_PROTECTED_BRANCHES CLAUDE_PROJECT_DIR="$p" bash "$STUB_GUARD" 2>&1 >/dev/null)"; rc=$?
  if [ "$rc" = 2 ]; then result "PreToolUse:Bash hook error: [bash $STUB_GUARD]: $err" error
  else result "${c#echo }"; fi
}
ended() {
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"Done."}],"stop_reason":"end_turn"}}\n'
  printf '{"type":"system","subtype":"turn_duration","durationMs":4210}\n'
}
write() {
  printf '{"type":"user","message":{"content":"%s"}}\n' "$(esc "$prompt")"
  case "$scn" in
    block|slowblock) guarded; ended ;;
    # another run's token takes the file over meanwhile
    swap) guarded; ended; printf 'coord-probe-1-anotherrun0000\n' > .claude/coordinator-probe.txt ;;
    noend) guarded ;;
    silent) ;;
    noendnb)
      printf '{"type":"attachment","attachment":{"type":"hook_non_blocking_error","hookName":"PreToolUse:Bash","stderr":"Failed with non-blocking status code: Blocked by safety-guard: the self-test%ss probe token (.claude/coordinator-probe.txt): this hook runs and its block holds.","exitCode":1}}\n' "'"
      result "$tok" ;;
    editnoend) result "PreToolUse:Write hook error: [bash guard]: Blocked by safety-guard: the owner's working copy is never edited by a worker (x); work in your worktree. If this is a false positive, ask the owner." error ;;
    noblock) result "${tok}"; ended ;;
    nonblock)
      printf '{"type":"attachment","attachment":{"type":"hook_non_blocking_error","hookName":"PreToolUse:Bash","stderr":"Failed with non-blocking status code: Blocked by safety-guard: the self-test%ss probe token (.claude/coordinator-probe.txt): this hook runs and its block holds.","exitCode":1}}\n' "'"
      result "$tok"; ended ;;
    quote) result "$tok"
      printf '{"type":"assistant","message":{"content":[{"type":"text","text":"Blocked by safety-guard: the self-test%ss probe token (.claude/coordinator-probe.txt): this hook runs and its block holds."}]}}\n' "'"
      ended ;;
    pushblock) result "PreToolUse:Bash hook error: [bash guard]: Blocked by safety-guard: push to a protected branch (main). If this is a false positive, ask the owner." error; ended ;;
    editblock) result "PreToolUse:Write hook error: [bash guard]: Blocked by safety-guard: the owner's working copy is never edited by a worker (x); work in your worktree. If this is a false positive, ask the owner." error; ended ;;
    editwrite)
      f="$(printf '%s\n' "$prompt" | sed -n 's/^Use the Write tool to create \(.*\) containing x\..*$/\1/p' | head -n 1)"
      printf 'x' > "$f"; result "File created successfully at: $f"; ended ;;
    *) ended ;;
  esac
}
if [ "$scn" = slowblock ]; then ( sleep 2; write >> "$tf" ) >/dev/null 2>&1 < /dev/null &
elif [ "$scn" != notx ]; then write > "$tf"; fi
# amb: a second transcript whose name starts with the same id
[ "$scn" != amb ] || cp "$tf" "$dir/$id-copy.jsonl"
echo "Started background session $id"
echo "  claude stop $id      stop this session"
exit 0
EOF
# PowerShell finds claude.ps1 on Windows; it hands the arguments to the bash stub as a native process,
# as claude.exe gets them
cat > "$tmp/bin/claude.ps1" <<'EOF'
& bash (Join-Path $PSScriptRoot 'claude') @args
exit $LASTEXITCODE
EOF
chmod +x "$tmp/bin/claude"
export PATH="$tmp/bin:$PATH" STUB_DIR="$T/stub" STUB_GUARD="$core/scripts/hooks/safety-guard.sh" CLAUDE_CONFIG_DIR="$T/cfg" COORD_PROBE_POLL=1
unset COORD_PROTECTED_ROOT COORD_PROTECTED_BRANCHES
printf '{}\n' > "$tmp/safety.json"
proj="$T/proj"; ws="$T/safety.json"; root="$T/root"; tokf="$tmp/proj/.claude/coordinator-probe.txt"

# st <step> <selftest.sh arguments>: the .sh, or the .ps1 with the same arguments in its own form
st() {
  if [ "$kind" = sh ]; then bash scripts/selftest.sh "$@"; return; fi
  local a=() x
  for x in "$@"; do
    case "$x" in
      --project) x=-Project ;; --worker-settings) x=-WorkerSettings ;; --own) x=-Own ;; --edit-root) x=-EditRoot ;;
      --model) x=-Model ;; --timeout) x=-Timeout ;; --settings) x=-Settings ;; --session) x=-Session ;; --expect) x=-Expect ;;
    esac
    a+=("$x")
  done
  "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File scripts/selftest.ps1 "${a[@]}"
}
fail=0; n=0; cur=""
bad() { echo "FAIL ($cur): $1"; [ -f "$tmp/one" ] && sed 's/^/    /' "$tmp/one"; fail=1; }
# scn <push> <own> <edit>: each probe's scenario
scn() { export STUB_PUSH="$1" STUB_OWN="$2" STUB_EDIT="$3"; }
# pr <what> <expected exit> <probes arguments>: runs selftest probes; its output in $tmp/one; the token
# file must be gone afterwards and every launched session stopped
pr() {
  cur="$1"; local want="$2" rc i; shift 2
  : > "$STUB_DIR/log"; : > "$STUB_DIR/stops"; : > "$STUB_DIR/ids"; : > "$STUB_DIR/prompts"
  st probes "$@" > "$tmp/one" 2>&1; rc=$?
  n=$((n + 1)); [ "$rc" = "$want" ] || bad "expected exit $want, got $rc"
  # keeptok=1: the file is not this run's to remove
  n=$((n + 1)); [ -n "${keeptok:-}" ] || [ ! -e "$tokf" ] || bad "the token file is still there"
  n=$((n + 1))
  while IFS= read -r i; do grep -qx "$i" "$STUB_DIR/stops" || bad "session $i was not stopped"; done < "$STUB_DIR/ids"
}
has() { n=$((n + 1)); tr -d '\r' < "$tmp/one" | grep -qxF -- "$1" || bad "no line '$1'"; }
hasre() { n=$((n + 1)); tr -d '\r' < "$tmp/one" | grep -qxE -- "$1" || bad "no line matching '$1'"; }
lacks() { n=$((n + 1)); ! tr -d '\r' < "$tmp/one" | grep -q -- "$1" || bad "a line matching '$1'"; }
# launched <name> <field> <value>: the stub's log line of that session has that field (2 model,
# 3 settings, 4 other flags, 5 cwd, 6 the token file's first line, 7 the token in the prompt)
launched() {
  n=$((n + 1))
  local v; v="$(awk -F'|' -v nm="$1" -v k="$(($2 + 1))" '$2 == nm { print $k; exit }' "$STUB_DIR/log")"
  [ "$v" = "$3" ] || bad "$1: field $2 is '$v', expected '$3'"
}
pcwd="$(cd "$tmp/proj" && pwd -P)"; pcwd="$(mp "$pcwd")"

# both token probes blocked by the guard through the token file; .claude is made when missing
scn block block editblock
pr "push and own, blocked" 0 --project "$proj" --worker-settings "$ws" --own
has "PASS probes: push: the command holding the probe token was blocked through Claude Code"
has "PASS probes: push (own settings): the command holding the probe token was blocked through Claude Code"
has "stopped: probe: push (p0000001), probe: push (own settings) (p0000002) - step 6 reads their cost and removes them"
has "selftest probes: 2 pass, 0 fail, 0 skipped"
launched "probe: push" 2 haiku; launched "probe: push" 3 "$ws"; launched "probe: push" 4 ""; launched "probe: push" 5 "$pcwd"
launched "probe: push (own settings)" 3 ""; launched "probe: push (own settings)" 7 yes
n=$((n + 1)); t="$(awk -F'|' 'NR == 1 { print $7 }' "$STUB_DIR/log")"
case "$t" in coord-probe-*) [ ${#t} -ge 16 ] && ! printf '%s' "$t" | grep -q '[^A-Za-z0-9-]' || bad "a token the guard ignores: $t" ;; *) bad "no token file at launch: $t" ;; esac
n=$((n + 1)); [ "$(awk -F'|' 'NR == 2 { print $7 }' "$STUB_DIR/log")" = "$t" ] || bad "the two probes got different tokens"
n=$((n + 1)); [ ! -e "$tmp/proj/.claude" ] || bad "the .claude folder made for the token is still there"
mkdir -p "$tmp/proj/.claude" && echo keep > "$tmp/proj/.claude/keep.txt"

# one probes run per project at a time: a fresh valid token is another run's - nothing launched, the
# file untouched; an old one is stale and overwritten; a token another run wrote meanwhile is left
printf 'coord-probe-9-otherrun00000000\n' > "$tokf"
keeptok=1 pr "another run going" 1 --project "$proj" --worker-settings "$ws" --own
hasre "BLOCKED probes: another probes run on this project \(started [0-9]+ s ago; if none is running, remove .*/proj/\.claude/coordinator-probe\.txt\)"
has "selftest probes: 0 pass, 0 fail, 0 skipped, 1 blocked"
n=$((n + 1)); [ ! -s "$STUB_DIR/log" ] || bad "a probe was launched"
n=$((n + 1)); [ "$(cat "$tokf")" = coord-probe-9-otherrun00000000 ] || bad "the other run's token file was changed"
touch -t 202001010000 "$tokf"
scn block block editblock
pr "a stale token file" 0 --project "$proj" --worker-settings "$ws"
hasre "stale token file .*/proj/\.claude/coordinator-probe\.txt \([0-9]+ s old: a run killed before its end\): overwritten"
has "PASS probes: push: the command holding the probe token was blocked through Claude Code"
# the file holds this run's timeout on its second line (the guard reads only the first)
launched "probe: push" 8 300
# a token file dated in the future is stale
printf 'coord-probe-9-otherrun00000000\n300\n' > "$tokf"; touch -t 203001010000 "$tokf"
pr "a token file dated in the future" 0 --project "$proj" --worker-settings "$ws" --timeout 9
hasre "stale token file .*/proj/\.claude/coordinator-probe\.txt \(dated in the future\): overwritten"
launched "probe: push" 8 9
# the other run's timeout (its second line) decides: 2 minutes old is stale for a run of 1 s, going
# for a run of 600 s, whatever this run's timeout
old2="$(($(date +%s) - 120))"; ts="$(date -d "@$old2" +%Y%m%d%H%M.%S 2>/dev/null || date -r "$old2" +%Y%m%d%H%M.%S)"
printf 'coord-probe-9-otherrun00000000\n1\n' > "$tokf"; touch -t "$ts" "$tokf"
pr "an old token of a short run" 0 --project "$proj" --worker-settings "$ws" --timeout 600
hasre "stale token file .*/proj/\.claude/coordinator-probe\.txt \(1[0-9][0-9] s old: a run killed before its end\): overwritten"
printf 'coord-probe-9-otherrun00000000\n600\n' > "$tokf"; touch -t "$ts" "$tokf"
keeptok=1 pr "an old token of a long run" 1 --project "$proj" --worker-settings "$ws" --timeout 1
hasre "BLOCKED probes: another probes run on this project \(started 1[0-9][0-9] s ago; if none is running, remove .*\)"
printf 'coord-probe-9-otherrun00000000\nsoon\n' > "$tokf"; touch -t "$ts" "$tokf"
keeptok=1 pr "an old token, its timeout not a number (300)" 1 --project "$proj" --worker-settings "$ws" --timeout 1
hasre "BLOCKED probes: another probes run on this project \(started 1[0-9][0-9] s ago; if none is running, remove .*\)"
rm -f "$tokf"
scn swap block editblock
keeptok=1 pr "the file taken over meanwhile" 0 --project "$proj" --worker-settings "$ws"
n=$((n + 1)); [ "$(cat "$tokf" 2>/dev/null)" = coord-probe-1-anotherrun0000 ] || bad "another run's token file was removed"
rm -f "$tokf"
n=$((n + 1)); [ -f "$tmp/proj/.claude/keep.txt" ] || bad "a .claude folder that was there was removed"

# a transcript that never appears is not "no answer"
scn notx block editblock
pr "no transcript" 1 --project "$proj" --worker-settings "$ws" --timeout 2
has "FAIL probes: push: no transcript for session $(head -n 1 "$STUB_DIR/ids") under $T/cfg/projects: the daemon may use another CLAUDE_CONFIG_DIR"
# two transcripts for one id: the ambiguous message, not "no transcript"
scn amb block editblock
pr "an ambiguous id" 1 --project "$proj" --worker-settings "$ws" --timeout 2
i="$(head -n 1 "$STUB_DIR/ids")"
has "FAIL probes: push: ambiguous session $i: $i-0000-4000-8000-000000000001 $i-copy"

# a fresh token per run
scn block block editblock
pr "a second run" 0 --project "$proj" --own --model sonnet
launched "probe: push (own settings)" 2 sonnet
n=$((n + 1)); [ "$(awk -F'|' 'NR == 1 { print $7 }' "$STUB_DIR/log")" != "$t" ] || bad "the same token as the run before"

# the transcript appears late: polled until its turn ends, the token file kept until then
scn slowblock block editblock
pr "a late transcript" 0 --project "$proj" --worker-settings "$ws"
has "PASS probes: push: the command holding the probe token was blocked through Claude Code"

scn noblock block editblock
pr "no block" 1 --project "$proj" --worker-settings "$ws" --own
has "FAIL probes: push: no block: the hook did not run from these settings, or it runs a guard older than this core (no probe-token rule)"
has "PASS probes: push (own settings): the command holding the probe token was blocked through Claude Code"
has "selftest probes: 1 pass, 1 fail, 0 skipped"

scn nonblock block editblock
pr "a non-blocking error" 1 --project "$proj" --worker-settings "$ws"
has "FAIL probes: push: the guard blocked, but Claude Code got it as a non-blocking error: a shell wrapper turns exit 2 into 1"

scn quote pushblock editblock
pr "the block quoted in a message, a push block" 1 --project "$proj" --worker-settings "$ws" --own
has "FAIL probes: push: no block: the hook did not run from these settings, or it runs a guard older than this core (no probe-token rule)"
has "FAIL probes: push (own settings): no block: the hook did not run from these settings, or it runs a guard older than this core (no probe-token rule)"

scn noid refused editblock
pr "launch failed" 1 --project "$proj" --worker-settings "$ws" --own
has "BLOCKED probe: push (launch failed: Started.)"
has "BLOCKED probe: push (own settings) (launch failed: Error: refused by policy)"
has "selftest probes: 0 pass, 0 fail, 0 skipped, 2 blocked"
lacks "^stopped:"

scn block noid editblock
pr "one launched, one not" 1 --project "$proj" --worker-settings "$ws" --own
has "PASS probes: push: the command holding the probe token was blocked through Claude Code"
has "BLOCKED probe: push (own settings) (launch failed: Started.)"
has "selftest probes: 1 pass, 0 fail, 0 skipped, 1 blocked"

# the time is up: judged as the transcript stands - a block already there passes, nothing yet fails
scn silent silent editblock
pr "no end of the turn, nothing yet" 1 --project "$proj" --worker-settings "$ws" --own --timeout 2
has "FAIL probes: push: no answer within 2 s"
has "FAIL probes: push (own settings): no answer within 2 s"
scn noend nonblock editblock
pr "no end of the turn, the block there" 0 --project "$proj" --worker-settings "$ws" --timeout 2
has "PASS probes: push: the command holding the probe token was blocked through Claude Code"
scn noendnb block editnoend
pr "no end of the turn, a non-blocking error, an edit block" 1 --project "$proj" --worker-settings "$ws" --edit-root "$root" --timeout 2
has "FAIL probes: push: the guard blocked, but Claude Code got it as a non-blocking error: a shell wrapper turns exit 2 into 1"
has "PASS probes: edit: the edit tool's write into the working copy was blocked through Claude Code"

# the edit probe: the guard's working-copy block; a file it created is removed (exactly that file);
# one there before the run is left
scn block block editblock
pr "edit blocked" 0 --project "$proj" --worker-settings "$ws" --edit-root "$root/"
has "PASS probes: edit: the edit tool's write into the working copy was blocked through Claude Code"
launched "probe: edit" 3 "$ws"
n=$((n + 1)); grep -qxF "Use the Write tool to create $root/probe-root.txt containing x. Do not retry it another way. Report in one line what happened, and stop." "$STUB_DIR/prompts" ||
  bad "the edit probe's prompt does not name $root/probe-root.txt"
echo keep > "$tmp/root/other.txt"
scn block block editwrite
pr "edit went through" 1 --project "$proj" --worker-settings "$ws" --edit-root "$root"
has "FAIL probes: edit: the write into the working copy went through: COORD_PROTECTED_ROOT is not in the settings' env, or its matcher leaves out the edit tools"
has "removed $root/probe-root.txt, which the edit probe created"
n=$((n + 1)); [ ! -e "$tmp/root/probe-root.txt" ] && [ -f "$tmp/root/other.txt" ] || bad "probe-root.txt left, or another file removed"
echo before > "$tmp/root/probe-root.txt"
scn block block editblock
pr "a probe-root.txt from before" 0 --project "$proj" --worker-settings "$ws" --edit-root "$root"
has "left as it was: $root/probe-root.txt was there before the edit probe"
n=$((n + 1)); [ "$(cat "$tmp/root/probe-root.txt")" = before ] || bad "the earlier probe-root.txt was changed"
# ... unless the probe changed it: said, a FAIL, and the file is not removed
scn block block editwrite
pr "a probe-root.txt from before, changed" 1 --project "$proj" --worker-settings "$ws" --edit-root "$root"
has "FAIL probes: edit: changed by the edit probe: $root/probe-root.txt"
lacks "^removed \|^left as it was"
n=$((n + 1)); [ "$(cat "$tmp/root/probe-root.txt")" = x ] || bad "the changed probe-root.txt was removed"
rm "$tmp/root/probe-root.txt"
# the edit root made absolute, as the worker settings are
scn block block editblock
pr "edit root not in its plain form" 0 --project "$proj" --worker-settings "$ws" --edit-root "$root/."
n=$((n + 1)); grep -qxF "Use the Write tool to create $root/probe-root.txt containing x. Do not retry it another way. Report in one line what happened, and stop." "$STUB_DIR/prompts" ||
  bad "the edit probe's prompt does not name $root/probe-root.txt"

# what cannot run
pr "no project folder" 1 --project "$T/nowhere" --own
has "FAIL probes: no folder $T/nowhere"
pr "no settings file" 1 --project "$proj" --worker-settings "$T/none.json"
has "FAIL probes: no settings file $T/none.json"
scn block block editblock
pr "no edit root" 1 --project "$proj" --worker-settings "$ws" --edit-root "$T/noroot"
has "FAIL probes: edit: no folder $T/noroot"
has "PASS probes: push: the command holding the probe token was blocked through Claude Code"

# Ctrl-C and the like: the token file goes and the sessions are stopped (bash: a trap; the .ps1's
# finally is not reached by a signal from outside, so only the .sh is tested here)
if [ "$kind" = sh ]; then
  cur="interrupted"; scn silent block editblock; : > "$STUB_DIR/stops"; : > "$STUB_DIR/ids"
  bash scripts/selftest.sh probes --project "$proj" --worker-settings "$ws" --timeout 60 > "$tmp/one" 2>&1 &
  pid=$!; i=0
  # signalled once it waits for the transcript (a signal during the launch itself loses the id it
  # has not read yet)
  while [ $i -lt 30 ] && ! [ -s "$STUB_DIR/ids" ]; do sleep 1; i=$((i + 1)); done
  sleep 3
  kill -TERM "$pid"; wait "$pid"
  n=$((n + 1)); [ ! -e "$tokf" ] || bad "the token file is still there"
  n=$((n + 1)); [ -s "$STUB_DIR/ids" ] && grep -qx "$(head -n 1 "$STUB_DIR/ids")" "$STUB_DIR/stops" || bad "the session was not stopped"
fi

# usage errors: no probe asked for, no project, the edit probe without the worker file, a bad timeout,
# another step's parameter
usage() {   # usage <selftest.sh arguments>: exit 2, no PASS / FAIL line, nothing launched
  cur="usage: $*"; n=$((n + 1)); : > "$STUB_DIR/log"
  st "$@" > "$tmp/one" 2>&1; rc=$?
  { [ "$rc" = 2 ] && ! grep -q '^PASS \|^FAIL \|^BLOCKED ' "$tmp/one" && [ ! -s "$STUB_DIR/log" ]; } ||
    bad "expected a usage error (exit 2), got exit $rc"
}
usage probes
usage probes --project "$proj"
usage probes --own
usage probes --project "$proj" --edit-root "$root"
usage probes --project "$proj" --own --timeout 0
usage probes --project "$proj" --own --timeout 5s
usage probes --project "$proj" --own extra
usage probes --project "$proj" --own --session s1
usage probes --project "$proj" --own --settings "$ws"
usage hooks --settings tests/selftest/hooks/good.json --own
usage hookcheck --session probeblk --timeout 5
usage hookcheck --session probeblk --expect token

# hookcheck --expect probe: only the guard's probe-token block in a tool's result passes; the push
# probe's default check never passes on it
hc() {   # hc <expect> <session> <expected exit> <expected line>
  cur="hookcheck --session $2 --expect $1"; n=$((n + 1))
  CLAUDE_CONFIG_DIR=tests/selftest/claude st hookcheck --session "$2" --expect "$1" > "$tmp/one" 2>&1; rc=$?
  { [ "$rc" = "$3" ] && tr -d '\r' < "$tmp/one" | grep -qxF -- "$4"; } || bad "expected exit $3 and '$4', got exit $rc"
}
hc probe probeblk 0 'PASS hookcheck: the command holding the probe token was blocked through Claude Code'
hc probe probeqt0 1 'FAIL hookcheck: no block: the hook did not run from these settings, or it runs a guard older than this core (no probe-token rule)'
hc probe blocked0 1 'FAIL hookcheck: no block: the hook did not run from these settings, or it runs a guard older than this core (no probe-token rule)'
hc probe editblk0 1 'FAIL hookcheck: no block: the hook did not run from these settings, or it runs a guard older than this core (no probe-token rule)'
hc probe nonblock 1 'FAIL hookcheck: the guard blocked, but Claude Code got it as a non-blocking error: a shell wrapper turns exit 2 into 1'
hc push probeblk 1 'FAIL hookcheck: no block in the transcript: the hook did not run (its path, its shell, or the settings were not loaded)'
hc push blocked0 0 'PASS hookcheck: the push to a protected branch was blocked through Claude Code'
hc edit editblk0 0 "PASS hookcheck: the edit tool's write into the working copy was blocked through Claude Code"

echo "selftest probes ($kind): $n checks, $( [ $fail = 0 ] && echo all pass || echo FAILURES )"
exit $fail
