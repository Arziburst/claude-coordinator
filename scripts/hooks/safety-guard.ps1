# PreToolUse safety hook for coordinator projects (Windows; macOS / Linux: safety-guard.sh - the same
# rules, checked against the same cases: tests/safety-guard/cases.txt).
# Reads the tool call JSON on stdin; exit 2 blocks the call and shows the reason to Claude.
# A safety net only - the real enforcement is branch protection on the code host (CORE section 2).
# Extra project patterns (one regular expression per line, '#' comments): .claude/coordinator-deny.txt
# Self-test: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\hooks\safety-guard.ps1 -SelfTest
# Windows PowerShell 5.1 or PowerShell 7; nothing to install.
param([switch]$SelfTest)

if ($SelfTest) {
  $exe = (Get-Process -Id $PID).Path
  '{"tool_input":{"command":"git push --force origin main"}}' |
    & $exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath 2>$null | Out-Null
  if ($LASTEXITCODE -eq 2) { 'safety-guard: OK'; exit 0 }
  'safety-guard: NOT WORKING - STOP: do not start workers until it is fixed (TOOLKIT.md).'
  exit 0   # stdout reaches the session's context; a non-zero exit would only show it to the user
}

[Console]::InputEncoding = [Text.Encoding]::UTF8
$raw = [Console]::In.ReadToEnd()
try { $d = $raw | ConvertFrom-Json } catch { exit 0 }
$cmd = [string]$d.tool_input.command
$cwd = [string]$d.cwd
# Drop comment lines (a "#" at the start of a line) so mentions in comments do not trigger.
$lines = @($cmd -split '\r?\n' | Where-Object { $_ -notmatch '^\s*#' })
if (-not ($lines -join '').Trim()) { exit 0 }

function Block([string]$why) {
  [Console]::Error.WriteLine("Blocked by safety-guard: $why. If this is a false positive, ask the owner.")
  exit 2
}
# Patterns are tested line by line, like grep: ^ and $ are a line's ends, [^;|] never crosses a line.
function Has([string]$re) { foreach ($l in $lines) { if ($l -match $re) { return $true } }; $false }
function HasCs([string]$re) { foreach ($l in $lines) { if ($l -cmatch $re) { return $true } }; $false }

$PROTECTED = '(main|master)'
# "git" as a command word: plain, quoted, with a path (a quoted one may contain spaces), .exe, any case.
$GITCMD = '("[^"]*[/\\]git(\.exe)?"|''[^'']*[/\\]git(\.exe)?''|["'']?([^\s"'']*[/\\])?git(\.exe)?["'']?)'
$GIT = '(^|[^A-Za-z0-9_.-])' + $GITCMD

function CurrentBranch {
  $dir = if ($cwd) { $cwd } elseif ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { '.' }
  $b = git -C $dir symbolic-ref --short -q HEAD 2>$null
  if ($LASTEXITCODE -eq 0) { "$b".Trim() } else { '' }
}
function OnProtected { (CurrentBranch) -match "^$PROTECTED$" }

# --- git push: force, protected targets, pushes resolving to the current (protected) branch ---
# Split on separators (incl. inside bash -c "..."), then inspect each segment that runs git ... push.
# A command substitution leaves a "$SUBST" marker (it resolves to an unknown ref -> treated as the
# current branch) and its inner command becomes a segment of its own.
$s = $lines -join "`n"
$s = $s.Replace('$(', "`$SUBST`n").Replace('`', "`$SUBST`n")
$s = $s.Replace('&&', "`n").Replace('||', "`n").Replace(';', "`n").Replace('|', "`n")
$pushRe = '^\s*(&\s*)?([A-Za-z_][A-Za-z0-9_]*=\S*\s+)*' + $GITCMD +
  '(\s+(-c\s+\S+|-C\s+\S+|--[a-z-]+(=\S+)?))*\s+push(\s|$|["''])'
foreach ($seg in ($s -split "`n")) {
  # "bash -c '...'" / "pwsh -c ..." - the inner command starts its own segment
  $seg = $seg -creplace '^\s*(bash|sh|zsh|pwsh|powershell)(\.exe)?\s+(-[a-zA-Z]+\s+)*-[cC](ommand)?\s+', ''
  # git must be the segment's command (optionally after env assignments or PowerShell's "&"),
  # so a mention inside a commit message, a PR body or an echo does not count.
  if ($seg -notmatch $pushRe) { continue }
  $rest = $seg -creplace '^.*\s[Pp][Uu][Ss][Hh](\s|$)', ''
  # Work branches may be pushed, force-pushed (e.g. after a rebase) and deleted freely;
  # only the protected branches are guarded.
  $refspecs = 0; $remoteSeen = $false; $toCurrent = $false
  foreach ($tok in ($rest -split '\s+' | Where-Object { $_ })) {
    $t = $tok -replace '^["''(]+', '' -replace '["'')]+$', ''
    if ($t -eq '--mirror') { Block 'mirror push (overwrites every branch, incl. protected ones)' }
    if ($t.StartsWith('-')) { continue }
    if (-not $remoteSeen) { $remoteSeen = $true; continue }
    $refspecs++
    if ($t -match "^\+?(refs/heads/)?([^:]*:)?(refs/heads/)?$PROTECTED$") { Block 'push to a protected branch' }
    # HEAD, @, variables or command substitutions resolve to the current branch
    if ($t -cmatch '^(HEAD|@|\$.*|.*\$\(.*|.*`.*)(:.*)?$') { $toCurrent = $true }
  }
  if (($refspecs -eq 0 -or $toCurrent) -and (OnProtected)) { Block "push while on $(CurrentBranch)" }
}

# Routine work-branch operations (reset, restore, amend, rebase, stash, deleting a work branch) are
# allowed: they are reversible and part of normal work (CORE section 1.9). Only protected branches are guarded.
if (HasCs ($GIT + '[^;&|]*\sbranch\s+(-D|-d|--delete)(\s+-f)?\s+' + $PROTECTED + '(\s|$)')) { Block 'deleting a protected branch' }
# --- irreversible removals ---
if (Has 'rm\s+-[a-z]*r[a-z]*\s+["'']?(/|~/?|\$HOME/?|\$\{HOME\}/?|/\*)["'']?(\s|$)') { Block 'recursive removal of / or home' }
if (Has 'rm\s+-[a-z]*r[a-z]*\s+[^;&|]*\.claude/worktrees(/[^/\s"'']+)?/?["'']?(\s|$)') { Block 'removing a worktree by hand (use the cleanup script)' }
if (Has 'Remove-Item[^;|]*\s["'']?(C:\\?|\$HOME|~)["'']?(\s[^;|]*)?-Recurse') { Block 'recursive removal of a drive or home' }
if (Has 'Remove-Item[^;|]*-Recurse[^;|]*\s["'']?(C:\\?|\$HOME|~)["'']?(\s|$)') { Block 'recursive removal of a drive or home' }

# --- project-specific patterns (POSIX classes such as [[:space:]] work in both scripts) ---
$proj = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { '.' }
$denyFile = Join-Path $proj '.claude/coordinator-deny.txt'
if (Test-Path -LiteralPath $denyFile) {
  foreach ($p in [IO.File]::ReadAllLines((Resolve-Path -LiteralPath $denyFile).Path)) {
    if (-not $p -or $p.StartsWith('#')) { continue }
    $re = $p.Replace('[:space:]', '\s').Replace('[:alnum:]', 'A-Za-z0-9').Replace('[:alpha:]', 'A-Za-z').Replace('[:digit:]', '0-9')
    if (Has $re) { Block "project rule: $p" }
  }
}
exit 0
