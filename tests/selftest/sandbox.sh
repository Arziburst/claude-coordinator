#!/usr/bin/env bash
# `selftest sandbox` and `selftest clean` on sandboxes under a temporary folder, the same verdict and
# message from both versions (paths compared with forward slashes):
#   - clean --keep resets a used sandbox (a merged worktree, a branch merged and pushed to the origin,
#     main pushed ahead, an untracked file, the owner's .claude/settings.local.json): the folder, its
#     marker, the repo's path and remote.git stay; only main, at the first commit, in both; no worktree;
#     nothing untracked but settings.local.json - and sandbox --in then reuses it;
#   - clean (with or without --keep) refuses a branch not merged into main (in a worktree, or only on
#     the origin) and keeps the sandbox, nothing reset; --keep adopts a marker without the first commit
#     (a sandbox from an older core: main's single root commit is recorded) and refuses one with two roots;
#   - sandbox refuses a kept sandbox that is not clean, and a folder that is not a sandbox;
#   - plain clean still removes the folder; sandbox --keep is a usage error;
#   - a relative --in is made absolute: from another folder the kept sandbox fetches, resets, is reused.
# The sessions are checked with a stub claude (the real one is never called): only those in the sandbox count.
#   tests/selftest/sandbox.sh sh                  # selftest.sh, with the bash running this file
#   tests/selftest/sandbox.sh ps pwsh             # selftest.ps1 (or: ps powershell)
# Exit 1 if any check fails.
set -u
[ $# -gt 0 ] || { sed -n '2,16s/^# \{0,1\}//p' "$0"; exit 2; }
kind="$1"; shift; PS=("$@")
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'chmod -R u+w "$tmp"; rm -r "$tmp"' EXIT
win=""; command -v cygpath >/dev/null 2>&1 && { win=1; core="$(cygpath -m "$core")"; }

# a stub claude first on PATH: `claude agents --json` lists no session; with --all (the stopped,
# `done` sessions too) $STUB_AGENTS_ALL when set
mkdir -p "$tmp/bin"
cat > "$tmp/bin/claude" <<'EOF'
#!/usr/bin/env bash
case " $* " in *" --all "*) [ -n "${STUB_AGENTS_ALL:-}" ] && { printf '%s\n' "$STUB_AGENTS_ALL"; exit 0; } ;; esac
echo "[]"
EOF
cat > "$tmp/bin/claude.ps1" <<'EOF'
if ($args -contains '--all' -and $env:STUB_AGENTS_ALL) { $env:STUB_AGENTS_ALL } else { '[]' }
EOF
chmod +x "$tmp/bin/claude"; export PATH="$tmp/bin:$PATH"

# P <path>: the path as this kind is given it (the .ps1 on Windows: C:/...); the flags as it names them
P() { if [ "$kind" = ps ] && [ -n "$win" ]; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
# P2 <path>: a session's cwd as either version prints it (Claude Code lists C:\... on Windows), / for \
P2() { if [ -n "$win" ]; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
if [ "$kind" = ps ]; then SB=-Sandbox KP=-Keep; else SB=--sandbox KP=--keep; fi
# st <selftest.sh arguments>: one run of this kind, its output in $LAST (backslashes as /), its exit code in $RC
st() {
  if [ "$kind" = sh ]; then bash "$core/scripts/selftest.sh" "$@" > "$tmp/out" 2>&1
  else
    local a=() x
    for x in "$@"; do
      case "$x" in --in) x=-In ;; --sandbox) x=-Sandbox ;; --keep) x=-Keep ;; esac
      a+=("$x")
    done
    "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$core/scripts/selftest.ps1" "${a[@]}" > "$tmp/out" 2>&1
  fi
  RC=$?; LAST="$(tr -d '\r' < "$tmp/out" | tr '\\' '/')"
}
fail=0; n=0
expect() {   # expect <case> <exit code> <line>
  n=$((n + 1))
  { [ "$RC" = "$2" ] && printf '%s\n' "$LAST" | grep -qxF -- "$3"; } ||
    { echo "FAIL ($1): expected exit $2 and the line '$3', got exit $RC:"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }
}
is() {   # is <case> <command...>: the command succeeds
  n=$((n + 1)); local c="$1"; shift
  "$@" || { echo "FAIL ($c)"; fail=1; }
}
g() { git -c user.email=t@t -c user.name=t "$@"; }
refs() { git -C "$1" for-each-ref --format='%(refname)' "$2" | LC_ALL=C sort | paste -sd ' ' -; }
untracked() { git -C "$1" status --porcelain --ignored --untracked-files=all | grep -vxF -e '?? .claude/settings.local.json' -e '!! .claude/settings.local.json'; }

a="$tmp/a"; mkdir "$a"; d="$a/coordinator-selftest"; r="$d/repo"; o="$d/remote.git"; w="$r/.claude/worktrees"
st sandbox --in "$(P "$a")"
expect "a new sandbox" 0 "PASS sandbox: repository with a local bare origin, branch main"
expect "a new sandbox" 0 "sandbox: $(P "$d")"
i="$(git -C "$r" rev-parse main)"
is "the marker records the first commit" grep -qx "initial $i" "$d/.coordinator-selftest"

# a used sandbox: t1 in a worktree, pushed and merged; main pushed ahead (the origin's main must go back
# too); an untracked file; the owner's permissions in .claude/settings.local.json
git -C "$r" worktree add -q -b t1 "$w/t1" main
echo a > "$w/t1/a.txt"; git -C "$w/t1" add a.txt; g -C "$w/t1" commit -q -m a
git -C "$w/t1" push -q origin t1 2>/dev/null; g -C "$r" merge -q --no-edit t1; git -C "$r" push -q origin main 2>/dev/null
echo x > "$r/junk.txt"; mkdir -p "$r/.claude"; echo '{}' > "$r/.claude/settings.local.json"
# not merged: t2 in a worktree, and t3 only on the origin
git -C "$r" worktree add -q -b t2 "$w/t2" main
echo b > "$w/t2/b.txt"; git -C "$w/t2" add b.txt; g -C "$w/t2" commit -q -m b
c="$(g -C "$r" commit-tree -p main -m c "$(git -C "$r" rev-parse 'main^{tree}')")"
git -C "$r" push -q origin "$c:refs/heads/t3" 2>/dev/null
m="$(git -C "$r" rev-parse main)"

st clean --sandbox "$(P "$d")" --keep
expect "clean --keep, t2 not merged" 1 "FAIL clean: 1 worktree(s) left: not clean or not merged into main"
expect "clean --keep, t2 not merged" 1 "FAIL clean: branches not merged into main: t2"
expect "clean --keep, t3 only on the origin" 1 "FAIL clean: branches on the origin not merged into main: t3"
expect "clean --keep, refused" 1 "sandbox kept for inspection: $(P "$d")"
is "refused: main not reset" [ "$(git -C "$r" rev-parse main)" = "$m" ]
is "refused: the origin's branches kept" [ "$(refs "$o" refs/heads)" = "refs/heads/main refs/heads/t1 refs/heads/t3" ]
is "refused: the untracked file kept" [ -f "$r/junk.txt" ]
is "refused: t2's worktree kept" [ -f "$w/t2/b.txt" ]

st sandbox --in "$(P "$a")"
expect "sandbox on a used sandbox" 1 "FAIL sandbox: $(P "$d") already exists and is not clean (worktrees left): run selftest clean $SB $(P "$d") [$KP] first"
is "sandbox on a used sandbox: nothing changed" [ "$(git -C "$r" rev-parse main)" = "$m" ]

# t2 merged, t3 still only on the origin: a full clean refuses it too and keeps the folder (it removes
# only the clean, merged worktree and branch, as before)
g -C "$r" merge -q --no-edit t2; m="$(git -C "$r" rev-parse main)"
st clean --sandbox "$(P "$d")"
expect "clean, t3 only on the origin" 1 "FAIL clean: branches on the origin not merged into main: t3"
expect "clean, t3 only on the origin" 1 "PASS clean: no branch left"
expect "clean, refused" 1 "sandbox kept for inspection: $(P "$d")"
is "clean refused: the folder kept" [ -f "$d/.coordinator-selftest" ]
is "clean refused: the origin's t3 kept" [ "$(refs "$o" refs/heads)" = "refs/heads/main refs/heads/t1 refs/heads/t3" ]
is "clean refused: main kept" [ "$(git -C "$r" rev-parse main)" = "$m" ]
is "clean refused: the untracked file kept" [ -f "$r/junk.txt" ]

# merged now, but a stopped (`done`) self-test session is still listed (claude agents --json --all only):
# clean --keep refuses, nothing reset (#151)
git -C "$r" fetch -q origin t3 2>/dev/null; g -C "$r" merge -q --no-edit FETCH_HEAD
m="$(git -C "$r" rev-parse main)"
# Each listed with its cwd as the real listing gives it (Windows: C:\..., each \ doubled in the JSON):
# only a session inside the sandbox counts; one in another folder, or in one that only shares the
# sandbox's name as a prefix (`<dir>-old`), is a SKIP line, not counted, not advised for removal (#158)
if [ -n "$win" ]; then J() { cygpath -w "$1" | sed 's/\\/\\\\/g'; }; else J() { printf '%s\n' "$1"; }; fi
foreign='{"id":"f1","cwd":"'"$(J "$a")"'","name":"#st1 lead: selftest c7","state":"done"},{"id":"f2","cwd":"'"$(J "$d-old")"'","name":"probe: push","state":"done"}'
export STUB_AGENTS_ALL='[{"id":"2be9934b","cwd":"'"$(J "$r/.claude/worktrees/st2")"'","sessionId":"2be9934b-aaaa-4bbb-8ccc-dddddddddddd","name":"#st2 worker: PR","state":"done"},{"id":"5c6d7e8f","cwd":"'"$(J "$r")"'","name":"other","state":"done"},'"$foreign]"
st clean --sandbox "$(P "$d")" --keep
expect "clean --keep, a done session left" 1 "FAIL clean: sessions left (claude rm <id> each): #st2 worker: PR (2be9934b)"
expect "clean --keep, a done session left" 1 "sandbox kept for inspection: $(P "$d")"
expect "clean --keep, a foreign session" 1 "SKIP foreign self-test session f1 ($(P2 "$a"))"
expect "clean --keep, a <dir>-old session" 1 "SKIP foreign self-test session f2 ($(P2 "$d-old"))"
is "a done session left: main not reset" [ "$(git -C "$r" rev-parse main)" = "$m" ]
unset STUB_AGENTS_ALL

# merged now: clean --keep resets the sandbox and keeps it - only foreign self-test sessions are listed:
# they do not stop it (their SKIP lines printed)
export STUB_AGENTS_ALL="[$foreign]"
st clean --sandbox "$(P "$d")" --keep
unset STUB_AGENTS_ALL
expect "clean --keep, only foreign sessions" 0 "PASS clean: no self-test session left"
expect "clean --keep, only foreign sessions" 0 "SKIP foreign self-test session f1 ($(P2 "$a"))"
expect "clean --keep" 0 "PASS clean: no worktree left"
expect "clean --keep" 0 "PASS clean: every branch on the origin is merged into main"
expect "clean --keep" 0 "PASS clean: only main, at the first commit $(git -C "$r" rev-parse --short "$i"), in the repo and its origin; nothing untracked"
expect "clean --keep" 0 "sandbox kept for the next run: $(P "$d")"
is "kept: the marker" grep -qx "initial $i" "$d/.coordinator-selftest"
is "kept: the repo at its path" [ "$(git -C "$r" rev-parse --git-dir)" = .git ]
is "kept: remote.git" [ "$(git -C "$o" rev-parse --is-bare-repository)" = true ]
is "only main in the repo" [ "$(refs "$r" refs/heads)" = refs/heads/main ]
is "only main on the origin" [ "$(refs "$o" refs/heads)" = refs/heads/main ]
is "only origin/main tracked" [ "$(refs "$r" refs/remotes | sed 's#refs/remotes/origin/HEAD ##')" = refs/remotes/origin/main ]
is "main at the first commit" [ "$(git -C "$r" rev-parse main)" = "$i" ]
is "the origin's main at the first commit" [ "$(git -C "$o" rev-parse main)" = "$i" ]
is "on main" [ "$(git -C "$r" symbolic-ref HEAD)" = refs/heads/main ]
is "no worktree" [ "$(git -C "$r" worktree list --porcelain | grep -c "^worktree ")" = 1 ]
is "no worktree folder" [ ! -e "$w/t2" ]
is "nothing untracked" [ -z "$(untracked "$r")" ]
is "the untracked file removed" [ ! -e "$r/junk.txt" ]
is "settings.local.json kept" [ -f "$r/.claude/settings.local.json" ]

st sandbox --in "$(P "$a")"
expect "sandbox reuses the kept sandbox" 0 "PASS sandbox: reusing the kept sandbox $(P "$d")"
expect "sandbox reuses the kept sandbox" 0 "sandbox: $(P "$d")"
echo y >> "$r/README.md"
st sandbox --in "$(P "$a")"
expect "sandbox on a changed file" 1 "FAIL sandbox: $(P "$d") already exists and is not clean (changed or untracked files in the repo): run selftest clean $SB $(P "$d") [$KP] first"
git -C "$r" checkout -q -- README.md

# a sandbox from an older core: its marker records no first commit. sandbox refuses it; clean --keep
# adopts it (main's single root commit, on the origin too, is recorded), resets it and keeps it
: > "$d/.coordinator-selftest"
st sandbox --in "$(P "$a")"
expect "sandbox, an older marker" 1 "FAIL sandbox: $(P "$d") already exists and is not clean (no first commit recorded in its .coordinator-selftest): run selftest clean $SB $(P "$d") [$KP] first"
st clean --sandbox "$(P "$d")" --keep
expect "clean --keep adopts an older marker" 0 "PASS clean: recorded the first commit $(git -C "$r" rev-parse --short "$i") of a sandbox from an older core"
is "the older marker now records the first commit" grep -qx "initial $i" "$d/.coordinator-selftest"
st sandbox --in "$(P "$a")"
expect "sandbox reuses an adopted sandbox" 0 "PASS sandbox: reusing the kept sandbox $(P "$d")"
# an older marker and two root commits on main: no first commit to adopt, nothing changed
: > "$d/.coordinator-selftest"
git -C "$r" checkout -q --orphan other && g -C "$r" commit -q --allow-empty -m other
git -C "$r" checkout -q main && g -C "$r" merge -q --no-edit --allow-unrelated-histories other && git -C "$r" branch -q -D other
st clean --sandbox "$(P "$d")" --keep
expect "clean --keep, an older marker and two roots" 1 "FAIL clean: no first commit recorded in $(P "$d")/.coordinator-selftest and none found (a sandbox from an older core): run selftest clean $SB $(P "$d") without $KP"
is "two roots: the marker untouched" [ ! -s "$d/.coordinator-selftest" ]
st clean --sandbox "$(P "$d")"
expect "plain clean" 0 "PASS clean: sandbox removed"
is "plain clean removes the folder" [ ! -e "$d" ]

# a folder that is not a sandbox: refused by both, untouched
b="$tmp/b/coordinator-selftest"; mkdir -p "$b"
st sandbox --in "$(P "$tmp/b")"
expect "sandbox on another folder" 1 "FAIL sandbox: $(P "$b") already exists and is not a self-test sandbox (no .coordinator-selftest): nothing changed"
st clean --sandbox "$(P "$b")" --keep
expect "clean --keep on another folder" 1 "FAIL clean: $(P "$b") is not a self-test sandbox (no .coordinator-selftest): nothing removed"
is "another folder untouched" [ -z "$(ls -A "$b")" ]

# a relative --in becomes an absolute path (the origin URL is stored from it): from another folder the
# kept sandbox still fetches, is reset and is reused. The path printed is checked as the same folder,
# not as the same text: the .ps1 on Windows prints the long form of a temp folder named in 8.3 form
# (RUNNER~1 on GitHub's runner)
mkdir "$tmp/c"; e="$tmp/c/coordinator-selftest"; cd "$tmp" || exit 1
isdir() {   # isdir <case> <exit code> <line prefix>: that exit code, and the line's path is $e, absolute
  local x
  n=$((n + 1))
  x="$(printf '%s\n' "$LAST" | sed -n "s/^$3//p" | head -n 1)"
  { [ "$RC" = "$2" ] && case "$x" in /*|[A-Za-z]:/*) true ;; *) false ;; esac && [ "$x" -ef "$e" ]; } ||
    { echo "FAIL ($1): expected exit $2 and the line '$3$e' (an absolute path), got exit $RC:"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }
}
st sandbox --in c
isdir "sandbox with a relative --in" 0 "sandbox: "
u="$(git -C "$e/repo" config remote.origin.url)"
n=$((n + 1)); case "$u" in /*|[A-Za-z]:*) ;; *) echo "FAIL (a relative --in): the origin URL is not absolute: $u"; fail=1 ;; esac
cd "$tmp/bin" || exit 1
git -C "$e/repo" push -q origin main:t5 2>/dev/null
is "a relative --in: the repo fetches from another folder" git -C "$e/repo" fetch -q origin
st clean --sandbox "$(P "$e")" --keep
expect "a relative --in: clean --keep from another folder" 0 "sandbox kept for the next run: $(P "$e")"
cd "$tmp" || exit 1
st sandbox --in c
isdir "a relative --in: reused" 0 "PASS sandbox: reusing the kept sandbox "
cd "$here" || exit 1

# --keep belongs to clean only
n=$((n + 1))
st sandbox --in "$(P "$tmp/b")" --keep
{ [ "$RC" = 2 ] && ! printf '%s\n' "$LAST" | grep -q '^PASS \|^FAIL '; } ||
  { echo "FAIL (sandbox --keep): expected a usage error (exit 2), got exit $RC:"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }

echo "selftest sandbox ($kind): $n checks, $( [ $fail = 0 ] && echo all pass || echo FAILURES )"
exit $fail
