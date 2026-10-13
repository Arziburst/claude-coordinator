#!/usr/bin/env bash
# Run tests/safety-guard/cases.txt against a safety hook (macOS / Linux; Windows: run.ps1).
#   tests/safety-guard/run.sh bash scripts/hooks/safety-guard.sh
#   tests/safety-guard/run.sh pwsh -NoProfile -File scripts/hooks/safety-guard.ps1
# Exit 1 if any verdict differs from the expected one.
set -u
[ $# -gt 0 ] || { sed -n '2,5s/^# \{0,1\}//p' "$0"; exit 2; }
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -"$1" "$2"; else printf '%s' "$2"; fi; }   # Git Bash -> C:/... or C:\...
# The cwd repositories: main and work (that branch checked out; in each, the branch before it is the
# other kind: 12-fix before main, main before work, for git checkout -), and on work with other deny
# files: crlf (saved with CRLF), blank (blank and whitespace-only lines), bad (a pattern that cannot be read).
for b in main work crlf blank bad; do
  r="$tmp/$b"; br=$b; [ "$b" = main ] || br=work
  git init -q -b "$br" "$r" && git -C "$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  before=main; [ "$br" = main ] && before=12-fix
  git -C "$r" branch "$before" && git -C "$r" checkout -q "$before" && git -C "$r" checkout -q "$br"
  mkdir -p "$r/.claude"
  case "$b" in
    crlf) printf '# a project rule\r\nterraform[[:space:]]+destroy\r\n' ;;
    blank) printf '# a project rule\n\n \n\t\n  # an indented comment\nterraform[[:space:]]+destroy\n' ;;
    bad) printf '# a project rule\nterraform(\n' ;;
    *) printf '# a project rule\nterraform[[:space:]]+destroy\n' ;;
  esac > "$r/.claude/coordinator-deny.txt"
done
# home in its forms, for the cases: @HOME@ as the shell has it, @HOME_M@ C:/Users/x, @HOME_W@ C:\Users\x
# (the same as @HOME@ where there is no cygpath)
export SG_HOME="$HOME" SG_HOME_M="$(winpath m "$HOME")" SG_HOME_W="$(winpath w "$HOME")"
fail=0; n=0
while IFS="$(printf '\t')" read -r expect branch cmd; do
  case "$expect" in ''|'#'*) continue ;; esac
  n=$((n + 1))
  dir="$(winpath m "$tmp/$branch")"
  json="$(printf '%s' "$cmd" | awk -v cwd="$dir" '
    function rep(s, from, to,    k, o) { o = ""; while ((k = index(s, from)) > 0) { o = o substr(s, 1, k - 1) to; s = substr(s, k + length(from)) }; return o s }
    { gsub(/\\n/, "\001"); gsub(/\\t/, "\002")
      $0 = rep($0, "@HOME_M@", ENVIRON["SG_HOME_M"]); $0 = rep($0, "@HOME_W@", ENVIRON["SG_HOME_W"]); $0 = rep($0, "@HOME@", ENVIRON["SG_HOME"])
      gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\001/, "\\n"); gsub(/\002/, "\\t")
      printf "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"%s\"},\"cwd\":\"%s\"}", $0, cwd }')"
  printf '%s' "$json" | CLAUDE_PROJECT_DIR="$dir" "$@" >/dev/null 2>&1
  rc=$?
  got=allow; [ "$rc" = 2 ] && got=block
  [ "$got" = "$expect" ] || { echo "FAIL ($branch) expected $expect, got $got (exit $rc): $cmd"; fail=1; }
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
