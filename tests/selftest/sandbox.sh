#!/usr/bin/env bash
# `selftest sandbox` and `selftest clean` on sandboxes under a temporary folder, the same verdict and
# message from both versions (paths compared with forward slashes):
#   - clean --keep resets a used sandbox (a merged worktree, a branch merged and pushed to the origin,
#     main pushed ahead, an untracked file, the owner's .claude/settings.local.json): the folder, its
#     marker, the repo's path and remote.git stay; only main, at the first commit, in both; no worktree;
#     nothing untracked but settings.local.json - and sandbox --in then reuses it;
#   - clean --keep refuses a branch not merged into main (in a worktree, or only on the origin) and
#     keeps everything; it refuses a marker without the first commit (a sandbox from an older core);
#   - sandbox refuses a kept sandbox that is not clean, and a folder that is not a sandbox;
#   - plain clean still removes the folder; sandbox --keep is a usage error.
# The sessions are checked with a stub claude that lists none (the real one is never called).
#   tests/selftest/sandbox.sh sh                  # selftest.sh, with the bash running this file
#   tests/selftest/sandbox.sh ps pwsh             # selftest.ps1 (or: ps powershell)
# Exit 1 if any check fails.
set -u
[ $# -gt 0 ] || { sed -n '2,15s/^# \{0,1\}//p' "$0"; exit 2; }
kind="$1"; shift; PS=("$@")
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'chmod -R u+w "$tmp"; rm -r "$tmp"' EXIT
win=""; command -v cygpath >/dev/null 2>&1 && { win=1; core="$(cygpath -m "$core")"; }

# a stub claude first on PATH: `claude agents --json` lists no session
mkdir -p "$tmp/bin"
printf '#!/usr/bin/env bash\necho "[]"\n' > "$tmp/bin/claude"
printf "'[]'\n" > "$tmp/bin/claude.ps1"
chmod +x "$tmp/bin/claude"; export PATH="$tmp/bin:$PATH"

# P <path>: the path as this kind is given it (the .ps1 on Windows: C:/...); the flags as it names them
P() { if [ "$kind" = ps ] && [ -n "$win" ]; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
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

# merged now: clean --keep resets the sandbox and keeps it
g -C "$r" merge -q --no-edit t2; git -C "$r" fetch -q origin t3 2>/dev/null; g -C "$r" merge -q --no-edit FETCH_HEAD
st clean --sandbox "$(P "$d")" --keep
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

# a sandbox from an older core: its marker records no first commit
: > "$d/.coordinator-selftest"
st clean --sandbox "$(P "$d")" --keep
expect "clean --keep, an older marker" 1 "FAIL clean: no first commit recorded in $(P "$d")/.coordinator-selftest (a sandbox from an older core): run selftest clean $SB $(P "$d") without $KP"
st sandbox --in "$(P "$a")"
expect "sandbox, an older marker" 1 "FAIL sandbox: $(P "$d") already exists and is not clean (no first commit recorded in its .coordinator-selftest): run selftest clean $SB $(P "$d") [$KP] first"
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

# --keep belongs to clean only
n=$((n + 1))
st sandbox --in "$(P "$tmp/b")" --keep
{ [ "$RC" = 2 ] && ! printf '%s\n' "$LAST" | grep -q '^PASS \|^FAIL '; } ||
  { echo "FAIL (sandbox --keep): expected a usage error (exit 2), got exit $RC:"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }

echo "selftest sandbox ($kind): $n checks, $( [ $fail = 0 ] && echo all pass || echo FAILURES )"
exit $fail
