# A SessionStart hook for the "compact" source (Windows; macOS / Linux: after-compact.sh - the same text):
# right after Claude Code compacts a conversation, it puts one instruction into the session's context -
# re-read the files that define its job, in full, from disk, before the next step: what the session knew
# is now a summary, and a summary loses rules and state.
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/hooks/after-compact.ps1 coordinator|worker
# worker: the brief start-worker saved for this session, <config>/coordinator/briefs/<session_id>.md
# (<config> = $env:CLAUDE_CONFIG_DIR, else ~/.claude); without one, its role file and the contract in its brief.
# coordinator: coordinator/core/CORE.md (section 1 first), PROJECT.md, BINDINGS.md and LOG.md's open
# questions under the session's folder, then the running sessions and the open PRs; silent in a session
# that is a worker (a kept brief, or a folder in .claude/worktrees): the project's settings, where this
# variant sits, load in workers launched from the same root too (#217).
# Prints {"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"..."}} (plain stdout
# does not reach the model), always exits 0.
param([string]$Role)
if ($Role -ne 'coordinator' -and $Role -ne 'worker') { [Console]::Error.WriteLine('usage: after-compact.ps1 coordinator|worker'); exit 0 }
$in = ''; try { $in = [Console]::In.ReadToEnd() } catch { }
function Str([string]$k) { $m = [regex]::Match(($in -replace "[`r`n]", ''), '"' + $k + '" *: *"([^"]*)"'); if ($m.Success) { $m.Groups[1].Value } else { '' } }
$sid = Str 'session_id'; $cwd = (Str 'cwd').Replace('\\', '\')
$cfg = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
$lead = 'The conversation was just compacted: what you knew is now a summary, and a summary loses rules and state.'
if ($Role -eq 'worker') {
  $b = ''
  if ($sid -match '^[0-9a-fA-F-]+$') { $f = Join-Path $cfg "coordinator/briefs/$sid.md"; if (Test-Path -LiteralPath $f -PathType Leaf) { $b = $f.Replace('\', '/') } }
  if ($b) {
    $msg = "$lead Before your next step, read your brief in full with the Read tool: $b - your role, your contract with its criteria, non_goals and do_not_decide, and your report address. Then check your branch with git status and git log. Follow the brief as written, not the summary."
  } else {
    $msg = "$lead Before your next step, re-read your role file and the contract your brief gave (its criteria, non_goals and do_not_decide), then check your branch with git status and git log. Follow them as written, not the summary."
  }
} else {
  # the coordinator variant sits in the project's settings, which a worker launched from the same root
  # loads too (#217): a session with a kept brief, or working in a worktree, is a worker - not this one
  if ($sid -match '^[0-9a-fA-F-]+$' -and (Test-Path -LiteralPath (Join-Path $cfg "coordinator/briefs/$sid.md") -PathType Leaf)) { exit 0 }
  $wd = $cwd.Replace('\', '/')
  if ($wd -like '*/.claude/worktrees/*' -or $wd -like '*/.claude/worktrees') { exit 0 }
  $p = if ($cwd) { "$cwd/coordinator" } else { 'coordinator' }
  $msg = "$lead Before your next step, re-read in full with the Read tool: $p/core/CORE.md (section 1, the hard rules, first; then the event table of section 4 - any duty there not done since the last journal line, do it now), $p/PROJECT.md, $p/BINDINGS.md and the open questions in $p/LOG.md. Then check the running sessions (claude agents --json) and the open PRs before acting. Act on the files, not on the summary."
}
$esc = $msg.Replace('\', '\\').Replace('"', '\"')
[Console]::Out.Write('{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"' + $esc + '"}}' + "`n")
exit 0
