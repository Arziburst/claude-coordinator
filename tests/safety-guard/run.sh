#!/usr/bin/env bash
# Run tests/safety-guard/cases.txt against a safety hook (macOS / Linux; Windows: run.ps1).
#   tests/safety-guard/run.sh bash scripts/hooks/safety-guard.sh
#   tests/safety-guard/run.sh pwsh -NoProfile -File scripts/hooks/safety-guard.ps1
# Exit 1 if any verdict differs from the expected one. SG_JOBS=<n>: cases at once (default: the cores).
set -u
[ $# -gt 0 ] || { sed -n '2,5s/^# \{0,1\}//p' "$0"; exit 2; }
unset COORD_PROTECTED_ROOT COORD_PROTECTED_BRANCHES   # set per case (the 4th and 6th columns of cases.txt); empty is the same as unset
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
acl=""   # a deny file whose read an NTFS permission denies (Git Bash): the permission is taken back first
finish() { [ -z "$acl" ] || MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' icacls "$acl" /remove:d "${USERNAME:-}" >/dev/null 2>&1; rm -rf "$tmp"; }
trap finish EXIT
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -"$1" "$2"; else printf '%s' "$2"; fi; }   # Git Bash -> C:/... or C:\...
# The cwd repositories: main, work and dev (that branch checked out; in each, the branch before it is the
# other kind: 12-fix before main, main before work and dev, for git checkout -), and on work with other deny
# files: crlf (saved with CRLF), blank (blank and whitespace-only lines), bad (a pattern that cannot be read),
# bom (saved with a UTF-8 BOM), utf16 (UTF-16 with its BOM, as Windows PowerShell 5.1's > writes it),
# utf16nul (UTF-16 without a BOM: NUL bytes); Üw, a project with a non-ASCII letter in its name, on work.
for b in main work dev crlf blank bad bom utf16 utf16nul Üw; do
  r="$tmp/$b"; br=work; case "$b" in main|dev) br=$b ;; esac
  git init -q -b "$br" "$r" && git -C "$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  before=main; [ "$br" = main ] && before=12-fix
  git -C "$r" branch "$before" && git -C "$r" checkout -q "$before" && git -C "$r" checkout -q "$br"
  mkdir -p "$r/.claude"
  case "$b" in
    crlf) printf '# a project rule\r\nterraform[[:space:]]+destroy\r\n' ;;
    blank) printf '# a project rule\n\n \n\t\n  # an indented comment\nterraform[[:space:]]+destroy\n' ;;
    bad) printf '# a project rule\nterraform(\n' ;;
    bom) printf '\357\273\277terraform[[:space:]]+destroy\n# a project rule\n' ;;
    utf16) printf '\377\376t\000e\000r\000r\000a\000f\000o\000r\000m\000\n\000' ;;
    utf16nul) printf 't\000e\000r\000r\000a\000f\000o\000r\000m\000\n\000' ;;
    *) printf '# a project rule\nterraform[[:space:]]+destroy\n' ;;
  esac > "$r/.claude/coordinator-deny.txt"
done
# working folders inside a worktree of work (the cases name them in the branch column)
mkdir -p "$tmp/work/.claude/worktrees/12-fix/src"
fail=0; n=0; cr="$(printf '\r')"
# Links (a junction in Git Bash, which needs no admin rights; a symlink elsewhere): links/work to the
# project work (@LINK@), and inside work out-link to a folder outside it, dangling to a folder that is not
# there, loopa and loopb to each other.
mklinkdir() {   # mklinkdir <link> <target>
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' cmd /c mklink /J "$(winpath w "$1")" "$(winpath w "$2")" >/dev/null 2>&1 ;;
    *) ln -s "$2" "$1" ;;
  esac
  [ -L "$1" ] || { echo "FAIL (links) could not make the link $1"; fail=1; }
}
mkdir -p "$tmp/links" "$tmp/elsewhere/x"
mklinkdir "$tmp/links/work" "$tmp/work"
mklinkdir "$tmp/work/out-link" "$tmp/elsewhere"
mklinkdir "$tmp/work/dangling" "$tmp/gone"
mklinkdir "$tmp/work/loopa" "$tmp/work/loopb"
mklinkdir "$tmp/work/loopb" "$tmp/work/loopa"
export SG_LINK="$(winpath m "$tmp/links/work")" SG_LINK_W="$(winpath w "$tmp/links/work")"
# home in its forms, for the cases: @HOME@ as the shell has it, @HOME_M@ C:/Users/x, @HOME_W@ C:\Users\x
# (the same as @HOME@ where there is no cygpath); @PROJECT@ the project's folder (C:/... in Git Bash)
export SG_HOME="$HOME" SG_HOME_M="$(winpath m "$HOME")" SG_HOME_W="$(winpath w "$HOME")"
# Sessions (CORE §1.17): a stub claude first on PATH (claude.ps1 for PowerShell on Windows, handing over
# to it) prints $tmp/agents.json for `claude agents --json --all` and logs every call; SG_AGENTS_FAIL
# makes it fail. The listing, its folders as the real one gives them (as they lie on disk; on Windows
# C:\...): a0000001 in the project work, a0000002 in its worktree, a0000003 under work-wt (a worktree root
# that work/coordinator/PROJECT.md names), b0000001 in another folder, b0000002 in work-old (a folder
# whose name starts with the project's), b0000003 in another folder with a0000001's name.
mkdir -p "$tmp/bin" "$tmp/other" "$tmp/work-old" "$tmp/work-wt/14-x" "$tmp/work/coordinator"
# #263: linked, a linked worktree of work (detached); work-wt/14-x, a repository of its own (a main checkout)
# under that declared worktree root; work/.claude/worktrees/13-clone, one under work's worktrees' folder
# (work/.claude/worktrees/12-fix/src stays a plain folder of work)
git -C "$tmp/work" worktree add -q --detach "$tmp/linked" && git init -q "$tmp/work-wt/14-x" &&
  git init -q "$tmp/work/.claude/worktrees/13-clone" || { echo "FAIL (worktrees) could not make linked, work-wt/14-x or 13-clone"; fail=1; }
cat > "$tmp/bin/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SG_CLAUDE_LOG"
[ -z "${SG_AGENTS_FAIL:-}" ] || { echo "claude: cannot list the sessions" >&2; exit 1; }
[ "${1:-}" = agents ] && cat "$SG_AGENTS"
exit 0
EOF
printf '%s\n' "& bash (Join-Path \$PSScriptRoot 'claude') @args" 'exit $LASTEXITCODE' > "$tmp/bin/claude.ps1"
chmod +x "$tmp/bin/claude"
export PATH="$tmp/bin:$PATH" SG_AGENTS="$tmp/agents.json" SG_CLAUDE_LOG="$tmp/claude.log"
: > "$SG_CLAUDE_LOG"
printf '| Setting | This project |\n|---|---|\n| Worktree roots | `../work-wt` |\n' > "$tmp/work/coordinator/PROJECT.md"
native() { (cd -P -- "$1" && case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) pwd -W | tr '/' '\\' ;; *) pwd -P ;; esac); }
{
  printf '['
  k=0
  for s in "a0000001 work #12 worker: Fix" "a0000002 work/.claude/worktrees/12-fix #13 worker: Own" \
    "a0000003 work-wt/14-x #14 worker: Wt" "b0000001 other Other Coordinator" "b0000002 work-old #15 worker: Old" \
    "b0000003 other #12 worker: Fix"; do
    id="${s%% *}"; r="${s#* }"; d="${r%% *}"; nm="${r#* }"
    cw="$(native "$tmp/$d" | sed 's/\\/\\\\/g')"
    [ $k = 0 ] || printf ','
    k=1
    printf '\n  {\n    "id": "%s",\n    "cwd": "%s",\n    "kind": "background",\n    "startedAt": 1791042522505,\n    "sessionId": "%s-0000-4000-8000-000000000001",\n    "name": "%s",\n    "state": "done"\n  }' "$id" "$cw" "$id" "$nm"
  done
  # a0000004 in the project Üw, its folder written üw (one folder on NTFS and APFS; on Linux another one)
  cw="$(native "$tmp" | sed 's/\\/\\\\/g')"; case "$cw" in *\\*) cw="$cw\\\\üw" ;; *) cw="$cw/üw" ;; esac
  printf ',\n  {\n    "id": "a0000004",\n    "cwd": "%s",\n    "kind": "background",\n    "startedAt": 1791042522505,\n    "sessionId": "a0000004-0000-4000-8000-000000000001",\n    "name": "#16 worker: Fold",\n    "state": "done"\n  }' "$cw"
  printf '\n]\n'
} > "$SG_AGENTS"
# letter case in paths: ignored on Windows and macOS (the expectation "fold" is block there), kept on Linux;
# a non-ASCII letter's case too (fold8 block, own8 allow there; fold8 allow, own8 block on Linux)
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*|Darwin) fold=block fold8=block own8=allow ;; *) fold=allow fold8=allow own8=block ;; esac
# the cases' placeholders, replaced in the command and the COORD_PROTECTED_ROOT columns (after \n and \t
# are read, so a \t in a Windows path stays a backslash and a t)
SUBST_AWK='
function rep(s, from, to,    k, o) { o = ""; while ((k = index(s, from)) > 0) { o = o substr(s, 1, k - 1) to; s = substr(s, k + length(from)) }; return o s }
function subst(s) {
  s = rep(s, "@HOME_M@", ENVIRON["SG_HOME_M"]); s = rep(s, "@HOME_W@", ENVIRON["SG_HOME_W"]); s = rep(s, "@HOME@", ENVIRON["SG_HOME"])
  s = rep(s, "@PROJECT_W@", ENVIRON["SG_PROJECT_W"]); s = rep(s, "@PROJECT_UP@", ENVIRON["SG_PROJECT_UP"])
  s = rep(s, "@PROJECT_U@", ENVIRON["SG_PROJECT_U"]); s = rep(s, "@LINK_W@", ENVIRON["SG_LINK_W"])
  s = rep(s, "@PROJECT_UML@", ENVIRON["SG_PROJECT_UML"])
  s = rep(s, "@LINK@", ENVIRON["SG_LINK"]); return rep(s, "@PROJECT@", ENVIRON["SG_PROJECT"])
}'
# The cases run in parallel, each still through a process of the hook of its own: SG_JOBS shards at once
# (default: the machine's cores), shard k taking every SG_JOBS-th case from the k-th. A shard writes its FAIL
# lines keyed by the case's line in cases.txt (printed in that order, without the key) and then
# "<cases run> <fail> <cases in cases.txt>"; a shard that did not finish, or fewer cases run than
# cases.txt holds, is a failure.
CMD=("$@")
jobs="${SG_JOBS:-${NUMBER_OF_PROCESSORS:-}}"
[ -n "$jobs" ] || jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null)"
case "$jobs" in ''|*[!0-9]*|0) jobs=4 ;; esac
shard() {   # shard <k> <shards>
  local ln=0 i=0
  n=0 fail=0
while IFS="$(printf '\t')" read -r expect branch cmd root pdir pbr; do
  ln=$((ln + 1))
  case "$expect" in ''|'#'*) continue ;; esac
  i=$((i + 1)); [ $(((i - 1) % $2)) = "$1" ] || continue
  [ "$expect" = fold ] && expect=$fold
  [ "$expect" = fold8 ] && expect=$fold8; [ "$expect" = own8 ] && expect=$own8
  cmd="${cmd%"$cr"}"; root="${root%"$cr"}"; pdir="${pdir%"$cr"}"; pbr="${pbr%"$cr"}"   # a checkout with CRLF line ends
  [ "$pbr" = - ] && pbr=""   # the 6th column: COORD_PROTECTED_BRANCHES; none or -: unset (main master)
  n=$((n + 1))
  # the branch column: [ps:|edit:|write:|multiedit:|notebook:|send:]<cwd under the temporary folder>; ps: is a
  # PowerShell tool call, send: a SendMessage call to the command column, the others an edit tool's call with
  # the command column as its file path; the project (CLAUDE_PROJECT_DIR) is the cwd's first folder
  tool=Bash
  case "$branch" in
    ps:*) tool=PowerShell ;; edit:*) tool=Edit ;; write:*) tool=Write ;; multiedit:*) tool=MultiEdit ;; notebook:*) tool=NotebookEdit ;; send:*) tool=SendMessage ;;
  esac
  branch="${branch#*:}"
  dir="$(winpath m "$tmp/$branch")"; export SG_PROJECT="$(winpath m "$tmp/${branch%%/*}")"
  export SG_PROJECT_W="$(winpath w "$tmp/${branch%%/*}")"
  export SG_PROJECT_U="$(printf '%s' "$SG_PROJECT" | awk '/^[A-Za-z]:\// { $0 = "/" tolower(substr($0, 1, 1)) substr($0, 3) } { printf "%s", $0 }')"
  export SG_PROJECT_UP="$(printf '%s' "$SG_PROJECT" | tr '[:lower:]' '[:upper:]')"
  export SG_PROJECT_UML="$(printf '%s' "$SG_PROJECT" | sed 's/Ü/ü/g')"   # Üw written üw
  # the 4th column: COORD_PROTECTED_ROOT; for an edit tool @PROJECT@ when there is none, - for unset
  case "$tool" in Bash|PowerShell|SendMessage) ;; *) [ -n "$root" ] || root=@PROJECT@ ;; esac
  [ "$root" = - ] && root=""
  root="$(printf '%s' "$root" | awk "$SUBST_AWK"'
    { printf "%s", subst($0) }')"
  # the 5th column: CLAUDE_PROJECT_DIR; the project's folder when there is none, - for unset
  case "$pdir" in '') pdir="$SG_PROJECT" ;; -) pdir="" ;; *) pdir="$(printf '%s' "$pdir" | awk "$SUBST_AWK"'
    { printf "%s", subst($0) }')" ;; esac
  json="$(printf '%s' "$cmd" | awk -v cwd="$dir" -v tool="$tool" "$SUBST_AWK"'
    { gsub(/\\n/, "\001"); gsub(/\\t/, "\002"); $0 = subst($0)
      gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\001/, "\\n"); gsub(/\002/, "\\t")
      if (tool == "Edit") ti = "{\"file_path\":\"" $0 "\",\"old_string\":\"a\",\"new_string\":\"b\"}"
      else if (tool == "Write") ti = "{\"file_path\":\"" $0 "\",\"content\":\"x\"}"
      else if (tool == "MultiEdit") ti = "{\"file_path\":\"" $0 "\",\"edits\":[{\"old_string\":\"a\",\"new_string\":\"b\"}]}"
      else if (tool == "NotebookEdit") ti = "{\"notebook_path\":\"" $0 "\",\"new_source\":\"x\",\"cell_id\":\"c1\"}"
      else if (tool == "SendMessage") ti = "{\"to\":\"" $0 "\",\"message\":\"x\"}"
      else ti = "{\"command\":\"" $0 "\"}"
      printf "{\"tool_name\":\"%s\",\"tool_input\":%s,\"cwd\":\"%s\"}", tool, ti, cwd }')"
  printf '%s' "$json" | CLAUDE_PROJECT_DIR="$pdir" COORD_PROTECTED_ROOT="$root" COORD_PROTECTED_BRANCHES="$pbr" "${CMD[@]}" >/dev/null 2>&1
  rc=$?
  got=allow; [ "$rc" = 2 ] && got=block
  nop=""; [ -n "$pdir" ] || nop=", CLAUDE_PROJECT_DIR unset"
  [ "$got" = "$expect" ] || { echo "$ln FAIL ($tool, $branch${root:+, root $root}${pbr:+, protected $pbr}$nop) expected $expect, got $got (exit $rc): $cmd"; fail=1; }
done < "$here/cases.txt"
  echo "$n $fail $i" > "$tmp/shard.$1.done"
}
k=0
while [ $k -lt "$jobs" ]; do shard $k "$jobs" > "$tmp/shard.$k.out" 2>&1 & k=$((k + 1)); done
wait
ran=0; total=""; k=0
while [ $k -lt "$jobs" ]; do
  if [ -f "$tmp/shard.$k.done" ]; then
    read -r sn sf total < "$tmp/shard.$k.done"; ran=$((ran + sn)); [ "$sf" = 0 ] || fail=1
  else echo "FAIL (cases) shard $k of $jobs did not finish"; fail=1; fi
  k=$((k + 1))
done
cat "$tmp"/shard.*.out | sort -n -k1,1 | sed 's/^[0-9]* //'
[ -n "$total" ] && [ "$ran" = "$total" ] || { echo "FAIL (cases) $ran of ${total:-?} cases of cases.txt ran"; fail=1; }
n=$((n + ran))

# Sessions (CORE §1.17): a listing that cannot be read lets a call to another project's session through
# (nothing to tell it by); only the session commands and SendMessage run claude agents at all.
sess() {   # sess <expect> <what> <tool call JSON> [env assignments...]
  local expect="$1" what="$2" js="$3" rc got d; shift 3; n=$((n + 1)); d="$(winpath m "$tmp/work")"
  printf '%s' "$js" | sed "s#@CWD@#$d#" | env CLAUDE_PROJECT_DIR="$d" "$@" "${CMD[@]}" >/dev/null 2>&1; rc=$?
  got=allow; [ "$rc" = 2 ] && got=block
  [ "$got" = "$expect" ] || { echo "FAIL (sessions) expected $expect, got $got (exit $rc): $what"; fail=1; }
}
sess allow "the listing cannot be read: claude rm of another folder's session" '{"tool_name":"Bash","tool_input":{"command":"claude rm b0000001"},"cwd":"@CWD@"}' SG_AGENTS_FAIL=1
sess allow "the listing cannot be read: a message to another folder's session" '{"tool_name":"SendMessage","tool_input":{"to":"Other Coordinator","message":"x"},"cwd":"@CWD@"}' SG_AGENTS_FAIL=1
printf '[{"id": "b0000001", "cwd": ' > "$tmp/agents-bad.json"
sess allow "a listing cut short: claude rm of another folder's session" '{"tool_name":"Bash","tool_input":{"command":"claude rm b0000001"},"cwd":"@CWD@"}' SG_AGENTS="$tmp/agents-bad.json"
sess block "the listing read again: claude rm of another folder's session" '{"tool_name":"Bash","tool_input":{"command":"claude rm b0000001"},"cwd":"@CWD@"}'
# a listing that writes non-ASCII as \uXXXX: an own session in a Cyrillic folder of the project stays own,
# another project's session with a Cyrillic name is still found (the .sh decoded them as ?)
mkdir -p "$tmp/work/Проект"
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/Проект/\\u041f\\u0440\\u043e\\u0435\\u043a\\u0442/g; s/Координатор/\\u041a\\u043e\\u043e\\u0440\\u0434\\u0438\\u043d\\u0430\\u0442\\u043e\\u0440/g'; }
printf '[{"id": "c0000001", "cwd": "%s", "sessionId": "c0000001-0000-4000-8000-000000000001", "name": "own"},\n {"id": "c0000002", "cwd": "%s", "sessionId": "c0000002-0000-4000-8000-000000000001", "name": "%s"}]\n' \
  "$(esc "$(native "$tmp/work/Проект")")" "$(esc "$(native "$tmp/other")")" "$(esc "Координатор")" > "$tmp/agents-esc.json"
sess allow "an escaped Cyrillic folder of the project: own" '{"tool_name":"Bash","tool_input":{"command":"claude stop c0000001"},"cwd":"@CWD@"}' SG_AGENTS="$tmp/agents-esc.json"
sess block "an escaped Cyrillic name of another project's session" '{"tool_name":"SendMessage","tool_input":{"to":"Координатор","message":"x"},"cwd":"@CWD@"}' SG_AGENTS="$tmp/agents-esc.json"
# a line before the JSON (a notice) or a UTF-8 BOM: the listing is still read, by both versions
{ echo "Update available"; cat "$SG_AGENTS"; } > "$tmp/agents-notice.json"
{ printf '\357\273\277'; cat "$SG_AGENTS"; } > "$tmp/agents-bom.json"
sess block "a notice line before the listing" '{"tool_name":"Bash","tool_input":{"command":"claude stop b0000001"},"cwd":"@CWD@"}' SG_AGENTS="$tmp/agents-notice.json"
sess block "a BOM before the listing" '{"tool_name":"Bash","tool_input":{"command":"claude stop b0000001"},"cwd":"@CWD@"}' SG_AGENTS="$tmp/agents-bom.json"
: > "$SG_CLAUDE_LOG"
sess allow "a git command" '{"tool_name":"Bash","tool_input":{"command":"git status && claude --version"},"cwd":"@CWD@"}'
sess allow "an edit" '{"tool_name":"Write","tool_input":{"file_path":"x.txt","content":"x"},"cwd":"@CWD@"}'
n=$((n + 1))
[ -s "$SG_CLAUDE_LOG" ] && { echo "FAIL (sessions) claude was called for a call that names no session:"; sed 's/^/    /' "$SG_CLAUDE_LOG"; fail=1; }

# The input itself: a BOM before the JSON is read through; what is not a JSON object blocks.
raw() {   # raw <expect> <what> <stdin bytes, printf format>
  local expect="$1" what="$2" rc got; n=$((n + 1))
  printf "$3" | "${CMD[@]}" >/dev/null 2>&1; rc=$?
  got=allow; [ "$rc" = 2 ] && got=block
  [ "$got" = "$expect" ] || { echo "FAIL (input) expected $expect, got $got (exit $rc): $what"; fail=1; }
}
CMD=("$@")
raw block "a BOM, then a push to main" '\357\273\277{"tool_input":{"command":"git push origin main"}}'
raw allow "a BOM, then a push to a work branch" '\357\273\277{"tool_input":{"command":"git push origin 12-fix"}}'
raw block "not JSON" 'git push origin 12-fix'
raw block "not JSON inside braces" '{foo}'
raw block "truncated JSON" '{"tool_input":{"command":"ls"'
raw block "no input" ''
raw allow "a tool call without a command" '{"tool_name":"Read","tool_input":{"file_path":"x"}}'
# only tool_input's own "command" counts
raw block "a command key after tool_input" '{"tool_input":{"command":"git push origin main"},"tool_response":{"command":"ls"}}'
raw block "a nested command key inside tool_input" '{"tool_input":{"command":"git push origin main","x":{"command":"ls"}}}'
raw allow "a push to main under another key" '{"tool_input":{"command":"ls"},"tool_response":{"command":"git push origin main"}}'
raw allow "JSON with numbers, arrays and escapes" '{"a":[1,-2.5e3,true,null,{}],"tool_input":{"command":"echo \\"x\\" \\u0041","n":0}}'

# A deny file that is there but cannot be read blocks every call: a folder in its place, a file without
# read permission (not as root; in Git Bash an NTFS permission that denies the read, which [ -r ] does
# not see), a file in UTF-16 (with the message that says so).
denied() {   # denied <what> <project folder> [<text the message holds>]
  local rc got d err; n=$((n + 1)); d="$(winpath m "$2")"
  err="$(printf '{"tool_input":{"command":"ls"},"cwd":"%s"}' "$d" | CLAUDE_PROJECT_DIR="$d" "${CMD[@]}" 2>&1 >/dev/null)"; rc=$?
  got=allow; [ "$rc" = 2 ] && got=block
  [ "$got" = block ] || { echo "FAIL (deny file) expected block, got $got (exit $rc): $1"; fail=1; }
  [ -z "${3:-}" ] || case "$err" in *"$3"*) ;; *) echo "FAIL (deny file) the message lacks '$3': $1: $err"; fail=1 ;; esac
}
mkdir -p "$tmp/denydir/.claude/coordinator-deny.txt"
denied "a folder in place of the deny file" "$tmp/denydir"
denied "a deny file in UTF-16 with a BOM" "$tmp/utf16" "project rule file cannot be read: .claude/coordinator-deny.txt (not UTF-8: re-save it as UTF-8)"
denied "a deny file in UTF-16 without a BOM" "$tmp/utf16nul" "(not UTF-8: re-save it as UTF-8)"
# an empty file written by Windows PowerShell 5.1 (its BOM only, no NUL byte), and big-endian UTF-16
mkdir -p "$tmp/utf16empty/.claude" "$tmp/utf16be/.claude"
printf '\377\376' > "$tmp/utf16empty/.claude/coordinator-deny.txt"
printf '\376\377\000l\000s\000\n' > "$tmp/utf16be/.claude/coordinator-deny.txt"
denied "an empty deny file in UTF-16 (its BOM only)" "$tmp/utf16empty" "(not UTF-8: re-save it as UTF-8)"
denied "a deny file in big-endian UTF-16" "$tmp/utf16be" "(not UTF-8: re-save it as UTF-8)"
mkdir -p "$tmp/denyperm/.claude" && printf 'terraform\n' > "$tmp/denyperm/.claude/coordinator-deny.txt"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    acl="$(winpath w "$tmp/denyperm/.claude/coordinator-deny.txt")"
    if MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' icacls "$acl" /deny "${USERNAME:-}:(R)" >/dev/null 2>&1; then
      denied "a deny file whose read an NTFS permission denies" "$tmp/denyperm" "project rule file cannot be read"
    else echo "FAIL (deny file) icacls could not deny the read"; fail=1; fi
    MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' icacls "$acl" /remove:d "${USERNAME:-}" >/dev/null 2>&1 && acl="" ;;
  *)
    if [ "$(id -u)" != 0 ]; then
      chmod 000 "$tmp/denyperm/.claude/coordinator-deny.txt"
      denied "a deny file without read permission" "$tmp/denyperm" "project rule file cannot be read"
      chmod 644 "$tmp/denyperm/.claude/coordinator-deny.txt"
    fi ;;
esac

# The self-test's probe token (#259): a shell command holding the token of the project's
# .claude/coordinator-probe.txt (CLAUDE_PROJECT_DIR; its first line, 16+ letters, digits and -) is blocked,
# Bash and PowerShell alike; a short or garbled token, a token on a later line, a missing file, an edit
# tool's call, and a guard run without CLAUDE_PROJECT_DIR from another folder block nothing.
mkdir -p "$tmp/probe/.claude" "$tmp/probe-other"
pdm="$(winpath m "$tmp/probe")"
ABS=()   # the hook command with its script as an absolute path, run from another folder
for a in "$@"; do
  if [ -f "$a" ]; then ABS+=("$(winpath m "$(cd "$(dirname "$a")" && pwd)")/${a##*/}"); else ABS+=("$a"); fi
done
ptok() {   # ptok <expect> <what> <the file's bytes, printf format; - for no file> <tool> <command> [nopd]
  local expect="$1" what="$2" rc got err js; n=$((n + 1))
  rm -f "$tmp/probe/.claude/coordinator-probe.txt"
  [ "$3" = - ] || printf "$3" > "$tmp/probe/.claude/coordinator-probe.txt"
  case "$4" in
    Write) js="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"notes.txt\",\"content\":\"$5\"},\"cwd\":\"$pdm\"}" ;;
    *) js="{\"tool_name\":\"$4\",\"tool_input\":{\"command\":\"$5\"},\"cwd\":\"$pdm\"}" ;;
  esac
  if [ -z "${6:-}" ]; then err="$(printf '%s' "$js" | CLAUDE_PROJECT_DIR="$pdm" "${CMD[@]}" 2>&1 >/dev/null)"; rc=$?
  else err="$(cd "$tmp/probe-other" && printf '%s' "$js" | env -u CLAUDE_PROJECT_DIR "${ABS[@]}" 2>&1 >/dev/null)"; rc=$?; fi
  got=allow; [ "$rc" = 2 ] && got=block
  [ "$got" = "$expect" ] || { echo "FAIL (probe token) expected $expect, got $got (exit $rc): $what"; fail=1; return; }
  [ "$got" = allow ] || case "$err" in
    *"Blocked by safety-guard: the self-test's probe token (.claude/coordinator-probe.txt): this hook runs and its block holds."*) ;;
    *) echo "FAIL (probe token) the message is not the probe token's: $what: $err"; fail=1 ;;
  esac
}
tk=coord-probe-1791042522-4f1c2a9b7e3d
ptok block "the token in a Bash command" "$tk\n" Bash "echo $tk"
ptok block "the token in a PowerShell command" "$tk\n" PowerShell "echo $tk"
ptok block "the token in a file with CRLF" "$tk\r\n" Bash "echo $tk"
ptok block "the token inside a longer command" "$tk\n" Bash "cd x && echo before-$tk-after"
ptok block "a token of 16 characters" "abcdefghijklmnop\n" Bash "echo abcdefghijklmnop"
ptok block "a UTF-8 BOM before the token" "\357\273\277$tk\r\n" Bash "echo $tk"
ptok block "the token, then a second line (the run's timeout)" "$tk\n300\n" Bash "echo $tk"
ptok allow "a token-like second line" "$tk\ncoord-probe-second-line-0000\n" Bash "echo coord-probe-second-line-0000"
ptok allow "a command without the token" "$tk\n" Bash "echo coord-probe-0"
ptok allow "a token of 15 characters" "abcdefghijklmno\n" Bash "echo abcdefghijklmno"
ptok allow "a token with spaces" "coord probe 1791042522 4f1c\n" Bash "echo coord probe 1791042522 4f1c"
ptok allow "a token with an underscore" "coord_probe_1791042522_4f1c\n" Bash "echo coord_probe_1791042522_4f1c"
ptok allow "the token on the second line" "\n$tk\n" Bash "echo $tk"
ptok allow "no token file" - Bash "echo $tk"
ptok allow "an edit tool's call holding the token" "$tk\n" Write "$tk"
ptok allow "no CLAUDE_PROJECT_DIR, run from another folder" "$tk\n" Bash "echo $tk" nopd
rm -f "$tmp/probe/.claude/coordinator-probe.txt"

# The self-test: OK for this hook; not OK for a copy that blocks every call (as a bash syntax error does).
for a in "$@"; do guard="$a"; done
case "$guard" in *.sh) flag=--self-test; brk='fi' ;; *.ps1) flag=-SelfTest; brk='exit 2' ;; *) flag="" ;; esac
if [ -n "$flag" ]; then
  n=$((n + 1))
  out="$("$@" "$flag" 2>/dev/null | tr -d '\r')"
  [ "$out" = "safety-guard: OK" ] || { echo "FAIL (self-test) expected OK, got: $out"; fail=1; }
  n=$((n + 1))
  broken="$tmp/broken-guard.${guard##*.}"
  awk -v brk="$brk" '{ print } /^input="\$\(cat\)"/ || /^\$raw = \[Console\]::In\.ReadToEnd\(\)/ { print brk }' "$guard" > "$broken"
  B=(); k=0
  for a in "$@"; do k=$((k + 1)); [ $k -lt $# ] && B+=("$a"); done
  B+=("$(winpath m "$broken")")
  if [ "$(wc -l < "$broken")" -le "$(wc -l < "$guard")" ]; then echo "FAIL (self-test) could not build a broken copy of $guard"; fail=1
  else
    out="$("${B[@]}" "$flag" 2>/dev/null | tr -d '\r')"
    [ "$out" != "safety-guard: OK" ] || { echo "FAIL (self-test) a guard that blocks every call still says OK"; fail=1; }
  fi
fi
echo "safety-guard cases: $n (cases.txt: $ran of ${total:-?}, $jobs in parallel), $( [ $fail = 0 ] && echo all pass || echo FAILURES )"
exit $fail
