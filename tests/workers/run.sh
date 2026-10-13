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
# --bg: remember the folder and the session name; agents --json: list the names started so far
if [ "${1:-}" = --bg ]; then printf 'cwd %s\n' "$(pwd -P)" >> "$STUB_LOG"; printf '%s\n' "$3" >> "$STUB_LOG.names"; fi
if [ "${1:-}" = agents ]; then printf '[%s]\n' "$(sed 's/.*/{"name":"&"}/' "$STUB_LOG.names" 2>/dev/null | paste -sd, -)"; fi
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
export PATH="$tmp/bin:$PATH" STUB_LOG="$tmp/claude.log"
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
  LAST="$out"
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
check 0 "start: dry run" -- start "${S[@]}" --dry-run
expect_in "[dry-run]"
expect_in "keep "
grep -q 'worktrees' "$tmp/repo/.git/info/exclude" 2>/dev/null && { echo "FAIL: the dry run wrote info/exclude"; fail=1; }
[ -d "$tmp/repo/.claude/worktrees/12-fix" ] && { echo "FAIL: the dry run created the worktree"; fail=1; }
[ -s "$STUB_LOG" ] && { echo "FAIL: the dry run called claude"; fail=1; }
check 0 "start: real start with the stub claude" -- start "${S[@]}"
expect_in 'subscribe: SendMessage(to: "#12 worker: Fix", notify_when_idle: true)'
# it waited until the new session was listed before printing the subscribe line (no race)
grep -qx "agents --json" "$STUB_LOG" || { echo "FAIL: start-worker did not wait for the session to be listed"; fail=1; }
case "$LAST" in *"not listed after"*) echo "FAIL: the started session was not found in claude agents"; fail=1 ;; esac
[ -d "$tmp/repo/.claude/worktrees/12-fix" ] || { echo "FAIL: no worktree after start"; fail=1; }
grep -q -- "--bg --name #12 worker: Fix --model opus --permission-mode auto --settings" "$STUB_LOG" ||
  { echo "FAIL: claude got unexpected arguments:"; sed 's/^/    /' "$STUB_LOG"; fail=1; }
grep -q 'Second line "quoted".' "$STUB_LOG" || { echo "FAIL: the brief did not reach claude intact"; fail=1; }
# launched from the repository root (trusted), the brief's first action entering the worktree
grep -qx "cwd $(cd "$tmp/repo" && pwd -P)" "$STUB_LOG" || { echo "FAIL: not launched from the repository root:"; sed 's/^/    /' "$STUB_LOG"; fail=1; }
grep -q 'Report to: the session named "Core lead"' "$STUB_LOG" || { echo "FAIL: the brief does not name the report address"; fail=1; }
grep -q "FIRST ACTION, before anything else: use the EnterWorktree tool with path = .*/.claude/worktrees/12-fix\." "$STUB_LOG" ||
  { echo "FAIL: the brief does not start with entering the worktree"; fail=1; }
: > "$STUB_LOG"
mkdir -p "$tmp/launch"
check 0 "start: --launch-from another folder" -- start "${S[@]}" --launch-from "$tmp/launch"
grep -qx "cwd $(cd "$tmp/launch" && pwd -P)" "$STUB_LOG" || { echo "FAIL: --launch-from ignored:"; sed 's/^/    /' "$STUB_LOG"; fail=1; }
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
# an unreachable origin: the script's own message (Windows PowerShell 5.1 included)
git init -q -b main "$tmp/repo4" && g -C "$tmp/repo4" commit -q --allow-empty -m init && git -C "$tmp/repo4" remote add origin "$mtmp/no-such-remote.git"
check 1 "start: an unreachable origin" -- start --repo "$tmp/repo4" --name "#38 worker: a" --branch 38-a "${W[@]}" --safety "$tmp/safety.json" --dry-run
expect_in "cannot reach origin"
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

# --- cleanup-worker ---
wt="$tmp/repo/.claude/worktrees/12-fix"
check 3 "cleanup: mistyped worktree path" -- cleanup --worktree "$tmp/repo/.claude/worktrees/12-fxi" --session s1
expect_in "NO WORKTREE"
check 3 "cleanup: the main checkout" -- cleanup --worktree "$tmp/repo"
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
STUB_HEADS="$head" check 0 "cleanup: dry run" -- cleanup --worktree "$wt" --session s1 --dry-run
expect_in "[dry-run]"
[ -d "$wt" ] || { echo "FAIL: the dry run removed the worktree"; fail=1; }
[ -s "$STUB_LOG" ] && { echo "FAIL: the dry run called claude"; fail=1; }
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

echo "worker scripts ($kind): $n checks, $( [ $fail = 0 ] && echo all pass || echo FAILURES )"
exit $fail
