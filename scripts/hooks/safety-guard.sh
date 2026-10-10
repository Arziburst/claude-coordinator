#!/usr/bin/env bash
# PreToolUse safety hook for coordinator projects (Bash / PowerShell tools).
# Reads the tool call JSON on stdin; exit 2 blocks the call and shows the reason to Claude.
# A safety net only — the real enforcement is branch protection on the code host (CORE §2).
# Extra project patterns (one extended regex per line, '#' comments): .claude/coordinator-deny.txt
# Self-test: scripts/hooks/safety-guard.sh --self-test   (prints to stdout so the session sees it)
# Works on macOS, Linux and Windows (Git Bash). Reference script — test it on each machine (TOOLKIT.md).

if [ "${1:-}" = "--self-test" ]; then
  out=$(printf '%s' '{"tool_input":{"command":"git push --force origin main"}}' | bash "$0" 2>/dev/null; echo $?)
  if [ "$out" = "2" ]; then echo "safety-guard: OK"; exit 0; fi
  echo "safety-guard: NOT WORKING — STOP: do not start workers until it is fixed (TOOLKIT.md)."
  exit 0   # stdout reaches the session's context; a non-zero exit would only show it to the user
fi

input="$(cat)"

# Extract tool_input.command and cwd (jq if present, otherwise a best-effort sed).
if command -v jq >/dev/null 2>&1; then
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
else
  cmd=$(printf '%s' "$input" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(\([^"\\]\|\\.\)*\)".*/\1/p' | sed 's/\\"/"/g')
  cmd="${cmd//\\n/$'\n'}"; cmd="${cmd//\\\\/\\}"
  cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi
# Drop comment lines (a "#" at the start of a line) so mentions in comments do not trigger.
cmd=$(printf '%s\n' "$cmd" | grep -Ev '^[[:space:]]*#')
[ -z "$cmd" ] && exit 0

block() {
  echo "Blocked by safety-guard: $1. If this is a false positive, ask the owner." >&2
  exit 2
}
has() { printf '%s' "$cmd" | grep -Eiq -- "$1"; }
has_cs() { printf '%s' "$cmd" | grep -Eq -- "$1"; }   # case-sensitive (e.g. -D vs -d)

PROTECTED='(main|master)'
# "git" as a command word: plain, quoted, with a path, .exe, any case.
GITCMD='["'"'"']?([^[:space:]"'"'"']*[/\\])?git(\.exe)?["'"'"']?'
GIT="(^|[^[:alnum:]_.-])${GITCMD}"

current_branch() {
  local dir="${cwd:-${CLAUDE_PROJECT_DIR:-.}}"
  git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null
}
on_protected() { current_branch | grep -Eiq "^${PROTECTED}$"; }

# --- git push: force, protected targets, pushes resolving to the current (protected) branch ---
# Split on separators (incl. inside bash -c "..."), then inspect each segment that runs git ... push.
# A command substitution leaves a "$SUBST" marker (it resolves to an unknown ref → treated as the
# current branch) and its inner command becomes a segment of its own.
# Pure bash splitting (portable: GNU and BSD/macOS sed differ on "\n" in replacements).
nl=$'\n'
s="$cmd"
s="${s//\$(/\$SUBST$nl}"; s="${s//\`/\$SUBST$nl}"
s="${s//&&/$nl}"; s="${s//||/$nl}"; s="${s//;/$nl}"; s="${s//|/$nl}"
# "bash -c '...'" / "pwsh -c ..." — the inner command starts its own segment
segments=$(printf '%s\n' "$s" | sed -E 's/^[[:space:]]*(bash|sh|zsh|pwsh|powershell)(\.exe)?[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*-[cC](ommand)?[[:space:]]+//')
while IFS= read -r seg; do
  # git must be the segment's command (optionally after env assignments or PowerShell's "&"),
  # so a mention inside a commit message, a PR body or an echo does not count.
  printf '%s' "$seg" | grep -Eiq "^[[:space:]]*(&[[:space:]]*)?([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*${GITCMD}([[:space:]]+(-c[[:space:]]+[^[:space:]]+|-C[[:space:]]+[^[:space:]]+|--[a-z-]+(=[^[:space:]]+)?))*[[:space:]]+push([[:space:]]|\$|[\"'])" || continue
  rest=$(printf '%s' "$seg" | sed -E 's/.*[[:space:]][Pp][Uu][Ss][Hh]([[:space:]]|$)//')
  # Work branches may be pushed, force-pushed (e.g. after a rebase) and deleted freely;
  # only the protected branches are guarded.
  refspecs=0; remote_seen=0; to_current=0
  for tok in $rest; do
    t=$(printf '%s' "$tok" | sed -E "s/^[\"'(]+//; s/[\"')]+$//")
    case "$t" in
      --mirror) block "mirror push (overwrites every branch, incl. protected ones)" ;;
      --*|-*) continue ;;
    esac
    if [ "$remote_seen" = 0 ]; then remote_seen=1; continue; fi
    refspecs=$((refspecs+1))
    printf '%s' "$t" | grep -Eiq "^\+?(refs/heads/)?([^:]*:)?(refs/heads/)?${PROTECTED}$" && block "push to a protected branch"
    # HEAD, @, variables or command substitutions resolve to the current branch
    printf '%s' "$t" | grep -Eq '^(HEAD|@|\$.*|.*\$\(.*|.*`.*)(:.*)?$' && to_current=1
  done
  if [ "$refspecs" = 0 ] || [ "$to_current" = 1 ]; then
    on_protected && block "push while on $(current_branch)"
  fi
done <<EOF
$segments
EOF

# Routine work-branch operations (reset, restore, amend, rebase, stash, deleting a work branch) are
# allowed: they are reversible and part of normal work (CORE §1.9). Only protected branches are guarded.
has_cs "${GIT}[^;&|]*[[:space:]]branch[[:space:]]+(-D|-d|--delete)([[:space:]]+-f)?[[:space:]]+${PROTECTED}([[:space:]]|$)" && block "deleting a protected branch"
# --- irreversible removals ---
has 'rm[[:space:]]+-[a-z]*r[a-z]*[[:space:]]+["'"'"']?(/|~/?|\$HOME/?|\$\{HOME\}/?|/\*)["'"'"']?([[:space:]]|$)' && block "recursive removal of / or home"
has 'rm[[:space:]]+-[a-z]*r[a-z]*[[:space:]]+[^;&|]*\.claude/worktrees(/[^/[:space:]"'"'"']+)?/?["'"'"']?([[:space:]]|$)' && block "removing a worktree by hand (use the cleanup script)"
has 'Remove-Item[^;|]*[[:space:]]["'"'"']?(C:\\?|\$HOME|~)["'"'"']?([[:space:]][^;|]*)?-Recurse' && block "recursive removal of a drive or home"
has 'Remove-Item[^;|]*-Recurse[^;|]*[[:space:]]["'"'"']?(C:\\?|\$HOME|~)["'"'"']?([[:space:]]|$)' && block "recursive removal of a drive or home"

# --- project-specific patterns ---
deny_file="${CLAUDE_PROJECT_DIR:-.}/.claude/coordinator-deny.txt"
if [ -f "$deny_file" ]; then
  while IFS= read -r pattern || [ -n "$pattern" ]; do
    case "$pattern" in ''|'#'*) continue ;; esac
    has "$pattern" && block "project rule: $pattern"
  done < "$deny_file"
fi

exit 0
