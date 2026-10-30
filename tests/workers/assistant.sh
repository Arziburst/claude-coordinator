#!/usr/bin/env bash
# The assistant checks of start-worker and cleanup-worker that must fail closed or agree (#281, sub-contract
# 281.3, the 281.2 review's M1-M4), against temporary repositories with stub `claude` and `gh` commands on PATH
# (the real claude is never called).
#   tests/workers/assistant.sh sh                 # the .sh scripts, with the bash running this file
#   tests/workers/assistant.sh ps pwsh            # the .ps1 scripts (or: ps powershell)
# The comparison of the two start-worker scripts (M1) runs both in either mode: with the PowerShell given, else
# powershell or pwsh from PATH (none: those cases are skipped, one line says so).
# Exit 1 if any check fails.
#
# Access points (281.3; the worker implements them as written here):
#   - the stub listing: STUB_AGENTS=ok (default, the sessions of $STUB_LOG.sessions as JSON), fail (exit 1, an
#     error on stderr, nothing on stdout), text (exit 0, `Error: not logged in` - no JSON list), empty (exit 0,
#     nothing at all); `claude stop` / `rm` work whatever STUB_AGENTS says.
#   - M2: an assistant start whose `claude agents --json --all` fails or prints no JSON list: exit 1, one output
#     line naming the listing (holding `claude agents`), no claude --bg. A worker's start with a failing listing:
#     as before (exit 0).
#   - M3: cleanup-worker --worktree <w> --session <id> whose listing fails or prints no JSON list: no claude stop,
#     no claude rm, the worktree, the branch and the session kept, an exit code that keeps (3, 4, 5 or 6 - never 0
#     or 1), one output line holding `claude agents`. With a working listing: cleaned as before (exit 0).
#   - M1: start-worker.sh and start-worker.ps1 (--dry-run) give the same exit for COORD_ASSISTANT_DIR written with
#     a trailing slash, in another letter case, in Git Bash's /c/ form, with backslashes, with a `..` segment,
#     through a link (a junction on Windows) to the repository, and for the brief given through that link; a
#     trailing slash, backslashes and a `..` segment are the same folder (both 0).
#   - M4: scripts/retro.sh's header (its top comment) says, in the sentence of the run log's rows by role, that
#     assistant rows are left out (`rows of the period by role` followed by `assistant` before the next period).
set -u
[ $# -gt 0 ] || { sed -n '2,9s/^# \{0,1\}//p' "$0"; exit 2; }
kind="$1"; shift; PS=("$@")
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
command -v cygpath >/dev/null 2>&1 && core="$(cygpath -m "$core")"
mtmp="$(cygpath -m "$tmp" 2>/dev/null || printf '%s' "$tmp")"
win=""; case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) win=1 ;; esac

mkdir -p "$tmp/bin"
cat > "$tmp/bin/claude" <<'EOF'
#!/usr/bin/env bash
# the stub claude of tests/workers/assistant.sh: sessions in $STUB_LOG.sessions (`<id> <sessionId> <state> <name>`)
printf '%s\n' "$*" >> "$STUB_LOG"
S="$STUB_LOG.sessions"; [ -f "$S" ] || : > "$S"
case "${1:-}" in
  --bg) printf '%s\n' "$3" >> "$STUB_LOG.names"; echo "backgrounded · s$(wc -l < "$STUB_LOG.names" | tr -d ' ') · $3"; exit 0 ;;
  agents)
    case "${STUB_AGENTS:-ok}" in
      fail) echo "Error: cannot reach the background daemon" >&2; exit 1 ;;
      text) echo "Error: not logged in"; exit 0 ;;
      empty) exit 0 ;;
    esac
    all=""; case " $* " in *" --all "*) all=1 ;; esac
    a="$(sed 's/\\/\\\\/g; s/"/\\"/g' "$STUB_LOG.names" 2>/dev/null | awk '{ printf "{\"id\":\"s%d\",\"name\":\"%s\",\"sessionId\":\"5e550000-0000-4000-8000-%012d\",\"state\":\"running\"}\n", NR, $0, NR }' | paste -sd, -)"
    b="$(awk -v all="$all" '$3 != "done" || all { n = $0; sub(/^[^ ]+ [^ ]+ [^ ]+ /, "", n)
      printf "%s{\n    \"id\": \"%s\",\n    \"sessionId\": \"%s\",\n    \"name\": \"%s\",\n    \"state\": \"%s\"\n  }", (m++ ? ",\n  " : ""), $1, $2, n, $3 }' "$S")"
    printf '[%s%s%s]\n' "$a" "$([ -n "$a" ] && [ -n "$b" ] && echo ,)" "$b"; exit 0 ;;
  stop|rm)
    st="$(awk -v i="$2" '$1 == i { print $3; exit }' "$S")"
    [ -n "$st" ] || { echo "No job matching '$2'. Run claude agents to list jobs." >&2; exit 1; }
    if [ "$1" = stop ]; then awk -v i="$2" '$1 == i { $3 = "done" } { print }' "$S" > "$S.new"; echo "stopped $2"
    else awk -v i="$2" '$1 != i' "$S" > "$S.new"; echo "removed $2"; fi
    mv "$S.new" "$S"; exit 0 ;;
esac
exit 0
EOF
cat > "$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
[ -n "${STUB_HEADS:-}" ] && printf '%s\n' "$STUB_HEADS"
exit 0
EOF
cat > "$tmp/bin/claude.ps1" <<'EOF'
& bash (Join-Path $PSScriptRoot 'claude') @args
exit $LASTEXITCODE
EOF
cat > "$tmp/bin/gh.ps1" <<'EOF'
if ($env:STUB_HEADS) { $env:STUB_HEADS }
exit 0
EOF
chmod +x "$tmp/bin/claude" "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" STUB_LOG="$tmp/claude.log" CLAUDE_CONFIG_DIR="$tmp/cfg"
: > "$STUB_LOG"; unset STUB_AGENTS

g() { git -c user.email=t@t -c user.name=t -c core.autocrlf=false "$@"; }
git init -q --bare "$tmp/remote.git"
git init -q -b main "$tmp/repo" && g -C "$tmp/repo" commit -q --allow-empty -m init
git -C "$tmp/repo" remote add origin "$tmp/remote.git" && git -C "$tmp/repo" push -q origin main 2>/dev/null
printf 'Fix the thing.\n' > "$tmp/brief.md"
sw() {   # sw <sh|ps>: the worker safety settings for that variant's guard
  if [ "$1" = ps ]; then sed 's#C:/ABSOLUTE/PATH/scripts/hooks/#'"$core"'/scripts/hooks/#g' "$core/settings.example.windows.json"
  else sed "s#/ABSOLUTE/PATH#$core#g" "$core/settings.example.json"; fi
}
sw "$kind" > "$tmp/safety.json"
grep -q "$core/scripts/hooks/safety-guard" "$tmp/safety.json" || { echo "FAIL: could not point the safety settings at $core"; exit 1; }

# runs <sh|ps> <script> <arguments in the .sh form>: the variant's script; the .ps1 with its own parameter names
runs() {
  local v="$1" f="$2"; shift 2
  if [ "$v" = ps ]; then
    local a=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --repo) a+=(-Repo "$2"); shift 2 ;; --name) a+=(-Name "$2"); shift 2 ;; --branch) a+=(-Branch "$2"); shift 2 ;;
        --model) a+=(-Model "$2"); shift 2 ;; --brief-file) a+=(-BriefFile "$2"); shift 2 ;; --safety) a+=(-Safety "$2"); shift 2 ;;
        --report-to) a+=(-ReportTo "$2"); shift 2 ;; --dry-run) a+=(-DryRun); shift ;;
        --assistant-dir) a+=(-AssistantDir "$2"); shift 2 ;;
        --worktree) a+=(-Worktree "$2"); shift 2 ;; --session) a+=(-Session "$2"); shift 2 ;;
        *) a+=("$1"); shift ;;
      esac
    done
    "${PSX[@]}" -NoProfile -ExecutionPolicy Bypass -File "$core/scripts/$f.ps1" "${a[@]}"
  else bash "$core/scripts/$f.sh" "$@"; fi
}
PSX=(${PS[@]+"${PS[@]}"})
start() { runs "$kind" start-worker "$@"; }
cleanup() { runs "$kind" cleanup-worker "$@"; }
fail=0; n=0
check() {   # check <expected exit> <description> -- command...
  local want="$1" what="$2" out rc; shift 3
  n=$((n + 1)); out="$("$@" 2>&1)"; rc=$?
  [ "$rc" = "$want" ] || { echo "FAIL ($what): expected exit $want, got $rc"; printf '%s\n' "$out" | sed 's/^/    /'; fail=1; }
  LAST="$out"; LRC=$rc
}
listing_line() {   # listing_line <what>: one output line names the listing (claude agents)
  n=$((n + 1))
  printf '%s\n' "$LAST" | tr -d '\r' | grep -qF 'claude agents' || { echo "FAIL ($1): no line names the failed listing (claude agents)"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }
}

# --- M2: an assistant start fails closed when the listing of sessions fails ---
ar="$tmp/arepo"; mar="$mtmp/arepo"
git init -q -b main "$ar" && g -C "$ar" commit -q --allow-empty -m init
mkas() {   # mkas <name> <env folder> [<settings variant>]: the folder with BRIEF.md and NOTES.md; settings in $asf
  ad="$ar/coordinator/assistants/$1"; mkdir -p "$ad"
  printf 'Log the hours (%s).\n' "$1" > "$ad/BRIEF.md"; printf '# Notes\n' > "$ad/NOTES.md"
  asf="$tmp/as-$1-${3:-$kind}.json"
  sw "${3:-$kind}" | awk -v d="$2" '/"COORD_PROTECTED_ROOT"/ { print "    \"COORD_ASSISTANT_DIR\": \"" d "\"," } { print }' > "$asf"
  grep -q '"COORD_ASSISTANT_DIR"' "$asf" || { echo "FAIL: could not write the assistant settings $asf"; fail=1; }
}
mkas fc "$mar/coordinator/assistants/fc"
A=(--repo "$ar" --name "assistant: fc" --model sonnet --brief-file "$ad/BRIEF.md" --safety "$asf" --report-to "Core lead")
for m in fail text empty; do
  : > "$STUB_LOG"; : > "$STUB_LOG.names"
  STUB_AGENTS=$m check 1 "start: an assistant, the listing $m" -- start "${A[@]}"
  listing_line "start: an assistant, the listing $m"
  n=$((n + 1)); grep -q -- '--bg' "$STUB_LOG" && { echo "FAIL (start: an assistant, the listing $m): claude --bg was started"; fail=1; }
done
# the negative control: a working listing starts it
: > "$STUB_LOG"; : > "$STUB_LOG.names"
check 0 "start: an assistant, the listing works" -- start "${A[@]}"
n=$((n + 1)); grep -q -- '--bg --name assistant: fc' "$STUB_LOG" || { echo "FAIL (start: an assistant, the listing works): not launched"; fail=1; }
: > "$STUB_LOG.names"
# --- the worker's own cases (281.3): --assistant-dir, and the settings never inside the assistant's folder ---
mkx() {   # mkx <folder> <name>: a folder with BRIEF.md and NOTES.md outside the repository; settings in $asf
  mkdir -p "$1"; printf 'Log the hours.\n' > "$1/BRIEF.md"; printf '# Notes\n' > "$1/NOTES.md"
  asf="$tmp/ax-$2-$kind.json"
  sw "$kind" | awk -v d="$(cygpath -m "$1" 2>/dev/null || printf '%s' "$1")" '/"COORD_PROTECTED_ROOT"/ { print "    \"COORD_ASSISTANT_DIR\": \"" d "\"," } { print }' > "$asf"
}
xd() { start --repo "$ar" --name "assistant: $1" --model sonnet --brief-file "$2/BRIEF.md" --safety "$asf" --report-to x --assistant-dir "$2" --dry-run; }
mkx "$tmp/ext/assistants/xa" xa
check 0 "--assistant-dir: a folder outside every git working tree" -- xd xa "$tmp/ext/assistants/xa"
mkx "$tmp/ext/assistants/other" xb
check 1 "--assistant-dir: a folder not named as the assistant" -- xd xb "$tmp/ext/assistants/other"
mkx "$tmp/ext/notas/xc" xc
check 1 "--assistant-dir: a folder whose parent is not assistants" -- xd xc "$tmp/ext/notas/xc"
mkx "$ar/inside/assistants/xd" xd
check 1 "--assistant-dir: a folder a git working tree sees" -- xd xd "$ar/inside/assistants/xd"
rm -rf "$ar/inside"
check 1 "--assistant-dir with a worker's name" -- start --repo "$tmp/repo" --name "#72 worker: Fix" --branch 72-fix --model opus --brief-file "$tmp/brief.md" --safety "$tmp/safety.json" --report-to x --assistant-dir "$tmp/ext/assistants/xa" --dry-run
mkas inset "$mar/coordinator/assistants/inset"; cp "$asf" "$ad/settings.json"
check 1 "the --safety file inside the assistant's folder" -- start --repo "$ar" --name "assistant: inset" --model sonnet --brief-file "$ad/BRIEF.md" --safety "$ad/settings.json" --report-to x --dry-run
n=$((n + 1)); printf '%s\n' "$LAST" | grep -q "lies in the assistant's folder" || { echo "FAIL (the --safety file inside the folder): not the refusal of it"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }
: > "$STUB_LOG.names"
# other roles: unchanged by a failing listing
STUB_AGENTS=fail check 0 "start: a worker, the listing fails, dry run" -- start --repo "$tmp/repo" --name "#70 worker: Fix" --branch 70-fix --model opus --brief-file "$tmp/brief.md" --safety "$tmp/safety.json" --report-to x --dry-run
# a real start is launched (its exit after the launch, with no listing to wait on, is not this contract's)
: > "$STUB_LOG"
LAST="$(STUB_AGENTS=fail start --repo "$tmp/repo" --name "#71 worker: Fix" --branch 71-fix --model opus --brief-file "$tmp/brief.md" --safety "$tmp/safety.json" --report-to x 2>&1)"
n=$((n + 1)); grep -q -- '--bg --name #71 worker: Fix' "$STUB_LOG" || { echo "FAIL (start: a worker, the listing fails): not launched"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }
git -C "$tmp/repo" worktree remove --force "$tmp/repo/.claude/worktrees/71-fix" 2>/dev/null; git -C "$tmp/repo" branch -q -D 71-fix 2>/dev/null
: > "$STUB_LOG.names"

# --- M3: cleanup-worker --session never stops or removes when the listing fails ---
mk() {   # mk <branch>: a worktree with one commit, pushed with -u; its path in $w, its head in $h
  w="$tmp/repo/.claude/worktrees/$1"
  git -C "$tmp/repo" worktree add -q -b "$1" "$w" main && g -C "$w" commit -q --allow-empty -m "$1" &&
    git -C "$w" push -q -u origin "$1" 2>/dev/null
  h="$(git -C "$w" rev-parse HEAD)"
}
SS="$STUB_LOG.sessions"
for v in "fail|a5515701" "text|a5515701" "empty|a5515701" "fail|a5515701-1111-4222-8333-444455556666"; do
  m="${v%%|*}"; s="${v#*|}"; br="80-$m-${#s}"
  mk "$br"
  printf '%s %s %s %s\n' a5515701 a5515701-1111-4222-8333-444455556666 running "assistant: timesheet" > "$SS"
  : > "$STUB_LOG"
  what="cleanup: --session $s, the listing $m"
  n=$((n + 1)); LAST="$(STUB_AGENTS=$m STUB_HEADS="$h" cleanup --worktree "$w" --session "$s" 2>&1)"; LRC=$?
  case "$LRC" in 3|4|5|6) ;; *) echo "FAIL ($what): exit $LRC, expected a kept code (3, 4, 5 or 6)"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1 ;; esac
  listing_line "$what"
  n=$((n + 1)); grep -q -e '^stop' -e '^rm' "$STUB_LOG" && { echo "FAIL ($what): a session was stopped or removed:"; sed 's/^/    /' "$STUB_LOG"; fail=1; }
  n=$((n + 1)); grep -q '^a5515701 .* running assistant: timesheet$' "$SS" || { echo "FAIL ($what): the session was changed: $(cat "$SS")"; fail=1; }
  n=$((n + 1)); [ -d "$w" ] && git -C "$tmp/repo" show-ref -q --verify "refs/heads/$br" || { echo "FAIL ($what): the worktree or branch was removed"; fail=1; }
done
# the negative control: a working listing, an ordinary worker's merged task - cleaned as before
mk 81-ok
printf '%s %s %s %s\n' c0ffee81 c0ffee81-1111-4222-8333-444455556666 running "#81 worker: Fix" > "$SS"
: > "$STUB_LOG"
STUB_HEADS="$h" check 0 "cleanup: a worker, the listing works" -- cleanup --worktree "$w" --session c0ffee81
n=$((n + 1)); grep -qx "rm c0ffee81" "$STUB_LOG" && [ ! -d "$w" ] || { echo "FAIL (cleanup: a worker, the listing works): not cleaned"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }

# --- M1: one decision in start-worker.sh and start-worker.ps1 on COORD_ASSISTANT_DIR and the brief's folder ---
if [ -z "${PSX[*]+x}" ]; then
  if command -v powershell >/dev/null 2>&1; then PSX=(powershell); elif command -v pwsh >/dev/null 2>&1; then PSX=(pwsh); fi
fi
if [ -z "${PSX[*]+x}" ]; then echo "SKIP: no PowerShell on PATH - the .sh / .ps1 comparison (M1) did not run"
else
  # agree <what> <expected exit or -> <name> <env folder> [<brief file>]: both variants (each with its own guard's
  # settings), --dry-run; the same exit, and the expected one when given
  agree() {
    local what="$1" want="$2" nm="$3" env="$4" bf="${5:-}" rs rp os op
    mkas "$nm" "$env" sh; local fs="$asf"; mkas "$nm" "$env" ps; local fp="$asf"
    [ -n "$bf" ] || bf="$ad/BRIEF.md"
    os="$(runs sh start-worker --repo "$ar" --name "assistant: $nm" --model sonnet --brief-file "$bf" --safety "$fs" --report-to x --dry-run 2>&1)"; rs=$?
    op="$(runs ps start-worker --repo "$ar" --name "assistant: $nm" --model sonnet --brief-file "$bf" --safety "$fp" --report-to x --dry-run 2>&1)"; rp=$?
    n=$((n + 1))
    if [ "$rs" != "$rp" ]; then
      echo "FAIL (M1 $what): start-worker.sh exits $rs, start-worker.ps1 exits $rp"
      printf '%s\n' "$os" | sed 's/^/    sh: /'; printf '%s\n' "$op" | sed 's/^/    ps: /'; fail=1
    elif [ "$want" != - ] && [ "$rs" != "$want" ]; then
      echo "FAIL (M1 $what): both exit $rs, expected $want"; printf '%s\n' "$os" | sed 's/^/    sh: /'; fail=1
    fi
  }
  base="$mar/coordinator/assistants"
  agree "a trailing slash" 0 cmp1 "$base/cmp1/"
  mkdir -p "$ar/coordinator/assistants/other"   # Linux and macOS resolve a .. only through a folder that exists
  agree "a .. segment" 0 cmp2 "$base/other/../cmp2"
  agree "letter case" - cmp3 "$(printf '%s' "$base/cmp3" | tr '[:lower:]' '[:upper:]')"
  if [ -n "$win" ]; then
    # C:/x as Git Bash writes it, /c/x; and C:\x (\\ in the JSON)
    gb="/$(printf '%s' "${base%%:*}" | tr '[:upper:]' '[:lower:]')${base#?:}"
    agree "Git Bash's /c/ form" - cmp4 "$gb/cmp4"
    agree "backslashes" 0 cmp5 "$(printf '%s' "$base/cmp5" | sed 's#/#\\\\\\\\#g')"
  fi
  # a link to the repository: a junction on Windows (no rights needed), a symbolic link elsewhere
  if [ -n "$win" ]; then cmd //c mklink //J "$(cygpath -w "$tmp/alink")" "$(cygpath -w "$ar")" >/dev/null 2>&1
  else ln -s "$ar" "$tmp/alink"; fi
  if [ -d "$tmp/alink/coordinator" ]; then
    agree "COORD_ASSISTANT_DIR through a link" - cmp6 "$mtmp/alink/coordinator/assistants/cmp6"
    mkas cmp7 "$base/cmp7" sh
    agree "the brief through a link" - cmp7 "$base/cmp7" "$mtmp/alink/coordinator/assistants/cmp7/BRIEF.md"
  else echo "FAIL (M1): could not make the link $tmp/alink"; fail=1; fi
fi

# --- M4: the retro's header says assistant rows are left out of the runs by role ---
n=$((n + 1))
awk 'NR > 1 && !/^#/ { exit } { sub(/^# ?/, ""); print }' "$core/scripts/retro.sh" | tr -d '\r' | tr '\n' ' ' |
  grep -qiE 'rows of the period by role[^.]{0,200}assistant' ||
  { echo "FAIL (M4): the header of scripts/retro.sh does not say assistant rows are left out of the rows by role"; fail=1; }

echo "assistant checks of the worker scripts ($kind): $n checks, $( [ $fail = 0 ] && echo all pass || echo FAILURES )"
exit $fail
