#!/usr/bin/env bash
# COORD_NO_PUSH (#367): the cases of tests/safety-guard/no-push.txt against a safety hook. run.sh runs this
# file too; alone it takes seconds, where the whole set takes minutes.
#   tests/safety-guard/no-push.sh bash scripts/hooks/safety-guard.sh
#   tests/safety-guard/no-push.sh powershell -NoProfile -ExecutionPolicy Bypass -File scripts/hooks/safety-guard.ps1   (the shim, #564)
# Exit 1 if any check fails.
#
# The access points the guard implements as written:
#   - the setting is the environment variable COORD_NO_PUSH of the hook's process. The value 1 turns every
#     push off; any other value, empty or unset leaves today's verdicts;
#   - a call the setting blocks exits 2, with the word COORD_NO_PUSH on stderr, also when the push's target
#     is a protected branch; with the setting off no message names it;
#   - the self-test (--self-test / -SelfTest) prints safety-guard: OK, exit 0, with COORD_NO_PUSH=1 in its
#     environment.
set -u
[ $# -gt 0 ] || { sed -n '2,6s/^# \{0,1\}//p' "$0"; exit 2; }
unset COORD_NO_PUSH COORD_PROTECTED_ROOT COORD_PROTECTED_BRANCHES COORD_ASSISTANT_DIR
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -r "$tmp"' EXIT
fail=0; n=0; cr="$(printf '\r')"; tab="$(printf '\t')"
# the cwd of every case: a repository on the work branch, with 12-fix and main beside it
r="$tmp/work"
git init -q -b work "$r" && git -C "$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init &&
  git -C "$r" branch main && git -C "$r" branch 12-fix || { echo "FAIL (no-push) could not make the repository"; exit 1; }
d="$r"; command -v cygpath >/dev/null 2>&1 && d="$(cygpath -m "$r")"
CMD=("$@")
cutl() { local l; while IFS= read -r l || [ -n "$l" ]; do printf '%s\n' "$1${l:0:200}"; done; }   # as run.sh's (#650): stdin's lines after the prefix, each cut at 200 characters

# one <expect> <value, or the word UNSET> <tool> <command>: \n in the command is a newline
one() {
  local expect="$1" val="$2" tool="$3" cmd="$4" json err rc got
  n=$((n + 1))
  json="$(printf '%s' "$cmd" | awk -v cwd="$d" -v tool="$tool" '
    { gsub(/\\n/, "\001"); gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\001/, "\\n")
      printf "{\"tool_name\":\"%s\",\"tool_input\":{\"command\":\"%s\"},\"cwd\":\"%s\"}", tool, $0, cwd }')"
  if [ "$val" = UNSET ]; then   # #662: in this shell, not in $(...): the shell's report of a signal goes to e.sig (bash 3.2 gives none in $(...))
    printf '%s' "$json" | CLAUDE_PROJECT_DIR="$d" "${CMD[@]}" >/dev/null 2>"$tmp/e"
  else
    printf '%s' "$json" | CLAUDE_PROJECT_DIR="$d" COORD_NO_PUSH="$val" "${CMD[@]}" >/dev/null 2>"$tmp/e"
  fi 2>"$tmp/e.sig"; rc=$?; err="$(cat "$tmp/e")"
  case "$rc" in 0) got=allow ;; 2) got=block ;; *) got=error ;; esac
  [ "$got" = "$expect" ] || { echo "FAIL (no-push, $tool, COORD_NO_PUSH=$val) expected $expect, got $got (exit $rc): $cmd"; { head -n 20 "$tmp/e"; head -n 5 "$tmp/e.sig"; } | cutl "    "; fail=1; return; }
  [ "$got" = block ] || return
  case "$err" in
    *COORD_NO_PUSH*) [ "$val" = 1 ] || { echo "FAIL (no-push, $tool, COORD_NO_PUSH=$val) the setting is off, the message names it: $cmd: $err"; fail=1; } ;;
    *) [ "$val" != 1 ] || { echo "FAIL (no-push, $tool, COORD_NO_PUSH=$val) the message does not name COORD_NO_PUSH: $cmd: $err"; fail=1; } ;;
  esac
}
while IFS="$tab" read -r on off tool cmd; do
  case "$on" in ''|'#'*) continue ;; esac
  cmd="${cmd%"$cr"}"
  one "$on" 1 "$tool" "$cmd"
  one "$off" 0 "$tool" "$cmd"
done < "$here/no-push.txt"

# any value but 1 is off: a push to a work branch passes, a push to main is blocked as it always was
for v in UNSET '' true yes on 01 2; do
  one allow "$v" Bash "git push origin 12-fix"
  one block "$v" Bash "git push origin main"
done

# the guard's own self-test, in a session whose settings turn pushes off
for a in "$@"; do guard="$a"; done
case "$guard" in *.sh) flag=--self-test ;; *.ps1) flag=-SelfTest ;; *) flag="" ;; esac
if [ -n "$flag" ]; then
  n=$((n + 1))
  { COORD_NO_PUSH=1 "$@" "$flag" < /dev/null > "$tmp/out" 2>"$tmp/e"; } 2>"$tmp/e.sig"; rc=$?; out="$(tr -d '\r' < "$tmp/out")"   # #662: stdin from /dev/null
  [ "$out" = "safety-guard: OK" ] && [ "$rc" = 0 ] || { echo "FAIL (no-push self-test) with COORD_NO_PUSH=1 expected OK (exit 0), got (exit $rc): $out"; { head -n 20 "$tmp/e"; head -n 5 "$tmp/e.sig"; } | cutl "    "; fail=1; }
fi
echo "safety-guard no-push: $n checks, $( [ $fail = 0 ] && echo all pass || echo FAILURES )"
exit $fail
