#!/usr/bin/env bash
# Checks of start-worker and cleanup-worker against temporary repositories, with stub `claude` and `gh`
# commands on PATH (the real claude is never called).
#   tests/workers/run.sh sh                    # the .sh scripts, with the bash running this file
#   tests/workers/run.sh ps pwsh               # the .ps1 scripts (or: ps powershell)
# Exit 1 if any check fails.
set -u
[ $# -gt 0 ] || { sed -n '2,6s/^# \{0,1\}//p' "$0"; exit 2; }
kind="$1"; shift
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
command -v cygpath >/dev/null 2>&1 && core="$(cygpath -m "$core")"

# stubs: claude logs its arguments; gh prints $STUB_HEADS (merged PR heads) or fails with $STUB_GH_RC
mkdir -p "$tmp/bin"
cat > "$tmp/bin/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
# --bg: remember the folder and the session name; agents --json: list the names started so far, then
# the sessions of $STUB_LOG.sessions (`<id> <sessionId> <state> <name>` per line, pretty-printed as the
# real listing; a `done` one with --all only), each with the working folder $STUB_LOG.sessions.cwd gives
# it (`<id><tab><cwd>` per line; none: no cwd field)
S="$STUB_LOG.sessions"
if [ "${1:-}" = --bg ]; then printf 'cwd %s\n' "$(pwd -P)" >> "$STUB_LOG"; printf '%s\n' "$3" >> "$STUB_LOG.names"
  # the session's first message (the last argument) as received, alone; $STUB_BG_RC: the launch fails (#291)
  printf '%s' "${!#}" > "$STUB_LOG.arg"
  [ "${STUB_BG_RC:-0}" = 0 ] || { echo "stub claude: launch failed" >&2; exit "$STUB_BG_RC"; }
fi
if [ "${1:-}" = agents ]; then
  all=""; case " $* " in *" --all "*) all=1 ;; esac
  a="$(sed 's/\\/\\\\/g; s/"/\\"/g' "$STUB_LOG.names" 2>/dev/null | awk '{ printf "{\"name\":\"%s\",\"sessionId\":\"5e550000-0000-4000-8000-%012d\"}\n", $0, NR }' | paste -sd, -)"
  [ -f "$S" ] || : > "$S"; [ -f "$S.cwd" ] || : > "$S.cwd"
  b="$(awk -v all="$all" 'FILENAME == ARGV[1] { k = index($0, "\t"); if (k) cw[substr($0, 1, k - 1)] = substr($0, k + 1); next }
    $3 != "done" || all { n = $0; sub(/^[^ ]+ [^ ]+ [^ ]+ /, "", n); w = cw[$1]; gsub(/\\/, "\\\\", w)
    printf "%s{\n    \"id\": \"%s\",\n%s    \"sessionId\": \"%s\",\n    \"name\": \"%s\",\n    \"state\": \"%s\"\n  }", (m++ ? ",\n  " : ""), $1, (w == "" ? "" : "    \"cwd\": \"" w "\",\n"), $2, n, $3 }' "$S.cwd" "$S" 2>/dev/null)"
  printf '[%s%s%s]\n' "$a" "$([ -n "$a" ] && [ -n "$b" ] && echo ,)" "$b"
fi
# stop / rm: as Claude Code 2.1.296 - the short job id only, a full sessionId is no job; rm fails with
# $STUB_RM_FAIL and keeps the session listed; a stopped (done) session refuses the stop
if [ "${1:-}" = stop ] || [ "${1:-}" = rm ]; then
  st="$(awk -v i="$2" '$1 == i { print $3; exit }' "$S" 2>/dev/null)"
  [ -n "$st" ] || { echo "No job matching '$2'. Run claude agents to list jobs." >&2; exit 1; }
  if [ "$1" = stop ]; then
    [ "$st" = done ] && { echo "$2 is not running" >&2; exit 1; }
    awk -v i="$2" '$1 == i { $3 = "done" } { print }' "$S" > "$S.new" && mv "$S.new" "$S"; echo "stopped $2"
    # $STUB_STOP_COMMIT: the stopping session makes one last commit in that worktree (#257)
    [ -z "${STUB_STOP_COMMIT:-}" ] || git -C "$STUB_STOP_COMMIT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m late
  else
    [ -n "${STUB_RM_FAIL:-}" ] && { echo "$STUB_RM_FAIL" >&2; exit 1; }
    awk -v i="$2" '$1 != i' "$S" > "$S.new" && mv "$S.new" "$S"; echo "removed $2"
  fi
fi
exit 0
EOF
cat > "$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
[ "${STUB_GH_RC:-0}" = 0 ] || exit "$STUB_GH_RC"
[ -n "${STUB_HEADS:-}" ] && printf '%s\n' "$STUB_HEADS"
exit 0
EOF
# PowerShell finds claude.ps1 on Windows; it hands the arguments to the bash stub as a native process,
# as claude.exe gets them (a script called in-process would see 5.1's quote escaping, which the
# command line consumes)
cat > "$tmp/bin/claude.ps1" <<'EOF'
& bash (Join-Path $PSScriptRoot 'claude') @args
exit $LASTEXITCODE
EOF
cat > "$tmp/bin/gh.ps1" <<'EOF'
if ($env:STUB_GH_RC -and $env:STUB_GH_RC -ne '0') { exit [int]$env:STUB_GH_RC }
if ($env:STUB_HEADS) { $env:STUB_HEADS }
exit 0
EOF
chmod +x "$tmp/bin/claude" "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" STUB_LOG="$tmp/claude.log" CLAUDE_CONFIG_DIR="$tmp/cfg"   # start-worker keeps briefs under it
: > "$STUB_LOG"

g() { git -c user.email=t@t -c user.name=t "$@"; }
git init -q --bare "$tmp/remote.git"
git init -q -b main "$tmp/repo" && g -C "$tmp/repo" commit -q --allow-empty -m init
git -C "$tmp/repo" remote add origin "$tmp/remote.git" && git -C "$tmp/repo" push -q origin main 2>/dev/null
printf 'Fix the thing.\nSecond line "quoted".\n' > "$tmp/brief.md"
if [ "$kind" = ps ]; then
  sed 's#C:/ABSOLUTE/PATH/scripts/hooks/#'"$core"'/scripts/hooks/#g' "$core/settings.example.windows.json" > "$tmp/safety.json"
else
  sed "s#/ABSOLUTE/PATH#$core#g" "$core/settings.example.json" > "$tmp/safety.json"
fi
grep -q "$core/scripts/hooks/safety-guard" "$tmp/safety.json" || { echo "FAIL: could not point the safety settings at $core"; exit 1; }

start() {
  if [ "$kind" = ps ]; then
    local a=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --repo) a+=(-Repo "$2"); shift 2 ;; --name) a+=(-Name "$2"); shift 2 ;;
        --branch) a+=(-Branch "$2"); shift 2 ;; --model) a+=(-Model "$2"); shift 2 ;;
        --mode) a+=(-Mode "$2"); shift 2 ;; --brief-file) a+=(-BriefFile "$2"); shift 2 ;;
        --safety) a+=(-Safety "$2"); shift 2 ;; --dry-run) a+=(-DryRun); shift ;;
        --launch-from) a+=(-LaunchFrom "$2"); shift 2 ;;
        --report-to) a+=(-ReportTo "$2"); shift 2 ;;
        --worktree-root) a+=(-WorktreeRoot "$2"); shift 2 ;; --base) a+=(-Base "$2"); shift 2 ;;
        --effort) a+=(-Effort "$2"); shift 2 ;; --contract) a+=(-Contract "$2"); shift 2 ;;
        --tester-commit) a+=(-TesterCommit "$2"); shift 2 ;; --tester-tests) a+=(-TesterTests "$2"); shift 2 ;;
        *) a+=("$1"); shift ;;
      esac
    done
    "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$core/scripts/start-worker.ps1" "${a[@]}"
  else bash "$core/scripts/start-worker.sh" "$@"; fi
}
cleanup() {
  if [ "$kind" = ps ]; then
    local a=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --worktree) a+=(-Worktree "$2"); shift 2 ;; --session) a+=(-Session "$2"); shift 2 ;;
        --dry-run) a+=(-DryRun); shift ;; *) a+=("$1"); shift ;;
      esac
    done
    "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$core/scripts/cleanup-worker.ps1" "${a[@]}"
  else bash "$core/scripts/cleanup-worker.sh" "$@"; fi
}
PS=("$@")
fail=0; n=0
check() {   # check <expected exit> <description> -- command...
  local want="$1" what="$2" out rc; shift 3
  n=$((n + 1))
  out="$("$@" 2>&1)"; rc=$?
  [ "$rc" = "$want" ] || { echo "FAIL ($what): expected exit $want, got $rc"; printf '%s\n' "$out" | sed 's/^/    /'; fail=1; }
  LAST="$out"; LRC=$rc
}
expect_in() { case "$LAST" in *"$1"*) ;; *) echo "FAIL: output lacks '$1'"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1 ;; esac; }
S=(--repo "$tmp/repo" --name "#12 worker: Fix" --branch 12-fix --model opus --brief-file "$tmp/brief.md" --safety "$tmp/safety.json" --report-to "Core lead")

# --- start-worker ---
if [ "$kind" = sh ]; then check 1 "start: --model without a value" -- start --repo "$tmp/repo" --model; fi
check 1 "start: bypassPermissions refused" -- start "${S[@]}" --mode bypassPermissions
expect_in "only the owner's own explicit setup"
check 1 "start: not a git repository" -- start --repo "$tmp" --name x --branch 12-fix --model opus --brief-file "$tmp/brief.md" --safety "$tmp/safety.json" --report-to x
check 1 "start: no report address" -- start --repo "$tmp/repo" --name "#12 worker: Fix" --branch 12-fix --model opus --brief-file "$tmp/brief.md" --safety "$tmp/safety.json"
expect_in "<session>"
# a brief that is missing, empty or blanks only is refused by name, before any worktree (#226)
: > "$tmp/empty-brief.md"; printf '  \r\n\t\n' > "$tmp/blank-brief.md"
for b in empty-brief blank-brief; do
  check 1 "start: an $b" -- start --repo "$tmp/repo" --name "#12 worker: Fix" --branch 12-fix --model opus --brief-file "$tmp/$b.md" --safety "$tmp/safety.json" --report-to x --dry-run
  expect_in "is empty - a worker with no task would start"
done
check 1 "start: a brief file that does not exist" -- start --repo "$tmp/repo" --name "#12 worker: Fix" --branch 12-fix --model opus --brief-file "$tmp/nope.md" --safety "$tmp/safety.json" --report-to x --dry-run
expect_in "nope.md does not exist"
check 0 "start: dry run" -- start "${S[@]}" --dry-run
expect_in "[dry-run]"
expect_in "keep "
grep -q 'worktrees' "$tmp/repo/.git/info/exclude" 2>/dev/null && { echo "FAIL: the dry run wrote info/exclude"; fail=1; }
expect_in "[dry-run] add /.lead/ to the repository's .git/info/exclude"
grep -q '^/.lead/' "$tmp/repo/.git/info/exclude" 2>/dev/null && { echo "FAIL: the dry run wrote /.lead/ to info/exclude"; fail=1; }
[ -d "$tmp/repo/.claude/worktrees/12-fix" ] && { echo "FAIL: the dry run created the worktree"; fail=1; }
[ -s "$STUB_LOG" ] && { echo "FAIL: the dry run called claude"; fail=1; }
check 0 "start: real start with the stub claude" -- start "${S[@]}"
expect_in 'subscribe: SendMessage(to: "#12 worker: Fix", notify_when_idle: true)'
expect_in "added /.lead/ to the repository's .git/info/exclude"
# it waited until the new session was listed before printing the subscribe line (no race)
grep -qx "agents --json" "$STUB_LOG" || { echo "FAIL: start-worker did not wait for the session to be listed"; fail=1; }
case "$LAST" in *"not listed after"*) echo "FAIL: the started session was not found in claude agents"; fail=1 ;; esac
[ -d "$tmp/repo/.claude/worktrees/12-fix" ] || { echo "FAIL: no worktree after start"; fail=1; }
grep -q -- "--bg --name #12 worker: Fix --model opus --permission-mode auto --settings" "$STUB_LOG" ||
  { echo "FAIL: claude got unexpected arguments:"; sed 's/^/    /' "$STUB_LOG"; fail=1; }
grep -q 'Second line "quoted".' "$STUB_LOG" || { echo "FAIL: the brief did not reach claude intact"; fail=1; }
# the brief as sent is kept by the session's id, for the after-compact hook
kb="$tmp/cfg/coordinator/briefs/5e550000-0000-4000-8000-000000000001.md"
grep -q 'Second line "quoted".' "$kb" 2>/dev/null && grep -q '^You implement one contract' "$kb" ||
  { echo "FAIL: the brief was not kept for after a compaction ($kb)"; fail=1; }
# launched from the repository root (trusted), the brief's first action entering the worktree
grep -qx "cwd $(cd "$tmp/repo" && pwd -P)" "$STUB_LOG" || { echo "FAIL: not launched from the repository root:"; sed 's/^/    /' "$STUB_LOG"; fail=1; }
grep -q 'Report to: the session named "Core lead"' "$STUB_LOG" || { echo "FAIL: the brief does not name the report address"; fail=1; }
grep -q "FIRST ACTION, before anything else: use the EnterWorktree tool with path = .*/.claude/worktrees/12-fix\." "$STUB_LOG" ||
  { echo "FAIL: the brief does not start with entering the worktree"; fail=1; }
: > "$STUB_LOG"
mkdir -p "$tmp/launch"
check 0 "start: --launch-from another folder" -- start "${S[@]}" --launch-from "$tmp/launch"
grep -qx "cwd $(cd "$tmp/launch" && pwd -P)" "$STUB_LOG" || { echo "FAIL: --launch-from ignored:"; sed 's/^/    /' "$STUB_LOG"; fail=1; }
case "$LAST" in *"/.lead/"*) echo "FAIL: /.lead/ added on a second start"; fail=1 ;; esac
# the self-test's shape: a repository without an origin (a local state repository), its worktree under
# another folder, launched from that folder - the branch starts from the local base, the brief says to
# work by absolute path instead of EnterWorktree
git init -q -b state "$tmp/state" && g -C "$tmp/state" commit -q --allow-empty -m state && git -C "$tmp/state" branch selftest-base
mkdir -p "$tmp/project"
: > "$STUB_LOG"
check 0 "start: a local repository, worktree elsewhere" -- start --repo "$tmp/state" --name "#st1 lead: selftest" --branch st1 \
  --base selftest-base --model haiku --brief-file "$tmp/brief.md" --safety "$tmp/safety.json" --report-to "Core lead" \
  --launch-from "$tmp/project" --worktree-root "$tmp/project/.claude/worktrees"
[ -d "$tmp/project/.claude/worktrees/st1" ] || { echo "FAIL: no worktree under --worktree-root"; fail=1; }
[ "$(git -C "$tmp/state" rev-parse st1)" = "$(git -C "$tmp/state" rev-parse selftest-base)" ] || { echo "FAIL: st1 did not start from the local base"; fail=1; }
grep -q "YOUR WORKING COPY is .*/project/.claude/worktrees/st1, a worktree of " "$STUB_LOG" ||
  { echo "FAIL: the brief does not send it to the worktree by absolute path:"; sed 's/^/    /' "$STUB_LOG"; fail=1; }
grep -q "EnterWorktree tool with path" "$STUB_LOG" && { echo "FAIL: EnterWorktree asked for another repository's worktree"; fail=1; }
git -C "$tmp/state" worktree remove "$tmp/project/.claude/worktrees/st1"
# the worker copies stay out of the project's git: one local info/exclude line, however many starts
[ -z "$(git -C "$tmp/repo" status --porcelain)" ] || { echo "FAIL: the project's git sees the worktrees:"; git -C "$tmp/repo" status --short | sed 's/^/    /'; fail=1; }
[ "$(grep -c '^/.claude/worktrees/$' "$tmp/repo/.git/info/exclude")" = 1 ] || { echo "FAIL: /.claude/worktrees/ is not in info/exclude exactly once"; fail=1; }
grep -q '^/.claude/worktrees/$' "$tmp/repo/.gitignore" 2>/dev/null && { echo "FAIL: .gitignore was written"; fail=1; }
# a lead's notes in <its worktree>/.lead/ are never committed: one line, however many starts
lw="$tmp/repo/.claude/worktrees/12-fix"
[ "$(grep -c '^/.lead/$' "$tmp/repo/.git/info/exclude")" = 1 ] || { echo "FAIL: /.lead/ is not in info/exclude exactly once"; fail=1; }
mkdir -p "$lw/.lead" && echo notes > "$lw/.lead/x"
[ -z "$(git -C "$lw" status --porcelain)" ] || { echo "FAIL: the worktree's git sees .lead/:"; git -C "$lw" status --short | sed 's/^/    /'; fail=1; }
rm "$lw/.lead/x" && rmdir "$lw/.lead"
# a lead's integration branch, created locally and not pushed yet: the worker starts from the local one
git -C "$tmp/repo" branch 20-lead main
W=(--repo "$tmp/repo" --name "#20.1 worker: Part" --model opus --brief-file "$tmp/brief.md" --safety "$tmp/safety.json" --report-to "#20 lead: Big")
check 0 "start: a base not on origin yet" -- start "${W[@]}" --branch 20.1-part --base 20-lead
expect_in "not on origin yet"
[ "$(git -C "$tmp/repo" rev-parse 20.1-part)" = "$(git -C "$tmp/repo" rev-parse 20-lead)" ] || { echo "FAIL: 20.1-part did not start from the local base"; fail=1; }
git -C "$tmp/repo" worktree remove "$tmp/repo/.claude/worktrees/20.1-part"
check 1 "start: a base nowhere" -- start "${W[@]}" --branch 21.1-part --base no-such-branch
expect_in "not on origin and no local branch"
# a PowerShell shell around the hook: its exit 2 would reach Claude Code as a non-blocking 1
awk '/safety-guard\./ && !/-SelfTest/ && !/--self-test/ { print "            \"shell\": \"powershell\"," } { print }' "$tmp/safety.json" > "$tmp/safety-shell.json"
check 1 "start: the hook under a PowerShell shell" -- start --repo "$tmp/repo" --name "#12 worker: Fix" --branch 12-fix --model opus --brief-file "$tmp/brief.md" --safety "$tmp/safety-shell.json" --report-to x
expect_in "PowerShell shell"
# a hook path with backslashes: Git Bash drops them on Windows and the hook never runs
sed 's#/scripts/hooks/#\\\\scripts\\\\hooks\\\\#g' "$tmp/safety.json" > "$tmp/safety-bs.json"
check 1 "start: a hook path with backslashes" -- start --repo "$tmp/repo" --name "#12 worker: Fix" --branch 12-fix --model opus --brief-file "$tmp/brief.md" --safety "$tmp/safety-bs.json" --report-to x
expect_in "forward slashes"
# launched from the working copy (EnterWorktree) with no COORD_PROTECTED_ROOT in the safety file's env:
# a notice, not a failure; none with it set, and none when launched from another folder
grep -v '"COORD_PROTECTED_ROOT"' "$tmp/safety.json" > "$tmp/safety-noprot.json"
sed 's#"COORD_PROTECTED_ROOT": "[^"]*"#"COORD_PROTECTED_ROOT": ""#' "$tmp/safety.json" > "$tmp/safety-emptyprot.json"
grep -q '"COORD_PROTECTED_ROOT": ""' "$tmp/safety-emptyprot.json" || { echo "FAIL: could not empty COORD_PROTECTED_ROOT"; fail=1; }
P=(--repo "$tmp/repo" --name "#12 worker: Fix" --branch 12-fix --model opus --brief-file "$tmp/brief.md" --report-to x --dry-run)
check 0 "start: from the root, COORD_PROTECTED_ROOT set" -- start "${P[@]}" --safety "$tmp/safety.json"
case "$LAST" in *"notice: COORD_PROTECTED_ROOT"*) echo "FAIL: a notice although COORD_PROTECTED_ROOT is set"; fail=1 ;; esac
check 0 "start: from the root, no COORD_PROTECTED_ROOT" -- start "${P[@]}" --safety "$tmp/safety-noprot.json"
expect_in "notice: COORD_PROTECTED_ROOT is not set in "
expect_in "safety-noprot.json: edit tools can reach the working copy (TOOLKIT Safety)"
check 0 "start: from the root, COORD_PROTECTED_ROOT empty" -- start "${P[@]}" --safety "$tmp/safety-emptyprot.json"
expect_in "notice: COORD_PROTECTED_ROOT is not set in "
check 0 "start: from another folder, no COORD_PROTECTED_ROOT" -- start "${P[@]}" --safety "$tmp/safety-noprot.json" --launch-from "$tmp/launch"
case "$LAST" in *"notice: COORD_PROTECTED_ROOT"*) echo "FAIL: a notice although launched from another folder"; fail=1 ;; esac

# --- findings of a tester session (tests/FEATURE-TEST.md, group WORKERS) ---
in_dir() { local d="$1"; shift; (cd "$d" && "$@"); }
mtmp="$(cygpath -m "$tmp" 2>/dev/null || printf '%s' "$tmp")"
W=(--model opus --brief-file "$tmp/brief.md" --report-to "Core lead")
# the PreToolUse guard path must exist, not only the self-test's
gl="$(grep -n 'safety-guard\.' "$tmp/safety.json" | grep -v -e '-SelfTest' -e '--self-test' | head -n 1 | cut -d: -f1)"
sed "${gl}s#scripts/hooks/#WRONG/hooks/#" "$tmp/safety.json" > "$tmp/safety-wrong.json"
check 1 "start: a wrong PreToolUse guard path" -- start --repo "$tmp/repo" --name "#30 worker: a" --branch 30-a "${W[@]}" --safety "$tmp/safety-wrong.json"
expect_in "hook not found"
# a "shell" field four lines above the command is in the same hook object
awk -v n="$gl" 'NR == n { print "            \"shell\": \"powershell\","; print "            \"async\": false,"; print "            \"statusMessage\": \"guard\","; print "            \"x\": 1," } { print }' "$tmp/safety.json" > "$tmp/safety-shell4.json"
check 1 "start: a PowerShell shell further up the hook object" -- start --repo "$tmp/repo" --name "#31 worker: a" --branch 31-a "${W[@]}" --safety "$tmp/safety-shell4.json"
expect_in "PowerShell shell"
# no PreToolUse guard at all, and a guard whose self-test prints nothing: a message, not silence
sed "${gl}s#safety-guard\.#other-tool.#" "$tmp/safety.json" > "$tmp/safety-none.json"
check 1 "start: no PreToolUse guard" -- start --repo "$tmp/repo" --name "#32 worker: a" --branch 32-a "${W[@]}" --safety "$tmp/safety-none.json"
expect_in "no PreToolUse safety-guard hook"
mkdir -p "$tmp/silent"; printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/silent/safety-guard.sh"; printf 'exit 0\n' > "$tmp/silent/safety-guard.ps1"
sed "s#$core/scripts/hooks/#$mtmp/silent/#g" "$tmp/safety.json" > "$tmp/safety-silent.json"
check 1 "start: a guard whose self-test prints nothing" -- start --repo "$tmp/repo" --name "#33 worker: a" --branch 33-a "${W[@]}" --safety "$tmp/safety-silent.json"
expect_in "printed nothing"
# bypassPermissions in any letter case, and a flag where a value belongs
check 1 "start: BypassPermissions" -- start "${S[@]}" --mode BypassPermissions --dry-run
expect_in "refusing bypassPermissions"
check 1 "start: --model followed by a flag" -- start --repo "$tmp/repo" --name "#34 worker: a" --branch 34-a --model --dry-run --brief-file "$tmp/brief.md" --safety "$tmp/safety.json" --report-to x
expect_in "missing value for"
git -C "$tmp/repo" show-ref -q --verify refs/heads/34-a && { echo "FAIL: --model --dry-run created a branch"; fail=1; }
# a stale folder where the worktree goes is refused, never entered
mkdir -p "$tmp/repo/.claude/worktrees/35-a" && echo junk > "$tmp/repo/.claude/worktrees/35-a/old.txt"
check 1 "start: a stale folder at the worktree path" -- start --repo "$tmp/repo" --name "#35 worker: a" --branch 35-a "${W[@]}" --safety "$tmp/safety.json"
expect_in "is not a worktree of"
# a relative --worktree-root is taken from the current folder
mkdir -p "$tmp/elsewhere"
check 0 "start: a relative --worktree-root" -- in_dir "$tmp/elsewhere" start --repo "$tmp/repo" --name "#36 worker: a" --branch 36-a "${W[@]}" --safety "$tmp/safety.json" --worktree-root wt
[ "$(git -C "$tmp/elsewhere/wt/36-a" rev-parse --abbrev-ref HEAD 2>/dev/null)" = 36-a ] || { echo "FAIL: the worktree is not under the current folder"; fail=1; }
[ -e "$tmp/repo/wt" ] && { echo "FAIL: the worktree went into the repository"; fail=1; }
git -C "$tmp/repo" worktree remove "$tmp/elsewhere/wt/36-a" 2>/dev/null
# an exclude file without a final newline: the new line is not glued to its last one
git init -q -b main "$tmp/repo3" && g -C "$tmp/repo3" commit -q --allow-empty -m init
mkdir -p "$tmp/repo3/coordinator" && echo x > "$tmp/repo3/coordinator/PROJECT.md"
printf 'coordinator/' > "$tmp/repo3/.git/info/exclude"
check 0 "start: an exclude file without a final newline" -- start --repo "$tmp/repo3" --name "#37 worker: a" --branch 37-a "${W[@]}" --safety "$tmp/safety.json"
grep -qx 'coordinator/' "$tmp/repo3/.git/info/exclude" && grep -qx '/.claude/worktrees/' "$tmp/repo3/.git/info/exclude" &&
  [ -z "$(git -C "$tmp/repo3" status --porcelain)" ] || { echo "FAIL: the exclude file was corrupted:"; sed 's/^/    /' "$tmp/repo3/.git/info/exclude"; fail=1; }
# a coordinator/ state repository in a project that got `git init` after it: kept out of the project's
# git with one info/exclude line (the common dir's), written by a real start only
git init -q -b main "$tmp/repo5" && g -C "$tmp/repo5" commit -q --allow-empty -m init
git init -q -b state "$tmp/repo5/coordinator" && echo x > "$tmp/repo5/coordinator/PROJECT.md"
check 0 "start: a dry run, coordinator/ not ignored" -- start --repo "$tmp/repo5" --name "#42 worker: a" --branch 42-a "${W[@]}" --safety "$tmp/safety.json" --dry-run
expect_in "[dry-run] add /coordinator/ to the repository's .git/info/exclude"
grep -q 'coordinator' "$tmp/repo5/.git/info/exclude" && { echo "FAIL: the dry run wrote /coordinator/ to info/exclude"; fail=1; }
check 0 "start: coordinator/ not ignored" -- start --repo "$tmp/repo5" --name "#42 worker: a" --branch 42-a "${W[@]}" --safety "$tmp/safety.json"
expect_in "added /coordinator/ to the repository's .git/info/exclude"
check 0 "start: coordinator/ ignored already" -- start --repo "$tmp/repo5" --name "#43 worker: a" --branch 43-a "${W[@]}" --safety "$tmp/safety.json"
case "$LAST" in *"/coordinator/ to the repository"*) echo "FAIL: /coordinator/ added a second time"; fail=1 ;; esac
[ "$(grep -c '^/coordinator/$' "$tmp/repo5/.git/info/exclude")" = 1 ] && [ -z "$(git -C "$tmp/repo5" status --porcelain)" ] ||
  { echo "FAIL: the project's git sees coordinator/:"; git -C "$tmp/repo5" status --short | sed 's/^/    /'; sed 's/^/    /' "$tmp/repo5/.git/info/exclude"; fail=1; }
# an unreachable origin: the script's own message (Windows PowerShell 5.1 included)
git init -q -b main "$tmp/repo4" && g -C "$tmp/repo4" commit -q --allow-empty -m init && git -C "$tmp/repo4" remote add origin "$mtmp/no-such-remote.git"
check 1 "start: an unreachable origin" -- start --repo "$tmp/repo4" --name "#38 worker: a" --branch 38-a "${W[@]}" --safety "$tmp/safety.json" --dry-run
expect_in "cannot reach origin"
# ... retried once, and git's own error is in the message (a transient DNS error is told apart)
expect_in "retrying once"
expect_in "does not appear to be a git repository"
# the role file heads the brief of a session, once
: > "$STUB_LOG"
check 0 "start: the role heads the brief" -- start --repo "$tmp/repo" --name "#39 worker: a" --branch 39-a "${W[@]}" --safety "$tmp/safety.json"
expect_in "role worker: roles/worker.md heads the brief"
grep -q "^You implement one contract" "$STUB_LOG" || { echo "FAIL: the worker role is not in the brief"; fail=1; }
{ sed -n '/^You implement one contract/,$p' "$core/roles/worker.md"; cat "$tmp/brief.md"; } > "$tmp/brief-role.md"
check 0 "start: the role already in the brief" -- start --repo "$tmp/repo" --name "#40 worker: a" --branch 40-a --model opus --brief-file "$tmp/brief-role.md" --report-to x --safety "$tmp/safety.json"
expect_in "already in the brief"
git -C "$tmp/repo" worktree remove "$tmp/repo/.claude/worktrees/39-a"; git -C "$tmp/repo" worktree remove "$tmp/repo/.claude/worktrees/40-a"
# the same root in another letter case is the root (Windows: case-insensitive paths)
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*)
  : > "$STUB_LOG"
  check 0 "start: --launch-from the root in another letter case" -- start --repo "$tmp/repo" --name "#41 worker: a" --branch 41-a "${W[@]}" --safety "$tmp/safety.json" --launch-from "$(git -C "$tmp/repo" rev-parse --show-toplevel | tr '[:lower:]' '[:upper:]')"
  grep -q "EnterWorktree tool with path" "$STUB_LOG" || { echo "FAIL: the root in another case was taken for another folder"; fail=1; }
  git -C "$tmp/repo" worktree remove "$tmp/repo/.claude/worktrees/41-a" ;;
esac

# --- findings of a macOS tester session (group WORKERS) ---
# a quoted guard path with a space is accepted (selftest hooks accepts it); an unquoted one is refused
mkdir -p "$tmp/core copy" && cp -R "$core/scripts" "$tmp/core copy/"
sed -E "s#$core/scripts/hooks/(safety-guard\.(sh|ps1))#\\\\\"$mtmp/core copy/scripts/hooks/\\1\\\\\"#g" "$tmp/safety.json" > "$tmp/safety-space.json"
grep -q 'core copy/scripts/hooks/safety-guard' "$tmp/safety-space.json" || { echo "FAIL: could not write the quoted guard path"; fail=1; }
check 0 "start: a quoted guard path with a space" -- start --repo "$tmp/repo" --name "#44 worker: a" --branch 44-a "${W[@]}" --safety "$tmp/safety-space.json" --dry-run
sed 's#\\"##g' "$tmp/safety-space.json" > "$tmp/safety-space-bare.json"
check 1 "start: an unquoted guard path with a space" -- start --repo "$tmp/repo" --name "#44 worker: a" --branch 44-a "${W[@]}" --safety "$tmp/safety-space-bare.json" --dry-run
expect_in "quote a path with a space"
# a branch that differs from an existing one only in letter case (Windows, macOS: one branch file and
# one worktree folder) is refused, with the worktree there and without it
case "$(uname -s)" in Darwin|MINGW*|MSYS*|CYGWIN*)
  check 0 "start: a branch for the letter-case checks" -- start --repo "$tmp/repo" --name "#45 worker: a" --branch 45-case "${W[@]}" --safety "$tmp/safety.json"
  check 1 "start: a branch in another letter case, its worktree there" -- start --repo "$tmp/repo" --name "#45 worker: b" --branch 45-CASE "${W[@]}" --safety "$tmp/safety.json"
  expect_in "differs only in letter case"
  git -C "$tmp/repo" branch 46-case main
  check 1 "start: a branch in another letter case, no worktree" -- start --repo "$tmp/repo" --name "#46 worker: a" --branch 46-Case "${W[@]}" --safety "$tmp/safety.json" --worktree-root "$tmp/wt46"
  expect_in "differs only in letter case"
  [ -e "$tmp/wt46/46-Case" ] && { echo "FAIL: a worktree was added for a branch in another letter case"; fail=1; }
  git -C "$tmp/repo" worktree remove "$tmp/repo/.claude/worktrees/45-case" ;;
esac
# an existing branch in the same letter case is still checked out into its worktree
git -C "$tmp/repo" branch 47-a main
check 0 "start: an existing branch without a worktree" -- start --repo "$tmp/repo" --name "#47 worker: a" --branch 47-a "${W[@]}" --safety "$tmp/safety.json" --worktree-root "$tmp/wt47"
[ "$(git -C "$tmp/wt47/47-a" rev-parse --abbrev-ref HEAD 2>/dev/null)" = 47-a ] || { echo "FAIL: 47-a was not checked out into its worktree"; fail=1; }
git -C "$tmp/repo" worktree remove "$tmp/wt47/47-a" 2>/dev/null
# a --worktree-root through a symlink (macOS: /tmp and /var are links): the second start reuses it
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) ;; *)
  mkdir -p "$tmp/real48" && ln -s "$tmp/real48" "$tmp/link48"
  check 0 "start: a worktree root through a symlink" -- start --repo "$tmp/repo" --name "#48 worker: a" --branch 48-a "${W[@]}" --safety "$tmp/safety.json" --worktree-root "$tmp/link48"
  check 0 "start: the same worktree root through a symlink again" -- start --repo "$tmp/repo" --name "#48 worker: a" --branch 48-a "${W[@]}" --safety "$tmp/safety.json" --worktree-root "$tmp/link48"
  expect_in "reusing worktree"
  git -C "$tmp/repo" worktree remove "$tmp/real48/48-a" 2>/dev/null ;;
esac
# a name that the JSON listing escapes is found at once, not after the 20 s wait; it reaches claude
# intact (Windows PowerShell 5.1 drops a " from a native argument unless it is escaped)
for nm in '#49 worker: a\b' '#50 worker: say "hi"'; do
  br="$(printf '%s' "$nm" | cut -c2-3)-a"
  : > "$STUB_LOG"
  check 0 "start: the name $nm in the listing" -- start --repo "$tmp/repo" --name "$nm" --branch "$br" "${W[@]}" --safety "$tmp/safety.json"
  case "$LAST" in *"not listed after"*) echo "FAIL: the name $nm was not found in the listing"; fail=1 ;; esac
  grep -qF -- "--bg --name $nm --model" "$STUB_LOG" || { echo "FAIL: the name $nm did not reach claude intact:"; sed 's/^/    /' "$STUB_LOG"; fail=1; }
  git -C "$tmp/repo" worktree remove "$tmp/repo/.claude/worktrees/$br" 2>/dev/null
done
# --- findings of re-proving on Windows (start-worker) ---
# a worktree folder is reused only with the requested branch checked out
git -C "$tmp/repo" worktree add -q -b 52-other "$tmp/repo/.claude/worktrees/52-a" main
check 1 "start: a worktree folder with another branch checked out" -- start --repo "$tmp/repo" --name "#52 worker: a" --branch 52-a "${W[@]}" --safety "$tmp/safety.json"
expect_in "has 52-other checked out, not 52-a"
git -C "$tmp/repo" worktree remove "$tmp/repo/.claude/worktrees/52-a"
# with packed refs git creates a branch beside one that differs only in letter case (Windows, macOS):
# start-worker refuses it although the exact name exists, and never enters the other branch's worktree
case "$(uname -s)" in Darwin|MINGW*|MSYS*|CYGWIN*)
  check 0 "start: a branch for the packed-refs check" -- start --repo "$tmp/repo" --name "#53 worker: a" --branch 53-case "${W[@]}" --safety "$tmp/safety.json"
  git -C "$tmp/repo" pack-refs --all
  if git -C "$tmp/repo" branch 53-CASE main 2>/dev/null; then
    check 1 "start: a branch beside another in another letter case (packed refs)" -- start --repo "$tmp/repo" --name "#53 worker: b" --branch 53-CASE "${W[@]}" --safety "$tmp/safety.json"
    expect_in "differs only in letter case from the existing 53-case"
    git -C "$tmp/repo" update-ref -d refs/heads/53-CASE
  else echo "FAIL: git did not create 53-CASE beside the packed 53-case"; fail=1; fi
  git -C "$tmp/repo" worktree remove "$tmp/repo/.claude/worktrees/53-case" ;;
esac
# the effort reaches claude as --effort (#211): it was dropped, every worker ran at the user's default
check 1 "start: an effort outside the five levels" -- start "${S[@]}" --effort turbo
expect_in "low, medium, high, xhigh or max"
check 0 "start: --effort in the dry run" -- start "${S[@]}" --effort xhigh --dry-run
expect_in "--model opus --effort xhigh --permission-mode auto"
# the conflict foresight before a worker's launch (#242): merge-queue status with the brief's touches
# (the stub gh prints $STUB_HEADS as the open PRs' list); informational, never a stop
expect_in "foresight: no touches in the brief - check the open PRs against the task yourself (CORE §4a)"
printf 'Do it.\ntouches: [src/a.ts, "docs/"]   # what it changes\n' > "$tmp/brief-touches.md"
T=(--repo "$tmp/repo" --branch 12-fix --model opus --brief-file "$tmp/brief-touches.md" --safety "$tmp/safety.json" --report-to x --dry-run)
STUB_HEADS="$(printf '31\tMERGEABLE\tCLEAN\t31-a\tsrc/a.ts\tlib/b.ts')" check 0 "start: the conflict foresight" -- start --name "#12 worker: Fix" "${T[@]}"
expect_in "foresight: TOUCHES #31: 31-a - src/a.ts"
expect_in "foresight: merge-queue status: 1 open, 0 conflicting, 0 overlapping pairs, 1 touching the task"
STUB_GH_RC=1 check 0 "start: the conflict foresight, gh failing" -- start --name "#12 lead: Fix" "${T[@]}"
expect_in "foresight: merge-queue status failed - check the open PRs against the task yourself (CORE §4a)"
check 0 "start: no conflict foresight for a verifier" -- start --name "#12 verifier: Fix" "${T[@]}"
case "$LAST" in *foresight*) echo "FAIL: a verifier start printed the conflict foresight"; fail=1 ;; esac
# touches as a YAML block list, which check-contract takes too (#258): one `- path` per line, a comment
# after the key and after an item, a quoted item; the list ends at the first line that is no item
printf 'Do it.\ntouches:   # what it changes\n  - lib/b.ts   # the helper\n  - "docs/"\ndepends_on: [31]\n' > "$tmp/brief-block.md"
STUB_HEADS="$(printf '31\tMERGEABLE\tCLEAN\t31-a\tsrc/a.ts\tlib/b.ts')" check 0 "start: the conflict foresight from a block list" -- \
  start --name "#12 worker: Fix" --repo "$tmp/repo" --branch 12-fix --model opus --brief-file "$tmp/brief-block.md" --safety "$tmp/safety.json" --report-to x --dry-run
expect_in "foresight: TOUCHES #31: 31-a - lib/b.ts"
expect_in "foresight: merge-queue status: 1 open, 0 conflicting, 0 overlapping pairs, 1 touching the task"
case "$LAST" in *"no touches"*|*"src/a.ts"*) echo "FAIL: the block list was not read as lib/b.ts and docs/"; fail=1 ;; esac
# the key in its own letter case (a `Touches:` line in the prose is not it); a comment line before the
# first item and a blank line between items do not end the list; a `#` inside a path is no comment
B=(--name "#12 worker: Fix" --repo "$tmp/repo" --branch 12-fix --model opus --safety "$tmp/safety.json" --report-to x --dry-run)
printf 'Do it.\nTouches: the cart\ntouches: [lib/b.ts]\n' > "$tmp/brief-tcase.md"
printf 'Do it.\ntouches:\n  # the main change\n  - lib/b.ts\n' > "$tmp/brief-tcomment.md"
printf 'Do it.\ntouches:\n  - docs/\n\n  - lib/b.ts\nThe rest.\n' > "$tmp/brief-tblank.md"
for b in tcase tcomment tblank; do
  STUB_HEADS="$(printf '31\tMERGEABLE\tCLEAN\t31-a\tsrc/a.ts\tlib/b.ts')" check 0 "start: the conflict foresight, brief-$b" -- start "${B[@]}" --brief-file "$tmp/brief-$b.md"
  expect_in "foresight: TOUCHES #31: 31-a - lib/b.ts"
done
printf 'Do it.\ntouches: [docs/c#.md]   # the page\n' > "$tmp/brief-thash.md"
STUB_HEADS="$(printf '31\tMERGEABLE\tCLEAN\t31-a\tdocs/c#.md')" check 0 "start: the conflict foresight, a # in a path" -- start "${B[@]}" --brief-file "$tmp/brief-thash.md"
expect_in "foresight: TOUCHES #31: 31-a - docs/c#.md"
# the contract passes check-contract before a worker or a lead starts (CORE §4, #267): the one in the brief
# (a block after a `---` line holding any key check-contract requires; a rule above it is no contract) or
# --contract; the temporary copy of the brief's contract is removed (TMPDIR for .sh, TMP / TEMP for .ps1)
cc="$core/tests/check-contract"
ct="$tmp/ct"; mkdir -p "$ct"; ctw="$ct"; command -v cygpath >/dev/null 2>&1 && ctw="$(cygpath -m "$ct")"
# these worker cases check check-contract itself: their contracts say `tests_first: no - <reason>`, so the
# tests_first gate (#276, below) does not stand in their way
tfno() { sed 's/^tests_first: yes$/tests_first: no - tests\/sort.sh exists already/' "$1"; }
# a worker's dry-run start without a tester flag that the agreement guard (below) would repeat - the same
# contract by --contract, or a brief of the same bytes - is kept: the guard checks its exit and output
# instead of starting it again (#287). A start by --contract matches on the contract's path alone: --contract
# takes precedence over the brief's own contract (the "--contract that passes" start below, given brief-cerr.md,
# asserts that), so its brief does not change what the guard checks
mkdir -p "$tmp/kept"; : > "$tmp/kept/index"; kn=0 nr=0
keep_start() {   # keep_start <contract | brief> <file>: the last start, by --contract <file> or --brief-file <file>
  kn=$((kn + 1)); printf '%s\n' "$LAST" > "$tmp/kept/$kn.out"; echo "$LRC" > "$tmp/kept/$kn.rc"
  printf '%s\t%s\t%s\n' "$1" "$2" "$kn" >> "$tmp/kept/index"
}
{ printf 'Do it.\n---\nnot a contract\n'; tfno "$cc/budget-time.md"; printf '\nThe rest of the brief.\n'; } > "$tmp/brief-cwarn.md"
{ printf 'Do it.\n\n'; cat "$cc/tests-first-missing.md"; } > "$tmp/brief-cerr.md"
C=(--repo "$tmp/repo" --branch 67-check --model opus --safety "$tmp/safety.json" --report-to x)
TMPDIR="$ct" TMP="$ctw" TEMP="$ctw" check 0 "start: a contract in the brief with a WARN starts" -- start --name "#67 worker: C" "${C[@]}" --brief-file "$tmp/brief-cwarn.md" --dry-run
expect_in "contract in the brief: WARN  budget.time (about an hour) is not minutes"
expect_in "contract in the brief: OK (0 errors, 1 warnings)"
expect_in "[dry-run] (cd "
: > "$STUB_LOG"
TMPDIR="$ct" TMP="$ctw" TEMP="$ctw" check 1 "start: a contract in the brief with an ERROR is refused" -- start --name "#67 lead: C" "${C[@]}" --brief-file "$tmp/brief-cerr.md"
expect_in "contract in the brief: ERROR missing \`tests_first\`"
expect_in "contract in the brief: FAIL (1 errors, 0 warnings)"
expect_in "refused: the contract fails check-contract - fix the ERROR lines above before it goes out"
[ -d "$tmp/repo/.claude/worktrees/67-check" ] && { echo "FAIL: a worktree was created for a contract with an ERROR"; fail=1; }
git -C "$tmp/repo" show-ref -q --verify refs/heads/67-check && { echo "FAIL: a branch was created for a contract with an ERROR"; fail=1; }
[ -s "$STUB_LOG" ] && { echo "FAIL: claude was called for a contract with an ERROR"; fail=1; }
[ -z "$(ls -A "$ct")" ] || { echo "FAIL: the contract's temporary file was left behind:"; ls -A "$ct" | sed 's/^/    /'; fail=1; }
# a contract missing `id:`, and one left open at the brief's end, are still checked (never "none found");
# a `---` block holding none of the contract's keys is no contract
{ printf 'Do it.\n\n'; tfno "$cc/budget-time-ok.md" | sed '/^id:/d'; } > "$tmp/brief-cnoid.md"
{ printf 'Do it.\n\n'; sed '$d' "$cc/tests-first-missing.md"; } > "$tmp/brief-copen.md"
printf 'Do it.\n---\nNotes: keep it short.\nsee: the docs\n---\nThe rest.\n' > "$tmp/brief-crule.md"
check 1 "start: a contract in the brief without id is refused" -- start --name "#67 worker: C" "${C[@]}" --brief-file "$tmp/brief-cnoid.md" --dry-run
expect_in "contract in the brief: ERROR missing \`id\`"
expect_in "refused: the contract fails check-contract"
check 1 "start: an unclosed contract in the brief with an ERROR is refused" -- start --name "#67 worker: C" "${C[@]}" --brief-file "$tmp/brief-copen.md" --dry-run
expect_in "contract in the brief: ERROR missing \`tests_first\`"
expect_in "refused: the contract fails check-contract"
check 0 "start: a --- block that is no contract" -- start --name "#67 worker: C" "${C[@]}" --brief-file "$tmp/brief-crule.md" --dry-run
expect_in "contract: none found in the brief - check-contract not run (CORE §4)"
expect_in "[dry-run] (cd "
# quoted Markdown front matter (title: is common there) is no contract either (#267)
printf 'Make docs/p.md with:\n---\ntitle: My page\nlayout: post\n---\nBody.\n' > "$tmp/brief-cfront.md"
check 0 "start: quoted front matter with title: is no contract" -- start --name "#67 worker: C" "${C[@]}" --brief-file "$tmp/brief-cfront.md" --dry-run
expect_in "contract: none found in the brief - check-contract not run (CORE §4)"
check 1 "start: --contract with an ERROR is refused" -- start --name "#67 worker: C" "${C[@]}" --brief-file "$tmp/brief.md" --contract "$cc/tests-first-missing.md" --dry-run
expect_in "tests-first-missing.md: ERROR missing \`tests_first\`"
expect_in "refused: the contract fails check-contract"
case "$LAST" in *"[dry-run]"*) echo "FAIL: the dry run went on after the contract's ERROR"; fail=1 ;; esac
tfno "$cc/budget-time-ok.md" > "$tmp/budget-time-ok.md"
check 0 "start: --contract that passes" -- start --name "#67 worker: C" "${C[@]}" --brief-file "$tmp/brief-cerr.md" --contract "$tmp/budget-time-ok.md" --dry-run
keep_start contract "$tmp/budget-time-ok.md"
expect_in "budget-time-ok.md: OK (0 errors, 0 warnings)"
case "$LAST" in *"contract in the brief"*) echo "FAIL: --contract given, the brief's contract was checked too"; fail=1 ;; esac
check 0 "start: a brief without a contract" -- start --name "#67 worker: C" "${C[@]}" --brief-file "$tmp/brief.md" --dry-run
expect_in "contract: none found in the brief - check-contract not run (CORE §4)"
check 0 "start: no contract check for a verifier" -- start --name "#67 verifier: C" "${C[@]}" --brief-file "$tmp/brief-cerr.md" --dry-run
case "$LAST" in *"check-contract"*|*"contract in the brief"*) echo "FAIL: a verifier start checked the contract"; fail=1 ;; esac
# the tests_first gate (#276): a worker whose contract (in the brief, or --contract) says `tests_first: yes`
# starts only with the tester's tests - --tester-commit <sha> (a commit that is the start point or an
# ancestor of it: a reused worktree's HEAD, else the base) or --tester-tests <path> (an existing file or
# folder, a lead's case); a refusal names the contract, the missing flag and CORE §4 step 3, and comes
# before anything is created (--dry-run too). Access points: the flags --tester-commit / -TesterCommit and
# --tester-tests / -TesterTests; a start with either prints one line naming the commit or the path.
{ printf 'Do it.\n\n'; cat "$cc/budget-time-ok.md"; } > "$tmp/brief-tfyes.md"
{ printf 'Do it.\n\n'; tfno "$cc/budget-time-ok.md"; } > "$tmp/brief-tfno.md"
cp "$cc/budget-time-ok.md" "$tmp/c276-yes.md"; tfno "$cc/budget-time-ok.md" > "$tmp/c276-no.md"
grep -q '^tests_first: yes$' "$tmp/brief-tfyes.md" && grep -q '^tests_first: no - ' "$tmp/brief-tfno.md" ||
  { echo "FAIL: could not write the tests_first briefs"; fail=1; }
F=(--repo "$tmp/repo" --model opus --safety "$tmp/safety.json" --report-to x)
expect_gate() {   # expect_gate <contract label>: the refusal's content, not its wording
  printf '%s\n' "$LAST" | grep -F -- "$1" | grep -q tests_first ||
    { echo "FAIL: no line names the contract ($1) and tests_first"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }
  case "$LAST" in *--tester-commit*|*-TesterCommit*|*--tester-tests*|*-TesterTests*) ;;
    *) echo "FAIL: the refusal does not name the missing flag (--tester-commit / --tester-tests)"; fail=1 ;; esac
  expect_in "§4 step 3"
}
nothing_made() {   # nothing_made <branch>: no worktree, no branch, no claude, no launch line
  [ -d "$tmp/repo/.claude/worktrees/$1" ] && { echo "FAIL: a worktree was created ($1)"; fail=1; }
  git -C "$tmp/repo" show-ref -q --verify "refs/heads/$1" && { echo "FAIL: a branch was created ($1)"; fail=1; }
  grep -q -- '--bg' "$STUB_LOG" && { echo "FAIL: claude was started ($1)"; fail=1; }
  case "$LAST" in *"[dry-run] (cd "*) echo "FAIL: the dry run went on to the launch ($1)"; fail=1 ;; esac
}
one_line() {   # one_line <text>: exactly one output line names the tester's tests
  [ "$(printf '%s\n' "$LAST" | grep -cF -- "$1")" = 1 ] ||
    { echo "FAIL: not exactly one line names the tester's tests ($1)"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }
}
: > "$STUB_LOG"
check 1 "start: tests_first yes in the brief, no tester flag, dry run" -- start --name "#76 worker: G" "${F[@]}" --branch 76-gate --brief-file "$tmp/brief-tfyes.md" --dry-run
keep_start brief "$tmp/brief-tfyes.md"; expect_gate "contract in the brief"; nothing_made 76-gate
check 1 "start: tests_first yes by --contract, no tester flag, dry run" -- start --name "#76 worker: G" "${F[@]}" --branch 76-gate --brief-file "$tmp/brief.md" --contract "$tmp/c276-yes.md" --dry-run
keep_start contract "$tmp/c276-yes.md"; expect_gate "c276-yes.md"; nothing_made 76-gate
check 1 "start: tests_first yes by --contract, no tester flag" -- start --name "#76 worker: G" "${F[@]}" --branch 76-gate --brief-file "$tmp/brief.md" --contract "$tmp/c276-yes.md"
expect_gate "c276-yes.md"; nothing_made 76-gate
check 1 "start: tests_first yes in the brief, no tester flag" -- start --name "#76 worker: G" "${F[@]}" --branch 76-gate --brief-file "$tmp/brief-tfyes.md"
expect_gate "contract in the brief"; nothing_made 76-gate
git -C "$tmp/repo" worktree remove --force "$tmp/repo/.claude/worktrees/76-gate" 2>/dev/null; git -C "$tmp/repo" branch -q -D 76-gate 2>/dev/null
# a valid --tester-commit: the reused worktree's HEAD (the tester's commit on the task branch), then an
# ancestor of it; on a new branch, a commit of the base
wtg="$tmp/repo/.claude/worktrees/77-gate"
git -C "$tmp/repo" worktree add -q -b 77-gate "$wtg" main && g -C "$wtg" commit -q --allow-empty -m "test: t8 (tester)"
tc="$(git -C "$wtg" rev-parse HEAD)"; tcs="$(printf '%s' "$tc" | cut -c1-7)"
: > "$STUB_LOG"
check 0 "start: tests_first yes, --tester-commit the worktree's HEAD" -- start --name "#77 worker: G" "${F[@]}" --branch 77-gate --brief-file "$tmp/brief-tfyes.md" --tester-commit "$tc"
expect_in "reusing worktree"; one_line "$tcs"
grep -qF -- "--bg --name #77 worker: G" "$STUB_LOG" || { echo "FAIL: the worker with --tester-commit was not started"; fail=1; }
g -C "$wtg" commit -q --allow-empty -m "work on top"
: > "$STUB_LOG"
check 0 "start: tests_first yes, --tester-commit an ancestor of the worktree's HEAD" -- start --name "#77 worker: G" "${F[@]}" --branch 77-gate --brief-file "$tmp/brief.md" --contract "$tmp/c276-yes.md" --tester-commit "$tc"
one_line "$tcs"
grep -qF -- "--bg --name #77 worker: G" "$STUB_LOG" || { echo "FAIL: the worker with an ancestor --tester-commit was not started"; fail=1; }
bc="$(git -C "$tmp/repo" rev-parse main)"; bcs="$(printf '%s' "$bc" | cut -c1-7)"
: > "$STUB_LOG"
check 0 "start: tests_first yes, --tester-commit on the base, a new branch" -- start --name "#78 worker: G" "${F[@]}" --branch 78-gate --brief-file "$tmp/brief-tfyes.md" --tester-commit "$bc"
one_line "$bcs"
[ -d "$tmp/repo/.claude/worktrees/78-gate" ] || { echo "FAIL: no worktree for a valid --tester-commit on the base"; fail=1; }
grep -qF -- "--bg --name #78 worker: G" "$STUB_LOG" || { echo "FAIL: the worker with a base --tester-commit was not started"; fail=1; }
# --tester-tests: the tests a lead's tester subagent returned, a folder or a file (kept in .lead/)
mkdir -p "$tmp/lead276/.lead/tt276" && echo 'exit 1' > "$tmp/lead276/.lead/tt276/t276-red.sh"
check 0 "start: tests_first yes, --tester-tests a folder" -- start --name "#79 worker: G" "${F[@]}" --branch 79-gate --brief-file "$tmp/brief-tfyes.md" --tester-tests "$tmp/lead276/.lead/tt276" --dry-run
expect_in "[dry-run] (cd "; one_line "tt276"
check 0 "start: tests_first yes, --tester-tests a file" -- start --name "#79 worker: G" "${F[@]}" --branch 79-gate --brief-file "$tmp/brief-tfyes.md" --tester-tests "$tmp/lead276/.lead/tt276/t276-red.sh" --dry-run
expect_in "[dry-run] (cd "; one_line "t276-red.sh"
: > "$STUB_LOG"
check 1 "start: tests_first yes, --tester-tests that does not exist" -- start --name "#79 worker: G" "${F[@]}" --branch 79-gate --brief-file "$tmp/brief-tfyes.md" --tester-tests "$tmp/lead276/no-tt276"
expect_in "no-tt276"; nothing_made 79-gate
# a --tester-commit that does not exist, and one that is not on the start point: each its own message
nx=0123456789abcdef0123456789abcdef01234567
off="$(g -C "$tmp/repo" commit-tree -p main -m "off the start point" "main^{tree}")"; offs="$(printf '%s' "$off" | cut -c1-7)"
: > "$STUB_LOG"
check 1 "start: a --tester-commit that does not exist, dry run" -- start --name "#80 worker: G" "${F[@]}" --branch 80-gate --brief-file "$tmp/brief-tfyes.md" --tester-commit "$nx" --dry-run
expect_in "0123456"; nothing_made 80-gate
check 1 "start: a --tester-commit that does not exist" -- start --name "#80 worker: G" "${F[@]}" --branch 80-gate --brief-file "$tmp/brief-tfyes.md" --tester-commit "$nx"
expect_in "0123456"; nothing_made 80-gate
m1="$(printf '%s\n' "$LAST" | sed "s/0123456[0-9a-f]*/SHA/g")"
check 1 "start: a --tester-commit not on the start point" -- start --name "#80 worker: G" "${F[@]}" --branch 80-gate --brief-file "$tmp/brief-tfyes.md" --tester-commit "$off"
expect_in "$offs"; nothing_made 80-gate
m2="$(printf '%s\n' "$LAST" | sed "s/$offs[0-9a-f]*/SHA/g")"
[ "$m1" != "$m2" ] || { echo "FAIL: the same message for a commit that does not exist and one not on the start point"; fail=1; }
: > "$STUB_LOG"
check 1 "start: a --tester-commit not on the reused worktree's HEAD" -- start --name "#77 worker: G" "${F[@]}" --branch 77-gate --brief-file "$tmp/brief-tfyes.md" --tester-commit "$off"
expect_in "$offs"
grep -q -- '--bg' "$STUB_LOG" && { echo "FAIL: claude was started with a --tester-commit off the worktree's HEAD"; fail=1; }
# unchanged starts, no new flag: tests_first no - <reason> (brief, --contract), a lead, a tester
# (a brief with no contract: "start: a brief without a contract" above)
for v in "#81 worker: G|--brief-file|$tmp/brief-tfno.md" "#81 worker: G|--contract|$tmp/c276-no.md" "#81 lead: G|--brief-file|$tmp/brief-tfno.md" "#81 tester: G|--brief-file|$tmp/brief-tfyes.md"; do
  vn="${v%%|*}"; vr="${v#*|}"; vf="${vr%%|*}"; vp="${vr#*|}"
  if [ "$vf" = --contract ]; then va=(--brief-file "$tmp/brief.md" --contract "$vp"); else va=(--brief-file "$vp"); fi
  check 0 "start: unchanged, $vn $vf $(basename "$vp")" -- start --name "$vn" "${F[@]}" --branch 81-gate "${va[@]}" --dry-run
  case "$vn" in *worker*) if [ "$vf" = --contract ]; then keep_start contract "$vp"; else keep_start brief "$vp"; fi ;; esac
  expect_in "[dry-run] (cd "
  case "$vn" in *tester*) ;; *) case "$LAST" in *--tester*|*-Tester*|*"tester's"*) echo "FAIL: $vn names a tester at an unchanged start"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1 ;; esac ;; esac
done
# round 2 (#276, the review of PR #286): the gate reads the contract block as check-contract does - the
# front matter, or the body of a top-level `contract:` (check-contract.sh line 5) - and only that block
cbody() { sed '1d;$d' "$1" | sed 's/^/  /'; }   # the front matter's lines, indented two spaces
{ printf 'contract:\n'; cbody "$cc/budget-time-ok.md"; } > "$tmp/c276-cblock-yes.md"
{ printf 'contract:\n'; cbody "$tmp/c276-no.md"; } > "$tmp/c276-cblock-no.md"
{ tfno "$cc/budget-time-ok.md"; printf '\n## An example\n\ntests_first: yes\n'; } > "$tmp/c276-body-yes.md"
{ printf 'Do it.\n\n'; cat "$tmp/c276-body-yes.md"; } > "$tmp/brief-body-yes.md"
grep -q '^  tests_first: yes$' "$tmp/c276-cblock-yes.md" && grep -q '^  tests_first: no - ' "$tmp/c276-cblock-no.md" &&
  grep -q '^tests_first: no - ' "$tmp/c276-body-yes.md" && [ "$(grep -c '^tests_first: yes$' "$tmp/c276-body-yes.md")" = 1 ] ||
  { echo "FAIL: could not write the round-2 contracts"; fail=1; }
: > "$STUB_LOG"
check 1 "start: tests_first yes in a contract: block, no tester flag, dry run" -- start --name "#82 worker: G" "${F[@]}" --branch 82-gate --brief-file "$tmp/brief.md" --contract "$tmp/c276-cblock-yes.md" --dry-run
keep_start contract "$tmp/c276-cblock-yes.md"; expect_in "c276-cblock-yes.md: OK"; expect_gate "c276-cblock-yes.md"; nothing_made 82-gate
check 1 "start: tests_first yes in a contract: block, no tester flag" -- start --name "#82 worker: G" "${F[@]}" --branch 82-gate --brief-file "$tmp/brief.md" --contract "$tmp/c276-cblock-yes.md"
expect_gate "c276-cblock-yes.md"; nothing_made 82-gate
for v in "--contract|$tmp/c276-cblock-no.md" "--contract|$tmp/c276-body-yes.md" "--brief-file|$tmp/brief-body-yes.md"; do
  vf="${v%%|*}"; vp="${v#*|}"
  if [ "$vf" = --contract ]; then va=(--brief-file "$tmp/brief.md" --contract "$vp"); else va=(--brief-file "$vp"); fi
  check 0 "start: unchanged, #83 worker: G $vf $(basename "$vp")" -- start --name "#83 worker: G" "${F[@]}" --branch 83-gate "${va[@]}" --dry-run
  if [ "$vf" = --contract ]; then keep_start contract "$vp"; else keep_start brief "$vp"; fi
  expect_in "[dry-run] (cd "
  case "$LAST" in *--tester*|*-Tester*|*"tester's"*) echo "FAIL: $(basename "$vp") names a tester at an unchanged start"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1 ;; esac
done
# the existing-branch start point: the task branch is there, its worktree removed; the tester's commit is
# the branch's tip, then an ancestor of it (a regression guard: the worker starts, one line names it)
wtb="$tmp/repo/.claude/worktrees/84-gate"
git -C "$tmp/repo" worktree add -q -b 84-gate "$wtb" main && g -C "$wtb" commit -q --allow-empty -m "test: t8 (tester)"
tb="$(git -C "$wtb" rev-parse HEAD)"; tbs="$(printf '%s' "$tb" | cut -c1-7)"
git -C "$tmp/repo" worktree remove --force "$wtb"
[ -d "$wtb" ] && { echo "FAIL: could not remove the 84-gate worktree"; fail=1; }
: > "$STUB_LOG"
check 0 "start: tests_first yes, --tester-commit the existing branch's tip, no worktree" -- start --name "#84 worker: G" "${F[@]}" --branch 84-gate --brief-file "$tmp/brief-tfyes.md" --tester-commit "$tb"
one_line "$tbs"
grep -qF -- "--bg --name #84 worker: G" "$STUB_LOG" || { echo "FAIL: the worker on the existing branch's tip was not started"; fail=1; }
[ "$(git -C "$wtb" rev-parse HEAD 2>/dev/null)" = "$tb" ] || { echo "FAIL: the worktree is not on the existing branch's tip"; fail=1; }
g -C "$wtb" commit -q --allow-empty -m "work on top"; git -C "$tmp/repo" worktree remove --force "$wtb"
: > "$STUB_LOG"
check 0 "start: tests_first yes, --tester-commit an ancestor of the existing branch's tip, no worktree" -- start --name "#84 worker: G" "${F[@]}" --branch 84-gate --brief-file "$tmp/brief-tfyes.md" --tester-commit "$tb"
one_line "$tbs"
grep -qF -- "--bg --name #84 worker: G" "$STUB_LOG" || { echo "FAIL: the worker on an ancestor of the branch's tip was not started"; fail=1; }
git -C "$tmp/repo" worktree remove --force "$wtb" 2>/dev/null
# --tester-commit and --tester-tests are alternatives: both together are refused with their own message,
# before anything is created (each value valid on its own)
both_named() {
  printf '%s\n' "$LAST" | grep -E -- '--tester-commit|-TesterCommit' | grep -Eq -- '--tester-tests|-TesterTests' ||
    { echo "FAIL: no line names both --tester-commit and --tester-tests"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }
  case "$LAST" in *"has tests_first: yes"*|*"tester's tests:"*) echo "FAIL: both flags: not their own message"; fail=1 ;; esac
}
: > "$STUB_LOG"
check 1 "start: both --tester-commit and --tester-tests, dry run" -- start --name "#85 worker: G" "${F[@]}" --branch 85-gate --brief-file "$tmp/brief-tfyes.md" --tester-commit "$bc" --tester-tests "$tmp/lead276/.lead/tt276" --dry-run
both_named; nothing_made 85-gate
check 1 "start: both --tester-commit and --tester-tests" -- start --name "#85 worker: G" "${F[@]}" --branch 85-gate --brief-file "$tmp/brief-tfyes.md" --tester-commit "$bc" --tester-tests "$tmp/lead276/.lead/tt276"
both_named; nothing_made 85-gate
# a lead's task gets no task-level tester (#289): the lead runs the tester per sub-contract, its tests on
# the sub-branches (roles/lead.md step 3), so a lead whose contract (in the brief, or --contract) says
# `tests_first: yes`, or a lead given --tester-commit / --tester-tests, is refused before anything is
# created (--dry-run too); the refusal says a lead's contract has `tests_first: no - the lead runs the
# tester per sub-contract`. A lead with `tests_first: no - <reason>` starts as before (the loop above)
expect_lead() {   # expect_lead [<contract label>]: one line says lead and sub-contract (and names the contract)
  printf '%s\n' "$LAST" | grep -F -- "${1:-lead}" | grep -i lead | grep -q sub-contract ||
    { echo "FAIL: no line${1:+ names the contract ($1),} says lead and sub-contract"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }
}
: > "$STUB_LOG"
check 1 "start: a lead, tests_first yes in the brief, dry run" -- start --name "#86 lead: G" "${F[@]}" --branch 86-lead --brief-file "$tmp/brief-tfyes.md" --dry-run
expect_lead "contract in the brief"; expect_in tests_first; nothing_made 86-lead
check 1 "start: a lead, tests_first yes in the brief" -- start --name "#86 lead: G" "${F[@]}" --branch 86-lead --brief-file "$tmp/brief-tfyes.md"
expect_lead "contract in the brief"; expect_in tests_first; nothing_made 86-lead
check 1 "start: a lead, tests_first yes by --contract, dry run" -- start --name "#86 lead: G" "${F[@]}" --branch 86-lead --brief-file "$tmp/brief.md" --contract "$tmp/c276-yes.md" --dry-run
expect_lead "c276-yes.md"; expect_in tests_first; nothing_made 86-lead
check 1 "start: a lead, tests_first yes by --contract" -- start --name "#86 lead: G" "${F[@]}" --branch 86-lead --brief-file "$tmp/brief.md" --contract "$tmp/c276-yes.md"
expect_lead "c276-yes.md"; expect_in tests_first; nothing_made 86-lead
check 1 "start: a lead, tests_first yes in a contract: block" -- start --name "#86 lead: G" "${F[@]}" --branch 86-lead --brief-file "$tmp/brief.md" --contract "$tmp/c276-cblock-yes.md"
expect_lead "c276-cblock-yes.md"; nothing_made 86-lead
# a lead given the tester's flags: refused the same way, whatever its contract says (each value valid)
for v in "--tester-commit|$bc|$tmp/brief-tfno.md" "--tester-tests|$tmp/lead276/.lead/tt276|$tmp/brief-tfno.md" "--tester-commit|$bc|$tmp/brief-tfyes.md" "--tester-tests|$tmp/lead276/.lead/tt276|$tmp/brief-tfyes.md"; do
  vf="${v%%|*}"; vr="${v#*|}"; vv="${vr%%|*}"; vb="${vr#*|}"
  for d in --dry-run ""; do
    check 1 "start: a lead given $vf, $(basename "$vb")${d:+, dry run}" -- start --name "#87 lead: G" "${F[@]}" --branch 87-lead --brief-file "$vb" "$vf" "$vv" $d
    expect_lead; nothing_made 87-lead
  done
done
# a lead with tests_first no starts as before, past the dry run too: a worktree and claude
check 0 "start: a lead, tests_first no by --contract" -- start --name "#88 lead: G" "${F[@]}" --branch 88-lead --brief-file "$tmp/brief.md" --contract "$tmp/c276-no.md"
[ -d "$tmp/repo/.claude/worktrees/88-lead" ] || { echo "FAIL: no worktree for a lead with tests_first no"; fail=1; }
grep -qF -- "--bg --name #88 lead: G" "$STUB_LOG" || { echo "FAIL: the lead with tests_first no was not started"; fail=1; }
case "$LAST" in *sub-contract*) echo "FAIL: a lead with tests_first no got the lead refusal's text"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1 ;; esac
git -C "$tmp/repo" worktree remove --force "$tmp/repo/.claude/worktrees/88-lead" 2>/dev/null; git -C "$tmp/repo" branch -q -D 88-lead 2>/dev/null
# round 3 (#276, the re-review of 2fe293c): one parser - start-worker takes tests_first from check-contract
# itself, so the two cannot disagree. Access point: check-contract's read-only option that prints the value
# of a key as its own extraction reads it (the key's text with its continuation lines, comment and quotes
# removed), exit 0 and the value on one line when the contract passes, else its usual errors and exit -
# `check-contract.sh --<fopt> tests_first <file>` / `check-contract.ps1 -<fopt> tests_first <file>`; the
# worker names it: set fopt to that name (PowerShell takes it in any case)
fopt=field
cc_run() {   # cc_run [option args] <file>: check-contract of this kind, its output without CRs
  if [ "$kind" = ps ]; then "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$core/scripts/check-contract.ps1" "$@" 2>&1 | tr -d '\r'
  else bash "$core/scripts/check-contract.sh" "$@" 2>&1 | tr -d '\r'; fi
  return "${PIPESTATUS[0]}"
}
cc_decide() {   # cc_decide <file>: what check-contract reads - fail, yes or no into GD (a FAIL if its option and check-contract disagree)
  local out rc prc v d=--
  [ "$kind" = ps ] && d=-
  cc_run "$1" > /dev/null; prc=$?
  out="$(cc_run "$d$fopt" tests_first "$1")"; rc=$?
  if [ "$rc" != "$prc" ]; then
    echo "FAIL: check-contract's $fopt option exits $rc on $(basename "$1"), check-contract itself $prc"
    printf '%s\n' "$out" | sed 's/^/    /'; fail=1; GD=fail; return
  fi
  [ "$rc" = 0 ] || { GD=fail; return; }
  [ "$(printf '%s\n' "$out" | grep -c .)" = 1 ] ||
    { echo "FAIL: check-contract's $fopt option printed not one line on $(basename "$1")"; printf '%s\n' "$out" | sed 's/^/    /'; fail=1; }
  v="$(printf '%s\n' "$out" | grep . | head -n 1)"
  if printf '%s\n' "$v" | grep -Eiq '^yes([[:space:],:;(]|$)'; then GD=yes; else GD=no; fi
}
gate_as() {   # gate_as <decision> <label>: the last start did what check-contract read (fail / yes; no: its exit 0)
  case "$1" in
    fail) case "$LAST" in *"refused: the contract fails check-contract"*) ;;
      *) echo "FAIL: $2: check-contract fails it, start-worker did not refuse on it"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1 ;; esac ;;
    yes) printf '%s\n' "$LAST" | grep tests_first | grep -q '§4 step 3' ||
      { echo "FAIL: $2: check-contract reads tests_first yes, no gate refusal"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; } ;;
  esac
}
drop_gate() {   # drop_gate <branch>: a start these cases wrongly let through leaves nothing for the next case
  git -C "$tmp/repo" worktree remove --force "$tmp/repo/.claude/worktrees/$1" 2>/dev/null; git -C "$tmp/repo" branch -q -D "$1" 2>/dev/null; : > "$STUB_LOG"
}
# N1: a quoted tests_first value spanning lines reads as yes in check-contract - the gate refuses it too
for qn in dq sq; do
  if [ "$qn" = dq ]; then qc='"'; else qc="'"; fi
  sed "s/^tests_first: yes\$/tests_first: ${qc}yes, because\\
  it is cheap${qc}/" "$cc/budget-time-ok.md" > "$tmp/c276-span-$qn.md"
  { printf 'contract:\n'; cbody "$tmp/c276-span-$qn.md"; } > "$tmp/c276-cspan-$qn.md"
  { printf 'Do it.\n\n'; cat "$tmp/c276-span-$qn.md"; } > "$tmp/brief-span-$qn.md"
  grep -q "^tests_first: ${qc}yes, because\$" "$tmp/c276-span-$qn.md" && grep -q "^  it is cheap${qc}\$" "$tmp/c276-span-$qn.md" &&
    grep -q "^    it is cheap${qc}\$" "$tmp/c276-cspan-$qn.md" || { echo "FAIL: could not write the spanning contracts ($qn)"; fail=1; }
  # the precondition: check-contract passes them (its own reading is yes: the gate's to agree with)
  cc_run "$tmp/c276-span-$qn.md" > /dev/null || { echo "FAIL: check-contract does not pass c276-span-$qn.md"; fail=1; }
  cc_run "$tmp/c276-cspan-$qn.md" > /dev/null || { echo "FAIL: check-contract does not pass c276-cspan-$qn.md"; fail=1; }
  : > "$STUB_LOG"
  check 1 "start: tests_first yes spanning lines ($qn), front matter, no tester flag, dry run" -- start --name "#86 worker: G" "${F[@]}" --branch 86-gate --brief-file "$tmp/brief.md" --contract "$tmp/c276-span-$qn.md" --dry-run
  keep_start contract "$tmp/c276-span-$qn.md"; expect_gate "c276-span-$qn.md"; nothing_made 86-gate
  check 1 "start: tests_first yes spanning lines ($qn), front matter, no tester flag" -- start --name "#86 worker: G" "${F[@]}" --branch 86-gate --brief-file "$tmp/brief.md" --contract "$tmp/c276-span-$qn.md"
  expect_gate "c276-span-$qn.md"; nothing_made 86-gate; drop_gate 86-gate
  check 1 "start: tests_first yes spanning lines ($qn), a contract: block, no tester flag, dry run" -- start --name "#86 worker: G" "${F[@]}" --branch 86-gate --brief-file "$tmp/brief.md" --contract "$tmp/c276-cspan-$qn.md" --dry-run
  keep_start contract "$tmp/c276-cspan-$qn.md"; expect_gate "c276-cspan-$qn.md"; nothing_made 86-gate
  check 1 "start: tests_first yes spanning lines ($qn), in the brief, no tester flag, dry run" -- start --name "#86 worker: G" "${F[@]}" --branch 86-gate --brief-file "$tmp/brief-span-$qn.md" --dry-run
  keep_start brief "$tmp/brief-span-$qn.md"; expect_gate "contract in the brief"; nothing_made 86-gate
  check 1 "start: tests_first yes spanning lines ($qn), in the brief, no tester flag" -- start --name "#86 worker: G" "${F[@]}" --branch 86-gate --brief-file "$tmp/brief-span-$qn.md"
  expect_gate "contract in the brief"; nothing_made 86-gate; drop_gate 86-gate
done
# N2: a valid tests_first yes contract saved with CR-only line endings - check-contract fails it (then
# start-worker refuses on its ERROR) or passes it (then the gate refuses it); never a start without the tester
tr '\n' '\r' < "$cc/budget-time-ok.md" > "$tmp/c276-cr.md"
[ "$(tr -cd '\n' < "$tmp/c276-cr.md" | wc -c | tr -d ' ')" = 0 ] && grep -q 'tests_first: yes' "$tmp/c276-cr.md" ||
  { echo "FAIL: could not write the CR-only contract"; fail=1; }
crd=fail; cc_run "$tmp/c276-cr.md" > /dev/null && crd=yes
: > "$STUB_LOG"
check 1 "start: tests_first yes with CR-only line endings, no tester flag, dry run" -- start --name "#87 worker: G" "${F[@]}" --branch 87-gate --brief-file "$tmp/brief.md" --contract "$tmp/c276-cr.md" --dry-run
keep_start contract "$tmp/c276-cr.md"; gate_as "$crd" c276-cr.md; nothing_made 87-gate; drop_gate 87-gate
check 1 "start: tests_first yes with CR-only line endings, no tester flag" -- start --name "#87 worker: G" "${F[@]}" --branch 87-gate --brief-file "$tmp/brief.md" --contract "$tmp/c276-cr.md"
gate_as "$crd" c276-cr.md; nothing_made 87-gate; drop_gate 87-gate
# the agreement guard: for every contract the gate's cases use, and the forms the round-2 review tried,
# start-worker (no tester flag, dry run) does what check-contract reads: refuses on its ERROR, refuses at
# the gate on yes, starts on no - by --contract, and in a brief for the front-matter forms; a start an earlier
# case kept (the same contract by --contract, or a brief of the same bytes) is not run again: the guard's
# checks run on its exit and output
sed 's/^tests_first: yes$/tests_first: "yes"/' "$cc/budget-time-ok.md" > "$tmp/g276-dq.md"
sed "s/^tests_first: yes\$/tests_first: 'Yes'/" "$cc/budget-time-ok.md" > "$tmp/g276-sq-cap.md"
sed 's/^tests_first: yes$/tests_first: yes   # the oracles have no tests yet/' "$cc/budget-time-ok.md" > "$tmp/g276-comment.md"
sed 's/^\(tests_first: no - .*\)$/\1   # yes, really/' "$tmp/c276-no.md" > "$tmp/g276-no-comment.md"
{ printf 'contract:\n'; sed '1d;$d' "$cc/budget-time-ok.md" | sed 's/^/    /'; } > "$tmp/g276-cblock4.md"
{ printf 'contract:\n'; sed '1d;$d' "$cc/budget-time-ok.md" | sed "s/^/$(printf '\t')/"; } > "$tmp/g276-cblock-tab.md"
{ printf '# Task\n\nSome words.\n\ncontract:\n'; cbody "$tmp/c276-no.md"; printf 'notes: after the block\ntests_first: yes\n'; } > "$tmp/g276-cblock-later.md"
{ cat "$tmp/c276-no.md"; printf '\ncontract:\n'; cbody "$cc/budget-time-ok.md"; } > "$tmp/g276-fm-then-cblock.md"
sed 's/$/\r/' "$cc/budget-time-ok.md" > "$tmp/g276-crlf.md"
{ printf '\357\273\277'; cat "$cc/budget-time-ok.md"; } > "$tmp/g276-bom.md"
reused() {   # reused <contract | brief> <file> <expected exit> <label>: a kept start of the same file and form, as the last start
  local k f m
  while IFS="$(printf '\t')" read -r k f m; do
    [ "$k" = "$1" ] || continue
    if [ "$k" = contract ]; then [ "$f" = "$2" ] || continue; else cmp -s "$f" "$2" || continue; fi
    LAST="$(cat "$tmp/kept/$m.out")"; LRC="$(cat "$tmp/kept/$m.rc")"; nr=$((nr + 1))
    [ "$LRC" = "$3" ] || { echo "FAIL ($4, the start kept from an earlier case): expected exit $3, got $LRC"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }
    return 0
  done < "$tmp/kept/index"
  return 1
}
gi=0
for gf in "$tmp/c276-yes.md" "$tmp/c276-no.md" "$tmp/budget-time-ok.md" "$tmp/c276-cblock-yes.md" "$tmp/c276-cblock-no.md" "$tmp/c276-body-yes.md" \
  "$cc/budget-time.md" "$cc/quoted.md" "$cc/tests-first-missing.md" "$cc/tests-first-bad.md" "$cc/tests-first-no-reason.md" \
  "$tmp/c276-span-dq.md" "$tmp/c276-span-sq.md" "$tmp/c276-cspan-dq.md" "$tmp/c276-cspan-sq.md" "$tmp/c276-cr.md" \
  "$tmp/g276-dq.md" "$tmp/g276-sq-cap.md" "$tmp/g276-comment.md" "$tmp/g276-no-comment.md" "$tmp/g276-cblock4.md" "$tmp/g276-cblock-tab.md" \
  "$tmp/g276-cblock-later.md" "$tmp/g276-fm-then-cblock.md" "$tmp/g276-crlf.md" "$tmp/g276-bom.md"; do
  gi=$((gi + 1)); gb="$(basename "$gf")"
  [ -f "$gf" ] || { echo "FAIL: the guard's fixture $gb is missing"; fail=1; continue; }
  cc_decide "$gf"; gd="$GD"; gw=1; [ "$gd" = no ] && gw=0
  : > "$STUB_LOG"
  reused contract "$gf" "$gw" "guard: --contract $gb (check-contract reads: $gd)" ||
  check "$gw" "guard: --contract $gb (check-contract reads: $gd)" -- start --name "#88 worker: G" "${F[@]}" --branch 88-gate --brief-file "$tmp/brief.md" --contract "$gf" --dry-run
  gate_as "$gd" "$gb"; [ "$gw" = 0 ] || nothing_made 88-gate
  # a brief holding it: the front-matter forms with LF endings and no BOM (a brief's contract follows its text)
  case "$gb" in g276-crlf.md|g276-bom.md|c276-cr.md) continue ;; esac
  [ "$(head -n 1 "$gf")" = "---" ] || continue
  { printf 'Do it.\n\n'; cat "$gf"; } > "$tmp/brief-g$gi.md"
  : > "$STUB_LOG"
  reused brief "$tmp/brief-g$gi.md" "$gw" "guard: a brief holding $gb (check-contract reads: $gd)" ||
  check "$gw" "guard: a brief holding $gb (check-contract reads: $gd)" -- start --name "#88 worker: G" "${F[@]}" --branch 88-gate --brief-file "$tmp/brief-g$gi.md" --dry-run
  gate_as "$gd" "brief with $gb"; [ "$gw" = 0 ] || nothing_made 88-gate
done
drop_gate 88-gate
git -C "$tmp/repo" worktree remove --force "$wtg" 2>/dev/null; git -C "$tmp/repo" worktree remove --force "$tmp/repo/.claude/worktrees/78-gate" 2>/dev/null
: > "$STUB_LOG"
check 0 "start: --effort passed to claude" -- start --repo "$tmp/repo" --name "#54 worker: e" --branch 54-effort "${W[@]}" --safety "$tmp/safety.json" --effort low
grep -q -- "--bg --name #54 worker: e --model opus --effort low --permission-mode auto" "$STUB_LOG" ||
  { echo "FAIL: claude did not get --effort low:"; sed 's/^/    /' "$STUB_LOG"; fail=1; }
git -C "$tmp/repo" worktree remove --force "$tmp/repo/.claude/worktrees/54-effort" 2>/dev/null

# --- a big brief through a file (#291): above 24 000 characters of full launch text (first line + role +
# brief) start-worker writes that text to a file under <config>/coordinator/briefs/ and the session's first
# message is one short instruction naming the file's absolute path (read it in full with the Read tool);
# one output line says the brief goes through a file and names it (the words "brief" and "file", and the
# path); a dry run says so too and creates nothing; at or below the threshold nothing changes. A launch
# that fails: a non-zero exit and a line naming what was created and cleanup-worker.
awk 'BEGIN { for (i = 1; i <= 800; i++) printf "Строка %04d брифа: проверка — ü ✓ \"quoted\" and plain ASCII text\n", i }' > "$tmp/brief-big.md"
# the role's body as start-worker puts it in front of the brief (CRs dropped for the comparison)
# (its leading blank lines are not compared: the .sh keeps them, the .ps1 drops them)
wbody="$(awk 'NR == 1 && /^---/ { f = 1; next } f && /^---/ { f = 0; next } !f' "$core/roles/worker.md" | tr -d '\r' | awk 'length || s { s = 1; print }')"
big0=(--repo "$tmp/repo" --name "#91 worker: Big" --model opus --safety "$tmp/safety.json" --report-to "Core lead"); big=("${big0[@]}" --brief-file "$tmp/brief-big.md")
bd291="$tmp/cfg/coordinator/briefs"
# the file a first message names: absolute, under <config>/coordinator/briefs/
argfile() { local p
  p="$(printf '%s' "$1" | grep -oE "[^ \"'<>()]*coordinator[/\\\\]briefs[/\\\\][^ \"'<>()]*" | head -n 1 | sed 's/[.,;:]*$//')"
  case "$p" in /*|[A-Za-z]:[/\\]*) ;; *) return 1 ;; esac
  command -v cygpath >/dev/null 2>&1 && p="$(cygpath -u "$p")"
  printf '%s' "$p"; }
# the full launch text: the first line, the report line, a blank, the role, a blank, the brief
is_launch_text() {   # is_launch_text <file> <branch> <brief file>
  local f="$1"
  [ -f "$f" ] || { echo "FAIL: no launch text file $f"; fail=1; return; }
  tr -d '\r' < "$f" | sed -n 1p | grep -q "^FIRST ACTION, before anything else: use the EnterWorktree tool with path = .*/.claude/worktrees/$2\." ||
    { echo "FAIL: $f does not start with the first line"; fail=1; }
  [ "$(tr -d '\r' < "$f" | sed -n 2p)" = 'Report to: the session named "Core lead" (SendMessage) - your report and your questions.' ] &&
    [ -z "$(tr -d '\r' < "$f" | sed -n 3p)" ] || { echo "FAIL: $f lacks the report line and a blank after it"; fail=1; }
  [ "$(tr -d '\r' < "$f" | sed -n '4,$p' | awk 'length || s { s = 1; print }')" = "$(printf '%s\n\n%s' "$wbody" "$(cat "$3")")" ] ||
    { echo "FAIL: $f is not the role and the brief exactly (line 4 on, leading blanks aside)"; tr -d '\r' < "$f" | sed -n '4,$p' | awk 'length || s { s = 1; print }' | diff - <(printf '%s\n\n%s\n' "$wbody" "$(cat "$3")") | head -n 5 | sed 's/^/    /'; fail=1; }
}
# the dry run: says it would go through a file, creates nothing
ls "$bd291" > "$tmp/briefs-before" 2>/dev/null; : > "$STUB_LOG"
check 0 "start: a big brief, dry run" -- start "${big[@]}" --branch 91-big --dry-run
printf '%s\n' "$LAST" | grep -i 'brief' | grep -v -e 'then the brief>' -e '^role ' -e '^contract: ' | grep -iq 'file' || { echo "FAIL: the dry run does not say a big brief would go through a file"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }
[ -e "$tmp/repo/.claude/worktrees/91-big" ] && { echo "FAIL: the dry run of a big brief created the worktree"; fail=1; }
git -C "$tmp/repo" show-ref -q --verify refs/heads/91-big && { echo "FAIL: the dry run of a big brief created the branch"; fail=1; }
[ "$(ls "$bd291" 2>/dev/null)" = "$(cat "$tmp/briefs-before")" ] || { echo "FAIL: the dry run of a big brief wrote under $bd291"; fail=1; }
[ -s "$STUB_LOG" ] && { echo "FAIL: the dry run of a big brief called claude"; fail=1; }
# the real start: a short first message naming the file, the file the full launch text, one output line
: > "$STUB_LOG"; rm -f "$STUB_LOG.arg"
check 0 "start: a big brief through a file" -- start "${big[@]}" --branch 91-big
a291="$(cat "$STUB_LOG.arg" 2>/dev/null)"
[ -n "$a291" ] && [ "${#a291}" -lt 2000 ] || { echo "FAIL: the first message of a big brief is not short (${#a291} characters)"; fail=1; }
case "$a291" in *"Read tool"*) ;; *) echo "FAIL: the first message does not say to read the file with the Read tool"; fail=1 ;; esac
case "$a291" in *"Строка 0001"*) echo "FAIL: the big brief went on the command line"; fail=1 ;; esac
if f291="$(argfile "$a291")"; then
  case "$f291" in "$bd291"/*|"$(cd "$bd291" 2>/dev/null && pwd -P)"/*) ;; *) echo "FAIL: the brief file $f291 is not under <config>/coordinator/briefs/"; fail=1 ;; esac
  is_launch_text "$f291" 91-big "$tmp/brief-big.md"
  [ "$(printf '%s\n' "$LAST" | grep -v 'kept for after a compaction' | grep -i 'brief' | grep -i 'file' | grep -cF "$(basename "$f291")")" = 1 ] ||
    { echo "FAIL: no one output line saying the brief goes through the file $(basename "$f291")"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }
else echo "FAIL: the first message names no absolute file under coordinator/briefs/: $(printf '%s' "$a291" | head -c 200)"; fail=1; fi
# the kept brief for after a compaction is the full launch text too
s291="$(grep -nxF "#91 worker: Big" "$STUB_LOG.names" | tail -n 1 | cut -d: -f1)"
k291="$bd291/5e550000-0000-4000-8000-$(printf '%012d' "${s291:-0}").md"
is_launch_text "$k291" 91-big "$tmp/brief-big.md"
git -C "$tmp/repo" worktree remove --force "$tmp/repo/.claude/worktrees/91-big" 2>/dev/null
# a small brief: on the command line as today, no line about a file
: > "$STUB_LOG"; rm -f "$STUB_LOG.arg"
check 0 "start: a small brief on the command line" -- start "${big0[@]}" --branch 91-small --brief-file "$tmp/brief.md"
is_launch_text "$STUB_LOG.arg" 91-small "$tmp/brief.md"
printf '%s\n' "$LAST" | grep -v 'kept for after a compaction' | grep -q 'coordinator[/\\]briefs' &&
  { echo "FAIL: a small brief got a line about a brief file"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }
check 0 "start: a small brief, dry run" -- start "${big0[@]}" --branch 91-small --brief-file "$tmp/brief.md" --dry-run
printf '%s\n' "$LAST" | grep -i 'brief' | grep -v -e 'then the brief>' -e '^role ' -e '^contract: ' | grep -iq 'file' &&
  { echo "FAIL: the dry run of a small brief speaks of a brief file"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }
git -C "$tmp/repo" worktree remove --force "$tmp/repo/.claude/worktrees/91-small" 2>/dev/null
# a launch that fails: non-zero, the worktree and branch it made named, and how to clean them
: > "$STUB_LOG"
n=$((n + 1)); LAST="$(STUB_BG_RC=3 start "${big0[@]}" --branch 91-fail --brief-file "$tmp/brief.md" 2>&1)"; LRC=$?
[ "$LRC" = 0 ] && { echo "FAIL (start: the launch fails): exited 0"; fail=1; }
case "$LAST" in *91-fail*cleanup-worker*|*cleanup-worker*91-fail*) ;; *) echo "FAIL: a failed launch does not name what it created and cleanup-worker"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1 ;; esac
git -C "$tmp/repo" worktree remove --force "$tmp/repo/.claude/worktrees/91-fail" 2>/dev/null

# --- a lead's notes beside its worktree (#310): start-worker makes <worktree>.lead/ (same parent, the
# worktree's folder name plus .lead) for a lead only, keeps an existing one, and names its absolute path
# in the launch text on a line that says notes; a dry run says it would create it and creates nothing ---
nwt="$tmp/repo/.claude/worktrees"
L=(--repo "$tmp/repo" --model opus --safety "$tmp/safety.json" --report-to "Core lead")
names_notes() {   # names_notes <launch text> <branch>: a line says notes and gives <worktree>.lead by absolute path
  local l p
  l="$(printf '%s\n' "$1" | tr -d '\r' | grep -i notes | grep -F "$2.lead" | head -n 1)"
  [ -n "$l" ] || { echo "FAIL: the launch text has no line naming the notes folder $2.lead"; fail=1; return; }
  p="$(printf '%s' "$l" | grep -oE "(/|[A-Za-z]:[/\\\\])[^ \"'<>()]*$2\\.lead" | head -n 1)"
  [ -n "$p" ] && command -v cygpath >/dev/null 2>&1 && p="$(cygpath -u "$p")"
  [ -n "$p" ] && [ -d "$p" ] && [ "$(cd "$p" && pwd -P)" = "$(cd "$nwt/$2.lead" 2>/dev/null && pwd -P)" ] ||
    { echo "FAIL: the notes line does not give $nwt/$2.lead by absolute path: $l"; fail=1; }
}
: > "$STUB_LOG"
check 0 "start: a lead, dry run - the notes folder" -- start "${L[@]}" --name "#310 lead: Notes" --branch 310-dry --brief-file "$tmp/brief.md" --dry-run
printf '%s\n' "$LAST" | grep -F '[dry-run]' | grep -qF "310-dry.lead" ||
  { echo "FAIL: a lead's dry run does not say it would create 310-dry.lead"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }
[ -e "$nwt/310-dry.lead" ] && { echo "FAIL: a lead's dry run created the notes folder"; fail=1; }
[ -e "$nwt/310-dry" ] && { echo "FAIL: a lead's dry run created the worktree"; fail=1; }
[ -s "$STUB_LOG" ] && { echo "FAIL: a lead's dry run called claude"; fail=1; }
rm -f "$STUB_LOG.arg"
check 0 "start: a lead - the notes folder beside the worktree" -- start "${L[@]}" --name "#310 lead: Notes" --branch 310-lead --brief-file "$tmp/brief.md"
[ -d "$nwt/310-lead.lead" ] || { echo "FAIL: no notes folder $nwt/310-lead.lead after a lead's start"; fail=1; }
[ -e "$nwt/310-lead/.lead" ] && { echo "FAIL: the notes folder was made inside the worktree"; fail=1; }
names_notes "$(cat "$STUB_LOG.arg" 2>/dev/null)" 310-lead
# an existing notes folder is kept: a file in it survives the start
mkdir -p "$nwt/311-lead.lead" && echo kept > "$nwt/311-lead.lead/sub-1.md"
rm -f "$STUB_LOG.arg"
check 0 "start: a lead, the notes folder there already" -- start "${L[@]}" --name "#311 lead: Notes" --branch 311-lead --brief-file "$tmp/brief.md"
[ "$(cat "$nwt/311-lead.lead/sub-1.md" 2>/dev/null)" = kept ] || { echo "FAIL: the existing notes folder's file did not survive the start"; fail=1; }
names_notes "$(cat "$STUB_LOG.arg" 2>/dev/null)" 311-lead
# a big brief: the launch file names the notes folder
rm -f "$STUB_LOG.arg"
check 0 "start: a lead, a big brief - the notes folder in the launch file" -- start "${L[@]}" --name "#312 lead: Notes" --branch 312-lead --brief-file "$tmp/brief-big.md"
[ -d "$nwt/312-lead.lead" ] || { echo "FAIL: no notes folder $nwt/312-lead.lead after a lead's start with a big brief"; fail=1; }
if f310="$(argfile "$(cat "$STUB_LOG.arg" 2>/dev/null)")"; then names_notes "$(cat "$f310" 2>/dev/null)" 312-lead
else echo "FAIL: a lead's big brief went through no launch file"; fail=1; fi
# a worker, a tester and a session with no role: no notes folder, none named
for v in "#313 worker: N|313-w" "#313 tester: N|313-t" "Plain session|313-n"; do
  vn="${v%%|*}" vb="${v#*|}"; rm -f "$STUB_LOG.arg"
  check 0 "start: $vn - no notes folder" -- start "${L[@]}" --name "$vn" --branch "$vb" --brief-file "$tmp/brief.md"
  [ -e "$nwt/$vb.lead" ] && { echo "FAIL ($vn): a notes folder $vb.lead was made"; fail=1; }
  grep -qF "$vb.lead" "$STUB_LOG.arg" 2>/dev/null && { echo "FAIL ($vn): the launch text names a notes folder"; fail=1; }
done
for b in 310-lead 311-lead 312-lead 313-w 313-t 313-n; do git -C "$tmp/repo" worktree remove --force "$nwt/$b" 2>/dev/null; done
# a lead's notes path that is another git worktree (a branch <x>.lead checked out there) is never used:
# start-worker refuses (exit 1) before anything is created, naming the conflict (#310, round 2)
git -C "$tmp/repo" worktree add -q -b 314-lead.lead "$nwt/314-lead.lead" main && echo precious > "$nwt/314-lead.lead/uncommitted.txt"
: > "$STUB_LOG"
check 1 "start: a lead whose notes path is another worktree - refused" -- start "${L[@]}" --name "#314 lead: Notes" --branch 314-lead --brief-file "$tmp/brief.md"
printf '%s\n' "$LAST" | grep -qF "314-lead.lead" || { echo "FAIL: the refusal does not name the notes path 314-lead.lead"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }
[ -e "$nwt/314-lead" ] && { echo "FAIL: a refused lead's start created the worktree"; fail=1; }
git -C "$tmp/repo" show-ref -q --verify refs/heads/314-lead && { echo "FAIL: a refused lead's start created the branch"; fail=1; }
[ -s "$STUB_LOG" ] && { echo "FAIL: a refused lead's start called claude"; fail=1; }
[ "$(cat "$nwt/314-lead.lead/uncommitted.txt" 2>/dev/null)" = precious ] || { echo "FAIL: the other worktree's file did not survive"; fail=1; }
git -C "$tmp/repo" worktree remove --force "$nwt/314-lead" 2>/dev/null; git -C "$tmp/repo" worktree remove --force "$nwt/314-lead.lead" 2>/dev/null
# the lead's first line - work only inside the worktree - names the notes folder as the exception, on
# that line or the one right after it, in both launch shapes; a worker's and a tester's first two lines
# stay as they were and name no notes folder
first2() { printf '%s\n' "$(cat "$STUB_LOG.arg" 2>/dev/null)" | tr -d '\r' | sed -n '1,2p'; }
rm -f "$STUB_LOG.arg"
check 0 "start: a lead - the first line names the notes folder" -- start "${L[@]}" --name "#315 lead: Notes" --branch 315-lead --brief-file "$tmp/brief.md"
first2 | grep -qF "315-lead.lead" ||
  { echo "FAIL: the lead's first-action line and the line after it do not name the notes folder 315-lead.lead"; first2 | sed 's/^/    /'; fail=1; }
rm -f "$STUB_LOG.arg"
check 0 "start: a lead launched from another folder - the first line names the notes folder" -- start "${L[@]}" --name "#316 lead: Notes" --branch 316-lead --brief-file "$tmp/brief.md" --launch-from "$tmp/launch"
first2 | grep -qF "316-lead.lead" ||
  { echo "FAIL: the lead's working-copy line and the line after it do not name the notes folder 316-lead.lead"; first2 | sed 's/^/    /'; fail=1; }
for v in "#317 worker: N|317-w" "#317 tester: N|317-t"; do
  vn="${v%%|*}" vb="${v#*|}"; rm -f "$STUB_LOG.arg"
  check 0 "start: $vn - the first two lines as before" -- start "${L[@]}" --name "$vn" --branch "$vb" --brief-file "$tmp/brief.md"
  first2 | sed -n 1p | grep -qxE "FIRST ACTION, before anything else: use the EnterWorktree tool with path = .*/$vb\. Work only inside it; never change files outside it\." &&
    first2 | sed -n 2p | grep -qxF 'Report to: the session named "Core lead" (SendMessage) - your report and your questions.' ||
    { echo "FAIL ($vn): the first two lines changed"; first2 | sed 's/^/    /'; fail=1; }
done
for b in 315-lead 316-lead 317-w 317-t; do git -C "$tmp/repo" worktree remove --force "$nwt/$b" 2>/dev/null; done

# --- an assistant (#281): --name "assistant: <name>" (letters, digits, . _ -) and --brief-file
# <repo>/coordinator/assistants/<name>/BRIEF.md start a background session with no worktree and no branch, from the
# --repo root, --settings the --safety file, whose env COORD_ASSISTANT_DIR names that folder. Access points: the
# settings fixture is $tmp/safety.json with the line `"COORD_ASSISTANT_DIR": "<folder>"` added to its env (the
# folder in the C:/... form on Windows, as a settings file holds it); the stub claude lists every name it started
# (`claude agents --json`, with --all too) and a session of $STUB_LOG.sessions (`<id> <sessionId> <state> <name>`).
# A refusal is exit 1 before anything is created, and its line names what it refuses: the name, BRIEF.md or the
# assistants/ folder, COORD_ASSISTANT_DIR and both folders, the flag (any spelling) with the word assistant, the
# existing session's name and id. The launch text's lines before its first blank line (the first one naming the
# folder, `<folder>/`) say BRIEF.md, NOTES.md, compaction, restart, SendMessage and the --report-to session ---
ar="$tmp/arepo"; mar="$mtmp/arepo"
git init -q -b main "$ar" && g -C "$ar" commit -q --allow-empty -m init
mkas() {   # mkas <name> [<env folder>]: <repo>/coordinator/assistants/<name> with BRIEF.md and NOTES.md (as the
  # coordinator's skill writes them) in $ad; a settings file whose COORD_ASSISTANT_DIR names <env folder> (default
  # that folder) in $asf
  ad="$ar/coordinator/assistants/$1"; mkdir -p "$ad"
  printf 'Log the hours (the fixture brief of %s).\n' "$1" > "$ad/BRIEF.md"; printf '# Notes\n' > "$ad/NOTES.md"
  asf="$tmp/as-$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '_').json"
  awk -v d="${2-$mar/coordinator/assistants/$1}" '/"COORD_PROTECTED_ROOT"/ { print "    \"COORD_ASSISTANT_DIR\": \"" d "\"," } { print }' "$tmp/safety.json" > "$asf"
  grep -q '"COORD_ASSISTANT_DIR"' "$asf" || { echo "FAIL: could not write the assistant settings $asf"; fail=1; }
}
asnothing() {   # asnothing <what>: no session started, no worktree, no branch but main, nothing added to the folder $ad
  grep -q -- '--bg' "$STUB_LOG" && { echo "FAIL ($1): claude was started"; fail=1; }
  [ -e "$ar/.claude/worktrees" ] && { echo "FAIL ($1): a worktree folder was created"; fail=1; }
  [ "$(git -C "$ar" for-each-ref --format='%(refname)' refs/heads)" = refs/heads/main ] || { echo "FAIL ($1): a branch was created"; fail=1; }
  [ "$(ls -A "$ad" | tr '\n' ' ')" = "BRIEF.md NOTES.md " ] || { echo "FAIL ($1): the folder $ad changed:"; ls -A "$ad" | sed 's/^/    /'; fail=1; }
}
says() {   # says <what> <text>...: one output line holds every text (\ read as /)
  local w="$1" l; shift; l="$(printf '%s\n' "$LAST" | tr -d '\r' | tr '\\' '/')"
  while [ $# -gt 0 ]; do l="$(printf '%s\n' "$l" | grep -F -- "$1")"; shift; done
  [ -n "$l" ] || { echo "FAIL ($w): no output line names all it should"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }
}
A=(--repo "$ar" --model sonnet --report-to "Core lead")
mkas timesheet; tsd="$ad"; tsf="$asf"
exb="$(cksum < "$ar/.git/info/exclude" 2>/dev/null)"; bdb="$(ls "$tmp/cfg/coordinator/briefs" 2>/dev/null)"
: > "$STUB_LOG"
check 0 "start: an assistant, dry run" -- start "${A[@]}" --name "assistant: timesheet" --brief-file "$tsd/BRIEF.md" --safety "$tsf" --dry-run
expect_in "[dry-run]"; expect_in "assistant: timesheet"
asnothing "an assistant, dry run"
[ -e "$ar/.claude" ] && { echo "FAIL (an assistant, dry run): $ar/.claude was created"; fail=1; }
[ "$(cksum < "$ar/.git/info/exclude" 2>/dev/null)" = "$exb" ] || { echo "FAIL (an assistant, dry run): info/exclude changed"; fail=1; }
[ "$(ls "$tmp/cfg/coordinator/briefs" 2>/dev/null)" = "$bdb" ] || { echo "FAIL (an assistant, dry run): a brief file was written"; fail=1; }
: > "$STUB_LOG"; rm -f "$STUB_LOG.arg"
check 0 "start: an assistant" -- start "${A[@]}" --name "assistant: timesheet" --brief-file "$tsd/BRIEF.md" --safety "$tsf"
grep -qF -- "--bg --name assistant: timesheet --model sonnet --permission-mode auto --settings " "$STUB_LOG" &&
  grep -F -- "--bg --name assistant: timesheet" "$STUB_LOG" | grep -qF "as-timesheet.json" ||
  { echo "FAIL (an assistant): claude got unexpected arguments:"; sed 's/^/    /' "$STUB_LOG"; fail=1; }
grep -qx "cwd $(cd "$ar" && pwd -P)" "$STUB_LOG" || { echo "FAIL (an assistant): not launched from the repository root:"; sed 's/^/    /' "$STUB_LOG"; fail=1; }
[ -e "$ar/.claude/worktrees" ] && { echo "FAIL (an assistant): a worktree folder was created"; fail=1; }
[ "$(git -C "$ar" for-each-ref --format='%(refname)' refs/heads)" = refs/heads/main ] || { echo "FAIL (an assistant): a branch was created"; fail=1; }
[ "$(ls -A "$tsd" | tr '\n' ' ')" = "BRIEF.md NOTES.md " ] || { echo "FAIL (an assistant): start-worker wrote into the folder"; fail=1; }
ahead="$(tr -d '\r' < "$STUB_LOG.arg" 2>/dev/null | tr '\\' '/' | awk '!length { exit } { print }')"
case "$(printf '%s\n' "$ahead" | sed -n 1p)" in *"$(basename "$tmp")/arepo/coordinator/assistants/timesheet/"*) ;;
  *) echo "FAIL (an assistant): the launch text's first line does not name the folder .../coordinator/assistants/timesheet/"; printf '%s\n' "$ahead" | sed 's/^/    /'; fail=1 ;; esac
for x in BRIEF.md NOTES.md SendMessage '"Core lead"' compact restart; do
  printf '%s\n' "$ahead" | grep -qiF -- "$x" || { echo "FAIL (an assistant): the launch text's first lines do not say $x"; printf '%s\n' "$ahead" | sed 's/^/    /'; fail=1; }
done
grep -q EnterWorktree "$STUB_LOG.arg" 2>/dev/null && { echo "FAIL (an assistant): the launch text sends it into a worktree"; fail=1; }
grep -qF 'Log the hours (the fixture brief of timesheet).' "$STUB_LOG.arg" 2>/dev/null || { echo "FAIL (an assistant): the brief is not in the launch text"; fail=1; }
expect_in 'claude attach "assistant: timesheet"'
expect_in 'subscribe: SendMessage(to: "assistant: timesheet", notify_when_idle: true)'
# its session exists now (listed): a second start of that name is refused
: > "$STUB_LOG"
check 1 "start: an assistant whose session exists" -- start "${A[@]}" --name "assistant: timesheet" --brief-file "$tsd/BRIEF.md" --safety "$tsf"
says "an assistant whose session exists" "assistant: timesheet"; ad="$tsd"; asnothing "an assistant whose session exists"
# a stopped (done) session of that name, listed by --all only: refused, the line naming it and its id
mkas jira
printf '%s %s %s %s\n' ab12cd34 ab12cd34-1111-4222-8333-444455556666 done "assistant: jira" > "$STUB_LOG.sessions"
: > "$STUB_LOG"
check 1 "start: an assistant whose stopped session is listed" -- start "${A[@]}" --name "assistant: jira" --brief-file "$ad/BRIEF.md" --safety "$asf"
says "an assistant whose stopped session is listed" "assistant: jira" ab12cd34; asnothing "an assistant whose stopped session is listed"
: > "$STUB_LOG.sessions"
# roles/assistant.md heads the brief when the core has it (a copy of the core with a fixture role), by the role
# mechanism; without it the brief goes alone
acore="$mtmp/acore"; ncore="$mtmp/ncore"
mkdir -p "$acore" "$ncore" && cp -R "$core/scripts" "$core/roles" "$acore/" && cp -R "$core/scripts" "$core/roles" "$ncore/"
rm -f "$ncore/roles/assistant.md"
printf -- '---\nname: assistant\n---\nYou are an assistant (the fixture role of tests/workers).\n' > "$acore/roles/assistant.md"
mkas r1; : > "$STUB_LOG"; rm -f "$STUB_LOG.arg"
core="$acore" check 0 "start: an assistant, roles/assistant.md there" -- start "${A[@]}" --name "assistant: r1" --brief-file "$ad/BRIEF.md" --safety "$asf"
expect_in "role assistant: roles/assistant.md heads the brief"
tr -d '\r' < "$STUB_LOG.arg" 2>/dev/null | awk '/^You are an assistant \(the fixture role/ { r = NR } /^Log the hours \(the fixture brief of r1\)/ { b = NR } END { exit !(r && b && r < b) }' ||
  { echo "FAIL (an assistant, roles/assistant.md there): the role does not head the brief"; fail=1; }
mkas r2; : > "$STUB_LOG"; rm -f "$STUB_LOG.arg"
core="$ncore" check 0 "start: an assistant, no roles/assistant.md" -- start "${A[@]}" --name "assistant: r2" --brief-file "$ad/BRIEF.md" --safety "$asf"
case "$LAST" in *"role assistant"*) echo "FAIL (an assistant, no roles/assistant.md): a role line"; fail=1 ;; esac
grep -qF 'Log the hours (the fixture brief of r2).' "$STUB_LOG.arg" 2>/dev/null || { echo "FAIL (an assistant, no roles/assistant.md): the brief is not in the launch text"; fail=1; }
# names outside letters, digits, . _ - are refused, the line naming the name (its folder and settings there)
for nm in "time sheet" "x!" "a/b"; do
  mkas "$nm"; : > "$STUB_LOG"
  check 1 "start: an assistant named '$nm'" -- start "${A[@]}" --name "assistant: $nm" --brief-file "$ad/BRIEF.md" --safety "$asf"
  says "an assistant named '$nm'" "$nm"; asnothing "an assistant named '$nm'"
done
mkas ""; : > "$STUB_LOG"
check 1 "start: an assistant with an empty name" -- start "${A[@]}" --name "assistant: " --brief-file "$ad/BRIEF.md" --safety "$asf"
grep -q -- '--bg' "$STUB_LOG" && { echo "FAIL (an assistant with an empty name): claude was started"; fail=1; }
rm -f "$ad/BRIEF.md" "$ad/NOTES.md"
# the brief: another file name, a folder outside assistants/, another assistant's folder
ad="$tsd"; : > "$STUB_LOG"
check 1 "start: an assistant, --brief-file NOTES.md" -- start "${A[@]}" --name "assistant: timesheet" --brief-file "$tsd/NOTES.md" --safety "$tsf"
says "an assistant, --brief-file NOTES.md" BRIEF.md; asnothing "an assistant, --brief-file NOTES.md"
mkdir -p "$tmp/elsewhere-as/timesheet" && printf 'Log the hours.\n' > "$tmp/elsewhere-as/timesheet/BRIEF.md"
mkas ts-env "$mtmp/elsewhere-as/timesheet"; ad="$tsd"; : > "$STUB_LOG"
check 1 "start: an assistant, its brief outside assistants/" -- start "${A[@]}" --name "assistant: timesheet" --brief-file "$tmp/elsewhere-as/timesheet/BRIEF.md" --safety "$asf"
says "an assistant, its brief outside assistants/" assistants; asnothing "an assistant, its brief outside assistants/"
mkas other; od="$ad"; ofs="$asf"; ad="$tsd"; : > "$STUB_LOG"
check 1 "start: an assistant, another assistant's folder" -- start "${A[@]}" --name "assistant: timesheet" --brief-file "$od/BRIEF.md" --safety "$ofs"
says "an assistant, another assistant's folder" assistants; asnothing "an assistant, another assistant's folder"
# COORD_ASSISTANT_DIR missing, or naming another folder: refused, naming both
: > "$STUB_LOG"
check 1 "start: an assistant, no COORD_ASSISTANT_DIR" -- start "${A[@]}" --name "assistant: timesheet" --brief-file "$tsd/BRIEF.md" --safety "$tmp/safety.json"
says "an assistant, no COORD_ASSISTANT_DIR" COORD_ASSISTANT_DIR assistants/timesheet; asnothing "an assistant, no COORD_ASSISTANT_DIR"
: > "$STUB_LOG"
check 1 "start: an assistant, COORD_ASSISTANT_DIR another folder" -- start "${A[@]}" --name "assistant: timesheet" --brief-file "$tsd/BRIEF.md" --safety "$ofs"
says "an assistant, COORD_ASSISTANT_DIR another folder" COORD_ASSISTANT_DIR assistants/other; says "an assistant, COORD_ASSISTANT_DIR another folder" assistants/timesheet
asnothing "an assistant, COORD_ASSISTANT_DIR another folder"
# the same folder in another letter case is that folder where letter case in paths is ignored (Windows)
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*)
  mkas lc "$(printf '%s' "$mar/coordinator/assistants/lc" | tr '[:lower:]' '[:upper:]')"; : > "$STUB_LOG"
  check 0 "start: an assistant, COORD_ASSISTANT_DIR in another letter case" -- start "${A[@]}" --name "assistant: lc" --brief-file "$ad/BRIEF.md" --safety "$asf" --dry-run
  asnothing "an assistant, COORD_ASSISTANT_DIR in another letter case" ;;
esac
# a worker's flags with an assistant are refused, the line naming the flag and the assistant
ad="$tsd"; ash="$(git -C "$ar" rev-parse HEAD)"; mkdir -p "$tmp/as-tt"
for v in "branch|--branch|70-as" "base|--base|main" "worktreeroot|--worktree-root|$tmp/as-wt" "contract|--contract|$tmp/c331.md" \
  "testercommit|--tester-commit|$ash" "testertests|--tester-tests|$tmp/as-tt"; do
  vk="${v%%|*}"; vr="${v#*|}"; vf="${vr%%|*}"; vv="${vr#*|}"
  : > "$STUB_LOG"
  check 1 "start: an assistant given $vf" -- start "${A[@]}" --name "assistant: timesheet" --brief-file "$tsd/BRIEF.md" --safety "$tsf" "$vf" "$vv"
  printf '%s\n' "$LAST" | tr 'A-Z' 'a-z' | tr -d '-' | grep -F "$vk" | grep -q assistant ||
    { echo "FAIL (an assistant given $vf): no line names the flag and the assistant"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }
  asnothing "an assistant given $vf"
  [ -e "$tmp/as-wt" ] && { echo "FAIL (an assistant given $vf): a worktree root was created"; fail=1; }
done
# --model, --safety and --report-to are required as for the other roles
for v in "--model|sonnet" "--safety|$tsf" "--report-to|Core lead"; do
  vf="${v%%|*}"; R=(--repo "$ar" --name "assistant: timesheet" --brief-file "$tsd/BRIEF.md" --model sonnet --safety "$tsf" --report-to "Core lead")
  a=(); i=0; while [ $i -lt ${#R[@]} ]; do [ "${R[$i]}" = "$vf" ] || a+=("${R[$i]}" "${R[$((i + 1))]}"); i=$((i + 2)); done
  : > "$STUB_LOG"
  check 1 "start: an assistant without $vf" -- start "${a[@]}"
  asnothing "an assistant without $vf"
done

# --- cleanup-worker ---
wt="$tmp/repo/.claude/worktrees/12-fix"
check 3 "cleanup: mistyped worktree path" -- cleanup --worktree "$tmp/repo/.claude/worktrees/12-fxi" --session s1
expect_in "NO WORKTREE"
check 3 "cleanup: the main checkout" -- cleanup --worktree "$tmp/repo"
# a commit of its own: never pushed is refused (an empty never-pushed branch is removed, #257, below)
g -C "$wt" commit -q --allow-empty -m first
check 3 "cleanup: never pushed" -- cleanup --worktree "$wt"
expect_in "NO UPSTREAM"
g -C "$wt" commit -q --allow-empty -m work && git -C "$wt" push -q -u origin 12-fix 2>/dev/null
head="$(git -C "$wt" rev-parse HEAD)"
echo dirt > "$wt/dirt.txt"
check 3 "cleanup: uncommitted changes" -- cleanup --worktree "$wt"
expect_in "NOT CLEAN"
mv "$wt/dirt.txt" "$tmp/dirt.txt"
STUB_GH_RC=1 check 3 "cleanup: gh fails" -- cleanup --worktree "$wt"
expect_in "UNKNOWN"
STUB_HEADS="" check 3 "cleanup: no merged PR" -- cleanup --worktree "$wt"
expect_in "NOT MERGED"
STUB_HEADS="0123456789012345678901234567890123456789" check 3 "cleanup: merged PR of an older use of the branch name" -- cleanup --worktree "$wt"
expect_in "branch name reused"
: > "$STUB_LOG"
# --session followed by a flag: a usage error, not a session called --dry-run and a real cleanup
STUB_HEADS="$head" check 1 "cleanup: --session followed by a flag" -- cleanup --worktree "$wt" --session --dry-run
expect_in "got the flag --dry-run"
[ -d "$wt" ] || { echo "FAIL: --session --dry-run removed the worktree"; fail=1; }
[ -s "$STUB_LOG" ] && { echo "FAIL: --session --dry-run called claude"; fail=1; }
STUB_HEADS="$head" check 0 "cleanup: dry run" -- cleanup --worktree "$wt" --session s1 --dry-run
expect_in "[dry-run]"
[ -d "$wt" ] || { echo "FAIL: the dry run removed the worktree"; fail=1; }
# it reads the listing (the session's folder, CORE §1.17), and stops or removes nothing
grep -v -x 'agents --json --all' "$STUB_LOG" | grep -q . && { echo "FAIL: the dry run called claude beyond the listing:"; sed 's/^/    /' "$STUB_LOG"; fail=1; }
STUB_HEADS="$head" check 0 "cleanup: merged" -- cleanup --worktree "$wt" --session s1
expect_in "cleaned: s1"
[ -d "$wt" ] && { echo "FAIL: the worktree is still there"; fail=1; }
grep -qx "stop s1" "$STUB_LOG" && grep -qx "rm s1" "$STUB_LOG" || { echo "FAIL: the session was not stopped and removed"; fail=1; }
# a branch pushed without -u (no upstream configured): origin/<branch> counts as its remote branch
wt2="$tmp/repo/.claude/worktrees/13-fix"
git -C "$tmp/repo" worktree add -q -b 13-fix "$wt2" main && g -C "$wt2" commit -q --allow-empty -m work2
check 3 "cleanup: not on the remote at all" -- cleanup --worktree "$wt2"
expect_in "NO UPSTREAM"
git -C "$wt2" push -q origin 13-fix 2>/dev/null
STUB_HEADS="$(git -C "$wt2" rev-parse HEAD)" check 0 "cleanup: pushed without -u" -- cleanup --worktree "$wt2" --session s2
expect_in "cleaned: s2"
# the server added a commit on top of the pushed head (gh pr update-branch) and the branch was deleted
# after the merge: the local origin/<branch> stays at the pushed head, the merged PR's head is newer
wt3="$tmp/repo/.claude/worktrees/15-fix"
git -C "$tmp/repo" worktree add -q -b 15-fix "$wt3" main && g -C "$wt3" commit -q --allow-empty -m work3
git -C "$wt3" push -q -u origin 15-fix 2>/dev/null
git clone -q "$tmp/remote.git" "$tmp/server" 2>/dev/null && git -C "$tmp/server" checkout -q 15-fix &&
  g -C "$tmp/server" commit -q --allow-empty -m "merge main into 15-fix" && git -C "$tmp/server" push -q origin 15-fix 2>/dev/null
prhead="$(git -C "$tmp/server" rev-parse HEAD)"
git -C "$tmp/server" push -q origin --delete 15-fix 2>/dev/null
git -C "$tmp/remote.git" config uploadpack.allowAnySHA1InWant true
STUB_HEADS="$prhead" check 0 "cleanup: a server-side commit on the merged PR's head" -- cleanup --worktree "$wt3" --session s3
expect_in "cleaned: s3"
expect_in "server-side commit"

# fetch.prune: the merged branch's remote branch was deleted and the script's own fetch prunes
# origin/<branch> - the merged PR's head still shows every commit is on the remote
wt4="$tmp/repo/.claude/worktrees/16-fix"
git -C "$tmp/repo" worktree add -q -b 16-fix "$wt4" main && g -C "$wt4" commit -q --allow-empty -m work4
git -C "$wt4" push -q -u origin 16-fix 2>/dev/null
h4="$(git -C "$wt4" rev-parse HEAD)"
git -C "$wt4" push -q origin --delete 16-fix 2>/dev/null
git -C "$tmp/repo" config fetch.prune true
STUB_HEADS="$h4" check 0 "cleanup: the remote branch pruned after the merge" -- cleanup --worktree "$wt4" --session s4
expect_in "cleaned: s4"
expect_in "remote branch is gone"
git -C "$tmp/repo" config --unset fetch.prune

# --- the session's two ids (#151): stop / rm take the short job id, a full sessionId is mapped to it
# through claude agents --json --all; a session still listed after rm is reported, never `cleaned` ---
mk() {   # mk <branch>: a worktree with one commit, pushed with -u; its path in $w, its head in $h
  w="$tmp/repo/.claude/worktrees/$1"
  git -C "$tmp/repo" worktree add -q -b "$1" "$w" main && g -C "$w" commit -q --allow-empty -m "$1" &&
    git -C "$w" push -q -u origin "$1" 2>/dev/null
  h="$(git -C "$w" rev-parse HEAD)"
}
SS="$STUB_LOG.sessions"
mk 17-fix
# the listing gives the job id (here not the sessionId's first 8 characters, so the mapping is proven)
sid=5f0e1d2c-1111-4222-8333-444455556666
printf '%s %s %s %s\n' a1b2c3d4 "$sid" running "#17 worker: Fix" > "$SS"
: > "$STUB_LOG"
STUB_HEADS="$h" check 0 "cleanup: a full sessionId, dry run" -- cleanup --worktree "$w" --session "$sid" --dry-run
expect_in "[dry-run] claude rm a1b2c3d4"
grep -q -e '^stop' -e '^rm' "$STUB_LOG" && { echo "FAIL: the dry run stopped or removed a session"; fail=1; }
STUB_HEADS="$h" check 0 "cleanup: a full sessionId mapped to its job id" -- cleanup --worktree "$w" --session "$sid"
expect_in "session $sid: job id a1b2c3d4"
expect_in "cleaned: a1b2c3d4"
grep -qx "stop a1b2c3d4" "$STUB_LOG" && grep -qx "rm a1b2c3d4" "$STUB_LOG" || { echo "FAIL: the job id was not stopped and removed:"; sed 's/^/    /' "$STUB_LOG"; fail=1; }
grep -q a1b2c3d4 "$SS" && { echo "FAIL: the session is still listed"; fail=1; }
[ -d "$w" ] && { echo "FAIL: the worktree is still there"; fail=1; }
# a full sessionId the listing does not have: its first 8 characters
mk 18-fix
STUB_HEADS="$h" check 0 "cleanup: an unlisted full sessionId, dry run" -- cleanup --worktree "$w" --session 9abcdef0-1111-4222-8333-444455556666 --dry-run
expect_in "[dry-run] claude rm 9abcdef0"
# claude rm fails and the session stays listed (stopped already, so the stop fails too): SESSION KEPT,
# exit 4, the worktree and branch left as is; after the session is gone, the same command cleans
printf '%s %s %s %s\n' 2be9934b 2be9934b-aaaa-4bbb-8ccc-dddddddddddd done "#18 worker: Fix" > "$SS"
STUB_RM_FAIL="Error: cannot remove 2be9934b" STUB_HEADS="$h" check 4 "cleanup: claude rm fails" -- cleanup --worktree "$w" --session 2be9934b-aaaa-4bbb-8ccc-dddddddddddd
expect_in "SESSION KEPT: 2be9934b (claude rm failed: Error: cannot remove 2be9934b)"
case "$LAST" in *cleaned*) echo "FAIL: cleaned although the session is still listed"; fail=1 ;; esac
[ -d "$w" ] && git -C "$tmp/repo" show-ref -q --verify refs/heads/18-fix || { echo "FAIL: the worktree or branch was removed although the session is kept"; fail=1; }
grep -q 2be9934b "$SS" || { echo "FAIL: the stub lost the session"; fail=1; }
STUB_HEADS="$h" check 0 "cleanup: run again once rm works" -- cleanup --worktree "$w" --session 2be9934b
expect_in "cleaned: 2be9934b"
[ -s "$SS" ] && { echo "FAIL: the session is still listed"; fail=1; }

# --- own sessions only (CORE §1.17): a session the listing gives a working folder outside the project
# (the repository's main checkout, its .claude/worktrees, the worktree) is never stopped or removed:
# SESSION FOREIGN, exit 5, the worktree and branch kept. The folders as the real listing gives them: as
# they lie on disk, on Windows in the C:\... form ---
native() { (cd -P -- "$1" && case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) pwd -W | tr '/' '\\' ;; *) pwd -P ;; esac); }
mkdir -p "$tmp/other" "$tmp/repo-old"
rp="$(native "$tmp/repo")"
mk 19-fix
printf '%s %s %s %s\n' c0ffee01 c0ffee01-1111-4222-8333-444455556666 running "#19 worker: Fix" > "$SS"
printf 'c0ffee01\t%s\n' "$(native "$w")" > "$SS.cwd"
STUB_HEADS="$h" check 0 "cleanup: a session in the worktree" -- cleanup --worktree "$w" --session c0ffee01
expect_in "cleaned: c0ffee01"
mk 20-fix
for f in other repo-old; do
  : > "$STUB_LOG"
  printf '%s %s %s %s\n' f0e1d2c3 f0e1d2c3-1111-4222-8333-444455556666 running "#20 worker: Fix" > "$SS"
  fw="$(native "$tmp/$f")"; printf 'f0e1d2c3\t%s\n' "$fw" > "$SS.cwd"
  STUB_HEADS="$h" check 5 "cleanup: a session in $f" -- cleanup --worktree "$w" --session f0e1d2c3
  expect_in "SESSION FOREIGN: f0e1d2c3 ($fw): not this project's session - nothing done"
  case "$LAST" in *cleaned*) echo "FAIL: cleaned a session of another folder"; fail=1 ;; esac
  grep -q -e '^stop' -e '^rm' "$STUB_LOG" && { echo "FAIL: a session of another folder was stopped or removed:"; sed 's/^/    /' "$STUB_LOG"; fail=1; }
  [ -d "$w" ] && git -C "$tmp/repo" show-ref -q --verify refs/heads/20-fix || { echo "FAIL: the worktree or branch was removed for a foreign session"; fail=1; }
  grep -q f0e1d2c3 "$SS" || { echo "FAIL: the stub lost the foreign session"; fail=1; }
done
# by its full sessionId, and in a dry run
STUB_HEADS="$h" check 5 "cleanup: a foreign session by its full sessionId" -- cleanup --worktree "$w" --session f0e1d2c3-1111-4222-8333-444455556666
expect_in "SESSION FOREIGN: f0e1d2c3 ("
STUB_HEADS="$h" check 5 "cleanup: a foreign session, dry run" -- cleanup --worktree "$w" --session f0e1d2c3 --dry-run
expect_in "SESSION FOREIGN: f0e1d2c3 ("
grep -q -e '^stop' -e '^rm' "$STUB_LOG" && { echo "FAIL: a session of another folder was stopped or removed"; fail=1; }
# launched from the repository's root (the usual case), its folder written with a trailing separator
sep=/; case "$rp" in *\\*) sep='\' ;; esac   # (no case inside $(...): bash 3.2 cannot parse it)
printf 'f0e1d2c3\t%s\n' "$rp$sep" > "$SS.cwd"
STUB_HEADS="$h" check 0 "cleanup: a session in the repository's root" -- cleanup --worktree "$w" --session f0e1d2c3
expect_in "cleaned: f0e1d2c3"
# the self-test's shape: a worktree under another folder's .claude/worktrees (a state repository's,
# started from the project root), the session in that folder - its folder is the project's
mkdir -p "$tmp/project2"
w="$tmp/project2/.claude/worktrees/22-fix"
git -C "$tmp/repo" worktree add -q -b 22-fix "$w" main && g -C "$w" commit -q --allow-empty -m 22-fix && git -C "$w" push -q -u origin 22-fix 2>/dev/null
h="$(git -C "$w" rev-parse HEAD)"
printf '%s %s %s %s\n' 5e1f7e57 5e1f7e57-1111-4222-8333-444455556666 running "#st1 worker: selftest" > "$SS"
printf '5e1f7e57\t%s\n' "$(native "$tmp/project2")" > "$SS.cwd"
STUB_HEADS="$h" check 0 "cleanup: the session in the folder that holds the worktree" -- cleanup --worktree "$w" --session 5e1f7e57
expect_in "cleaned: 5e1f7e57"
# the same root in another letter case is the root where letter case in paths is ignored (Windows, macOS)
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*|Darwin)
  mk 21-fix
  printf '%s %s %s %s\n' 0a0b0c0d 0a0b0c0d-1111-4222-8333-444455556666 running "#21 worker: Fix" > "$SS"
  printf '0a0b0c0d\t%s\n' "$(printf '%s' "$rp" | tr '[:lower:]' '[:upper:]')" > "$SS.cwd"
  STUB_HEADS="$h" check 0 "cleanup: the root in another letter case" -- cleanup --worktree "$w" --session 0a0b0c0d
  expect_in "cleaned: 0a0b0c0d" ;;
esac

# --- findings of a macOS review: an upper-case sessionId, a session folder through a symlink, a
# non-ASCII letter in another case, no claude on PATH ---
# a full sessionId typed in upper case is the listed session: here a foreign one, so nothing is removed
mk 23-fix
printf '%s %s %s %s\n' f0e1d2c3 f0e1d2c3-1111-4222-8333-444455556666 running "#23 worker: Fix" > "$SS"
printf 'f0e1d2c3\t%s\n' "$(native "$tmp/other")" > "$SS.cwd"
: > "$STUB_LOG"
STUB_HEADS="$h" check 5 "cleanup: a full sessionId in upper case" -- cleanup --worktree "$w" --session F0E1D2C3-1111-4222-8333-444455556666
expect_in "SESSION FOREIGN: f0e1d2c3 ("
[ -d "$w" ] || { echo "FAIL: an upper-case sessionId removed the worktree"; fail=1; }
grep -q -e '^stop' -e '^rm' "$STUB_LOG" && { echo "FAIL: an upper-case sessionId stopped or removed a session"; fail=1; }
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    # the listing gives the session's folder through a junction to the repository (C:\...): own
    MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' cmd /c mklink /J "$(cygpath -w "$tmp/repo-link")" "$(cygpath -w "$tmp/repo")" >/dev/null 2>&1
    printf 'f0e1d2c3\t%s\n' "$(cygpath -w "$tmp/repo-link")" > "$SS.cwd"
    STUB_HEADS="$h" check 0 "cleanup: the session's folder through a junction" -- cleanup --worktree "$w" --session f0e1d2c3 --dry-run
    expect_in "[dry-run] claude rm f0e1d2c3" ;;
  *)
    # the listing gives the session's folder through a symlink to the repository (macOS: /tmp is one): own
    ln -s "$tmp/repo" "$tmp/repo-link"
    printf 'f0e1d2c3\t%s\n' "$tmp/repo-link" > "$SS.cwd"
    STUB_HEADS="$h" check 0 "cleanup: the session's folder through a symlink" -- cleanup --worktree "$w" --session f0e1d2c3 --dry-run
    expect_in "[dry-run] claude rm f0e1d2c3" ;;
esac
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*|Darwin)
  # a non-ASCII letter in another case is the same folder on APFS and NTFS (in a UTF-8 locale, as a
  # session runs; Git Bash's tr folds ASCII only)
  git clone -q "$tmp/remote.git" "$tmp/Ü/proj" 2>/dev/null
  w="$tmp/Ü/proj/.claude/worktrees/24-fix"
  git -C "$tmp/Ü/proj" worktree add -q -b 24-fix "$w" origin/main && g -C "$w" commit -q --allow-empty -m 24-fix && git -C "$w" push -q -u origin 24-fix 2>/dev/null
  h="$(git -C "$w" rev-parse HEAD)"
  printf 'f0e1d2c3\t%s%sü%sproj\n' "$(native "$tmp")" "$sep" "$sep" > "$SS.cwd"
  LC_ALL=en_US.UTF-8 STUB_HEADS="$h" check 0 "cleanup: a non-ASCII letter in another case" -- cleanup --worktree "$w" --session f0e1d2c3 --dry-run
  expect_in "[dry-run] claude rm f0e1d2c3" ;;
esac
# no claude on PATH (only where the stub is the only claude): nothing can be removed - SESSION KEPT, exit 4
nocl="$tmp/nocl"; mkdir -p "$nocl"; cp "$tmp/bin/gh" "$tmp/bin/gh.ps1" "$nocl/"
p2="$(printf '%s' "$PATH" | tr ':' '\n' | grep -vxF "$tmp/bin" | paste -sd: -)"
if ! PATH="$nocl:$p2" command -v claude >/dev/null 2>&1; then
  mk 25-fix
  PATH="$nocl:$p2" STUB_HEADS="$h" check 4 "cleanup: no claude on PATH" -- cleanup --worktree "$w" --session 0d0d0d0d
  expect_in "SESSION KEPT: 0d0d0d0d (claude rm failed: claude: command not found)"
  [ -d "$w" ] || { echo "FAIL: no claude on PATH, the worktree was removed"; fail=1; }
fi

# --- a folder git could not delete (a just-stopped session still holding it, #238): git unregisters the
# worktree but the folder stays - removed when empty, left with an error when not
realgit="$(command -v git)"; gw="$tmp/gitwrap"; mkdir -p "$gw"
cat > "$gw/git" <<EOF
#!/usr/bin/env bash
if [ "\$3 \$4" = "worktree remove" ] && [ -f "$tmp/leave-folder" ]; then
  rm -f "$tmp/leave-folder"; "$realgit" "\$@"; mkdir -p "\$5"; [ -z "\${LEAVE_FILE:-}" ] || : > "\$5/held"; exit 1
fi
exec "$realgit" "\$@"
EOF
# (MSYS noglob: the bash started from PowerShell gets git's arguments as given - its own globbing would
# expand the braces of `<ref>^{commit}`)
printf '%s\n' '$env:MSYS = ("$env:MSYS noglob").Trim()' '& bash (Join-Path $PSScriptRoot "git") @args' 'exit $LASTEXITCODE' > "$gw/git.ps1"; chmod +x "$gw/git"
mk 26-fix; : > "$tmp/leave-folder"
PATH="$gw:$PATH" STUB_HEADS="$h" check 0 "cleanup: git leaves the folder empty - it is removed" -- cleanup --worktree "$w"
expect_in "removed the empty folder git left"
[ -d "$w" ] && { echo "FAIL: the empty folder git left was not removed"; fail=1; }
mk 27-fix; : > "$tmp/leave-folder"
PATH="$gw:$PATH" STUB_HEADS="$h" LEAVE_FILE=1 check 1 "cleanup: git leaves the folder with a file - kept, reported" -- cleanup --worktree "$w"
expect_in "is no longer a worktree but not empty - left as is"
[ -f "$w/held" ] || { echo "FAIL: a folder with a file in it was touched"; fail=1; }

# --- nothing to lose (#257): a branch with no commits beyond its base, never pushed, in a clean worktree
# is removed without a merged PR (gh is not needed: it fails here); a commit, a push, an upstream or a
# dirty worktree keeps today's checks and leaves everything as is ---
me() {   # me <branch> [<start>]: a worktree on a new branch with no commits of its own, not pushed
  w="$tmp/repo/.claude/worktrees/$1"
  git -C "$tmp/repo" worktree add -q --no-track -b "$1" "$w" "${2:-main}"
}
kept() {   # kept <branch> <what>: the worktree, the branch and the checkout are all still there
  [ -d "$w" ] && git -C "$tmp/repo" show-ref -q --verify "refs/heads/$1" &&
    [ "$(git -C "$w" symbolic-ref -q HEAD)" = "refs/heads/$1" ] || { echo "FAIL ($2): the worktree or branch $1 was touched"; fail=1; }
}
gone() {   # gone <branch> <what>: the worktree and the branch are removed
  [ -d "$w" ] && { echo "FAIL ($2): the worktree $w is still there"; fail=1; }
  git -C "$tmp/repo" show-ref -q --verify "refs/heads/$1" && { echo "FAIL ($2): the branch $1 is still there"; fail=1; }
}
me 30-empty
printf '%s %s %s %s\n' e3030303 e3030303-1111-4222-8333-444455556666 running "#30 worker: e" > "$SS"
printf 'e3030303\t%s\n' "$(native "$w")" > "$SS.cwd"
: > "$STUB_LOG"
STUB_GH_RC=1 check 0 "cleanup: an empty never-pushed branch, dry run" -- cleanup --worktree "$w" --session e3030303 --dry-run
expect_in "EMPTY: 30-empty has no commits beyond origin/main and was never pushed - would be removed"
expect_in "[dry-run] git -C"
kept 30-empty "empty branch, dry run"
grep -v -x 'agents --json --all' "$STUB_LOG" | grep -q . && { echo "FAIL: the empty-branch dry run called claude beyond the listing:"; sed 's/^/    /' "$STUB_LOG"; fail=1; }
STUB_GH_RC=1 check 0 "cleanup: an empty never-pushed branch" -- cleanup --worktree "$w" --session e3030303
expect_in "EMPTY: 30-empty has no commits beyond origin/main and was never pushed - removed"
expect_in "cleaned: e3030303"
gone 30-empty "empty branch"
grep -qx "stop e3030303" "$STUB_LOG" && grep -qx "rm e3030303" "$STUB_LOG" || { echo "FAIL: the empty branch's session was not stopped and removed"; fail=1; }
# one commit, never pushed: refused as before
me 31-empty; g -C "$w" commit -q --allow-empty -m one
STUB_GH_RC=1 check 3 "cleanup: one commit, never pushed" -- cleanup --worktree "$w"
expect_in "UNKNOWN"
check 3 "cleanup: one commit, never pushed (gh works)" -- cleanup --worktree "$w"
expect_in "NO UPSTREAM"
kept 31-empty "one commit"
# no commits but pushed with -u: the merged-PR checks as before
me 32-empty; git -C "$w" push -q -u origin 32-empty 2>/dev/null
check 3 "cleanup: an empty branch pushed with -u" -- cleanup --worktree "$w"
expect_in "NOT MERGED"
kept 32-empty "pushed with -u"
# its upstream configured but the remote branch and its local copy gone: still not "never pushed"
me 33-empty; git -C "$w" push -q -u origin 33-empty 2>/dev/null; git -C "$w" push -q origin --delete 33-empty 2>/dev/null
git -C "$tmp/repo" update-ref -d refs/remotes/origin/33-empty 2>/dev/null
check 3 "cleanup: an empty branch with an upstream configured" -- cleanup --worktree "$w"
expect_in "NO UPSTREAM"
kept 33-empty "upstream configured"
# pushed without -u and its origin/<branch> not fetched (a narrow fetch refspec): ls-remote finds it
me 34-empty; git -C "$w" push -q origin 34-empty 2>/dev/null
git -C "$tmp/repo" update-ref -d refs/remotes/origin/34-empty 2>/dev/null
git -C "$tmp/repo" config remote.origin.fetch '+refs/heads/main:refs/remotes/origin/main'
check 3 "cleanup: an empty branch on origin, not fetched" -- cleanup --worktree "$w"
expect_in "NO UPSTREAM"
git -C "$tmp/repo" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
kept 34-empty "on origin, not fetched"
# a dirty worktree (an untracked file): refused as before
me 35-empty; echo dirt > "$w/dirt.txt"
STUB_GH_RC=1 check 3 "cleanup: an empty branch, untracked file" -- cleanup --worktree "$w"
expect_in "NOT CLEAN"
kept 35-empty "untracked file"
rm -f "$w/dirt.txt"
# a session of another folder: SESSION FOREIGN as for a merged branch, nothing touched
me 36-empty; : > "$STUB_LOG"
printf '%s %s %s %s\n' f0e1d2c3 f0e1d2c3-1111-4222-8333-444455556666 running "#36 worker: e" > "$SS"
printf 'f0e1d2c3\t%s\n' "$(native "$tmp/other")" > "$SS.cwd"
check 5 "cleanup: an empty branch, a foreign session" -- cleanup --worktree "$w" --session f0e1d2c3
expect_in "SESSION FOREIGN: f0e1d2c3 ("
kept 36-empty "foreign session"
grep -q -e '^stop' -e '^rm' "$STUB_LOG" && { echo "FAIL: a foreign session of an empty branch was stopped or removed"; fail=1; }
# a commit made after the checks, as its session stops: decided again before anything is deleted -
# CHANGED, exit 3, the branch with the new commit and the worktree kept
me 40-empty
printf '%s %s %s %s\n' e4040404 e4040404-1111-4222-8333-444455556666 running "#40 worker: e" > "$SS"
printf 'e4040404\t%s\n' "$(native "$w")" > "$SS.cwd"
STUB_STOP_COMMIT="$w" STUB_GH_RC=1 check 3 "cleanup: an empty branch gets a commit as its session stops" -- cleanup --worktree "$w" --session e4040404
expect_in "CHANGED: "
expect_in " moved since the checks - left as is"
kept 40-empty "a commit as the session stops"
[ "$(git -C "$w" rev-list --count main..HEAD)" = 1 ] || { echo "FAIL: the commit made as the session stopped is gone"; fail=1; }
# the removal fails (a locked worktree, as a folder a just-stopped session holds): the branch is put
# back on the worktree at the same commit, and a run once the removal works removes it as EMPTY
me 41-empty; git -C "$tmp/repo" worktree lock "$w"
STUB_GH_RC=1 check 1 "cleanup: an empty branch, the removal fails" -- cleanup --worktree "$w"
expect_in "REMOVE FAILED: git worktree remove "
expect_in "; branch 41-empty put back at "
kept 41-empty "the removal fails"
git -C "$tmp/repo" worktree unlock "$w"
STUB_GH_RC=1 check 0 "cleanup: an empty branch, run again once the removal works" -- cleanup --worktree "$w"
expect_in "EMPTY: 41-empty has no commits beyond origin/main and was never pushed - removed"
gone 41-empty "run again once the removal works"
# git unregisters the worktree but leaves a file in the folder: the branch is put back in the repository
me 42-empty; : > "$tmp/leave-folder"
PATH="$gw:$PATH" STUB_GH_RC=1 LEAVE_FILE=1 check 1 "cleanup: an empty branch, git leaves the folder with a file" -- cleanup --worktree "$w"
expect_in "is no longer a worktree but not empty - left as is; branch 42-empty put back at "
git -C "$tmp/repo" show-ref -q --verify refs/heads/42-empty || { echo "FAIL: the branch was not put back after the failed removal"; fail=1; }
# pushed to another remote only (refs/remotes/backup/<branch>): not never pushed - the usual checks
git init -q --bare "$tmp/backup.git" && git -C "$tmp/repo" remote add backup "$tmp/backup.git"
me 43-empty; git -C "$w" push -q backup 43-empty 2>/dev/null
STUB_GH_RC=1 check 3 "cleanup: an empty branch pushed to another remote" -- cleanup --worktree "$w"
expect_in "UNKNOWN"
kept 43-empty "pushed to another remote"
git -C "$tmp/repo" remote remove backup
# the main checkout's HEAD behind the base (origin/main moved on, local main did not): the branch is
# still deleted with git branch -d (checked against its own commit, not the main checkout's HEAD)
git clone -q "$tmp/remote.git" "$tmp/server2" 2>/dev/null && g -C "$tmp/server2" commit -q --allow-empty -m "main moves on" &&
  git -C "$tmp/server2" push -q origin main 2>/dev/null
git -C "$tmp/repo" fetch -q
me 37-empty origin/main
STUB_GH_RC=1 check 0 "cleanup: an empty branch ahead of the main checkout's HEAD" -- cleanup --worktree "$w"
expect_in "EMPTY: 37-empty has no commits beyond origin/main and was never pushed - removed"
gone 37-empty "ahead of the main checkout's HEAD"
# no origin at all (a local-only repository): the base is the local main
git init -q -b main "$tmp/local" && g -C "$tmp/local" commit -q --allow-empty -m init
w="$tmp/local/.claude/worktrees/38-empty"; git -C "$tmp/local" worktree add -q -b 38-empty "$w" main
STUB_GH_RC=1 check 0 "cleanup: an empty branch, no origin" -- cleanup --worktree "$w"
expect_in "EMPTY: 38-empty has no commits beyond main and was never pushed - removed"
[ -d "$w" ] && { echo "FAIL (no origin): the worktree is still there"; fail=1; }
git -C "$tmp/local" show-ref -q --verify refs/heads/38-empty && { echo "FAIL (no origin): the branch is still there"; fail=1; }
w="$tmp/local/.claude/worktrees/39-empty"; git -C "$tmp/local" worktree add -q -b 39-empty "$w" main && g -C "$w" commit -q --allow-empty -m one
STUB_GH_RC=1 check 3 "cleanup: one commit, no origin" -- cleanup --worktree "$w"
[ -d "$w" ] && git -C "$tmp/local" show-ref -q --verify refs/heads/39-empty || { echo "FAIL (one commit, no origin): touched"; fail=1; }

# --- a lead's notes beside its worktree (#310): <worktree>.lead/ is removed with the worktree (one line
# says so, naming the folder), kept whenever the worktree is left (a dry run, NOT CLEAN, NOT MERGED,
# CHANGED, a failed removal); a worktree with no notes folder is cleaned as before ---
notes() { mkdir -p "$w.lead" && echo n > "$w.lead/run-notes.md"; }
nkept() { [ -f "$w.lead/run-notes.md" ] || { echo "FAIL ($1): the notes folder $w.lead was removed"; fail=1; }; }
ngone() {   # ngone <branch> <what>: the notes folder is gone and one output line names it as notes
  [ -e "$w.lead" ] && { echo "FAIL ($2): the notes folder $1.lead is still there"; fail=1; }
  printf '%s\n' "$LAST" | grep -i notes | grep -qF "$1.lead" ||
    { echo "FAIL ($2): no output line says the notes folder $1.lead was removed"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }
}
mk 50-lead; notes
STUB_HEADS="$h" check 0 "cleanup: merged, dry run - the notes folder kept" -- cleanup --worktree "$w" --dry-run
nkept "merged, dry run"
STUB_HEADS="$h" check 0 "cleanup: merged - the notes folder removed with the worktree" -- cleanup --worktree "$w"
ngone 50-lead "merged"
me 51-lead origin/main; notes
STUB_GH_RC=1 check 0 "cleanup: an empty never-pushed branch - the notes folder removed with the worktree" -- cleanup --worktree "$w"
ngone 51-lead "empty branch"
mk 52-lead; notes; echo dirt > "$w/dirt.txt"
STUB_HEADS="$h" check 3 "cleanup: NOT CLEAN - the notes folder kept" -- cleanup --worktree "$w"
expect_in "NOT CLEAN"; nkept "not clean"
rm -f "$w/dirt.txt"
mk 53-lead; notes
STUB_HEADS="" check 3 "cleanup: NOT MERGED - the notes folder kept" -- cleanup --worktree "$w"
expect_in "NOT MERGED"; nkept "not merged"
me 54-lead origin/main; notes
printf '%s %s %s %s\n' e5454545 e5454545-1111-4222-8333-444455556666 running "#54 lead: n" > "$SS"
printf 'e5454545\t%s\n' "$(native "$w")" > "$SS.cwd"
STUB_STOP_COMMIT="$w" STUB_GH_RC=1 check 3 "cleanup: CHANGED - the notes folder kept" -- cleanup --worktree "$w" --session e5454545
expect_in "CHANGED: "; nkept "changed"
mk 55-lead; notes; : > "$tmp/leave-folder"
PATH="$gw:$PATH" STUB_HEADS="$h" LEAVE_FILE=1 check 1 "cleanup: a failed removal - the notes folder kept" -- cleanup --worktree "$w"
expect_in "not empty - left as is"; nkept "failed removal"
mk 56-lead
STUB_HEADS="$h" check 0 "cleanup: merged, no notes folder - no error" -- cleanup --worktree "$w"
expect_in "cleaned: "
[ -d "$w" ] && { echo "FAIL (no notes folder): the worktree is still there"; fail=1; }
# a lead's notes path that is another git worktree (a branch <x>.lead checked out there) is never removed:
# its uncommitted file survives, it stays a listed, not prunable worktree, and one line names it as a
# git working copy that was left (#310, round 2); the exit code is the script's choice
nwtree() { git -C "$tmp/repo" worktree add -q -b "$1.lead" "$w.lead" main && echo precious > "$w.lead/uncommitted.txt"; }
nwkept() {   # nwkept <branch> <what>
  [ "$(cat "$w.lead/uncommitted.txt" 2>/dev/null)" = precious ] || { echo "FAIL ($2): the uncommitted file in $1.lead was removed"; fail=1; }
  git -C "$tmp/repo" worktree list --porcelain | tr -d '\r' |
    awk -v s="/$1.lead" 'BEGIN { RS = "" } { p = $2; if (substr(p, length(p) - length(s) + 1) == s) { f = 1; if ($0 ~ /prunable/) b = 1 } } END { exit !(f && !b) }' ||
    { echo "FAIL ($2): the worktree $1.lead is no longer a listed, not prunable worktree"; git -C "$tmp/repo" worktree list --porcelain | sed 's/^/    /'; fail=1; }
  printf '%s\n' "$LAST" | tr -d '\r' | grep -F "$1.lead" | sed 's#[^ ]*[/\\][^ ]*##g' | grep -qiE 'worktree|working copy' ||
    { echo "FAIL ($2): no output line says the notes path $1.lead is a git working copy and was left"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }
  git -C "$tmp/repo" worktree remove --force "$w.lead" 2>/dev/null
}
mk 57-lead; nwtree 57-lead; n=$((n + 1))
LAST="$(STUB_HEADS="$h" cleanup --worktree "$w" 2>&1)"
nwkept 57-lead "merged, the notes path a worktree"
me 58-lead origin/main; nwtree 58-lead; n=$((n + 1))
LAST="$(STUB_GH_RC=1 cleanup --worktree "$w" 2>&1)"
nwkept 58-lead "empty branch, the notes path a worktree"
# a worktree path given with a trailing backslash (Windows) - its notes folder goes with it, as in the .ps1
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*)
  mk 59-lead; notes
  STUB_HEADS="$h" check 0 "cleanup: merged, a trailing backslash - the notes folder removed" -- cleanup --worktree "$(native "$w")\\"
  ngone 59-lead "a trailing backslash" ;;
esac

# --- an assistant is never cleaned up (#281): --session naming a session the listing calls `assistant: <name>`
# (by its short id or full sessionId, running or stopped) changes nothing and exits 6 with one line
# `ASSISTANT KEPT: <name> (<id>) - an assistant is removed only on the owner's word`, before any stop, removal or
# worktree check; the header documents code 6. A name that only holds `assistant:` further on is no assistant ---
mk 60-asst
printf '%s %s %s %s\n' a5515700 a5515700-1111-4222-8333-444455556666 running "assistant: timesheet" > "$SS"
printf 'a5515700\t%s\n' "$(native "$tmp/repo")" > "$SS.cwd"
akl="ASSISTANT KEPT: timesheet (a5515700) - an assistant is removed only on the owner's word"
akept() {   # akept <what>: exit 6 checked; one line akl, nothing stopped or removed, the worktree, branch and session kept
  [ "$(printf '%s\n' "$LAST" | tr -d '\r' | grep -cxF "$akl")" = 1 ] || { echo "FAIL ($1): not exactly one line '$akl'"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }
  grep -q -e '^stop' -e '^rm' "$STUB_LOG" && { echo "FAIL ($1): a session was stopped or removed:"; sed 's/^/    /' "$STUB_LOG"; fail=1; }
  [ -d "$w" ] && git -C "$tmp/repo" show-ref -q --verify refs/heads/60-asst || { echo "FAIL ($1): the worktree or branch was removed"; fail=1; }
  grep -q a5515700 "$SS" || { echo "FAIL ($1): the assistant's session is gone"; fail=1; }
}
for v in "a5515700|" "a5515700-1111-4222-8333-444455556666|" "a5515700|--dry-run"; do
  vs="${v%%|*}" vd="${v#*|}"; : > "$STUB_LOG"
  STUB_HEADS="$h" check 6 "cleanup: an assistant by $vs${vd:+ $vd}" -- cleanup --worktree "$w" --session "$vs" $vd
  akept "an assistant by $vs${vd:+ $vd}"
done
printf '%s %s %s %s\n' a5515700 a5515700-1111-4222-8333-444455556666 done "assistant: timesheet" > "$SS"
: > "$STUB_LOG"
STUB_HEADS="$h" check 6 "cleanup: a stopped assistant" -- cleanup --worktree "$w" --session a5515700
akept "a stopped assistant"
# before the worktree checks: a worktree that does not exist, one with uncommitted changes
: > "$STUB_LOG"
STUB_HEADS="$h" check 6 "cleanup: an assistant, no such worktree" -- cleanup --worktree "$tmp/repo/.claude/worktrees/60-nope" --session a5515700
akept "an assistant, no such worktree"
echo dirt > "$w/dirt.txt"; : > "$STUB_LOG"
STUB_HEADS="$h" check 6 "cleanup: an assistant, a worktree not clean" -- cleanup --worktree "$w" --session a5515700
akept "an assistant, a worktree not clean"
rm -f "$w/dirt.txt"
# the negative control: `assistant:` later in the name is an ordinary session, cleaned as before (its own worktree)
mk 61-asst
printf '%s %s %s %s\n' c0ffee60 c0ffee60-1111-4222-8333-444455556666 running "#60 worker: assistant: tools" > "$SS"
printf 'c0ffee60\t%s\n' "$(native "$tmp/repo")" > "$SS.cwd"
STUB_HEADS="$h" check 0 "cleanup: a worker whose title holds assistant:" -- cleanup --worktree "$w" --session c0ffee60
expect_in "cleaned: c0ffee60"
for f in cleanup-worker.sh cleanup-worker.ps1; do
  awk 'NR > 1 && !/^#/ { exit } { sub(/^# ?/, ""); print }' "$core/scripts/$f" | tr -d '\r' | tr '\n' ' ' | grep -q '6 ASSISTANT KEPT' ||
    { echo "FAIL: the header of $f does not document exit code 6 (ASSISTANT KEPT)"; fail=1; }
done

# --- --contract only checks a contract: the session reads the brief alone (#331) ---
# given --contract <file> whose text is not in the brief (its `id:` line and its `title:` line both absent
# from the brief file): one line holding WARN and --contract (-Contract in the .ps1) says so, and the start
# goes on - a real start calls claude, a dry run prints the line and creates nothing. With the contract's
# text in the brief, or without --contract, no such line
tfno "$cc/budget-time-ok.md" > "$tmp/c331.md"
{ printf 'Do it.\n\n'; cat "$tmp/c331.md"; } > "$tmp/brief-c331.md"
grep -qx 'id: t8' "$tmp/c331.md" && ! grep -q '^id:\|^title:' "$tmp/brief.md" || { echo "FAIL: could not write the #331 contract and briefs"; fail=1; }
cwarn() { printf '%s\n' "$LAST" | tr -d '\r' | grep -F WARN | grep -ci -- '-contract'; }
K=(--repo "$tmp/repo" --model opus --safety "$tmp/safety.json" --report-to x --contract "$tmp/c331.md")
: > "$STUB_LOG"
check 0 "start: --contract, its text not in the brief" -- start --name "#331 worker: W" "${K[@]}" --branch 331-warn --brief-file "$tmp/brief.md"
[ "$(cwarn)" = 1 ] || { echo "FAIL (--contract, its text not in the brief): not exactly one line holding WARN and --contract"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }
grep -q -- '--bg' "$STUB_LOG" || { echo "FAIL (--contract, its text not in the brief): claude was not started"; fail=1; }
: > "$STUB_LOG"
check 0 "start: --contract, its text not in the brief, dry run" -- start --name "#331 worker: W" "${K[@]}" --branch 331-dry --brief-file "$tmp/brief.md" --dry-run
[ "$(cwarn)" = 1 ] || { echo "FAIL (--contract, its text not in the brief, dry run): not exactly one line holding WARN and --contract"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }
[ -d "$tmp/repo/.claude/worktrees/331-dry" ] && { echo "FAIL (dry run): a worktree was created"; fail=1; }
git -C "$tmp/repo" show-ref -q --verify refs/heads/331-dry && { echo "FAIL (dry run): a branch was created"; fail=1; }
grep -q -- '--bg' "$STUB_LOG" && { echo "FAIL (dry run): claude was started"; fail=1; }
check 0 "start: --contract, its text in the brief" -- start --name "#331 worker: W" "${K[@]}" --branch 331-dry --brief-file "$tmp/brief-c331.md" --dry-run
[ "$(cwarn)" = 0 ] || { echo "FAIL (--contract, its text in the brief): a line holding WARN and --contract"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }
check 0 "start: no --contract" -- start --name "#331 worker: W" --repo "$tmp/repo" --model opus --safety "$tmp/safety.json" --report-to x --branch 331-dry --brief-file "$tmp/brief.md" --dry-run
[ "$(cwarn)" = 0 ] || { echo "FAIL (no --contract): a line holding WARN and --contract"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }

# --- the after-compact hook: one instruction into the context, as JSON (plain stdout never reaches the model)
ac() { local role="$1"; shift
  if [ "$kind" = ps ]; then "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$core/scripts/hooks/after-compact.ps1" "$role"
  else bash "$core/scripts/hooks/after-compact.sh" "$role"; fi; }
cfgw="$tmp/cfg"; command -v cygpath >/dev/null 2>&1 && cfgw="$(cygpath -m "$tmp/cfg")"
j='{"session_id":"5e550000-0000-4000-8000-000000000001","cwd":"/work/proj","source":"compact"}'
LAST="$(printf '%s' "$j" | CLAUDE_CONFIG_DIR="$cfgw" ac worker | tr -d '\r')"
expect_in '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"The conversation was just compacted'
expect_in "read your brief in full with the Read tool: $cfgw/coordinator/briefs/5e550000-0000-4000-8000-000000000001.md"
LAST="$(printf '%s' '{"session_id":"5e550000-0000-4000-8000-0000000000ff"}' | CLAUDE_CONFIG_DIR="$cfgw" ac worker | tr -d '\r')"
expect_in "re-read your role file and the contract your brief gave"
jc='{"session_id":"c0c00000-0000-4000-8000-000000000001","cwd":"/work/proj","source":"compact"}'
LAST="$(printf '%s' "$jc" | CLAUDE_CONFIG_DIR="$cfgw" ac coordinator | tr -d '\r')"
expect_in "re-read in full with the Read tool: /work/proj/coordinator/core/CORE.md (section 1, the hard rules, first; then the event table of section 4 - any duty there not done since the last journal line, do it now), /work/proj/coordinator/PROJECT.md"
# the coordinator variant also loads in a worker launched from the project root (#217): silent there -
# a session with a kept brief, or one working in a worktree (either separator)
out="$(printf '%s' "$j" | CLAUDE_CONFIG_DIR="$cfgw" ac coordinator | tr -d '\r')"
[ -z "$out" ] || { echo "FAIL: the coordinator variant spoke in a session with a kept brief: $out"; fail=1; }
for wc in '/work/proj/.claude/worktrees/12-fix' 'E:\\work\\proj\\.claude\\worktrees\\12-fix\\src'; do
  out="$(printf '{"session_id":"c0c00000-0000-4000-8000-000000000002","cwd":"%s"}' "$wc" | CLAUDE_CONFIG_DIR="$cfgw" ac coordinator | tr -d '\r')"
  [ -z "$out" ] || { echo "FAIL: the coordinator variant spoke in a worktree ($wc): $out"; fail=1; }
done
LAST="$(printf 'not json' | ac coordinator | tr -d '\r')"
expect_in '"additionalContext":"The conversation was just compacted'
out="$(printf '%s' "$j" | ac nobody 2>/dev/null)"; rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] || { echo "FAIL: after-compact with an unknown role: exit $rc, printed '$out'"; fail=1; }
# the assistant variant (281.5): an assistant outlives its kept brief (pruned after 14 days), so with or
# without one it names its own files - <COORD_ASSISTANT_DIR>/BRIEF.md and NOTES.md, and the core's
# roles/assistant.md (the core the hook runs from) - to read in full with the Read tool and follow, not the
# summary; paths in the forward-slash form the worker variant prints; never a worker's or the coordinator's
# text. Access points: the text holds "with the Read tool", "not the summary" and the three paths; without
# COORD_ASSISTANT_DIR it still names BRIEF.md and NOTES.md and says the folder is "unknown"; the usage line
# names assistant.
ad="$tmp/assist/a1"; mkdir -p "$ad"; printf 'brief\n' > "$ad/BRIEF.md"; printf 'notes\n' > "$ad/NOTES.md"
adw="$ad"; command -v cygpath >/dev/null 2>&1 && adw="$(cygpath -m "$ad")"
mkdir -p "$tmp/cfg/coordinator/briefs"; printf 'You implement one contract\n' > "$tmp/cfg/coordinator/briefs/a5500000-0000-4000-8000-000000000001.md"
not_worker_or_coord() {   # <case>: the text of neither the worker nor the coordinator variant
  case "$LAST" in *coordinator/briefs*|*"your role file and the contract"*|*CORE.md*|*BINDINGS.md*|*"git status"*)
    echo "FAIL (after-compact assistant, $1): a worker's or the coordinator's text: $LAST"; fail=1 ;; esac; }
for as in a5500000-0000-4000-8000-000000000001 a5500000-0000-4000-8000-0000000000ff; do   # a kept brief, none
  w="kept brief"; [ "$as" = a5500000-0000-4000-8000-000000000001 ] || w="no kept brief"
  LAST="$(set -o pipefail; printf '{"session_id":"%s","cwd":"/work/proj","source":"compact"}' "$as" | CLAUDE_CONFIG_DIR="$cfgw" COORD_ASSISTANT_DIR="$adw" ac assistant | tr -d '\r')"; rc=$?
  [ "$rc" = 0 ] || { echo "FAIL (after-compact assistant, $w): exit $rc"; fail=1; }
  expect_in '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"The conversation was just compacted'
  expect_in "with the Read tool"; expect_in "not the summary"
  expect_in "$adw/BRIEF.md"; expect_in "$adw/NOTES.md"; expect_in "$core/roles/assistant.md"
  not_worker_or_coord "$w"
done
# COORD_ASSISTANT_DIR with backslashes (Windows): printed in the forward-slash form
if command -v cygpath >/dev/null 2>&1; then
  LAST="$(printf '%s' '{"session_id":"a5500000-0000-4000-8000-0000000000ff"}' | COORD_ASSISTANT_DIR="$(cygpath -w "$ad")" ac assistant | tr -d '\r')"
  expect_in "$adw/BRIEF.md"; expect_in "$adw/NOTES.md"
fi
LAST="$(set -o pipefail; unset COORD_ASSISTANT_DIR; printf '%s' '{"session_id":"a5500000-0000-4000-8000-0000000000ff","cwd":"/work/proj"}' | CLAUDE_CONFIG_DIR="$cfgw" ac assistant | tr -d '\r')"; rc=$?
[ "$rc" = 0 ] || { echo "FAIL (after-compact assistant, no COORD_ASSISTANT_DIR): exit $rc"; fail=1; }
expect_in '"additionalContext":"The conversation was just compacted'
expect_in "BRIEF.md"; expect_in "NOTES.md"; expect_in "unknown"
not_worker_or_coord "no COORD_ASSISTANT_DIR"
# the coordinator variant is silent in an assistant's session (its settings load the project's too)
out="$(set -o pipefail; printf '%s' "$jc" | CLAUDE_CONFIG_DIR="$cfgw" COORD_ASSISTANT_DIR="$adw" ac coordinator | tr -d '\r')"; rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] || { echo "FAIL: the coordinator variant spoke in an assistant's session: exit $rc, printed '$out'"; fail=1; }
err="$(printf '%s' "$j" | ac nobody 2>&1 >/dev/null | tr -d '\r')"
case "$err" in *usage*assistant*) ;; *) echo "FAIL: the after-compact usage line does not name assistant: '$err'"; fail=1 ;; esac

echo "worker scripts ($kind): $n checks ($nr agreement-guard starts kept from earlier cases), $( [ $fail = 0 ] && echo all pass || echo FAILURES )"
exit $fail
