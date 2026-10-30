#!/usr/bin/env bash
# `selftest assistant` (#281, sub-contract 281.3) against a stub `claude` first on PATH (the real claude is
# never called): the throwaway assistant is started with the core's start-worker, its transcript is written by
# the stub - the Write outside its folder and the `git commit` fed to the guard named in the --settings file it
# got, with that file's env, so the blocks come from this core's guard - and judged; cleanup-worker and the
# session check of `selftest clean` run against the stub's listing; at the end the session, its status file and
# the throwaway folder are gone. Each run's scenario is set by STUB_ASST.
#   tests/selftest/assistant.sh sh                  # selftest.sh, with the bash running this file
#   tests/selftest/assistant.sh ps pwsh             # selftest.ps1 (or: ps powershell)
# Exit 1 if any check fails.
#
# Access points (281.3; the worker implements them as written here):
#   - the subcommand: selftest.sh assistant --project <root> --core <core> [--model <m>] [--timeout <s>]
#     (selftest.ps1 assistant -Project -Core -Model -Timeout); a missing --project or --core, a timeout that is
#     not a whole number above 0, a stray word or another step's parameter (--own) is a usage error: exit 2, no
#     PASS / FAIL line, nothing launched. COORD_PROBE_POLL (seconds) sets the transcript poll, as for probes.
#   - its check lines start `PASS assistant: ` or `FAIL assistant: `, one per check, each naming its check by:
#       `RUNS.tsv`          the run log was read and the answer holds the token
#       `Write`             the Write outside the folder was blocked by the guard
#       `git commit`        the git commit was blocked by the guard
#       `cleanup-worker`    cleanup-worker --session <id> exited 6 and changed nothing
#       `selftest clean`    the self-test session check leaves the session listed
#     (each word in exactly one line); the LAST line is `assistant: <n> PASS, <m> FAIL`, n and m the counts of
#     those lines; exit 0 only when m is 0 (and nothing failed to launch).
#   - the launch (claude --bg, by start-worker): --name "assistant: selftest-<token>", --model (haiku by
#     default), --settings <a file filled from settings.example.assistant(.windows).json: no ABSOLUTE left, the
#     guard of --core, env COORD_ASSISTANT_DIR the throwaway folder .../assistants/selftest-<token>, which holds
#     BRIEF.md and an empty NOTES.md at launch>, from the project root. The folder lies outside the project's
#     coordinator/assistants/ and no git working tree sees it. BRIEF.md names the run log by a path ending in
#     RUNS.tsv (absolute, or relative to the folder), says `git commit --allow-empty -m x` and Write.
#   - the transcript the stub writes ($CLAUDE_CONFIG_DIR/projects/stub/<sessionId>.jsonl, the short id the
#     sessionId's first 8 characters; launch output `backgrounded · <id> · <name>` and `claude stop <id>`), in
#     JSON lines as Claude Code writes them: the prompt; a Read tool_use of the RUNS.tsv and its tool_result (the
#     file's text); an assistant text answer quoting that text; a Write tool_use (file_path outside the folder)
#     and its tool_result - the guard's block as `PreToolUse:Write hook error: [<cmd>]: Blocked by
#     safety-guard: ...` with is_error, or `File created successfully at: <path>`; a Bash tool_use
#     `git commit --allow-empty -m x` and its tool_result - the block as `PreToolUse:Bash hook error: ...` with
#     is_error, or `[main 0a1b2c3] x`; then a text `Done.` and {"type":"system","subtype":"turn_duration"}.
#     STUB_ASST: pass (default), noread (no Read, an answer without the token), notoken (the Read, an answer
#     without the token), writeok (the Write went through), commitok (the commit went through), silent (only the
#     prompt, no end of the turn), notx (no transcript), launchfail (claude --bg exits 1).
#   - the session's status file: $CLAUDE_CONFIG_DIR/coordinator/sessions/<sessionId>.json (the stub writes it
#     at launch, as the status line would); the end removes it, stops the session (claude stop <id>, once) and
#     removes it (claude rm <id>, once, after the stop) - also after a FAIL or a timeout.
set -u
[ $# -gt 0 ] || { sed -n '2,10s/^# \{0,1\}//p' "$0"; exit 2; }
kind="$1"; shift; PS=("$@")
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mp() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
core="$(mp "$core")"; T="$(mp "$tmp")"
cd "$core" || exit 1
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*|Darwin) fold=1 ;; *) fold="" ;; esac
# a folder in one form for comparing: / separators, no trailing /, C:/ on Windows, one letter case where paths ignore it
canon() {
  local q; [ -n "$1" ] || return 0; q="$( (cd -P "$1" 2>/dev/null && pwd -P) || printf '%s' "$1")"; q="$(mp "$q" | tr '\\' '/')"
  while :; do case "$q" in ?*/) q="${q%/}" ;; *) break ;; esac; done
  if [ -n "$fold" ]; then printf '%s' "$q" | tr '[:upper:]' '[:lower:]'; else printf '%s' "$q"; fi
}

mkdir -p "$tmp/bin" "$tmp/stub" "$tmp/cfg"
cat > "$tmp/bin/claude" <<'EOF'
#!/usr/bin/env bash
# the stub claude of tests/selftest/assistant.sh: sessions in $STUB_DIR/sessions, one per line
# `<id>|<sessionId>|<state>|<cwd>|<name>`; every call logged in $STUB_DIR/log
D="$STUB_DIR"; S="$D/sessions"; [ -f "$S" ] || : > "$S"
printf '%s\n' "$*" >> "$D/log"
jesc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk 'NR > 1 { printf "\\n" } { gsub(/\t/, "\\t"); gsub(/\r/, "\\r"); printf "%s", $0 }'; }
case "${1:-}" in
  agents)
    all=""; case " $* " in *" --all "*) all=1 ;; esac
    printf '['; m=0
    while IFS='|' read -r i s st c nm; do
      [ -n "$i" ] || continue
      [ "$st" != done ] || [ -n "$all" ] || continue
      [ $m = 0 ] || printf ','; m=1
      printf '\n  {\n    "id": "%s",\n    "cwd": "%s",\n    "sessionId": "%s",\n    "name": "%s",\n    "state": "%s"\n  }' "$i" "$(jesc "$c")" "$s" "$(jesc "$nm")" "$st"
    done < "$S"
    printf '\n]\n'; exit 0 ;;
  stop|rm)
    st="$(awk -F'|' -v i="${2:-}" '$1 == i { print $3; exit }' "$S")"
    [ -n "$st" ] || { echo "No job matching '${2:-}'. Run claude agents to list jobs." >&2; exit 1; }
    if [ "$1" = stop ]; then awk -F'|' -v OFS='|' -v i="$2" '$1 == i { $3 = "done" } { print }' "$S" > "$S.new"; echo "stopped $2"
    else awk -F'|' -v i="$2" '$1 != i' "$S" > "$S.new"; echo "removed $2"; fi
    mv "$S.new" "$S"; exit 0 ;;
  --bg) ;;
  *) exit 0 ;;
esac
shift; name="" model="" settings="" prompt=""
while [ $# -gt 0 ]; do
  case "$1" in
    --name) name="$2"; shift 2 ;; --model) model="$2"; shift 2 ;; --settings) settings="$2"; shift 2 ;;
    --permission-mode|--effort) shift 2 ;; --*) shift ;;
    *) prompt="$1"; shift ;;
  esac
done
scn="${STUB_ASST:-pass}"
cwd="$(pwd -P)"; command -v cygpath >/dev/null 2>&1 && cwd="$(cygpath -m "$cwd")"
printf 'launch|%s|%s|%s|%s\n' "$name" "$model" "$settings" "$cwd" >> "$D/launches"
printf '%s' "$prompt" > "$D/prompt"
# the facts at launch: the settings as given, the folder they name (copied), what git sees
sv() { sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$D/settings.json" | head -n 1 | sed 's/\\\\/\\/g'; }
cp "$settings" "$D/settings.json" 2>/dev/null || : > "$D/settings.json"
adir="$(sv COORD_ASSISTANT_DIR)"; proot="$(sv COORD_PROTECTED_ROOT)"; pbr="$(sv COORD_PROTECTED_BRANCHES)"
printf '%s' "$adir" > "$D/adir"
rm -rf "$D/atlaunch"; mkdir -p "$D/atlaunch"; [ -z "$adir" ] || cp -R "$adir/." "$D/atlaunch/" 2>/dev/null
git -C "$cwd" status --porcelain --untracked-files=all > "$D/gitstatus" 2>&1
if [ -n "$adir" ] && git -C "$adir" rev-parse --show-toplevel >/dev/null 2>&1; then
  git -C "$adir" status --porcelain --untracked-files=all -- . > "$D/foldergit" 2>&1
else : > "$D/foldergit"; fi
# the run log the brief points to: a path ending in RUNS.tsv, absolute or relative to the folder
rl="$(grep -o '[^][ "'"'"'`<>()]*RUNS\.tsv' "$adir/BRIEF.md" 2>/dev/null | head -n 1)"
case "$rl" in ''|/*|[A-Za-z]:*) ;; *) rl="$adir/$rl" ;; esac
printf '%s' "$rl" > "$D/runs"; rm -f "$D/runs.tsv"; [ -n "$rl" ] && [ -f "$rl" ] && cp "$rl" "$D/runs.tsv"
[ "$scn" != launchfail ] || { echo "Error: the stub refused the launch" >&2; exit 1; }
k=$(($(cat "$D/count" 2>/dev/null || echo 0) + 1)); echo "$k" > "$D/count"
id="$(printf 'a%07d' "$k")"; sid="$id-0000-4000-8000-000000000001"
nc="$cwd"; command -v cygpath >/dev/null 2>&1 && nc="$(cygpath -w "$cwd")"
printf '%s|%s|running|%s|%s\n' "$id" "$sid" "$nc" "$name" >> "$S"
printf '%s\n' "$id" >> "$D/ids"
mkdir -p "$CLAUDE_CONFIG_DIR/coordinator/sessions" && printf '{"session_id":"%s"}\n' "$sid" > "$CLAUDE_CONFIG_DIR/coordinator/sessions/$sid.json"
# the guard's verdict on a tool call, run as Claude Code runs the PreToolUse hook of these settings
gcmd="$(grep 'safety-guard\.' "$D/settings.json" | grep -v -e '--self-test' -e '-SelfTest' | head -n 1 |
  sed 's/.*"command"[[:space:]]*:[[:space:]]*"//; s/"[[:space:]]*,\{0,1\}[[:space:]]*$//; s/\\"/"/g')"
printf '%s' "$gcmd" > "$D/guardcmd"
guard() {   # guard <tool> <tool_input JSON>: the guard's stderr in $gerr, its exit in $grc
  [ -n "$gcmd" ] || { gerr="no guard command in the settings"; grc=0; return; }
  gerr="$(printf '{"tool_name":"%s","tool_input":%s,"cwd":"%s"}' "$1" "$2" "$(jesc "$cwd")" |
    env COORD_ASSISTANT_DIR="$adir" COORD_PROTECTED_ROOT="$proot" COORD_PROTECTED_BRANCHES="$pbr" CLAUDE_PROJECT_DIR="$cwd" bash -c "$gcmd" 2>&1 >/dev/null)"; grc=$?
}
use() { printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t%s","name":"%s","input":%s}]}}\n' "$3" "$1" "$2"; }
result() {   # result <id> <content> [error]
  printf '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t%s","content":"%s"%s}]}}\n' "$1" "$(jesc "$2")" "${3:+,\"is_error\":true}"
}
say() { printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$(jesc "$1")"; }
mp() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
out="$(mp "$D/outside.txt")"
write() {
  printf '{"type":"user","message":{"content":"%s"}}\n' "$(jesc "$prompt")"
  [ "$scn" != silent ] || return 0
  case "$scn" in
    noread) say "I found no run log to read." ;;
    *) use Read "{\"file_path\":\"$(jesc "$rl")\"}" 1
       if [ -f "$rl" ]; then result 1 "$(cat "$rl")"; else result 1 "File does not exist." error; fi
       if [ "$scn" = notoken ]; then say "I read the run log."
       else say "The run log RUNS.tsv holds: $(tr '\t\r\n' '   ' < "$rl" 2>/dev/null)"; fi ;;
  esac
  wi="{\"file_path\":\"$(jesc "$out")\",\"content\":\"x\"}"
  use Write "$wi" 2
  if [ "$scn" = writeok ]; then printf 'x' > "$D/outside.txt"; result 2 "File created successfully at: $out"
  else guard Write "$wi"
    if [ "$grc" = 2 ]; then result 2 "PreToolUse:Write hook error: [$gcmd]: $gerr" error
    else printf 'x' > "$D/outside.txt"; result 2 "File created successfully at: $out"; fi
  fi
  ci='{"command":"git commit --allow-empty -m x"}'
  use Bash "$ci" 3
  if [ "$scn" = commitok ]; then result 3 "[main 0a1b2c3] x"
  else guard Bash "$ci"
    if [ "$grc" = 2 ]; then result 3 "PreToolUse:Bash hook error: [$gcmd]: $gerr" error
    else result 3 "[main 0a1b2c3] x"; fi
  fi
  say "Done."
  printf '{"type":"system","subtype":"turn_duration","durationMs":4210}\n'
}
if [ "$scn" != notx ]; then
  dir="$CLAUDE_CONFIG_DIR/projects/stub"; mkdir -p "$dir"; write > "$dir/$sid.jsonl"
fi
echo "backgrounded · $id · $name"
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
export PATH="$tmp/bin:$PATH" STUB_DIR="$T/stub" CLAUDE_CONFIG_DIR="$T/cfg" COORD_PROBE_POLL=1
unset COORD_PROTECTED_ROOT COORD_PROTECTED_BRANCHES COORD_ASSISTANT_DIR

# the project: a git repository with a state repository at coordinator/ (kept out by info/exclude, as start-worker
# and the init do) holding a real assistant's folder
g() { git -c user.email=t@t -c user.name=t -c core.autocrlf=false "$@"; }
proj="$T/proj"
git init -q -b main "$tmp/proj" && printf 'project\n' > "$tmp/proj/README.md" && g -C "$tmp/proj" add README.md && g -C "$tmp/proj" commit -q -m init
printf '/.claude/worktrees/\n/coordinator/\n' >> "$tmp/proj/.git/info/exclude"
git init -q -b main "$tmp/proj/coordinator"
mkdir -p "$tmp/proj/coordinator/assistants/timesheet"
printf 'Log the hours.\n' > "$tmp/proj/coordinator/assistants/timesheet/BRIEF.md"; printf '# Notes\n' > "$tmp/proj/coordinator/assistants/timesheet/NOTES.md"
g -C "$tmp/proj/coordinator" add -A && g -C "$tmp/proj/coordinator" commit -q -m state
realas() { (cd "$tmp/proj/coordinator/assistants" && find . | LC_ALL=C sort && cat timesheet/BRIEF.md timesheet/NOTES.md) | cksum; }
ra0="$(realas)"
pstate() { git -C "$tmp/proj" status --porcelain --ignored --untracked-files=all; git -C "$tmp/proj/coordinator" status --porcelain --ignored --untracked-files=all; }
ps0="$(pstate)"
pcwd="$(canon "$tmp/proj")"; rcanon="$(canon "$tmp/proj/coordinator/assistants")"

# st <selftest.sh arguments>: the .sh, or the .ps1 with the same arguments in its own form
st() {
  if [ "$kind" = sh ]; then bash scripts/selftest.sh "$@"; return; fi
  local a=() x
  for x in "$@"; do
    case "$x" in
      --project) x=-Project ;; --core) x=-Core ;; --model) x=-Model ;; --timeout) x=-Timeout ;; --own) x=-Own ;;
    esac
    a+=("$x")
  done
  "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File scripts/selftest.ps1 "${a[@]}"
}
fail=0; n=0; cur=""
bad() { echo "FAIL ($cur): $1"; [ -f "$tmp/one" ] && sed 's/^/    /' "$tmp/one"; fail=1; }
lines() { tr -d '\r' < "$tmp/one"; }
# ck <keyword> <PASS|FAIL>: exactly one check line names the keyword, with that verdict
ck() {
  n=$((n + 1))
  local l c; l="$(lines | grep -E '^(PASS|FAIL) assistant: ' | grep -F -- "$1")"; c="$(printf '%s' "$l" | grep -c .)"
  [ "$c" = 1 ] || { bad "expected one check line naming '$1', got $c"; return; }
  case "$l" in "$2 assistant: "*) ;; *) bad "the '$1' line is not $2: $l" ;; esac
}
# as <what> <expected exit> <selftest arguments>: one run of selftest assistant; its output in $tmp/one; then the
# checks every run must pass: the last line and its counts, the exit, the session gone (stopped once, removed once,
# after the stop), its status file gone, the throwaway folder gone, the project and its real assistants untouched
as() {
  cur="$1"; local want="$2" rc i last np nf c; shift 2
  : > "$STUB_DIR/log"; : > "$STUB_DIR/ids"; : > "$STUB_DIR/launches"; : > "$STUB_DIR/sessions"; rm -f "$STUB_DIR/adir" "$STUB_DIR/outside.txt"
  st assistant "$@" > "$tmp/one" 2>&1; rc=$?
  n=$((n + 1)); [ "$rc" = "$want" ] || bad "expected exit $want, got $rc"
  n=$((n + 1)); last="$(lines | awk 'NF { l = $0 } END { print l }')"
  np="$(lines | grep -c '^PASS assistant: ')"; nf="$(lines | grep -c '^FAIL assistant: ')"
  [ "$last" = "assistant: $np PASS, $nf FAIL" ] || bad "the last line is '$last', expected 'assistant: $np PASS, $nf FAIL'"
  n=$((n + 1)); [ "$nf" = 0 ] || [ "$rc" != 0 ] || bad "exit 0 with $nf FAIL lines"
  while IFS= read -r i; do
    [ -n "$i" ] || continue
    n=$((n + 1)); grep -q "^$i|" "$STUB_DIR/sessions" && bad "session $i is still listed"
    n=$((n + 1)); c="$(grep -cx "stop $i" "$STUB_DIR/log")"; [ "$c" = 1 ] || bad "session $i stopped $c times, expected once"
    n=$((n + 1)); c="$(grep -cx "rm $i" "$STUB_DIR/log")"; [ "$c" = 1 ] || bad "session $i removed $c times, expected once"
    n=$((n + 1)); awk -v i="$i" '$0 == "stop " i { s = NR } $0 == "rm " i { r = NR } END { exit !(s && r && s < r) }' "$STUB_DIR/log" ||
      bad "session $i was not stopped before its removal"
    n=$((n + 1)); [ ! -e "$tmp/cfg/coordinator/sessions/$i-0000-4000-8000-000000000001.json" ] || bad "the status file of $i is still there"
  done < "$STUB_DIR/ids"
  if [ -s "$STUB_DIR/adir" ]; then n=$((n + 1)); [ ! -e "$(cat "$STUB_DIR/adir")" ] || bad "the throwaway folder $(cat "$STUB_DIR/adir") is still there"; fi
  n=$((n + 1)); [ "$(pstate)" = "$ps0" ] || bad "the project's git sees something new: $(pstate | tr '\n' ' ')"
  n=$((n + 1)); [ "$(realas)" = "$ra0" ] || bad "the project's coordinator/assistants/ changed"
}
# launched <field> <value>: the launch line's field (2 the name, 3 the model, 4 the settings, 5 the cwd)
launched() { n=$((n + 1)); local v; v="$(awk -F'|' -v k="$1" 'NR == 1 { print $k }' "$STUB_DIR/launches")"; [ "$v" = "$2" ] || bad "launch field $1 is '$v', expected '$2'"; }

# --- the pass: every check line PASS; what the launch got ---
export STUB_ASST=pass
as "the pass" 0 --project "$proj" --core "$core"
ck RUNS.tsv PASS; ck Write PASS; ck "git commit" PASS; ck cleanup-worker PASS; ck "selftest clean" PASS
n=$((n + 1)); [ "$(grep -c . "$STUB_DIR/launches")" = 1 ] || bad "expected one launch, got $(grep -c . "$STUB_DIR/launches")"
nm="$(awk -F'|' 'NR == 1 { print $2 }' "$STUB_DIR/launches")"; ad="$(cat "$STUB_DIR/adir" 2>/dev/null)"
n=$((n + 1)); printf '%s\n' "$nm" | grep -Eqx 'assistant: selftest-[A-Za-z0-9._-]+' || bad "the session name '$nm' is not 'assistant: selftest-<token>'"
n=$((n + 1)); [ -n "$ad" ] && [ "assistant: $(basename "$ad")" = "$nm" ] || bad "COORD_ASSISTANT_DIR '$ad' is not the folder of '$nm'"
n=$((n + 1)); [ "$(basename "$(dirname "$ad")")" = assistants ] || bad "the folder $ad is not .../assistants/selftest-<token>"
n=$((n + 1)); case "$(canon "$ad")/" in "$rcanon/"*) bad "the folder $ad is inside the project's coordinator/assistants/" ;; esac
launched 3 haiku
n=$((n + 1)); [ "$(canon "$(awk -F'|' 'NR == 1 { print $5 }' "$STUB_DIR/launches")")" = "$pcwd" ] || bad "not launched from the project root: $(awk -F'|' 'NR == 1 { print $5 }' "$STUB_DIR/launches")"
n=$((n + 1)); [ "$(ls -A "$STUB_DIR/atlaunch" 2>/dev/null | grep -cx -e BRIEF.md -e NOTES.md)" = 2 ] || bad "the folder did not hold BRIEF.md and NOTES.md at launch: $(ls -A "$STUB_DIR/atlaunch" 2>/dev/null | tr '\n' ' ')"
n=$((n + 1)); [ -f "$STUB_DIR/atlaunch/NOTES.md" ] && [ ! -s "$STUB_DIR/atlaunch/NOTES.md" ] || bad "NOTES.md was not empty at launch"
n=$((n + 1)); grep -q '[^[:space:]]' "$STUB_DIR/atlaunch/BRIEF.md" 2>/dev/null || bad "BRIEF.md was empty at launch"
n=$((n + 1)); grep -qF 'git commit --allow-empty -m x' "$STUB_DIR/atlaunch/BRIEF.md" 2>/dev/null || bad "BRIEF.md does not say git commit --allow-empty -m x"
n=$((n + 1)); grep -qF 'Write' "$STUB_DIR/atlaunch/BRIEF.md" 2>/dev/null || bad "BRIEF.md does not say Write"
n=$((n + 1)); [ -s "$STUB_DIR/runs.tsv" ] || bad "BRIEF.md points to no RUNS.tsv that exists at launch ('$(cat "$STUB_DIR/runs" 2>/dev/null)')"
n=$((n + 1)); [ ! -s "$STUB_DIR/gitstatus" ] || bad "the project's git saw something at launch: $(tr '\n' ' ' < "$STUB_DIR/gitstatus")"
n=$((n + 1)); [ ! -s "$STUB_DIR/foldergit" ] || bad "a git working tree sees the throwaway folder: $(tr '\n' ' ' < "$STUB_DIR/foldergit")"
n=$((n + 1)); ! grep -q ABSOLUTE "$STUB_DIR/settings.json" || bad "the settings still hold an ABSOLUTE placeholder"
n=$((n + 1)); grep -q "$core/scripts/hooks/safety-guard\.\(sh\|ps1\)" "$STUB_DIR/guardcmd" || bad "the settings' guard is not the core's: $(cat "$STUB_DIR/guardcmd")"
n=$((n + 1)); [ ! -e "$STUB_DIR/outside.txt" ] || bad "the Write outside the folder went through with the guard of these settings"
r1="$(cat "$STUB_DIR/runs.tsv" 2>/dev/null)"; nm1="$nm"

# a second run: a fresh token, --model and --timeout taken
as "a second run, --model sonnet" 0 --project "$proj" --core "$core" --model sonnet --timeout 60
launched 3 sonnet
n=$((n + 1)); [ "$(awk -F'|' 'NR == 1 { print $2 }' "$STUB_DIR/launches")" != "$nm1" ] || bad "the same session name as the run before"
n=$((n + 1)); [ "$(cat "$STUB_DIR/runs.tsv" 2>/dev/null)" != "$r1" ] || bad "the same RUNS.tsv (token) as the run before"

# --- each FAIL, the rest still judged and everything removed ---
export STUB_ASST=noread
as "the run log not read" 1 --project "$proj" --core "$core"
ck RUNS.tsv FAIL; ck Write PASS; ck "git commit" PASS
export STUB_ASST=notoken
as "the answer without the token" 1 --project "$proj" --core "$core"
ck RUNS.tsv FAIL; ck Write PASS; ck "git commit" PASS
export STUB_ASST=writeok
as "the Write went through" 1 --project "$proj" --core "$core"
ck RUNS.tsv PASS; ck Write FAIL; ck "git commit" PASS
export STUB_ASST=commitok
as "the commit went through" 1 --project "$proj" --core "$core"
ck RUNS.tsv PASS; ck Write PASS; ck "git commit" FAIL
# the time is up: nothing in the transcript passes
export STUB_ASST=silent
as "no end of the turn" 1 --project "$proj" --core "$core" --timeout 2
ck RUNS.tsv FAIL; ck Write FAIL; ck "git commit" FAIL
export STUB_ASST=notx
as "no transcript" 1 --project "$proj" --core "$core" --timeout 2
ck RUNS.tsv FAIL; ck Write FAIL; ck "git commit" FAIL
# the launch fails: no PASS for the session's checks, the folder removed
export STUB_ASST=launchfail
as "the launch failed" 1 --project "$proj" --core "$core" --timeout 2
n=$((n + 1)); ! lines | grep -E '^PASS assistant: ' | grep -qF -e RUNS.tsv -e Write -e 'git commit' || bad "a session check passed although nothing was launched"
n=$((n + 1)); [ -s "$STUB_DIR/adir" ] || bad "start-worker was not reached"
export STUB_ASST=pass

# --- the worker's own case (281.3): interrupted (TERM) while it waits - the session and the folder still go.
# selftest.sh only: a TERM to Windows PowerShell runs no handler (its finally covers Ctrl-C and errors)
if [ "$kind" = sh ]; then
  cur="interrupted"; export STUB_ASST=silent
  : > "$STUB_DIR/log"; : > "$STUB_DIR/ids"; : > "$STUB_DIR/launches"; : > "$STUB_DIR/sessions"; rm -f "$STUB_DIR/adir"
  bash scripts/selftest.sh assistant --project "$proj" --core "$core" --timeout 60 > "$tmp/one" 2>&1 & bp=$!
  # TERM once it waits on the transcript (start-worker done: `started:`), at most 180 s on
  i=0; while [ "$i" -lt 360 ] && ! grep -q '^started: ' "$tmp/one"; do i=$((i + 1)); sleep 0.5; done
  n=$((n + 1)); grep -q '^started: ' "$tmp/one" || bad "not started within 180 s"
  kill -TERM "$bp" 2>/dev/null; wait "$bp"; rc=$?
  n=$((n + 1)); [ "$rc" != 0 ] || bad "exit 0 after a TERM"
  i="$(head -n 1 "$STUB_DIR/ids")"
  n=$((n + 1)); [ -n "$i" ] || bad "no session was launched before the TERM"
  if [ -n "$i" ]; then
    n=$((n + 1)); ! grep -q "^$i|" "$STUB_DIR/sessions" || bad "session $i is still listed after a TERM"
    n=$((n + 1)); [ "$(grep -cx "stop $i" "$STUB_DIR/log")" = 1 ] && [ "$(grep -cx "rm $i" "$STUB_DIR/log")" = 1 ] || bad "session $i not stopped and removed once each"
    n=$((n + 1)); [ ! -e "$tmp/cfg/coordinator/sessions/$i-0000-4000-8000-000000000001.json" ] || bad "the status file of $i is still there"
  fi
  n=$((n + 1)); [ -s "$STUB_DIR/adir" ] && [ ! -e "$(cat "$STUB_DIR/adir")" ] || bad "the throwaway folder is still there after a TERM"
  export STUB_ASST=pass
fi

# --- usage errors: exit 2, no PASS / FAIL line, nothing launched ---
usage() {
  cur="usage: $*"; n=$((n + 1)); : > "$STUB_DIR/launches"
  st "$@" > "$tmp/one" 2>&1; rc=$?
  { [ "$rc" = 2 ] && ! grep -q '^PASS \|^FAIL \|^BLOCKED ' "$tmp/one" && [ ! -s "$STUB_DIR/launches" ]; } ||
    bad "expected a usage error (exit 2), got exit $rc"
}
usage assistant
usage assistant --project "$proj"
usage assistant --core "$core"
usage assistant --project "$proj" --core "$core" --timeout 0
usage assistant --project "$proj" --core "$core" --timeout 5s
usage assistant --project "$proj" --core "$core" extra
usage assistant --project "$proj" --core "$core" --own

echo "selftest assistant ($kind): $n checks, $( [ $fail = 0 ] && echo all pass || echo FAILURES )"
exit $fail
