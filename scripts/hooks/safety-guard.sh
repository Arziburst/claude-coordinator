#!/usr/bin/env bash
# PreToolUse safety hook for coordinator projects (Bash / PowerShell tools).
# Reads the tool call JSON on stdin; exit 2 blocks the call and shows the reason to Claude.
# A safety net only — the real enforcement is branch protection on the code host (CORE §2).
# Extra project patterns (one extended regex per line, '#' comments): .claude/coordinator-deny.txt
# Self-test: scripts/hooks/safety-guard.sh --self-test   (exit 0 = working)
# Works on macOS, Linux and Windows (Git Bash). Reference script — test it on each machine (TOOLKIT.md).

if [ "${1:-}" = "--self-test" ]; then
  out=$(printf '%s' '{"tool_input":{"command":"git push --force origin x"}}' | bash "$0" 2>/dev/null; echo $?)
  if [ "$out" = "2" ]; then echo "safety-guard: OK"; exit 0; fi
  echo "safety-guard: NOT WORKING — fix before running workers" >&2; exit 1
fi

input="$(cat)"

# Extract tool_input.command and cwd (jq if present, otherwise a best-effort sed).
if command -v jq >/dev/null 2>&1; then
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
else
  cmd=$(printf '%s' "$input" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(\([^"\\]\|\\.\)*\)".*/\1/p' | sed 's/\\n/\n/g; s/\\"/"/g; s/\\\\/\\/g')
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

# --- git push: force, protected targets, bare push from a protected branch ---
# Split on command separators and inspect each git push segment token by token.
while IFS= read -r seg; do
  printf '%s' "$seg" | grep -Eq '(^|[[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push([[:space:]]|$)' || continue
  rest=$(printf '%s' "$seg" | sed -E 's/.*[[:space:]]push([[:space:]]|$)//')
  refspecs=0; remote_seen=0
  for tok in $rest; do
    t=$(printf '%s' "$tok" | sed -E "s/^[\"']//; s/[\"']$//")
    case "$t" in
      --force|--force-with-lease*|--force-if-includes|-f|--mirror|--delete|-d) block "force / mirror / delete push" ;;
      --*|-*) continue ;;
    esac
    if [ "$remote_seen" = 0 ]; then remote_seen=1; continue; fi
    refspecs=$((refspecs+1))
    case "$t" in +*) block "force-push (+refspec)" ;; esac
    printf '%s' "$t" | grep -Eiq "^(refs/heads/)?([^:]*:)?(refs/heads/)?${PROTECTED}$" && block "push to a protected branch"
  done
  if [ "$refspecs" = 0 ]; then
    dir="${cwd:-${CLAUDE_PROJECT_DIR:-.}}"
    branch=$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null)
    printf '%s' "$branch" | grep -Eiq "^${PROTECTED}$" && block "push while on $branch"
  fi
done <<EOF
$(printf '%s' "$cmd" | sed -E 's/(&&|\|\||;|\|)/\n/g')
EOF

# --- discarding work, rewriting history, deleting branches ---
has 'git([^;&|]*)[[:space:]](reset[[:space:]]+--hard|clean[[:space:]]+-[a-z]*f|filter-branch|filter-repo)' && block "discarding work or rewriting history"
has 'git([^;&|]*)[[:space:]]checkout[[:space:]]+(-f[[:space:]]+)?--[[:space:]]+\.' && block "discarding uncommitted changes"
has 'git([^;&|]*)[[:space:]]restore([[:space:]]+--worktree)?[[:space:]]+\.' && block "discarding uncommitted changes"
has 'git([^;&|]*)[[:space:]]stash[[:space:]]+(drop|clear)' && block "dropping stashed work"
has_cs 'git([^;&|]*)[[:space:]]branch[[:space:]]+(-D|--delete[[:space:]]+--force)' && block "force-deleting a branch"
# --- destructive removals ---
has 'rm[[:space:]]+-[a-z]*r[a-z]*[[:space:]]+(/|~|\$HOME|/\*)([[:space:]]|$)' && block "recursive removal of / or home"
has 'rm[[:space:]]+-[a-z]*r[a-z]*[[:space:]]+[^;&|]*\.claude/worktrees' && block "removing worktrees by hand (use the cleanup script)"
has 'Remove-Item[^;|]*-Recurse[^;|]*[[:space:]](C:\\|\$HOME|~)([[:space:]]|$)' && block "recursive removal of a drive or home"

# --- project-specific patterns ---
deny_file="${CLAUDE_PROJECT_DIR:-.}/.claude/coordinator-deny.txt"
if [ -f "$deny_file" ]; then
  while IFS= read -r pattern || [ -n "$pattern" ]; do
    case "$pattern" in ''|'#'*) continue ;; esac
    has "$pattern" && block "project rule: $pattern"
  done < "$deny_file"
fi

exit 0
