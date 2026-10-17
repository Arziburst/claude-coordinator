#!/usr/bin/env bash
# A SessionStart hook for the "compact" source: right after Claude Code compacts a conversation, it puts
# one instruction into the session's context - re-read the files that define its job, in full, from disk,
# before the next step: what the session knew is now a summary, and a summary loses rules and state.
#   bash scripts/hooks/after-compact.sh coordinator|worker      (reads the hook's JSON on stdin)
# worker: the brief start-worker saved for this session, <config>/coordinator/briefs/<session_id>.md
# (<config> = $CLAUDE_CONFIG_DIR, else ~/.claude); without one, its role file and the contract in its brief.
# coordinator: coordinator/core/CORE.md (section 1 first), PROJECT.md, BINDINGS.md and LOG.md's open
# questions under the session's folder, then the running sessions and the open PRs.
# Prints {"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"..."}} (plain stdout
# does not reach the model), always exits 0. Windows: after-compact.ps1, the same text.
role="${1:-}"
case "$role" in coordinator|worker) ;; *) echo "usage: after-compact.sh coordinator|worker" >&2; exit 0 ;; esac
in="$(cat 2>/dev/null)"
str() { printf '%s' "$in" | tr -d '\r\n' | sed -n "s/.*\"$1\" *: *\"\\([^\"]*\\)\".*/\\1/p"; }
sid="$(str session_id)"; cwd="$(str cwd | sed 's/\\\\/\\/g')"
cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
lead="The conversation was just compacted: what you knew is now a summary, and a summary loses rules and state."
if [ "$role" = worker ]; then
  b=""; case "$sid" in *[!0-9a-fA-F-]*|"") ;; *) [ -f "$cfg/coordinator/briefs/$sid.md" ] && b="$cfg/coordinator/briefs/$sid.md" ;; esac
  command -v cygpath >/dev/null 2>&1 && [ -n "$b" ] && b="$(cygpath -m "$b")"
  if [ -n "$b" ]; then
    msg="$lead Before your next step, read your brief in full with the Read tool: $b - your role, your contract with its criteria, non_goals and do_not_decide, and your report address. Then check your branch with git status and git log. Follow the brief as written, not the summary."
  else
    msg="$lead Before your next step, re-read your role file and the contract your brief gave (its criteria, non_goals and do_not_decide), then check your branch with git status and git log. Follow them as written, not the summary."
  fi
else
  p="${cwd:+$cwd/}coordinator"
  msg="$lead Before your next step, re-read in full with the Read tool: $p/core/CORE.md (section 1, the hard rules, first), $p/PROJECT.md, $p/BINDINGS.md and the open questions in $p/LOG.md. Then check the running sessions (claude agents --json) and the open PRs before acting. Act on the files, not on the summary."
fi
esc="$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g')"
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$esc"
exit 0
