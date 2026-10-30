# Start a named worker session in its own git worktree, with the safety settings applied
# (Windows; macOS / Linux: start-worker.sh - the same steps and checks).
#   powershell -File scripts\start-worker.ps1 -Repo <project repo path> -Name "#12 worker: Fix login" `
#       -Branch 12-fix-login -Model opus [-Effort high] -BriefFile brief.md -Safety <worker settings .json> [-Mode auto] [-Base main]
#       -ReportTo <coordinator session> [-Contract <file>] [-TesterCommit <sha> | -TesterTests <path>]
#       [-LaunchFrom <folder>] [-WorktreeRoot <folder>] [-DryRun]
# -Effort: low, medium, high, xhigh or max, passed as claude --effort (CORE section 7, the contract's
# budget.effort); without it the session runs at the user's default effort for its model.
# -ReportTo: the session the worker reports to - the coordinator's name as ListAgents shows it now
# (names change on a restart). It heads the brief; at the end the script prints the line that
# subscribes to the new session's idle notice (CORE section 4, Control).
# -Safety: a settings file for the worker (from settings.example.windows.json) with the deny rules, the
#          PreToolUse hook at an ABSOLUTE path and "worktree": {"bgIsolation": "none"}. The hook's
#          self-test must pass, or no worker starts. -Model is required (CORE section 7). Default mode auto;
#          acceptEdits for the cautious level; bypassPermissions is refused. Exit 1 on any failed check.
#          Launched from the root without env COORD_PROTECTED_ROOT in it: a notice (edit tools can reach
#          the working copy).
# The session starts in the repository root (-LaunchFrom overrides it), which the owner trusts once:
# Claude Code refuses --bg in a folder nobody trusted, and a new worktree never is (trust is not
# inherited from a parent). The brief's first line sends it into its worktree (EnterWorktree).
# -WorktreeRoot puts the worktree elsewhere (default <repo>/.claude/worktrees). Launched from a folder
# that is not the repository's root (the self-test: the state repository's worktrees under the trusted
# project), the brief says to work in the worktree by absolute path instead. A repository without an
# origin, or a -Base not on origin yet (a lead's integration branch), starts the branch from the local -Base.
# The hook path in -Safety uses forward slashes: hooks run through Git Bash on Windows, which drops
# backslashes, and a hook that fails to run blocks nothing.
# The worktrees' folder, a coordinator/ state repository at the root and a lead's .lead/ notes in any
# worktree are kept out of the project's git: one line each in its .git/info/exclude, never .gitignore.
# A lead gets a notes folder beside its worktree, <worktree>.lead/ (made, or an existing one kept), named
# in its launch text (#310); a dry run says it would make it.
# A worker or a lead: before the launch it prints the conflict foresight (CORE section 4a) - merge-queue
# status with the brief's `touches` - as `foresight:` lines; informational, never a stop.
# The contract must pass check-contract before it goes out (CORE section 4, #267): -Contract <file>, or for
# a worker or a lead without it the contract in the brief (a block after a `---` line, to the next one or
# the end, holding any key check-contract requires, CONTRACT.md), is checked before anything is created (-DryRun too). An ERROR refuses
# the start (exit 1) with check-contract's lines; WARNs are printed and the start goes on; a worker or a
# lead with no contract found: one notice line, the start goes on. Other roles' briefs are not searched.
# -Contract only checks a contract; the session reads the brief alone (#331): a -Contract whose text is
# not in the brief (its first `id:` line and its first `title:` line both absent from the brief) prints one
# WARN line, and the start goes on (-DryRun too); the brief is never changed.
# The tests_first gate (CORE section 4 step 3, #276): a worker whose contract says `tests_first: yes` starts
# only with the tester's tests - -TesterCommit <sha>, a commit that is the worker's start point or an
# ancestor of it (a reused worktree's HEAD, else the branch, else the base), or -TesterTests <path>, an
# existing file or folder (a lead's case: the tests its tester subagent returned, kept in its notes folder); else it
# is refused (exit 1) before anything is created (-DryRun too). `tests_first` comes from check-contract
# itself (`check-contract.ps1 -Field tests_first`, one parser): its contract block (the front matter, or a
# top-level `contract:`), never the rest of the file. A start with either flag prints one line naming the tester's tests; both flags together are
# refused. A tester start is not gated. A lead's task gets no task-level tester (#289): a lead whose
# contract says `tests_first: yes`, or a lead given -TesterCommit / -TesterTests, is refused (exit 1)
# before anything is created (-DryRun too) - a lead's contract has `tests_first: no - the lead runs the
# tester per sub-contract` (roles/lead.md step 3).
# The brief is passed as the session's first prompt argument. Run with -DryRun first on a new machine.
# A launch text (first line + role + brief) over 24 000 characters goes through a file instead (#291):
# <config>/coordinator/briefs/launch-<branch>-<time>-<pid>.md, decided before anything is created, the
# first message one short instruction to read it in full with the Read tool; one line names the file.
# A launch that fails names what it created and cleanup-worker, and exits 1.
# An assistant (#281): -Name "assistant: <name>" and -BriefFile <repo>/coordinator/assistants/<name>/BRIEF.md start
# a persistent session with no worktree and no branch from the repository root, its -Safety env
# COORD_ASSISTANT_DIR naming that folder; -Branch, -Base, -WorktreeRoot, -LaunchFrom, -Contract, -TesterCommit and
# -TesterTests are refused, and so is a session of that name already listed, or a listing that fails or prints no
# JSON list; -AssistantDir <folder> (an assistant only, the self-test's throwaway one) puts the folder elsewhere -
# <folder>/assistants/<name>, seen by no git working tree; a -Safety file inside the folder is refused. Folders are
# compared by start-worker.sh's own bash code, run here through bash, so both scripts decide alike; after the
# launch the attach command (the rules: start-worker.sh's top comment).
param([string]$Repo, [string]$Name, [string]$Branch, [string]$Model, [string]$BriefFile, [string]$Safety,
      [string]$Mode = 'auto', [string]$Base = 'main', [string]$LaunchFrom = '', [string]$ReportTo = '', [string]$WorktreeRoot = '', [switch]$DryRun, [string]$Effort = '', [string]$Contract = '',
      [string]$TesterCommit = '', [string]$TesterTests = '', [string]$AssistantDir = '')
# native output (git, bash) is read and this script's own output written as UTF-8, whatever the console's
# code page (cp866 on a Russian Windows garbles a non-ASCII path or a section sign); no console: left as is.
# The caller's console gets its own encoding back on every way out (the end, any exit N, a terminating
# error): the body below runs inside try, the encoding is restored in finally.
$enc0 = $null; try { $enc0 = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
try {
$ErrorActionPreference = 'Stop'
function Fail([string]$m) { [Console]::Error.WriteLine($m); exit 1 }

# a brief that is missing, or empty / blanks only, would start a worker with no task (#226)
if ($BriefFile) {
  if (-not (Test-Path -LiteralPath $BriefFile -PathType Leaf)) { Fail "-BriefFile: $BriefFile does not exist" }
  if (-not ("$(Get-Content -Raw -LiteralPath $BriefFile)" -match '\S')) { Fail "-BriefFile: $BriefFile is empty - a worker with no task would start" }
}
# an assistant (#281): a session beside the coordinator, no worktree and no branch - a worker's flags are refused
$asst = $Name.StartsWith('assistant:', [StringComparison]::Ordinal)
if ($asst) {
  $given = @('Branch', 'Base', 'WorktreeRoot', 'LaunchFrom', 'Contract', 'TesterCommit', 'TesterTests' | Where-Object { $PSBoundParameters.ContainsKey($_) })
  if ($given.Count) { Fail "refused: -$($given[0]) with an assistant ($Name) - an assistant has no worktree, branch, base or contract; it starts from the repository root" }
}
if (-not $asst -and $AssistantDir) { Fail "refused: -AssistantDir with $Name - it is for an assistant (-Name `"assistant: <name>`") only" }
if (-not ($Repo -and $Name -and ($Branch -or $asst) -and $Model -and $ReportTo -and $BriefFile -and $Safety) -or
    -not (Test-Path -LiteralPath $BriefFile -PathType Leaf) -or -not (Test-Path -LiteralPath $Safety -PathType Leaf)) {
  if ($asst) { [Console]::Error.WriteLine('usage: -Repo <path> -Name "assistant: <name>" -Model <model> [-Effort <level>] -BriefFile <repo>/coordinator/assistants/<name>/BRIEF.md -Safety <settings.json> -ReportTo <session> [-AssistantDir <folder>] [-Mode auto] [-DryRun]') }
  Fail 'usage: -Repo <path> -Name <session name> -Branch <branch> -Model <model> [-Effort <level>] -BriefFile <file> -Safety <settings.json> -ReportTo <session> [-Contract <file>] [-TesterCommit <sha> | -TesterTests <path>] [-Mode auto] [-Base main] [-LaunchFrom <folder>] [-WorktreeRoot <folder>] [-DryRun]'
}
foreach ($v in @(@('Repo', $Repo), @('Name', $Name), @('Branch', $Branch), @('Model', $Model), @('Effort', $Effort), @('BriefFile', $BriefFile),
                  @('Safety', $Safety), @('Mode', $Mode), @('Base', $Base), @('LaunchFrom', $LaunchFrom),
                  @('ReportTo', $ReportTo), @('WorktreeRoot', $WorktreeRoot), @('Contract', $Contract),
                  @('TesterCommit', $TesterCommit), @('TesterTests', $TesterTests), @('AssistantDir', $AssistantDir))) {
  if ("$($v[1])".StartsWith('-')) { Fail "missing value for -$($v[0]) (got the flag $($v[1]))" }
}
if ($Mode -eq 'bypassPermissions') { Fail "refusing bypassPermissions for a worker (TOOLKIT.md Safety: only the owner's own explicit setup)" }
if ($Effort -and $Effort -cnotin @('low', 'medium', 'high', 'xhigh', 'max')) { Fail "-Effort: low, medium, high, xhigh or max (got $Effort)" }
if ($Contract -and -not (Test-Path -LiteralPath $Contract -PathType Leaf)) { Fail "-Contract: $Contract does not exist" }
if ($TesterCommit -and $TesterTests) { Fail "-TesterCommit and -TesterTests are alternatives: give one - the tester's commit, or (a lead's case) the path of the tests its tester returned (CORE $([char]0x00A7)4 step 3)" }
# Absolute paths: both files are used from inside the worktree; the contract is read by .NET, whose
# current folder is not PowerShell's.
$Safety = (Resolve-Path -LiteralPath $Safety).Path; $BriefFile = (Resolve-Path -LiteralPath $BriefFile).Path
$cLabel0 = $Contract; if ($Contract) { $Contract = (Resolve-Path -LiteralPath $Contract).Path }
# a relative -WorktreeRoot is taken from the current folder (git would resolve it against the repository)
if ($WorktreeRoot -and -not [IO.Path]::IsPathRooted($WorktreeRoot)) { $WorktreeRoot = Join-Path (Get-Location).Path $WorktreeRoot }

$root = (git -C $Repo rev-parse --show-toplevel)
if ($LASTEXITCODE -ne 0) { Fail "not a git repository: $Repo" }
# an assistant's name and folder: <root>/coordinator/assistants/<name>/, its brief BRIEF.md there
$aname = ''; $adir = ''
if ($asst) {
  $aname = if ($Name.StartsWith('assistant: ', [StringComparison]::Ordinal)) { $Name.Substring(11) } else { '' }
  if ($aname -cnotmatch '^[A-Za-z0-9._-]+\z' -or $aname -cmatch '^\.+\z') {
    Fail "refused: the assistant name `"$($Name.Substring(10))`" in -Name `"$Name`" - write `"assistant: <name>`", <name> letters, digits, . _ - (not dots only)"
  }
  $adir = "$($root.Replace('\', '/'))/coordinator/assistants/$aname"
  # the one comparison of folders (M1): start-worker.sh's fcanon, the same bash code (given on stdin, so no
  # quote reaches a native argument): as on disk, C:/... on Windows, no trailing /, one letter case where paths
  # ignore it; no answer from bash compares as nothing else does, so the start is refused
  $fcanonSh = @'
q="$( (cd -P -- "$1" 2>/dev/null && pwd -P) || true)"; [ -n "$q" ] || q="$1"
command -v cygpath >/dev/null 2>&1 && q="$(cygpath -m "$q")"
while :; do case "$q" in ?*/) q="${q%/}" ;; *) break ;; esac; done
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*|Darwin) printf '%s' "$q" | tr '[:upper:]' '[:lower:]' ;; *) printf '%s' "$q" ;; esac
#
'@
  $script:fcn = 0
  function FCanon([string]$p) {
    # Windows PowerShell 5.1 puts a UTF-8 BOM before the piped text: an empty first line takes it (an error on stderr)
    $b = & { $ErrorActionPreference = 'Continue'; ("`n" + ($fcanonSh -replace "`r", '')) | bash -s -- $p.Replace('\', '/') 2>$null }
    if ($LASTEXITCODE -ne 0 -or -not "$b") { $script:fcn++; return "?no answer $($script:fcn)" }
    "$b".TrimEnd("`r", "`n")
  }
  # -AssistantDir: the folder elsewhere (the self-test's throwaway assistant), seen by no git working tree
  if ($AssistantDir) {
    if (-not (Test-Path -LiteralPath $AssistantDir -PathType Container)) { Fail "refused: -AssistantDir $AssistantDir is not a folder" }
    $AssistantDir = (Resolve-Path -LiteralPath $AssistantDir).ProviderPath.Replace('\', '/').TrimEnd('/')
    if ((Split-Path -Leaf $AssistantDir) -cne $aname -or (Split-Path -Leaf (Split-Path -Parent $AssistantDir)) -cne 'assistants') {
      Fail "refused: -AssistantDir $AssistantDir - it must be <folder>/assistants/$aname"
    }
    $atop = & { $ErrorActionPreference = 'Continue'; git -C $AssistantDir rev-parse --show-toplevel 2>$null }
    if ($LASTEXITCODE -eq 0) {
      $null = & { $ErrorActionPreference = 'Continue'; git -C $AssistantDir check-ignore -q -- "$AssistantDir/BRIEF.md" 2>$null }
      if ($LASTEXITCODE -ne 0) { Fail "refused: -AssistantDir $AssistantDir lies in a git working tree ($atop) that sees it - it must be outside every one, or ignored there" }
    }
    $adir = $AssistantDir
  }
  if ((Split-Path -Leaf $BriefFile) -cne 'BRIEF.md' -or (FCanon (Split-Path -Parent $BriefFile)) -cne (FCanon $adir)) {
    Fail "refused: an assistant's brief is $adir/BRIEF.md (its folder in coordinator/assistants/), got $BriefFile"
  }
  # COORD_ASSISTANT_DIR in the safety file's env: the guard keeps the assistant's writes inside that folder
  $acfg = [IO.File]::ReadAllText($Safety) | ConvertFrom-Json
  $aenv = ''; if ($acfg.env -is [Management.Automation.PSCustomObject] -and $acfg.env.COORD_ASSISTANT_DIR -is [string]) { $aenv = $acfg.env.COORD_ASSISTANT_DIR.Replace('\', '/') }
  if (-not $aenv) { Fail "refused: no COORD_ASSISTANT_DIR in the env of $Safety - it must name the assistant's folder $adir" }
  if ((FCanon $aenv) -cne (FCanon $adir)) { Fail "refused: COORD_ASSISTANT_DIR in $Safety is $aenv - it must name the assistant's folder $adir" }
  # the settings outside the folder: the guard lets the assistant write inside it, so it could edit them there
  if ("$(FCanon (Split-Path -Parent $Safety))/".StartsWith("$(FCanon $adir)/", [StringComparison]::Ordinal)) {
    Fail "refused: the -Safety file $Safety lies in the assistant's folder $adir - the assistant could edit its own settings; keep it outside the folder (coordinator/assistant-settings/$aname.json)"
  }
}
$wt = if ($asst) { '' } else { Join-Path $(if ($WorktreeRoot) { $WorktreeRoot } else { Join-Path $root '.claude/worktrees' }) $Branch }
$from = if ($LaunchFrom) { $LaunchFrom } else { $root }
if (-not (Test-Path -LiteralPath $from -PathType Container)) { Fail "no folder to launch from: $from" }
# the branch exactly as named: on a case-insensitive file system (Windows, macOS) a branch that differs
# only in letter case is the same branch file and the same worktree folder; with packed refs git lets
# both exist, so another one in another letter case is refused even then
$heads = @(git -C $root for-each-ref --format='%(refname)' refs/heads | ForEach-Object { $_ -replace '^refs/heads/', '' })
$hasBranch = $heads -ccontains $Branch
if (($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows -or $IsMacOS) {
  $other = @($heads | Where-Object { $_ -eq $Branch -and $_ -cne $Branch })[0]
  if ($other) { Fail "branch $Branch differs only in letter case from the existing ${other}: on this file system they are one branch - pick another name" }
}

# Safety settings: the hook path inside the file must exist and pass its self-test.
$text = [IO.File]::ReadAllText($Safety)
$cfg = $text | ConvertFrom-Json
$hookCmd = @($cfg.hooks.PreToolUse | ForEach-Object { $_.hooks } | ForEach-Object { $_.command } |
  Where-Object { $_ -match 'safety-guard\.(ps1|sh)' })[0]
if (-not $hookCmd) { Fail "safety settings: no PreToolUse safety-guard hook in $Safety" }
# the guard's path in one hook command: quoted ("..." or '...'), so it may hold a space, or else the
# word without spaces
function HookPath([string]$c) {
  if ($c -match '"([^"]*safety-guard\.(ps1|sh))"') { return $Matches[1] }
  if ($c -match "'([^']*safety-guard\.(ps1|sh))'") { return $Matches[1] }
  if ($c -match '([^"\s]*safety-guard\.(ps1|sh))') { return $Matches[1] }
  return ''
}
# every guard path in the file must exist; the self-test runs the PreToolUse hook itself
$cmds = @($cfg.hooks.PSObject.Properties | ForEach-Object { $_.Value } | ForEach-Object { $_.hooks } | ForEach-Object { $_.command } |
  Where-Object { $_ -match 'safety-guard\.(ps1|sh)' })
foreach ($c in $cmds) {
  $p = HookPath $c
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { Fail "safety settings: hook not found at '$p' (use an absolute path; quote a path with a space)" }
}
$hook = HookPath $hookCmd
if ($hookCmd -match '\\') { Fail 'safety settings: write the hook path with forward slashes (C:/...): hooks run through Git Bash on Windows, which drops backslashes, and a hook that fails to run blocks nothing' }
# a PowerShell shell around the hook turns its exit 2 (block) into 1 (a non-blocking error), unless the
# command passes the code through
$hookObj = @($cfg.hooks.PreToolUse | ForEach-Object { $_.hooks } | Where-Object { $_.command -match 'safety-guard\.(ps1|sh)' -and $_.command -notmatch '-SelfTest|--self-test' })[0]
if ($hookObj -and $hookObj.shell -eq 'powershell' -and -not ([string]$hookObj.command).Contains('exit $LASTEXITCODE')) {
  Fail 'safety settings: the hook runs under a PowerShell shell without "; exit $LASTEXITCODE": its block (exit 2) would reach Claude Code as a non-blocking error (1)'
}
if (-not $hook -or -not (Test-Path -LiteralPath $hook -PathType Leaf)) { Fail "safety settings: hook not found at '$hook' (use an absolute path)" }
if (-not $cfg.worktree.bgIsolation) { Fail 'safety settings: add "worktree": {"bgIsolation": "none"}' }
if ($hook.EndsWith('.ps1')) {
  $selftest = & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $hook -SelfTest
} else { $selftest = bash $hook --self-test }
if (-not "$selftest".Trim()) { Fail "safety settings: the hook's self-test printed nothing ($hook)" }
if ("$selftest".Trim() -ne 'safety-guard: OK') { Fail "$selftest" }
# an assistant is one session per name: one already listed (running or stopped) is refused, never a second
if ($asst -and (Get-Command claude -ErrorAction SilentlyContinue)) {
  # (fail closed: a listing that fails or prints no JSON list cannot tell, so the start is refused)
  $aj = & { $ErrorActionPreference = 'Continue'; (@(& claude agents --json --all 2>$null | ForEach-Object { "$_" }) -join '') -replace "[`r`n]", '' }
  if ($LASTEXITCODE -ne 0 -or ($aj -replace '\s', '') -notmatch '^\[.*\]$') {
    Fail "refused: the listing of sessions (claude agents --json --all) failed or printed no JSON list - cannot tell whether `"$Name`" exists already"
  }
  foreach ($o in ($aj -split '}')) {
    if ($o -cnotmatch ('"name": *"' + [regex]::Escape($Name) + '"')) { continue }
    $xid = [regex]::Match($o, '"id": *"([^"]*)"').Groups[1].Value
    if (-not $xid) { $xid = [regex]::Match($o, '"sessionId": *"([^"]*)"').Groups[1].Value }
    $xst = [regex]::Match($o, '"state": *"([^"]*)"').Groups[1].Value
    Fail "refused: the session `"$Name`" exists already ($(if ($xid) { $xid } else { 'no id' })$(if ($xst) { ", $xst" })) - wake it (SendMessage, claude attach), or remove it on the owner's word first"
  }
}

# The contract passes check-contract before it goes out (CORE section 4, #267), checked before anything is
# created: -Contract <file>, or for a worker or a lead (the role from the name, as the foresight below)
# the first block after a `---` line of the brief - up to the next `---` or the brief's end - that holds
# any key check-contract requires at its top level but title (id, intent, acceptance, non_goals,
# do_not_decide, tests_first; title is common in quoted front matter, #267): a contract missing some of them is still checked, never "none found"
$sect = [string][char]0x00A7   # not a literal: Windows PowerShell 5.1 reads a BOM-less script as ANSI
$crole = ''; if ($Name -cmatch '^(#\S* )?([a-z]+):') { $crole = $Matches[2] }
$cFile = $Contract; $cLabel = $cLabel0; $cTmp = ''
if (-not $Contract -and $crole -in @('worker', 'lead', '')) {
  # each `---` line ends a candidate block and opens the next (a rule above the contract is no contract)
  $cl = [IO.File]::ReadAllText($BriefFile).TrimStart([char]0xFEFF).Replace("`r", '') -split "`n"
  $on = $false; $buf = @(); $hasKey = $false; $found = $false
  foreach ($l in $cl) {
    if ($l -match '^---[ \t]*$') {
      if ($on -and $hasKey) { $found = $true; break }
      $on = $true; $buf = @(); $hasKey = $false; continue
    }
    if ($on) { $buf += $l; if ($l -cmatch '^(id|intent|acceptance|non_goals|do_not_decide|tests_first):') { $hasKey = $true } }
  }
  # a block left open at the brief's end counts too
  if (-not $found -and $on -and $hasKey) { $found = $true }
  if ($found) {
    $cTmp = [IO.Path]::GetTempFileName(); $cFile = $cTmp; $cLabel = 'contract in the brief'
    [IO.File]::WriteAllText($cTmp, "---`n" + ($buf -join "`n") + "`n---`n", (New-Object System.Text.UTF8Encoding $false))
  } else { "contract: none found in the brief - check-contract not run (CORE ${sect}4)" }
}
# the tests_first gate (CORE section 4 step 3, #276): a worker's contract with `tests_first: yes` needs the
# tester's tests; a lead runs its own tester, a tester writes them
# - its value as check-contract itself reads it (its -Field option: one parser, so the two never
# disagree), asked once the contract has passed it; its result starts as a failure, so a call that never
# returns one refuses (fail closed, #288). A lead's task gets no task-level tester (#289): the lead runs the
# tester per sub-contract (roles/lead.md step 3), so a lead whose contract says yes, or a lead given
# -TesterCommit / -TesterTests, is refused
$tfYes = $false
if ($cFile) {
  $cOut = @(); $cRc = 1; $tfOut = @(); $tfRc = 0
  try {
    $cOut = @(& { $ErrorActionPreference = 'Continue'; & (Join-Path $PSScriptRoot 'check-contract.ps1') $cFile 2>&1 } | ForEach-Object { "$_" }); $cRc = $LASTEXITCODE
    if ($cRc -eq 0 -and $crole -in @('worker', 'lead', '')) {
      $tfRc = 1
      $tfOut = @(& { $ErrorActionPreference = 'Continue'; & (Join-Path $PSScriptRoot 'check-contract.ps1') -Field tests_first $cFile 2>&1 } | ForEach-Object { "$_" }); $tfRc = $LASTEXITCODE
    }
  }
  catch { $cOut = @("$_") }
  finally { if ($cTmp) { Remove-Item -LiteralPath $cTmp -Force -ErrorAction SilentlyContinue } }
  # its lines name the file it read: the brief's contract by that name, not by the temporary file
  $cOut | ForEach-Object { if ($_.StartsWith("${cFile}: ")) { "${cLabel}: " + $_.Substring($cFile.Length + 2) } else { $_ } }
  if ($cRc -ne 0) { Fail "refused: the contract fails check-contract - fix the ERROR lines above before it goes out (CORE ${sect}4)" }
  if ($tfRc -ne 0) { $tfOut | ForEach-Object { [Console]::Error.WriteLine($_) }; Fail "refused: check-contract could not read tests_first (CORE ${sect}4 step 3)" }
  $tfYes = ((@($tfOut) -join "`n").Trim().ToLower()) -cmatch '^yes([ \t,:;(]|$)'
}
if ($Contract) {
  # the contract's first `id:` and `title:` lines against the brief's lines, all trimmed
  $trimmed = { param($f) [IO.File]::ReadAllText($f).TrimStart([char]0xFEFF).Replace("`r", '') -split "`n" | ForEach-Object { $_.Trim(" `t") } }
  $want = @{}; foreach ($l in (& $trimmed $Contract)) { if ($l -cmatch '^(id|title):' -and -not $want.ContainsKey($Matches[1])) { $want[$Matches[1]] = $l } }
  $have = @(& $trimmed $BriefFile)
  if ($want.Count -and -not @($want.Values | Where-Object { $have -ccontains $_ }).Count) {
    'WARN: -Contract only checks the contract - the session will not see it: its text (its id: and title: lines) is not in the brief; put the contract into the brief file (#331)'
  }
}
if ($crole -eq 'lead' -and ($TesterCommit -or $TesterTests)) {
  Fail "refused: a lead's task gets no task-level tester - start the lead without -TesterCommit / -TesterTests; its contract has ``tests_first: no - the lead runs the tester per sub-contract`` (roles/lead.md step 3)"
}
if ($crole -eq 'lead' -and $tfYes) {
  Fail "refused: $cLabel has tests_first: yes, but a lead's task gets no task-level tester - a lead's contract has ``tests_first: no - the lead runs the tester per sub-contract``, yes belongs only in its sub-contracts (roles/lead.md step 3)"
}
if ($tfYes -and -not $TesterCommit -and -not $TesterTests) {
  Fail "refused: $cLabel has tests_first: yes - start the worker with the tester's tests: -TesterCommit <sha> or -TesterTests <path> (CORE ${sect}4 step 3)"
}
if ($TesterTests) {
  if (-not (Test-Path -LiteralPath $TesterTests)) { Fail "-TesterTests: $TesterTests does not exist - give the tester's tests file or folder (CORE ${sect}4 step 3)" }
  "tester's tests: $TesterTests"
}
$tFull = ''
if ($TesterCommit) {
  $tFull = & { $ErrorActionPreference = 'Continue'; "$(git -C $root rev-parse -q --verify "$TesterCommit^{commit}" 2>$null)".Trim() }
  if (-not $tFull) { Fail "-TesterCommit: $TesterCommit is not a commit in ${root} - give the sha of the tester's commit (CORE ${sect}4 step 3)" }
}

function Run([string]$exe, [string[]]$a) {
  if ($DryRun) { "[dry-run] $exe $($a -join ' ')" } else { & $exe @a; if ($LASTEXITCODE -ne 0) { Fail "$exe failed" } }
}

# no origin (a local-only repository, e.g. a state repository without a remote): the local base branch;
# a base not on origin yet (a lead's integration branch before its first push): the local one too
$origin = if ($asst) { '' } else { git -C $root config --get remote.origin.url }
if ($asst) { $start = '' }   # no branch, so no base
elseif ($origin) {
  # Windows PowerShell 5.1 under 'Stop' turns git's stderr into a terminating error: read it as records.
  # git's first error line goes into the message; a failure other than "no such branch" (2) is retried
  # once: a transient DNS or network error should not stop a start
  $lsr = {
    $ErrorActionPreference = 'Continue'
    $out = @(git -C $root ls-remote -q --exit-code --heads origin $Base 2>&1)
    $script:lsErr = @($out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } |
      ForEach-Object { "$_".Trim() } | Where-Object { $_ }) | Select-Object -First 1
    $LASTEXITCODE
  }
  $rc = & $lsr
  if ($rc -ne 0 -and $rc -ne 2) { "origin did not answer: retrying once in 3 s"; Start-Sleep -Seconds 3; $rc = & $lsr }
  if ($rc -eq 0) { Run git @('-C', $root, 'fetch', '-q', 'origin', $Base); $start = "origin/$Base" }
  else {
    git -C $root show-ref -q --verify "refs/heads/$Base" *> $null
    $local = ($LASTEXITCODE -eq 0)
    if ($rc -eq 2 -and $local) { "base $Base is not on origin yet: the branch starts from the local $Base"; $start = $Base }
    elseif ($rc -eq 2) { Fail "base ${Base}: not on origin and no local branch" }
    else { Fail "cannot reach origin to read the base ${Base}: $script:lsErr" }
  }
} else { $start = $Base }
# the tester's commit is on the worker's start point (it or an ancestor of it): a reused worktree's HEAD,
# else the existing branch, else the base - still before anything is created
if ($tFull) {
  if (Test-Path -LiteralPath (Join-Path $wt '.git')) {
    $sp = & { $ErrorActionPreference = 'Continue'; "$(git -C $wt rev-parse -q --verify HEAD 2>$null)".Trim() }; $spl = "the worktree's HEAD"
  } elseif ($hasBranch) { $sp = "refs/heads/$Branch"; $spl = "the branch $Branch" }
  else { $sp = $start; $spl = "the base $start" }
  $anc = & { $ErrorActionPreference = 'Continue'; if (-not $sp) { return 1 }; git -C $root merge-base --is-ancestor $tFull $sp 2>$null; $LASTEXITCODE }
  if ($anc -ne 0) { Fail "-TesterCommit: $TesterCommit is not on the worker's start point (${spl}): neither it nor an ancestor of it - the tester's commit goes on the task branch or its base (CORE ${sect}4 step 3)" }
  "tester's tests: commit $($tFull.Substring(0, 7)), on $spl"
}

# The launch text (the first line, the role, the brief) and the way it goes, decided before anything is
# created (#291): up to 24 000 characters on the command line; above it - Windows cuts a command line at
# 32 767, after the worktree and branch exist - in a file beside the kept briefs (pruned with them), and
# the session's first message is a short instruction to read that file
$notice = ''
$wtFwd = $wt.Replace('\', '/')
$same = (Resolve-Path -LiteralPath $from).Path.Replace('\', '/').TrimEnd('/') -eq (Resolve-Path -LiteralPath $root).Path.Replace('\', '/').TrimEnd('/')
if ($asst) {
  # an assistant: its folder is its memory - it lives on across compactions and restarts from the files there
  $first = "YOUR FOLDER is $adir/ - you are the assistant `"$aname`": no worktree, no branch. Read $adir/BRIEF.md in full before anything else and keep $adir/NOTES.md as your memory; re-read both after every compaction (a summary loses rules) and after a restart. Write only inside $adir/; never change, commit, push or open a PR in the project."
  $protRoot = ''
  if ($cfg.env -is [Management.Automation.PSCustomObject] -and $cfg.env.COORD_PROTECTED_ROOT -is [string]) { $protRoot = $cfg.env.COORD_PROTECTED_ROOT }
  if (-not $protRoot) { $notice = "notice: COORD_PROTECTED_ROOT is not set in ${Safety}: edit tools can reach the working copy (TOOLKIT Safety)" }
} elseif ($same) {
  $first = "FIRST ACTION, before anything else: use the EnterWorktree tool with path = $wtFwd. Work only inside it; never change files outside it."
  # it starts in the owner's working copy: the guard keeps the edit tools out of it only with
  # COORD_PROTECTED_ROOT in the safety file's env (a notice, not a failure)
  $protRoot = ''
  if ($cfg.env -is [Management.Automation.PSCustomObject] -and $cfg.env.COORD_PROTECTED_ROOT -is [string]) { $protRoot = $cfg.env.COORD_PROTECTED_ROOT }
  if (-not $protRoot) { $notice = "notice: COORD_PROTECTED_ROOT is not set in ${Safety}: edit tools can reach the working copy (TOOLKIT Safety)" }
} else {
  # launched outside the repository (its root not trusted): EnterWorktree into another repository's
  # worktree asks for permission and the session would wait, so it works there by absolute path
  $rootFwd = $root.Replace('\', '/')
  $first = "YOUR WORKING COPY is $wtFwd, a worktree of $rootFwd. Work in it by absolute path (git -C $wtFwd ..., files under $wtFwd); do not use EnterWorktree; never change files outside it."
}
if ($asst) { $first += "`nQuestions to: the session named `"$ReportTo`" (SendMessage) - only what your folder, the run log and the journal do not hold." }
else { $first += "`nReport to: the session named `"$ReportTo`" (SendMessage) - your report and your questions." }
# the role from the name (#<task> <role>: <title>): a session is not a subagent, so its role file's body
# heads the brief (TOOLKIT Roles) - from this core's roles/, unless the brief already carries it
$briefText = [IO.File]::ReadAllText($BriefFile)
$roleText = ''; $roleMsg = ''
if ($Name -cmatch '^(#\S* )?([a-z]+):') {
  $role = $Matches[2]
  $roleFile = Join-Path (Split-Path -Parent $PSScriptRoot) "roles/$role.md"
  if (Test-Path -LiteralPath $roleFile -PathType Leaf) {
    $lines = @([IO.File]::ReadAllLines($roleFile)); $body = @(); $front = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
      if ($i -eq 0 -and $lines[$i] -match '^---') { $front = $true; continue }
      if ($front -and $lines[$i] -match '^---') { $front = $false; continue }
      if (-not $front) { $body += $lines[$i] }
    }
    # the body without its leading and trailing blank lines, as the shell's $(...) keeps it
    $bodyText = ($body -join "`n").Trim("`n")
    $key = @($body | Where-Object { $_ -ne '' })[0]
    if ($key -and $briefText.Replace("`r", '').Contains($key)) { $roleMsg = "role ${role}: already in the brief" }
    else { $roleText = $bodyText; $roleMsg = "role ${role}: roles/$role.md heads the brief" }
  }
}
# a lead's notes (sub-contracts, briefs, run notes, the tester's test copies, evidence) live beside its
# worktree, in <worktree>.lead/, where the project's own checks (test runners, linters) never read them (#310)
$notes = ''
if ($Name -cmatch '^(#\S* )?([a-z]+):' -and $Matches[2] -ceq 'lead') {
  $notes = "$wtFwd.lead"
  # never a git working copy (a registered worktree, or a folder holding a .git entry): its files would be
  # mixed with the notes and lost at the cleanup - refused before anything is created
  $nFold = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows -or $IsMacOS
  $nForm = { param([string]$x) $x = $x.Replace('\', '/').TrimEnd('/'); if ($nFold) { $x.ToLowerInvariant() } else { $x } }
  $nwc = Test-Path -LiteralPath (Join-Path $notes '.git')
  $nc = & $nForm $notes
  $np = ''; if (Test-Path -LiteralPath $notes -PathType Container) { $np = & $nForm (Resolve-Path -LiteralPath $notes).Path }
  $wl = & { $ErrorActionPreference = 'Continue'; git -C $root worktree list --porcelain 2>$null }
  foreach ($l in @($wl)) {
    if ("$l" -cmatch '^worktree (.+)$') { $x = & $nForm $Matches[1].Trim(); if ($x -ceq $nc -or ($np -and $x -ceq $np)) { $nwc = $true } }
  }
  if ($nwc) { Fail "refused: the lead's notes path $notes is a git working copy (a worktree or a folder holding .git) - a notes folder never is one; move that worktree away or start the lead on another branch" }
  # the one exception to "never change files outside it", right after the first line
  $i = $first.IndexOf("`n")
  $first = $first.Substring(0, $i) + "`nYour notes folder: $notes - the one exception to `"never change files outside it`": beside your worktree, never inside it; your sub-contracts, briefs, run notes, the tester's test copies and evidence go there (roles/lead.md)." + $first.Substring($i)
}
$full = $first + "`n`n" + $(if ($roleText) { $roleText + "`n`n" } else { '' }) + $briefText
# characters as the .sh counts them: a surrogate pair is one
$nChars = $full.Length - [regex]::Matches($full, '[\uDC00-\uDFFF]').Count
$cfgDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
$bd = (Join-Path $cfgDir 'coordinator/briefs').Replace('\', '/')
$lFile = ''
if ($nChars -gt 24000) { $lFile = "$bd/launch-$($(if ($asst) { "assistant-$aname" } else { $Branch }) -replace '[^A-Za-z0-9._-]', '-')-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$PID.md" }

# The worktrees' folder stays out of its repository's git, like coordinator/ (INIT 3.4): a line in the
# local .git/info/exclude, never .gitignore - nothing the project's history, its team or a client sees.
$wroot = if ($WorktreeRoot) { $WorktreeRoot } else { Join-Path $root '.claude/worktrees' }
if ($asst) { }   # an assistant creates nothing: no worktree, no exclude line
elseif ($DryRun) { "[dry-run] keep $wroot out of its repository's git (.git/info/exclude)" }
else {
  New-Item -ItemType Directory -Force -Path $wroot | Out-Null
  $r = & {
    $ErrorActionPreference = 'Continue'
    $p = git -C $wroot rev-parse --show-prefix 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $p) { return }
    git -C $wroot check-ignore -q x 2>$null
    if ($LASTEXITCODE -eq 0) { return }
    , @($p, (git -C $wroot rev-parse --path-format=absolute --git-common-dir))
  }
  if ($r) {
    New-Item -ItemType Directory -Force -Path (Join-Path $r[1] 'info') | Out-Null
    $ex = Join-Path $r[1] 'info/exclude'
    # a file without a final newline would glue the new line to its last one (e.g. coordinator/)
    $nl = ''
    if ((Test-Path -LiteralPath $ex) -and (Get-Item -LiteralPath $ex).Length -gt 0) {
      $bytes = [IO.File]::ReadAllBytes($ex); if ($bytes[$bytes.Length - 1] -ne 10) { $nl = "`n" }
    }
    [IO.File]::AppendAllText($ex, "$nl/$($r[0])`n")
    "added /$($r[0]) to the repository's .git/info/exclude"
  }
}
# The coordinator's own state repository (<root>/coordinator, INIT 3.4) never shows in the project's git
# either: a project that got `git init` after coordinator/ existed has no line for it yet
if (-not $asst -and (Test-Path -LiteralPath (Join-Path $root 'coordinator/.git'))) {
  $ign = & { $ErrorActionPreference = 'Continue'; git -C $root check-ignore -q coordinator/ 2>$null; $LASTEXITCODE }
  if ($ign -ne 0) {
    if ($DryRun) { "[dry-run] add /coordinator/ to the repository's .git/info/exclude" }
    else {
      $common = & { $ErrorActionPreference = 'Continue'; git -C $root rev-parse --path-format=absolute --git-common-dir }
      New-Item -ItemType Directory -Force -Path (Join-Path $common 'info') | Out-Null
      $ex = Join-Path $common 'info/exclude'
      # a file without a final newline would glue the new line to its last one
      $nl = ''
      if ((Test-Path -LiteralPath $ex) -and (Get-Item -LiteralPath $ex).Length -gt 0) {
        $bytes = [IO.File]::ReadAllBytes($ex); if ($bytes[$bytes.Length - 1] -ne 10) { $nl = "`n" }
      }
      [IO.File]::AppendAllText($ex, "$nl/coordinator/`n")
      "added /coordinator/ to the repository's .git/info/exclude"
    }
  }
}
# An older lead kept its sub-contracts, briefs and run notes in <its worktree>/.lead/ (now beside it, #310),
# never committed: one line, which info/exclude applies to every worktree of the repository
$ign = if ($asst) { 0 } else { & { $ErrorActionPreference = 'Continue'; git -C $root check-ignore -q .lead/x 2>$null; $LASTEXITCODE } }
if ($ign -ne 0) {
  if ($DryRun) { "[dry-run] add /.lead/ to the repository's .git/info/exclude" }
  else {
    $common = & { $ErrorActionPreference = 'Continue'; git -C $root rev-parse --path-format=absolute --git-common-dir }
    New-Item -ItemType Directory -Force -Path (Join-Path $common 'info') | Out-Null
    $ex = Join-Path $common 'info/exclude'
    $nl = ''
    if ((Test-Path -LiteralPath $ex) -and (Get-Item -LiteralPath $ex).Length -gt 0) {
      $bytes = [IO.File]::ReadAllBytes($ex); if ($bytes[$bytes.Length - 1] -ne 10) { $nl = "`n" }
    }
    [IO.File]::AppendAllText($ex, "$nl/.lead/`n")
    "added /.lead/ to the repository's .git/info/exclude"
  }
}

if ($asst) { $made = 'nothing (an assistant has no worktree or branch)' }
elseif (Test-Path -LiteralPath $wt) {
  # only a worktree of this repository is reused; a stale folder there is refused, never entered
  $ok = & {
    $ErrorActionPreference = 'Continue'
    # the folder is the worktree's top when git sees no prefix there (a symlink in the path does not
    # matter: git reports the real path, Resolve-Path keeps the link)
    $prefix = git -C $wt rev-parse --show-prefix 2>$null
    if ($LASTEXITCODE -ne 0 -or $prefix) { return $false }
    "$(git -C $wt rev-parse --path-format=absolute --git-common-dir)" -eq "$(git -C $root rev-parse --path-format=absolute --git-common-dir)"
  }
  if (-not $ok) { Fail "$wt exists but is not a worktree of ${root}: remove or rename it first" }
  # and only with this branch checked out (a folder in another letter case is the same folder)
  $cur = & { $ErrorActionPreference = 'Continue'; "$(git -C $wt symbolic-ref --short -q HEAD 2>$null)".Trim() }
  if ($cur -cne $Branch) { Fail "$wt has $(if ($cur) { $cur } else { 'a detached HEAD' }) checked out, not $Branch" }
  "reusing worktree $wt"
  $made = "nothing new (the worktree $wtFwd was reused)"
}
else {
  $made = if ($hasBranch) { "the worktree $wtFwd (on the existing branch $Branch)" } else { "the worktree $wtFwd and the branch $Branch" }
  # with a tester's commit, git's own "HEAD is now at <sha>" is left out: the line above names the commit
  $wq = @(if ($tFull) { '-q' })
  if ($hasBranch) { Run git (@('-C', $root, 'worktree', 'add') + $wq + @($wt, $Branch)) }
  else { Run git (@('-C', $root, 'worktree', 'add') + $wq + @('--no-track', '-b', $Branch, $wt, $start)) }
}

# the lead's notes folder beside its worktree: made once, an existing one kept as it is
if ($notes) {
  if ($DryRun) { "[dry-run] create the notes folder $notes" }
  elseif (Test-Path -LiteralPath $notes -PathType Container) { "notes folder: $notes (kept)" }
  else {
    try { New-Item -ItemType Directory -Force -Path $notes -ErrorAction Stop | Out-Null }
    catch { Fail "cannot create the notes folder $notes. Created: $made - clean it with cleanup-worker (-Worktree $wtFwd), or start again with the same branch" }
    "notes folder: $notes"
  }
}
if ($notice) { $notice }
if ($roleMsg) { $roleMsg }
# conflict foresight (CORE section 4a, #242): the open PRs changing what the brief's `touches` names - inline
# `touches: [a, b]` or a block list (`touches:` then one `- a` per line, as check-contract takes it, #258) -,
# printed for the coordinator, never a stop - for a worker or a lead (gh missing or failing: a notice)
$sect = [string][char]0x00A7   # not a literal: Windows PowerShell 5.1 reads a BOM-less script as ANSI
$fr = ''; if ($Name -cmatch '^(#\S* )?([a-z]+):') { $fr = $Matches[2] }
if ($fr -in @('worker', 'lead', '')) {
  $raw = @(); $bl = $briefText.Replace("`r", '') -split "`n"
  for ($i = 0; $i -lt $bl.Count; $i++) {
    if ($bl[$i] -cnotmatch '^[ \t]*touches:') { continue }
    # a comment needs a blank before it (docs/c#.md is a path); blank and comment lines inside the list are skipped
    $s = (($bl[$i] -creplace '^[ \t]*touches:[ \t]*', '') -replace '[ \t]+#.*$', '') -replace '^#.*$', ''
    if ($s.StartsWith('[')) { $raw = @(($s.Substring(1) -replace '\].*$', '') -split ',') }
    elseif ($s -eq '') {
      for ($j = $i + 1; $j -lt $bl.Count; $j++) {
        if ($bl[$j] -match '^[ \t]*(#.*)?$') { continue }
        if ($bl[$j] -notmatch '^[ \t]*-[ \t]') { break }
        $raw += (($bl[$j] -replace '^[ \t]*-[ \t]*', '') -replace '[ \t]+#.*$', '')
      }
    }
    break
  }
  $tl = @($raw | ForEach-Object { $_.Trim().Trim('"', "'").Trim() } | Where-Object { $_ })
  if (-not $tl.Count) {
    "foresight: no touches in the brief - check the open PRs against the task yourself (CORE ${sect}4a)"
  } else {
    $fo = @(); $frc = 1
    Push-Location -LiteralPath $root
    try { $fo = @(& (Join-Path $PSScriptRoot 'merge-queue.ps1') status -Touches ($tl -join ',') 2>&1 | ForEach-Object { "$_" }); $frc = $LASTEXITCODE }
    catch { $fo = @("$_") } finally { Pop-Location }
    if ($frc -eq 0) { $fo | Where-Object { $_ -match '^(TOUCHES|merge-queue status:)' } | ForEach-Object { "foresight: $_" } }
    else { "foresight: merge-queue status failed - check the open PRs against the task yourself (CORE ${sect}4a): $(@($fo)[0])" }
  }
}
$brief = $full   # $full as sent, before the escaping below: kept for after a compaction
$subscribe = "subscribe: SendMessage(to: `"$Name`", notify_when_idle: true)"
if ($DryRun -and $lFile) { "[dry-run] brief through a file: $nChars characters of launch text, over 24000 - it would go to $lFile and the first message would point to it" }
$where = if ($asst) { "the folder $adir/, questions to `"$ReportTo`"" } else { "working copy $wtFwd, report to `"$ReportTo`"" }
if ($DryRun) { "[dry-run] (cd $from && claude --bg --name `"$Name`" --model $Model$(if ($Effort) { " --effort $Effort" }) --permission-mode $Mode --settings $Safety <$where, $(if ($roleText) { 'the role, ' })then the brief>)"; $subscribe; exit 0 }
$claude = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claude) { Fail 'claude not found on PATH' }
# A .cmd shim (npm install) cuts a multi-line argument at the first line break.
if ($claude.Source -match '\.(cmd|bat)$') { Fail "claude is a $($Matches[1]) shim ($($claude.Source)): install the native claude.exe, which carries a multi-line brief intact" }
if ($lFile) {
  try {
    $null = New-Item -ItemType Directory -Force -Path $bd
    [IO.File]::WriteAllText($lFile, $full + "`n", (New-Object System.Text.UTF8Encoding $false))
  } catch { Fail "launch not started: cannot write the brief file $lFile. Created: $made - clean it with cleanup-worker (-Worktree $wtFwd), or start again with the same branch" }
  $brief = "Your brief is too long for the command line ($nChars characters), so it is in the file `"$lFile`". Before anything else, read that whole file with the Read tool (in parts with offset and limit if a read is cut short), then follow it as your brief: it holds your first action, your report address, your role and your task."
  "brief through a file: $nChars characters of launch text, over 24000 - the session's first message points to $lFile"
}
# Windows PowerShell 5.1 (and 7.0-7.2) does not escape quotes inside native arguments: do it here,
# for the brief and the session's name (a name with a " would reach claude without it).
$argName = $Name
if ($PSVersionTable.PSVersion -lt [version]'7.3') {
  $brief = ($brief -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1'
  $argName = ($Name -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1'
}
Push-Location -LiteralPath $from
$eff = @(if ($Effort) { '--effort', $Effort })
# the launch output is read for its id (`backgrounded · <id> · <name>`), then printed as it came
$bgOut = @()
try { $bgOut = @(& $claude.Source --bg --name $argName --model $Model @eff --permission-mode $Mode --settings $Safety $brief | ForEach-Object { "$_" }) }
finally { Pop-Location }
$bgRc = $LASTEXITCODE
$bgOut
$bgId = ''; foreach ($l in $bgOut) { $m = [regex]::Match($l, 'backgrounded[^0-9A-Za-z]*([0-9A-Za-z][0-9A-Za-z-]*)'); if ($m.Success) { $bgId = $m.Groups[1].Value; break } }
# a launch that fails leaves the worktree and branch: say so, and how to clean them
if ($bgRc -ne 0) {
  if ($lFile) { Remove-Item -LiteralPath $lFile -Force -ErrorAction SilentlyContinue }
  if ($asst) { Fail "launch failed: claude --bg did not start the session. Created: $made - start again" }
  Fail "launch failed: claude --bg did not start the session. Created: $made - clean it with cleanup-worker (-Worktree $wtFwd), or start again with the same branch"
}
# wait (up to 20 s) until the new session is listed, so the subscribe below does not race it
# the listing is JSON: a backslash or a double quote in the name is escaped there
$jname = $Name.Replace('\', '\\').Replace('"', '\"')
for ($i = 0; $i -lt 20; $i++) {
  if ("$(& $claude.Source agents --json)".Contains('"' + $jname + '"')) { break }
  Start-Sleep -Seconds 1
}
if ($i -ge 20) { [Console]::Error.WriteLine('not listed after 20 s: if the subscribe fails, retry it in a few seconds') }
# the brief as sent, kept by the session's id: hooks/after-compact.ps1 points the session back to it after
# a compaction (a summary loses rules); briefs older than 14 days are pruned
$sid = ''
foreach ($o in ("$(& $claude.Source agents --json 2>$null)" -replace "[`r`n]", '') -split '}') {
  if ($o.Contains('"' + $jname + '"')) { $m = [regex]::Match($o, '"sessionId": *"([0-9a-fA-F-]+)"'); if ($m.Success) { $sid = $m.Groups[1].Value } }
}
if ($sid) {
  $null = New-Item -ItemType Directory -Force -Path $bd
  [IO.File]::WriteAllText((Join-Path $bd "$sid.md"), $full + "`n", (New-Object System.Text.UTF8Encoding $false))
  "brief kept for after a compaction: $((Join-Path $bd "$sid.md").Replace('\', '/'))"
  Get-ChildItem -LiteralPath $bd -Filter '*.md' -File | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-14) } | Remove-Item -Force -ErrorAction SilentlyContinue
} else { [Console]::Error.WriteLine('no sessionId in the listing: the brief is not kept for after a compaction') }
if ($asst) {
  "attach: claude attach `"$Name`""
  if ($bgId) { "attach: claude attach $bgId" }
}
$subscribe
exit 0
} finally { if ($enc0) { try { [Console]::OutputEncoding = $enc0 } catch { } } }
