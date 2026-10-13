#!/usr/bin/env bash
# Run tests/safety-guard/cases.txt against a safety hook (macOS / Linux; Windows: run.ps1).
#   tests/safety-guard/run.sh bash scripts/hooks/safety-guard.sh
#   tests/safety-guard/run.sh pwsh -NoProfile -File scripts/hooks/safety-guard.ps1
# Exit 1 if any verdict differs from the expected one.
set -u
[ $# -gt 0 ] || { sed -n '2,5s/^# \{0,1\}//p' "$0"; exit 2; }
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
acl=""   # a deny file whose read an NTFS permission denies (Git Bash): the permission is taken back first
finish() { [ -z "$acl" ] || MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' icacls "$acl" /remove:d "${USERNAME:-}" >/dev/null 2>&1; rm -rf "$tmp"; }
trap finish EXIT
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -"$1" "$2"; else printf '%s' "$2"; fi; }   # Git Bash -> C:/... or C:\...
# The cwd repositories: main and work (that branch checked out; in each, the branch before it is the
# other kind: 12-fix before main, main before work, for git checkout -), and on work with other deny
# files: crlf (saved with CRLF), blank (blank and whitespace-only lines), bad (a pattern that cannot be read),
# bom (saved with a UTF-8 BOM), utf16 (UTF-16 with its BOM, as Windows PowerShell 5.1's > writes it),
# utf16nul (UTF-16 without a BOM: NUL bytes).
for b in main work crlf blank bad bom utf16 utf16nul; do
  r="$tmp/$b"; br=$b; [ "$b" = main ] || br=work
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
# home in its forms, for the cases: @HOME@ as the shell has it, @HOME_M@ C:/Users/x, @HOME_W@ C:\Users\x
# (the same as @HOME@ where there is no cygpath); @PROJECT@ the project's folder (C:/... in Git Bash)
export SG_HOME="$HOME" SG_HOME_M="$(winpath m "$HOME")" SG_HOME_W="$(winpath w "$HOME")"
fail=0; n=0
while IFS="$(printf '\t')" read -r expect branch cmd; do
  case "$expect" in ''|'#'*) continue ;; esac
  n=$((n + 1))
  # the branch column: [ps:]<cwd under the temporary folder>; ps: is a PowerShell tool call, the project
  # (CLAUDE_PROJECT_DIR) is the cwd's first folder
  tool=Bash; case "$branch" in ps:*) tool=PowerShell; branch="${branch#ps:}" ;; esac
  dir="$(winpath m "$tmp/$branch")"; export SG_PROJECT="$(winpath m "$tmp/${branch%%/*}")"
  json="$(printf '%s' "$cmd" | awk -v cwd="$dir" -v tool="$tool" '
    function rep(s, from, to,    k, o) { o = ""; while ((k = index(s, from)) > 0) { o = o substr(s, 1, k - 1) to; s = substr(s, k + length(from)) }; return o s }
    { gsub(/\\n/, "\001"); gsub(/\\t/, "\002")
      $0 = rep($0, "@HOME_M@", ENVIRON["SG_HOME_M"]); $0 = rep($0, "@HOME_W@", ENVIRON["SG_HOME_W"]); $0 = rep($0, "@HOME@", ENVIRON["SG_HOME"])
      $0 = rep($0, "@PROJECT@", ENVIRON["SG_PROJECT"])
      gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\001/, "\\n"); gsub(/\002/, "\\t")
      printf "{\"tool_name\":\"%s\",\"tool_input\":{\"command\":\"%s\"},\"cwd\":\"%s\"}", tool, $0, cwd }')"
  printf '%s' "$json" | CLAUDE_PROJECT_DIR="$SG_PROJECT" "$@" >/dev/null 2>&1
  rc=$?
  got=allow; [ "$rc" = 2 ] && got=block
  [ "$got" = "$expect" ] || { echo "FAIL ($tool, $branch) expected $expect, got $got (exit $rc): $cmd"; fail=1; }
done < "$here/cases.txt"

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
echo "safety-guard cases: $n, $( [ $fail = 0 ] && echo all pass || echo FAILURES )"
exit $fail
