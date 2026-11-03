#!/usr/bin/env bash
# A SessionStart hook for the "compact" source: right after Claude Code compacts a conversation, it puts
# one instruction into the session's context - re-read the files that define its job, in full, from disk,
# before the next step: what the session knew is now a summary, and a summary loses rules and state.
#   bash scripts/hooks/after-compact.sh coordinator|worker|assistant      (reads the hook's JSON on stdin)
# worker: the brief start-worker saved for this session, <config>/coordinator/briefs/<session_id>.md
# (<config> = $CLAUDE_CONFIG_DIR, else ~/.claude); without one, its role file and the contract in its brief.
# assistant (#281): its own folder's BRIEF.md and NOTES.md (COORD_ASSISTANT_DIR) and the core's
# roles/assistant.md (the core this hook runs from) - never the kept brief, which an assistant outlives
# (pruned after 14 days); without COORD_ASSISTANT_DIR the same two files, their folder named unknown.
# coordinator: coordinator/core/CORE.md (section 1 first), PROJECT.md, BINDINGS.md and LOG.md's open
# questions under the session's folder, then the running sessions and the open PRs; silent in a session
# that is a worker (a kept brief, or a folder in .claude/worktrees) or an assistant (COORD_ASSISTANT_DIR
# set): the project's settings, where this variant sits, load in sessions launched from the same root
# too (#217). Then the checkpoint before-compact.sh wrote (coordinator/CHECKPOINT.md, #342), as it is, and a
# note when it is stale (written over 60 minutes ago, or no moment) or missing - a note, never a loss.
# Prints {"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"..."}} (plain stdout
# does not reach the model; at most 9600 bytes of text, then `truncated`), always exits 0. Windows: after-compact.ps1, the same text.
role="${1:-}"
case "$role" in coordinator|worker|assistant) ;; *) echo "usage: after-compact.sh coordinator|worker|assistant" >&2; exit 0 ;; esac
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
elif [ "$role" = assistant ]; then
  core="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)"
  command -v cygpath >/dev/null 2>&1 && core="$(cygpath -m "$core")"
  ad="${COORD_ASSISTANT_DIR:-}"
  if [ -n "$ad" ]; then
    command -v cygpath >/dev/null 2>&1 && ad="$(cygpath -m "$ad")"
    ad="$(printf '%s' "$ad" | tr '\\' '/')"
    while [ "${ad%/}" != "$ad" ] && [ "${ad%/}" != "" ]; do ad="${ad%/}"; done   # E:/a/ -> E:/a, never / -> ''
    msg="$lead Before your next step, read in full with the Read tool: $ad/BRIEF.md (your brief: your job, your limits, your report address), $ad/NOTES.md (your own notes) and $core/roles/assistant.md (your role). Follow them as written, not the summary."
  else
    msg="$lead Before your next step, read in full with the Read tool: BRIEF.md (your brief: your job, your limits, your report address) and NOTES.md (your own notes) in your own folder - its path is unknown here (COORD_ASSISTANT_DIR is not set): ask the owner for it - and $core/roles/assistant.md (your role). Follow them as written, not the summary."
  fi
else
  # the coordinator variant sits in the project's settings, which a worker or an assistant launched from
  # the same root loads too (#217): a session with a kept brief, working in a worktree, or with
  # COORD_ASSISTANT_DIR set is not this one
  [ -n "${COORD_ASSISTANT_DIR:-}" ] && exit 0
  b=""; case "$sid" in *[!0-9a-fA-F-]*|"") ;; *) b="$cfg/coordinator/briefs/$sid.md" ;; esac
  wd="$(printf '%s' "$cwd" | tr '\\' '/')"
  if { [ -n "$b" ] && [ -f "$b" ]; } || case "$wd" in */.claude/worktrees/*|*/.claude/worktrees) true ;; *) false ;; esac; then exit 0; fi
  p="${cwd:+$cwd/}coordinator"
  msg="$lead Before your next step, re-read in full with the Read tool: $p/core/CORE.md (section 1, the hard rules, first; then the event table of section 4 - any duty there not done since the last journal line, do it now), $p/PROJECT.md, $p/BINDINGS.md and the open questions in $p/LOG.md. Then check the running sessions (claude agents --json) and the open PRs before acting. Act on the files, not on the summary."
  # the checkpoint before-compact wrote (#342), as it is; stale (written: over 60 minutes ago, or none) is a note, never a loss
  if ck="$(cat "${wd:+$wd/}coordinator/CHECKPOINT.md" 2>/dev/null)"; then
    s=$(( $(date +%s) - 3600 )); lim="$(date -u -r "$s" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$s" +%Y-%m-%dT%H:%M:%SZ)"
    wr="$(printf '%s\n' "$ck" | sed -n '1s/^written: \([0-9T:-]*Z\).*/\1/p')"
    if [ -n "$wr" ] && [ ! "$wr" \< "$lim" ]; then note="fresh, written $wr"
    else note="checkpoint is stale (written ${wr:-at an unknown moment}, the limit 60 minutes): a note, never a loss - read it, then the files"; fi
    msg="$msg
Checkpoint written before this compaction ($p/CHECKPOINT.md; $note):
$ck"
  else msg="$msg checkpoint is missing: $p/CHECKPOINT.md is absent or unreadable (the PreCompact hook before-compact writes it: TOOLKIT, After a compaction)."; fi
fi
# the JSON string: \ " tab and newline escaped, other control characters dropped; at most 9600 bytes, then `truncated`
esc="$(printf '%s\n' "$msg" | LC_ALL=C awk '{ gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t"); gsub(/[\001-\010\013-\037\177]/, "")
  n += length($0) + 2; if (n > 9600) { printf "%s", (NR > 1 ? "\\n" : "") "truncated"; exit } printf "%s%s", (NR > 1 ? "\\n" : ""), $0 }')"
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$esc"
exit 0
