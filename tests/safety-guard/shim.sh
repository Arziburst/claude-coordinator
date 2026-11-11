#!/usr/bin/env bash
# #564: scripts/hooks/safety-guard.ps1, the shim an older Windows settings file still names, against safety-guard.sh it
# hands each call to: the same stdout, stderr bytes and exit code; its self-test; closed when it cannot run (no Git Bash,
# no .sh beside it). The whole case set through the shim: tests/safety-guard/run.sh <the shim's command>.
#   tests/safety-guard/shim.sh powershell      (or pwsh)
set -u
[ $# -eq 1 ] || { sed -n '2,5s/^# \{0,1\}//p' "$0"; exit 2; }
ps="$1"; here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
unset COORD_PROTECTED_ROOT COORD_PROTECTED_BRANCHES COORD_ASSISTANT_DIR COORD_NO_PUSH CLAUDE_CODE_GIT_BASH_PATH
m() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
shim() { local f="$1"; shift; "$ps" -NoProfile -ExecutionPolicy Bypass -File "$(m "$f")" "$@"; }
fail=0; n=0; bad() { echo "FAIL (shim) $1"; fail=1; }
S="$core/scripts/hooks/safety-guard.ps1"
# a project folder with non-ASCII letters, as the owner's working copy may have
pr="$tmp/Üд proj"; mkdir -p "$pr/src"; prm="$(m "$pr")"
same() {   # same <what> <expected exit> <payload> [<env>...]: the shim and the .sh give the same bytes and exit code
  n=$((n + 1)); printf '%s' "$3" > "$tmp/in"; local w="$1" x="$2"; shift 3
  env "$@" "$ps" -NoProfile -ExecutionPolicy Bypass -File "$(m "$S")" < "$tmp/in" > "$tmp/o1" 2> "$tmp/e1"; r1=$?
  env "$@" bash "$core/scripts/hooks/safety-guard.sh" < "$tmp/in" > "$tmp/o2" 2> "$tmp/e2"; r2=$?
  [ "$r1" = "$x" ] && [ "$r2" = "$x" ] || bad "$w: exit $r1 through the shim, $r2 from the .sh, expected $x"
  cmp -s "$tmp/o1" "$tmp/o2" && cmp -s "$tmp/e1" "$tmp/e2" || bad "$w: the output differs: $(head -c 300 "$tmp/e1") | $(head -c 300 "$tmp/e2")"
}
same "a push to main (Bash)" 2 '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}'
same "a push to master (PowerShell)" 2 '{"tool_name":"PowerShell","tool_input":{"command":"git push origin master"}}'
same "a work-branch push" 0 '{"tool_name":"Bash","tool_input":{"command":"git push -u origin 12-fix"}}'
same "not a JSON object" 2 'not json'
same "a write in a non-ASCII working copy" 2 "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$prm/src/ä.txt\",\"content\":\"x\"},\"cwd\":\"$prm\"}" COORD_PROTECTED_ROOT="$prm"
same "a write in its worktree" 0 "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$prm/.claude/worktrees/1-a/ä.txt\",\"content\":\"x\"},\"cwd\":\"$prm\"}" COORD_PROTECTED_ROOT="$prm"
n=$((n + 1)); out="$(shim "$S" -SelfTest | tr -d '\r')"; [ "$out" = "safety-guard: OK" ] || bad "self-test: $out"
# closed when it cannot run: the shim alone, no .sh beside it
mkdir -p "$tmp/alone"; cp "$S" "$tmp/alone/"; printf '%s' '{"tool_input":{"command":"ls"}}' > "$tmp/in"
n=$((n + 1)); shim "$tmp/alone/safety-guard.ps1" < "$tmp/in" > /dev/null 2> "$tmp/e1"; r=$?
[ "$r" = 2 ] && grep -q '^Blocked by safety-guard: the guard cannot run (no ' "$tmp/e1" || bad "no .sh beside it: exit $r, $(head -c 200 "$tmp/e1")"
n=$((n + 1)); out="$(shim "$tmp/alone/safety-guard.ps1" -SelfTest | tr -d '\r')"; case "$out" in "safety-guard: NOT WORKING"*) ;; *) bad "no .sh, self-test: $out" ;; esac
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*)
  # no bash and no git on PATH (System32 keeps WSL's bash.exe, which the shim never takes): closed; git alone: its Git Bash
  psd="$(dirname "$(command -v "$ps")")"; sys="$(cygpath -u "${SYSTEMROOT:-C:/Windows}")/System32"
  n=$((n + 1)); PATH="$psd:$sys" shim "$S" < "$tmp/in" > /dev/null 2> "$tmp/e1"; r=$?
  [ "$r" = 2 ] && grep -q '^Blocked by safety-guard: the guard cannot run (no Git Bash found' "$tmp/e1" || bad "no bash on PATH: exit $r, $(head -c 200 "$tmp/e1")"
  n=$((n + 1)); out="$(PATH="$psd:$sys" shim "$S" -SelfTest | tr -d '\r')"; case "$out" in "safety-guard: NOT WORKING"*) ;; *) bad "no bash, self-test: $out" ;; esac
  printf '%s' '{"tool_input":{"command":"git push origin main"}}' > "$tmp/in"
  n=$((n + 1)); PATH="$psd:$sys:$(dirname "$(command -v git)")" shim "$S" < "$tmp/in" > /dev/null 2> "$tmp/e1"; r=$?
  [ "$r" = 2 ] && grep -q '^Blocked by safety-guard: push to a protected branch (main)' "$tmp/e1" || bad "git alone on PATH: exit $r, $(head -c 200 "$tmp/e1")" ;;
esac
echo "safety-guard shim: $n checks, $( [ $fail = 0 ] && echo all pass || echo FAILURES )"
exit $fail
