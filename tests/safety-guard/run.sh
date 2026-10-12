#!/usr/bin/env bash
# Run tests/safety-guard/cases.txt against a safety hook (macOS / Linux; Windows: run.ps1).
#   tests/safety-guard/run.sh bash scripts/hooks/safety-guard.sh
#   tests/safety-guard/run.sh pwsh -NoProfile -File scripts/hooks/safety-guard.ps1
# Exit 1 if any verdict differs from the expected one.
set -u
[ $# -gt 0 ] || { sed -n '2,5s/^# \{0,1\}//p' "$0"; exit 2; }
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
for b in main work; do
  git init -q -b "$b" "$tmp/$b" && git -C "$tmp/$b" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  mkdir -p "$tmp/$b/.claude" && printf '# a project rule\nterraform[[:space:]]+destroy\n' > "$tmp/$b/.claude/coordinator-deny.txt"
done
fail=0; n=0
while IFS="$(printf '\t')" read -r expect branch cmd; do
  case "$expect" in ''|'#'*) continue ;; esac
  n=$((n + 1))
  dir="$tmp/$branch"; command -v cygpath >/dev/null 2>&1 && dir="$(cygpath -m "$dir")"   # Git Bash -> C:/...
  json="$(printf '%s' "$cmd" | awk -v cwd="$dir" '
    { gsub(/\\n/, "\001"); gsub(/\\t/, "\002"); gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\001/, "\\n"); gsub(/\002/, "\\t")
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
raw block "truncated JSON" '{"tool_input":{"command":"ls"'
raw block "no input" ''
raw allow "a tool call without a command" '{"tool_name":"Read","tool_input":{"file_path":"x"}}'
echo "safety-guard cases: $n, $( [ $fail = 0 ] && echo all pass || echo FAILURES )"
exit $fail
