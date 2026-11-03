#!/usr/bin/env bash
# Checks of reset-coordinator on scratch projects in a temp folder, with stub `gh` and `claude` on PATH.
#   tests/reset-coordinator/run.sh sh              # reset-coordinator.sh, with the bash running this file
#   tests/reset-coordinator/run.sh ps pwsh         # reset-coordinator.ps1 (or: ps powershell)
# Exit 1 if any check fails, 3 if a call would have left the temp folder (nothing was run then).
#
# THE OWNER'S CONDITION: nobody runs the reset on a real project. rst below checks with pwd -P that HOME, the root
# and the state repository (its remote too) are under this run's temp folder before EVERY call, and aborts otherwise.
#
# Access points the script implements as written here (#446):
#   scripts/reset-coordinator.{sh,ps1} --root <project root> --confirm <the project folder's name> --core-from <a clean
#   clone of claude-coordinator>: the same double-dash arguments in both files. It stands alone (no other script of the
#   core), and works from any cwd, by --root: `.` too, and from the folder it replaces (coordinator/core/scripts).
#   --core-from is copied as UPDATE-CORE does: everything but .git/, .github/ and CLAUDE.md, nothing else in core/ left.
#   Success: exit 0 and the line `reset-coordinator: done tag=before-reset-<YYYY-MM-DD> core=<the clone's full HEAD sha>`.
#   A refusal: exit 1, nothing changed, its message holding: `core's own repository` (THE GUARD, checked first, before
#   any other refusal: the root holds CORE.md and scripts/check-core.sh; a project's coordinator/core/ holding them is
#   no reason), `--confirm`, `open PR` with `#<n>`, `running session` with the session's id, `assistants`, `remote`.
#   A failed push of the tag: exit 1, a message holding `tag`, nothing removed.
#   Open PRs: `gh pr list --json number,...` with the cwd at the project root (no --repo, so it is the project's
#   repository, never the state repository's), read from gh's JSON: the stub applies no --jq or --template.
#   Sessions: `claude agents --json` (with or without --all) in its real shape. Running = state working, or a `status`
#   field (it exists only while the process lives). The project's = cwd is the root or inside it. The caller: sessionId
#   equal to CLAUDE_CODE_SESSION_ID. A finished session (state done, no status) and another project's do not count.
#   The memory folder: $HOME/.claude/projects/<the root with every character but A-Za-z0-9 as ->/memory (Windows: the
#   root as C:/x/y, $env:USERPROFILE). Behind the tag at `before-reset-memory/<its path in memory/>` in the tag's tree.
#   The tag's tree holds every file of coordinator/, a .gitignore'd one too (CHECKPOINT.md), at its own path, with its
#   bytes: git's core.autocrlf is true here, as Git for Windows' default, so commit with -c core.autocrlf=false.
#   Restoring (here, and in the procedure): `git -c core.autocrlf=false checkout <tag>`.
set -u
[ $# -gt 0 ] || { sed -n '2,5s/^# \{0,1\}//p' "$0"; exit 2; }
kind="$1"; shift
case "$kind" in sh) ;; ps) ps="${1:-pwsh}" ;; *) echo "unknown kind: $kind" >&2; exit 2 ;; esac
here="$(cd "$(dirname "$0")" && pwd -P)"; core="$(cd "$here/../.." && pwd -P)"
tmp="$(cd "$(mktemp -d)" && pwd -P)"; trap 'cd /; rm -rf "$tmp"' EXIT
bin="$tmp/bin"; mkdir -p "$bin"; path0="$PATH"
# w: the form every path handed to the script takes (C:/x on Windows); jp: a path as claude's JSON holds it
w() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
jp() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1" | sed 's/\\/\\\\/g'; else printf '%s\n' "$1"; fi; }
core="$(w "$core")"; tmp="$(w "$tmp")"
case "$tmp/" in "$core"/*) echo "ABORT: the temp folder is inside the repository"; exit 3 ;; esac

mkdir -p "$tmp/stub"; export STUB_D="$tmp/stub"
cat > "$bin/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1 $2" = "pr list" ] && [ "$(basename "$PWD")" = proj ] && [ -f "$STUB_D/prs" ]; then cat "$STUB_D/prs"; else echo '[]'; fi
EOF
cat > "$bin/claude" <<'EOF'
#!/usr/bin/env bash
[ "$1" = agents ] && cat "$STUB_D/agents"
EOF
for c in gh claude; do printf '& bash (Join-Path $PSScriptRoot '"'"'%s'"'"') @args\nexit $LASTEXITCODE\n' "$c" > "$bin/$c.ps1"; chmod +x "$bin/$c"; done

# Nothing inherited: HOME, PATH (stubs first) and the caller's id are this test's; what could point git or claude elsewhere is unset
unset CLAUDE_CONFIG_DIR CLAUDE_PROJECT_DIR GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_CONFIG_GLOBAL XDG_CONFIG_HOME
CALLER=5e550000-0000-4000-8000-00000000ca11
export HOME="$tmp/home" USERPROFILE="$tmp/home" PATH="$bin:$path0" CLAUDE_CODE_SESSION_ID="$CALLER"
mkdir -p "$HOME"
[ "$(command -v gh)" = "$bin/gh" ] && [ "$(command -v claude)" = "$bin/claude" ] || { echo "ABORT: the stubs are not first on PATH"; exit 3; }
printf '[user]\n\tname = t\n\temail = t@t\n[init]\n\tdefaultBranch = main\n[core]\n\tautocrlf = true\n\tsafecrlf = false\n[safe]\n\tdirectory = *\n' > "$HOME/.gitconfig"

pass=0 fail=0 seq=0 name="" out="" rc=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL [$name] $*"; printf '%s\n' "$out" | sed 's/^/    | /'; }
has() { printf '%s\n' "$out" | grep -qF -- "$1" && ok || bad "expected in the output: $1"; }
hasnt() { printf '%s\n' "$out" | grep -qF -- "$1" && bad "unexpected in the output: $1" || ok; }
code() { [ "$rc" = "$1" ] && ok || bad "expected exit $1, got $rc"; }
chk() { local what="$1"; shift; "$@" >/dev/null 2>&1 && ok || bad "$what"; }
same() { [ "$2" = "$3" ] && ok || { bad "$1 differs"; diff <(printf '%s\n' "$2") <(printf '%s\n' "$3") | head -n 12 | sed 's/^/    d /'; }; }
under() { local c; c="$(cd "$1" 2>/dev/null && pwd -P)" || return 1; [ -n "$c" ] || return 1; case "$(w "$c")/" in "$tmp"/*) return 0 ;; esac; return 1; }
# rst <script dir> <root as typed> <args...>: one call of the script; out and rc
rst() { local d="$1" r="$2" u=""; shift 2
  under "$d" || case "$d" in "$core"/scripts) ;; *) echo "ABORT: script dir $d"; exit 3 ;; esac
  { under "$HOME" && under "$r" && { [ ! -d "$r/coordinator" ] || under "$r/coordinator"; }; } || { echo "ABORT: HOME or root outside $tmp: $HOME $r"; exit 3; }
  [ -d "$r/coordinator/.git" ] && u="$(git -C "$r/coordinator" remote get-url origin 2>/dev/null)"
  [ -z "$u" ] || case "$u" in "$tmp"/*) ;; *) echo "ABORT: remote outside $tmp: $u"; exit 3 ;; esac
  if [ "$kind" = sh ]; then out="$(bash "$d/reset-coordinator.sh" --root "$r" "$@" 2>&1 </dev/null)"; rc=$?
  else out="$("$ps" -NoProfile -ExecutionPolicy Bypass -File "$d/reset-coordinator.ps1" --root "$r" "$@" 2>&1 </dev/null)"; rc=$?; fi
  out="$(printf '%s\n' "$out" | tr -d '\r')"; }
# th <folder>: every file's bytes, by path (.git, the project's coordinator/ and the tag's memory folder apart)
th() { (cd "$1" 2>/dev/null && find . \( -path ./.git -o -path ./coordinator -o -path ./before-reset-memory \) -prune -o -type f -exec cksum {} + | LC_ALL=C sort -k3); }
gc() { git -c core.autocrlf=false "$@"; }
# agents "<id> <sessionId> <state> <status or -> <cwd>"...: the stub's answer, in claude's real shape
agents() { local e i s st stat c n=0; { echo '['; for e in "$@"; do read -r i s st stat c <<< "$e"; [ $n = 0 ] || echo ','; n=1
    printf '  {\n    "id": "%s",\n    "sessionId": "%s",\n    "name": "s-%s",\n    "cwd": "%s",\n    "state": "%s"%s\n  }\n' "$i" "$s" "$i" "$(jp "$c")" "$st" "$([ "$stat" = - ] || printf ',\n    "status": "%s"' "$stat")"
  done; echo ']'; } > "$STUB_D/agents"; }

# Upstream: a clean clone. Its copy of the script is poison longer than the script itself: run, or read at an old
# offset after an overwrite in place (bash reads a running script as it goes), it exits 99.
mkdir -p "$tmp/up/scripts" "$tmp/up/.github"
echo "upstream core" > "$tmp/up/CORE.md"; echo "upstream check" > "$tmp/up/scripts/check-core.sh"
echo "upstream claude" > "$tmp/up/CLAUDE.md"; echo "ci" > "$tmp/up/.github/ci.yml"
awk 'BEGIN { for (i = 0; i < 3000; i++) print "echo POISON-UPSTREAM; exit 99" }' > "$tmp/up/scripts/reset-coordinator.sh"
cp "$tmp/up/scripts/reset-coordinator.sh" "$tmp/up/scripts/reset-coordinator.ps1"
gc -C "$tmp/up" init -q; gc -C "$tmp/up" add -A; gc -C "$tmp/up" commit -qm upstream
from="$tmp/from"; gc clone -q "$tmp/up" "$from"; UP="$(git -C "$from" rev-parse HEAD)"
cp -R "$from" "$tmp/exp"; rm -rf "$tmp/exp/.git" "$tmp/exp/.github" "$tmp/exp/CLAUDE.md"; CORE_EXP="$(th "$tmp/exp")"
go=(--confirm proj --core-from "$from")

# project <case name>: $root, $st (the state repository), $bare (its remote), $mem; a real project's state, with uncommitted work
project() { name="$1"; seq=$((seq + 1)); root="$tmp/p$seq/proj"; st="$root/coordinator"; bare="$root-remote.git"
  echo '[]' > "$STUB_D/agents"; rm -f "$STUB_D/prs"
  mkdir -p "$root/.claude" "$st/core/scripts" "$st/briefs"
  git -C "$root" init -q; echo 'coordinator/' > "$root/.gitignore"; echo app > "$root/app.txt"; echo '{"worktree":{"bgIsolation":"none"}}' > "$root/.claude/settings.json"
  git -C "$root" add -A; git -C "$root" commit -qm app; git -C "$root" branch feature
  echo rules > "$st/PROJECT.md"; echo binds > "$st/BINDINGS.md"; echo log > "$st/LOG.md"; echo 'CHECKPOINT.md' > "$st/.gitignore"
  echo "old core" > "$st/core/CORE.md"; echo "old check" > "$st/core/scripts/check-core.sh"
  cp "$core"/scripts/reset-coordinator.* "$st/core/scripts/" 2>/dev/null
  git -C "$st" init -q; git -C "$st" add -A; git -C "$st" commit -qm state
  git init -q --bare "$bare"; git -C "$st" remote add origin "$bare"; git -C "$st" push -q origin main 2>/dev/null
  echo edited >> "$st/PROJECT.md"; printf 'a\r\nb\n' > "$st/briefs/crlf.md"; echo moment > "$st/CHECKPOINT.md"
  echo "local edit" >> "$st/core/CORE.md"; echo extra > "$st/core/extra.txt"
  pdir="$HOME/.claude/projects/$(printf '%s' "$root" | sed 's/[^A-Za-z0-9]/-/g')"; mem="$pdir/memory"; mkdir -p "$mem/sub"
  echo "old rule" > "$mem/MEMORY.md"; printf 'no newline' > "$mem/sub/note.md"; echo '{}' > "$pdir/transcript.jsonl"
  mkdir -p "$HOME/.claude/projects/-other/memory"; echo keep > "$HOME/.claude/projects/-other/memory/keep.md"; }
pj() { th "$root"; git -C "$root" log --all --format=%H; git -C "$root" branch -a; git -C "$root" status --short; }
snap() { th "$st"; th "$mem"; git -C "$st" log --all --format='%H %D'; git -C "$st" status --short; git -C "$st" for-each-ref; git ls-remote "$bare" 2>&1; pj; }
# refused <the message's words> <args>: exit 1, the words, everything as it was; $SCR the core's script here
SCR="$core/scripts"
refused() { local want="$1" s; shift; s="$(snap)"; rst "$SCR" "$root" "$@"; code 1; has "$want"; same "the state after a refusal" "$(snap)" "$s"; }
# the state after a reset, whichever way it went; $saved $msaved $psaved as before it
keep() { saved="$(th "$st")"; msaved="$(th "$mem")"; psaved="$(pj)"; }
after() { code 0; hasnt "core's own repository"; has "core=$UP"
  tag="$(printf '%s\n' "$out" | sed -n 's/^reset-coordinator: done tag=\(before-reset-[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\) core=.*$/\1/p')"
  chk "the line reset-coordinator: done tag=before-reset-<date> core=<sha>" [ -n "$tag" ]
  same "coordinator/ listing" "$(LC_ALL=C ls -A "$st" | tr '\n' ' ')" ".git core "
  same "git status" "$(git -C "$st" status --short)" ""
  same "the core copy against upstream" "$(th "$st/core")" "$CORE_EXP"; chk "the core copy has no .git" [ ! -e "$st/core/.git" ]
  same "the memory folder" "$(ls -A "$mem" 2>/dev/null)" ""
  chk "the transcript beside the memory stays" [ -f "$pdir/transcript.jsonl" ]; chk "another project's memory stays" [ -f "$HOME/.claude/projects/-other/memory/keep.md" ]
  same "the project's own repository" "$(pj)" "$psaved"; chk ".claude/settings.json stays" [ -f "$root/.claude/settings.json" ]
  chk "the tag is local" git -C "$st" rev-parse -q --verify "refs/tags/$tag^{commit}"; chk "history kept: the tag under the state branch" git -C "$st" merge-base --is-ancestor "$tag" HEAD; }

project "THE GUARD: a scratch copy of the core's shape"
echo core > "$root/CORE.md"; mkdir -p "$root/scripts"; echo check > "$root/scripts/check-core.sh"; git -C "$root" add -A; git -C "$root" commit -qm core
refused "core's own repository" "${go[@]}"
name="THE GUARD: --root ."; s="$(snap)"; cd "$root" || exit 1; rst "$SCR" . "${go[@]}"; cd "$tmp" || exit 1; code 1; has "core's own repository"; same "the state" "$(snap)" "$s"
name="THE GUARD: a linked worktree of it"; git -C "$root" worktree add -q "$root-wt" -b wt; s="$(snap)"; t="$(th "$root-wt")"
rst "$SCR" "$root-wt" --confirm proj-wt --core-from "$from"; code 1; has "core's own repository"; same "the state" "$(snap)" "$s"; same "the worktree" "$(th "$root-wt")" "$t"

project "refused: --confirm missing"; refused "--confirm" --core-from "$from"
name="refused: --confirm wrong"; refused "--confirm" --confirm other --core-from "$from"
name="refused: an open PR"; echo '[{"number":7,"title":"wip"}]' > "$STUB_D/prs"; refused "open PR" "${go[@]}"; has "#7"; rm -f "$STUB_D/prs"
OTHER=5e550000-0000-4000-8000-000000000001
name="refused: a worker running in the project's worktree"; agents "ca11e700 $CALLER working busy $root" "abcd1234 $OTHER working busy $root/.claude/worktrees/w1"
refused "running session" "${go[@]}"; has abcd1234; hasnt ca11e700
name="refused: a session between turns in the root"; agents "ca11e700 $CALLER working busy $root" "abcd1235 $OTHER done idle $root"
refused "running session" "${go[@]}"; has abcd1235; hasnt ca11e700; echo '[]' > "$STUB_D/agents"
name="refused: a file in coordinator/assistants"; mkdir -p "$st/assistants/helper"; echo brief > "$st/assistants/helper/BRIEF.md"; refused "assistants" "${go[@]}"; rm -rf "$st/assistants"
name="refused: a remote the tag cannot reach"; git -C "$st" remote set-url origin "$tmp/gone.git"; refused "remote" "${go[@]}"

project "a reset from the project's own core copy"; keep
agents "ca11e700 $CALLER working busy $root" "feed0001 $OTHER done - $root" "feed0002 $OTHER working busy $root-other"
rst "$st/core/scripts" "$root" "${go[@]}"; after
name="a reset: the remote"; chk "the tag on the remote" git -C "$bare" rev-parse -q --verify "refs/tags/$tag^{commit}"
same "the state branch pushed" "$(git -C "$bare" rev-parse main 2>&1)" "$(git -C "$st" rev-parse HEAD)"
name="restoring the tag, every file by its bytes"; d="$tmp/restored"; gc clone -q "$bare" "$d" 2>/dev/null; gc -C "$d" checkout -q "$tag" 2>/dev/null
same "the tag's tree against coordinator/ before the reset" "$(th "$d")" "$saved"
same "the tag's memory against the memory before the reset" "$(th "$d/before-reset-memory")" "$msaved"

project "the tag cannot be pushed: nothing removed"; mkdir -p "$bare/hooks"; printf '#!/bin/sh\ncase "$1" in refs/tags/*) echo refused >&2; exit 1 ;; esac\n' > "$bare/hooks/update"; chmod +x "$bare/hooks/update"; keep
rst "$st/core/scripts" "$root" "${go[@]}"; code 1; has "tag"
same "coordinator/ with the push refused" "$(th "$st")" "$saved"; same "the memory with the push refused" "$(th "$mem")" "$msaved"; same "the tag on the remote" "$(git ls-remote --tags "$bare")" ""

project "no remote at all: the tag stays local, the reset goes on"; git -C "$st" remote remove origin; keep
rst "$st/core/scripts" "$root" "${go[@]}"; after
chk "the tag holds the state" git -C "$st" cat-file -e "$tag:PROJECT.md"; chk "the tag holds the memory" git -C "$st" cat-file -e "$tag:before-reset-memory/MEMORY.md"

# On Windows a process's cwd holds its folder: nobody can replace it, whatever the script does
if ! command -v cygpath >/dev/null 2>&1; then
  project "a reset with the cwd in the folder it replaces"; keep; cd "$st/core/scripts" || exit 1
  rst "$st/core/scripts" "$root" "${go[@]}"; cd "$tmp" || exit 1; after
fi

echo "reset-coordinator ($kind): $((pass + fail)) checks, $([ $fail = 0 ] && echo "all pass" || echo "$fail FAILED")"
[ $fail = 0 ]
