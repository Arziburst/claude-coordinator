#!/usr/bin/env bash
# PreToolUse safety hook for coordinator projects (Bash / PowerShell tools).
# Reads the tool call JSON on stdin; exit 2 blocks the call and shows the reason to Claude.
# Extra project patterns (one extended regex per line, '#' comments) go in .claude/coordinator-deny.txt.
# Works on macOS, Linux and Windows (Git Bash). Reference script — test it on each machine (TOOLKIT.md).
input="$(cat)"

block() {
  echo "Blocked by safety-guard: $1. If this is a false positive, ask the owner." >&2
  exit 2
}

check() { printf '%s' "$input" | grep -Eiq -- "$1"; }

# Force-push and pushes to protected branches
check 'git[^"]*[[:space:]]push[^"]*(--force|--force-with-lease|[[:space:]]-f([[:space:]"]|$))' && block "force-push"
check 'git[^"]*[[:space:]]push[^"]*[[:space:]](origin|upstream)[[:space:]]+(main|master)([[:space:]"]|$)' && block "push to a protected branch"
check 'git[^"]*[[:space:]]push[^"]*:(refs/heads/)?(main|master)([[:space:]"]|$)' && block "push to a protected branch"
# History rewrites and discarding work
check 'git[^"]*[[:space:]](reset[[:space:]]+--hard|clean[[:space:]]+-[a-z]*f|filter-branch|filter-repo)' && block "discarding work or rewriting history"
check 'git[^"]*[[:space:]]branch[[:space:]]+-D[[:space:]]+(main|master)([[:space:]"]|$)' && block "deleting a protected branch"
# Destructive file removal at the root or home
check 'rm[[:space:]]+-[a-z]*r[a-z]*[[:space:]]+(/|~|\$HOME|/\*)([[:space:]"]|$)' && block "recursive removal of / or home"
check 'Remove-Item[^"]*-Recurse[^"]*[[:space:]](C:\\\\|\$HOME|~)([[:space:]"]|$)' && block "recursive removal of a drive or home"

# Project-specific patterns
deny_file="${CLAUDE_PROJECT_DIR:-.}/.claude/coordinator-deny.txt"
if [ -f "$deny_file" ]; then
  while IFS= read -r pattern || [ -n "$pattern" ]; do
    case "$pattern" in ''|'#'*) continue ;; esac
    check "$pattern" && block "project rule: $pattern"
  done < "$deny_file"
fi

exit 0
