#!/usr/bin/env bash
# `selftest prepare` and `selftest verify` against temporary projects and state repositories, the same
# verdict and message from both versions:
#   - CORE-FINDINGS.md: an empty status, a capitalised status, a UTF-16 file (Windows PowerShell 5.1's
#     Out-File), and a UTF-8 BOM with CRLF line ends (which pass);
#   - a core commit whose base branch is only on the remote (a fresh clone on another machine) is refused;
#   - a project under a folder with a non-ASCII name (`prj ü`): verify removes the clean, merged worktree.
#     On Windows the .ps1 runs as on a Russian Windows, with the console's code page 866;
#   - the worktrees in the project's .claude/worktrees, not the state repository's (#260): prepare makes
#     the base's worktree there, out of the project's git; verify removes an older run's at the old place;
#   - the self-test sessions still listed by `claude agents` (a stub claude: the real one is never called),
#     each with its cwd: only the run's own folders count; another folder's session is a SKIP line (#158).
#   tests/selftest/prepare.sh sh                  # selftest.sh, with the bash running this file
#   tests/selftest/prepare.sh ps pwsh             # selftest.ps1 (or: ps powershell)
# Exit 1 if any check fails.
set -u
[ $# -gt 0 ] || { sed -n '2,15s/^# \{0,1\}//p' "$0"; exit 2; }
kind="$1"; shift; PS=("$@")
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'chmod -R u+w "$tmp"; rm -r "$tmp"' EXIT
win=""; command -v cygpath >/dev/null 2>&1 && { win=1; core="$(cygpath -m "$core")"; }

# a stub claude first on PATH: `claude agents --json` prints $STUB_AGENTS, else an empty list; with
# --all (the stopped, `done` sessions too) $STUB_AGENTS_ALL when set
mkdir -p "$tmp/bin"
cat > "$tmp/bin/claude" <<'EOF'
#!/usr/bin/env bash
case " $* " in *" --all "*) [ -n "${STUB_AGENTS_ALL:-}" ] && { printf '%s\n' "$STUB_AGENTS_ALL"; exit 0; } ;; esac
printf '%s\n' "${STUB_AGENTS:-[]}"
EOF
cat > "$tmp/bin/claude.ps1" <<'EOF'
if ($args -contains '--all' -and $env:STUB_AGENTS_ALL) { $env:STUB_AGENTS_ALL } elseif ($env:STUB_AGENTS) { $env:STUB_AGENTS } else { '[]' }
EOF
chmod +x "$tmp/bin/claude"; export PATH="$tmp/bin:$PATH"

# st <step> <selftest.sh arguments>: one run of this kind, its output in $LAST, its exit code in $RC
st() {
  if [ "$kind" = sh ]; then bash "$core/scripts/selftest.sh" "$@" > "$tmp/out" 2>&1
  elif [ -n "$win" ]; then
    # as on a Russian Windows: the console's code page is 866, and the script runs under it
    local a="" x
    for x in "$@"; do
      case "$x" in
        --project) x=-Project ;; --state) x=-State ;; --core) x=-Core ;; --state-repo) x=-StateRepo ;;
        /*) x="'$(cygpath -m "$x")'" ;; *) x="'$x'" ;;
      esac
      a="$a $x"
    done
    "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -Command "\$o = [Console]::OutputEncoding; try { [Console]::OutputEncoding = [Text.Encoding]::GetEncoding(866) } catch { }; & '$core/scripts/selftest.ps1'$a; \$rc = \$LASTEXITCODE; try { [Console]::OutputEncoding = \$o } catch { }; exit \$rc" > "$tmp/out" 2>&1
  else
    local a=() x
    for x in "$@"; do
      case "$x" in --project) x=-Project ;; --state) x=-State ;; --core) x=-Core ;; --state-repo) x=-StateRepo ;; esac
      a+=("$x")
    done
    "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$core/scripts/selftest.ps1" "${a[@]}" > "$tmp/out" 2>&1
  fi
  RC=$?; LAST="$(tr -d '\r' < "$tmp/out")"
}
fail=0; n=0
expect() {   # expect <case> <exit code> <line>
  n=$((n + 1))
  { [ "$RC" = "$2" ] && printf '%s\n' "$LAST" | grep -qxF -- "$3"; } ||
    { echo "FAIL ($1): expected exit $2 and the line '$3', got exit $RC:"; printf '%s\n' "$LAST" | sed 's/^/    /'; fail=1; }
}

g() { git -c user.email=t@t -c user.name=t "$@"; }
p="$tmp/project"; s="$p/coordinator"
git init -q -b main "$p" && g -C "$p" commit -q --allow-empty -m p
git init -q -b state "$s" && g -C "$s" commit -q --allow-empty -m s
printf 'coordinator/\n' >> "$p/.git/info/exclude"
tpl="$(tr -d '\r' < "$core/CORE-FINDINGS.template.md")"
prepare() { st prepare --project "$p" --state "$s" --core "$1"; }
row() { printf '| CF-1 | 2026-10-13 | abc1234 | a check | what happened | none | %s |\n' "$1"; }
f="$s/CORE-FINDINGS.md"

{ printf '%s\n' "$tpl"; row ''; } > "$f"
prepare c1; expect "an empty status cell" 1 "FAIL prepare: CORE-FINDINGS.md: unknown status '<empty>'"
{ printf '%s\n' "$tpl"; row 'Sent #12'; } > "$f"
prepare c2; expect "a capitalised status" 1 "FAIL prepare: CORE-FINDINGS.md: unknown status 'Sent #12'"
{ printf '\377\376'; { printf '%s\n' "$tpl"; row 'sent #12'; } | iconv -f UTF-8 -t UTF-16LE; } > "$f"
prepare c3; expect "a UTF-16 LE file" 1 "FAIL prepare: CORE-FINDINGS.md is not UTF-8 (re-save it as UTF-8)"
{ printf '\357\273\277'; { printf '%s\n' "$tpl"; row 'sent #12'; row 'new'; } | awk '{ printf "%s\r\n", $0 }'; } > "$f"
prepare c4; expect "a UTF-8 BOM and CRLF" 0 "PASS prepare: CORE-FINDINGS.md in the template's format"

# the state repository with a remote; a fresh clone of it knows the base only as origin's branch
r="$tmp/remote.git"
git init -q --bare "$r" && git -C "$r" symbolic-ref HEAD refs/heads/state
git -C "$s" remote add origin "$r" && git -C "$s" push -q -u origin state 2>/dev/null
prepare c6; expect "prepare with a remote" 0 "PASS prepare: pushed selftest/c6/base"
git clone -q "$r" "$tmp/clone" 2>/dev/null; cp "$f" "$tmp/clone/CORE-FINDINGS.md"
st prepare --project "$p" --state "$tmp/clone" --core c6
expect "the base only on the remote" 1 "FAIL prepare: selftest/c6/base exists: core c6 was tested here already - its branches are the evidence, nothing is deleted"

# a project under a folder with a non-ASCII name: the worktree paths git prints must reach git again intact
p2="$tmp/prj $(printf '\303\274')"; s2="$p2/coordinator"; w2="$p2/.claude/worktrees/selftest/c7"
git init -q -b main "$p2" && g -C "$p2" commit -q --allow-empty -m p
git init -q -b state "$s2" && g -C "$s2" commit -q --allow-empty -m s
printf 'coordinator/\n' >> "$p2/.git/info/exclude"; cp "$f" "$s2/CORE-FINDINGS.md"
st prepare --project "$p2" --state "$s2" --core c7; expect "prepare under a non-ASCII folder" 0 "PASS prepare: branch selftest/c7/base from state"
git -C "$s2" worktree add -q -b selftest/c7/st1 "$w2/st1" selftest/c7/base
echo a > "$w2/st1/a.txt"; git -C "$w2/st1" add a.txt 2>/dev/null; g -C "$w2/st1" commit -q -m a
g -C "$w2/base" merge -q --no-ff --no-edit selftest/c7/st1   # the base's worktree, made by prepare
st verify --project "$p2" --state "$s2" --core c7; expect "verify under a non-ASCII folder" 0 "PASS verify: no worktree left"
n=$((n + 1)); [ ! -e "$w2/st1" ] && [ ! -e "$w2/base" ] || { echo "FAIL (verify under a non-ASCII folder): the merged worktrees are still there"; fail=1; }

# the run's worktrees lie in the project's .claude/worktrees, never in the state repository's, which is
# inside the root the guard keeps a worker's edit tools out of (COORD_PROTECTED_ROOT, #260): prepare makes
# the base's worktree at <project>/.claude/worktrees/selftest/<c>/base, out of the project's git, nothing
# at the old place; verify still removes a worktree an older self-test left at the old place
# (<state>/.claude/worktrees), merged into that run's own base
p3="$tmp/p3"; s3="$p3/coordinator"; w3="$p3/.claude/worktrees/selftest/c8"; o3="$s3/.claude/worktrees/selftest/c0"
git init -q -b main "$p3" && g -C "$p3" commit -q --allow-empty -m p
git init -q -b state "$s3" && g -C "$s3" commit -q --allow-empty -m s
printf 'coordinator/\n' >> "$p3/.git/info/exclude"; cp "$f" "$s3/CORE-FINDINGS.md"
git -C "$s3" branch selftest/c0/base state
git -C "$s3" worktree add -q -b selftest/c0/st1 "$o3/st1" selftest/c0/base
echo z > "$o3/st1/z.txt"; git -C "$o3/st1" add z.txt 2>/dev/null; g -C "$o3/st1" commit -q -m z
git -C "$s3" branch -f selftest/c0/base selftest/c0/st1
if [ -n "$win" ]; then M() { cygpath -m "$1"; }; else M() { printf '%s\n' "$1"; }; fi
st prepare --project "$p3" --state "$s3" --core c8
expect "prepare: the base's worktree in the project's .claude/worktrees" 0 "PASS prepare: worktree of selftest/c8/base at $(M "$p3")/.claude/worktrees/selftest/c8/base"
expect "prepare: the worktree root it names" 0 "worktrees: $(M "$p3")/.claude/worktrees/selftest/c8 (start-worker's worktree root: $(M "$p3")/.claude/worktrees)"
n=$((n + 1)); [ "$(git -C "$w3/base" symbolic-ref -q --short HEAD 2>/dev/null)" = selftest/c8/base ] ||
  { echo "FAIL (prepare: the base's worktree): no worktree of selftest/c8/base at $w3/base"; fail=1; }
n=$((n + 1)); [ ! -e "$s3/.claude/worktrees/selftest/c8" ] ||
  { echo "FAIL (prepare: the base's worktree): a worktree at the old place $s3/.claude/worktrees/selftest/c8"; fail=1; }
n=$((n + 1)); [ -z "$(git -C "$p3" status --porcelain)" ] ||
  { echo "FAIL (prepare: the base's worktree): the project's git sees it:"; git -C "$p3" status --porcelain | sed 's/^/    /'; fail=1; }
git -C "$s3" worktree add -q -b selftest/c8/st1 "$w3/st1" selftest/c8/base   # as start-worker --worktree-root makes it
echo a > "$w3/st1/a.txt"; git -C "$w3/st1" add a.txt 2>/dev/null; g -C "$w3/st1" commit -q -m a
g -C "$w3/base" merge -q --no-ff --no-edit selftest/c8/st1
st verify --project "$p3" --state "$s3" --core c8
expect "verify: the run's worktrees and an older run's at the old place" 0 "PASS verify: no worktree left"
n=$((n + 1)); [ ! -e "$w3/st1" ] && [ ! -e "$w3/base" ] && [ ! -e "$o3/st1" ] ||
  { echo "FAIL (verify: the run's worktrees and an older run's at the old place): merged worktrees are still there"; fail=1; }

# the sessions claude agents still lists, each with its cwd as the real listing gives it: D <path> as
# Claude Code prints a folder (Windows: C:\...), J <path> as a JSON string holds it (each \ doubled),
# B <path> Windows-style (Windows: C:\...; elsewhere with \ for each /)
if [ -n "$win" ]; then D() { cygpath -w "$1"; }; else D() { printf '%s\n' "$1"; }; fi
J() { D "$1" | sed 's/\\/\\\\/g'; }
B() { if [ -n "$win" ]; then J "$1"; else printf '%s\n' "$1" | sed 's|/|\\\\|g'; fi; }
# their names, unquoted, and ids, in both versions
export STUB_AGENTS='[{"id":"a1","cwd":"'"$(J "$p2")"'","name":"selftest-st1"},{"id":"b2","cwd":"'"$(J "$p2")"'","name":"other"},{"id":"c3","cwd":"'"$(J "$p2")"'","name":"selftest-task-1"}]'
st verify --project "$p2" --state "$s2" --core c7; expect "sessions left" 1 "FAIL verify: sessions left (in step 6's order: claude stop <id>, read its cost, delete its status file, claude rm <id>): selftest-st1 (a1), selftest-task-1 (c3)"
# a stopped (`done`) session is listed only with --all, as the real listing prints it; a `#st` name
# without `selftest` and a `probe:` name count too (#151)
export STUB_AGENTS='[]' STUB_AGENTS_ALL='[
  {
    "id": "2be9934b",
    "cwd": "'"$(J "$p2")"'",
    "sessionId": "2be9934b-aaaa-4bbb-8ccc-dddddddddddd",
    "name": "#st2 worker: PR",
    "state": "done"
  },
  {
    "id": "5c6d7e8f",
    "cwd": "'"$(J "$p2")"'",
    "sessionId": "5c6d7e8f-aaaa-4bbb-8ccc-dddddddddddd",
    "name": "#12 worker: stuff",
    "state": "done"
  },
  {
    "id": "77aa88bb",
    "cwd": "'"$(J "$s2")"'",
    "sessionId": "77aa88bb-aaaa-4bbb-8ccc-dddddddddddd",
    "name": "probe: push",
    "state": "done"
  }
]'
st verify --project "$p2" --state "$s2" --core c7; expect "done sessions left" 1 "FAIL verify: sessions left (in step 6's order: claude stop <id>, read its cost, delete its status file, claude rm <id>): #st2 worker: PR (2be9934b), probe: push (77aa88bb)"
# only the run's own sessions count (#158): a cwd in the project root, in a worktree under it written
# Windows-style, in a worktree root the state repository's PROJECT.md names (relative to the root). Another
# project's session and one in a folder that only shares the root's name as a prefix (`<root>-old`) are
# foreign: a SKIP line each, not counted, not advised for removal
printf '| Setting | Value |\n|---|---|\n| Worktree roots | `../wt-c7`; none |\n' > "$s2/PROJECT.md"
own='{"id":"a1","cwd":"'"$(J "$p2")"'","name":"#st1 lead: selftest c7"},
  {"id":"w1","cwd":"'"$(B "$p2/.claude/worktrees/selftest/c7/st2")"'","name":"#st2 worker: PR"},
  {"id":"r1","cwd":"'"$(J "$tmp/wt-c7/x")"'","name":"probe: push"}'
foreign='{"id":"f1","cwd":"'"$(J "$tmp/other")"'","name":"#st1 lead: selftest c7"},
  {"id":"f2","cwd":"'"$(J "$p2-old")"'","name":"#st2 worker: PR"},
  {"id":"n1","cwd":"'"$(J "$tmp/other")"'","name":"#12 worker: stuff"}'
export STUB_AGENTS_ALL="[$own, $foreign]"
st verify --project "$p2" --state "$s2" --core c7
expect "own and foreign sessions" 1 "FAIL verify: sessions left (in step 6's order: claude stop <id>, read its cost, delete its status file, claude rm <id>): #st1 lead: selftest c7 (a1), #st2 worker: PR (w1), probe: push (r1)"
expect "own and foreign sessions: another project's" 1 "SKIP foreign self-test session f1 ($(D "$tmp/other"))"
expect "own and foreign sessions: <root>-old" 1 "SKIP foreign self-test session f2 ($(D "$p2-old"))"
n=$((n + 1)); ! printf '%s\n' "$LAST" | grep -Eq 'session n1 |\(n1\)' || { echo "FAIL (own and foreign sessions): n1 is not a self-test session"; fail=1; }
export STUB_AGENTS_ALL="[$foreign]"
st verify --project "$p2" --state "$s2" --core c7
expect "only foreign sessions" 0 "PASS verify: no self-test session left"
expect "only foreign sessions" 0 "SKIP foreign self-test session f1 ($(D "$tmp/other"))"
expect "only foreign sessions" 0 "SKIP foreign self-test session f2 ($(D "$p2-old"))"
# the project given through a symlink (macOS: /tmp and /var are links), the session's cwd as it lies on
# disk, as a real session lists it: still the run's own, never a SKIP and a PASS
if [ -z "$win" ]; then
  ln -s "$p2" "$tmp/p2link"
  export STUB_AGENTS_ALL='[{"id":"a1","cwd":"'"$(J "$(cd -P "$p2" && pwd -P)")"'","name":"#st1 lead: selftest c7"}]'
  st verify --project "$tmp/p2link" --state "$tmp/p2link/coordinator" --core c7
  expect "the project through a symlink, the session's folder on disk" 1 "FAIL verify: sessions left (in step 6's order: claude stop <id>, read its cost, delete its status file, claude rm <id>): #st1 lead: selftest c7 (a1)"
fi
unset STUB_AGENTS STUB_AGENTS_ALL

echo "selftest prepare ($kind): $n checks, $( [ $fail = 0 ] && echo all pass || echo FAILURES )"
exit $fail
