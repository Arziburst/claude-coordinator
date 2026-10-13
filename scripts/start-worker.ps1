# Start a named worker session in its own git worktree, with the safety settings applied
# (Windows; macOS / Linux: start-worker.sh - the same steps and checks).
#   powershell -File scripts\start-worker.ps1 -Repo <project repo path> -Name "#12 worker: Fix login" `
#       -Branch 12-fix-login -Model opus -BriefFile brief.md -Safety <worker settings .json> [-Mode auto] [-Base main]
#       -ReportTo <coordinator session> [-LaunchFrom <folder>] [-WorktreeRoot <folder>] [-DryRun]
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
# The brief is passed as the session's first prompt argument. Run with -DryRun first on a new machine.
param([string]$Repo, [string]$Name, [string]$Branch, [string]$Model, [string]$BriefFile, [string]$Safety,
      [string]$Mode = 'auto', [string]$Base = 'main', [string]$LaunchFrom = '', [string]$ReportTo = '', [string]$WorktreeRoot = '', [switch]$DryRun)
# native output (git, bash) is read and this script's own output written as UTF-8, whatever the console's
# code page (cp866 on a Russian Windows garbles a non-ASCII path or a section sign); no console: left as is.
# The caller's console gets its own encoding back on every way out (the end, any exit N, a terminating
# error): the body below runs inside try, the encoding is restored in finally.
$enc0 = $null; try { $enc0 = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
try {
$ErrorActionPreference = 'Stop'
function Fail([string]$m) { [Console]::Error.WriteLine($m); exit 1 }

if (-not ($Repo -and $Name -and $Branch -and $Model -and $ReportTo -and $BriefFile -and $Safety) -or
    -not (Test-Path -LiteralPath $BriefFile -PathType Leaf) -or -not (Test-Path -LiteralPath $Safety -PathType Leaf)) {
  Fail 'usage: -Repo <path> -Name <session name> -Branch <branch> -Model <model> -BriefFile <file> -Safety <settings.json> -ReportTo <session> [-Mode auto] [-Base main] [-LaunchFrom <folder>] [-WorktreeRoot <folder>] [-DryRun]'
}
foreach ($v in @(@('Repo', $Repo), @('Name', $Name), @('Branch', $Branch), @('Model', $Model), @('BriefFile', $BriefFile),
                  @('Safety', $Safety), @('Mode', $Mode), @('Base', $Base), @('LaunchFrom', $LaunchFrom),
                  @('ReportTo', $ReportTo), @('WorktreeRoot', $WorktreeRoot))) {
  if ("$($v[1])".StartsWith('-')) { Fail "missing value for -$($v[0]) (got the flag $($v[1]))" }
}
if ($Mode -eq 'bypassPermissions') { Fail "refusing bypassPermissions for a worker (TOOLKIT.md Safety: only the owner's own explicit setup)" }
# Absolute paths: both files are used from inside the worktree.
$Safety = (Resolve-Path -LiteralPath $Safety).Path; $BriefFile = (Resolve-Path -LiteralPath $BriefFile).Path
# a relative -WorktreeRoot is taken from the current folder (git would resolve it against the repository)
if ($WorktreeRoot -and -not [IO.Path]::IsPathRooted($WorktreeRoot)) { $WorktreeRoot = Join-Path (Get-Location).Path $WorktreeRoot }

$root = (git -C $Repo rev-parse --show-toplevel)
if ($LASTEXITCODE -ne 0) { Fail "not a git repository: $Repo" }
$wt = Join-Path $(if ($WorktreeRoot) { $WorktreeRoot } else { Join-Path $root '.claude/worktrees' }) $Branch
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

function Run([string]$exe, [string[]]$a) {
  if ($DryRun) { "[dry-run] $exe $($a -join ' ')" } else { & $exe @a; if ($LASTEXITCODE -ne 0) { Fail "$exe failed" } }
}

# The worktrees' folder stays out of its repository's git, like coordinator/ (INIT 3.4): a line in the
# local .git/info/exclude, never .gitignore - nothing the project's history, its team or a client sees.
$wroot = if ($WorktreeRoot) { $WorktreeRoot } else { Join-Path $root '.claude/worktrees' }
if ($DryRun) { "[dry-run] keep $wroot out of its repository's git (.git/info/exclude)" }
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
if (Test-Path -LiteralPath (Join-Path $root 'coordinator/.git')) {
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
# A lead keeps its sub-contracts, briefs and run notes in <its worktree>/.lead/ (roles/lead.md), never
# committed: one line, which info/exclude applies to every worktree of the repository
$ign = & { $ErrorActionPreference = 'Continue'; git -C $root check-ignore -q .lead/x 2>$null; $LASTEXITCODE }
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

# no origin (a local-only repository, e.g. a state repository without a remote): the local base branch;
# a base not on origin yet (a lead's integration branch before its first push): the local one too
$origin = git -C $root config --get remote.origin.url
if ($origin) {
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
if (Test-Path -LiteralPath $wt) {
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
}
else {
  if ($hasBranch) { Run git @('-C', $root, 'worktree', 'add', $wt, $Branch) }
  else { Run git @('-C', $root, 'worktree', 'add', '--no-track', '-b', $Branch, $wt, $start) }
}

$wtFwd = $wt.Replace('\', '/')
$same = (Resolve-Path -LiteralPath $from).Path.Replace('\', '/').TrimEnd('/') -eq (Resolve-Path -LiteralPath $root).Path.Replace('\', '/').TrimEnd('/')
if ($same) {
  $first = "FIRST ACTION, before anything else: use the EnterWorktree tool with path = $wtFwd. Work only inside it; never change files outside it."
  # it starts in the owner's working copy: the guard keeps the edit tools out of it only with
  # COORD_PROTECTED_ROOT in the safety file's env (a notice, not a failure)
  $protRoot = ''
  if ($cfg.env -is [Management.Automation.PSCustomObject] -and $cfg.env.COORD_PROTECTED_ROOT -is [string]) { $protRoot = $cfg.env.COORD_PROTECTED_ROOT }
  if (-not $protRoot) { "notice: COORD_PROTECTED_ROOT is not set in ${Safety}: edit tools can reach the working copy (TOOLKIT Safety)" }
} else {
  # launched outside the repository (its root not trusted): EnterWorktree into another repository's
  # worktree asks for permission and the session would wait, so it works there by absolute path
  $rootFwd = $root.Replace('\', '/')
  $first = "YOUR WORKING COPY is $wtFwd, a worktree of $rootFwd. Work in it by absolute path (git -C $wtFwd ..., files under $wtFwd); do not use EnterWorktree; never change files outside it."
}
$first += "`nReport to: the session named `"$ReportTo`" (SendMessage) - your report and your questions."
# the role from the name (#<task> <role>: <title>): a session is not a subagent, so its role file's body
# heads the brief (TOOLKIT Roles) - from this core's roles/, unless the brief already carries it
$briefText = [IO.File]::ReadAllText($BriefFile)
$roleText = ''
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
    if ($key -and $briefText.Replace("`r", '').Contains($key)) { "role ${role}: already in the brief" }
    else { $roleText = $bodyText; "role ${role}: roles/$role.md heads the brief" }
  }
}
$brief = $first + "`n`n" + $(if ($roleText) { $roleText + "`n`n" } else { '' }) + $briefText
$subscribe = "subscribe: SendMessage(to: `"$Name`", notify_when_idle: true)"
if ($DryRun) { "[dry-run] (cd $from && claude --bg --name `"$Name`" --model $Model --permission-mode $Mode --settings $Safety <working copy $wtFwd, report to `"$ReportTo`", $(if ($roleText) { 'the role, ' })then the brief>)"; $subscribe; exit 0 }
$claude = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claude) { Fail 'claude not found on PATH' }
# A .cmd shim (npm install) cuts a multi-line argument at the first line break.
if ($claude.Source -match '\.(cmd|bat)$') { Fail "claude is a $($Matches[1]) shim ($($claude.Source)): install the native claude.exe, which carries a multi-line brief intact" }
# Windows PowerShell 5.1 (and 7.0-7.2) does not escape quotes inside native arguments: do it here,
# for the brief and the session's name (a name with a " would reach claude without it).
$argName = $Name
if ($PSVersionTable.PSVersion -lt [version]'7.3') {
  $brief = ($brief -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1'
  $argName = ($Name -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1'
}
Push-Location -LiteralPath $from
try { & $claude.Source --bg --name $argName --model $Model --permission-mode $Mode --settings $Safety $brief }
finally { Pop-Location }
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
# wait (up to 20 s) until the new session is listed, so the subscribe below does not race it
# the listing is JSON: a backslash or a double quote in the name is escaped there
$jname = $Name.Replace('\', '\\').Replace('"', '\"')
for ($i = 0; $i -lt 20; $i++) {
  if ("$(& $claude.Source agents --json)".Contains('"' + $jname + '"')) { break }
  Start-Sleep -Seconds 1
}
if ($i -ge 20) { [Console]::Error.WriteLine('not listed after 20 s: if the subscribe fails, retry it in a few seconds') }
$subscribe
exit 0
} finally { if ($enc0) { try { [Console]::OutputEncoding = $enc0 } catch { } } }
