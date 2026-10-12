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
# The session starts in the repository root (-LaunchFrom overrides it), which the owner trusts once:
# Claude Code refuses --bg in a folder nobody trusted, and a new worktree never is (trust is not
# inherited from a parent). The brief's first line sends it into its worktree (EnterWorktree).
# -WorktreeRoot puts the worktree elsewhere (default <repo>/.claude/worktrees). Launched from a folder
# that is not the repository's root (the self-test: the state repository's worktrees under the trusted
# project), the brief says to work in the worktree by absolute path instead. A repository without an
# origin starts the branch from the local -Base.
# The hook path in -Safety uses forward slashes: hooks run through Git Bash on Windows, which drops
# backslashes, and a hook that fails to run blocks nothing.
# The brief is passed as the session's first prompt argument. Run with -DryRun first on a new machine.
param([string]$Repo, [string]$Name, [string]$Branch, [string]$Model, [string]$BriefFile, [string]$Safety,
      [string]$Mode = 'auto', [string]$Base = 'main', [string]$LaunchFrom = '', [string]$ReportTo = '', [string]$WorktreeRoot = '', [switch]$DryRun)
$ErrorActionPreference = 'Stop'
function Fail([string]$m) { [Console]::Error.WriteLine($m); exit 1 }

if (-not ($Repo -and $Name -and $Branch -and $Model -and $ReportTo -and $BriefFile -and $Safety) -or
    -not (Test-Path -LiteralPath $BriefFile -PathType Leaf) -or -not (Test-Path -LiteralPath $Safety -PathType Leaf)) {
  Fail 'usage: -Repo <path> -Name <session name> -Branch <branch> -Model <model> -BriefFile <file> -Safety <settings.json> -ReportTo <session> [-Mode auto] [-Base main] [-LaunchFrom <folder>] [-WorktreeRoot <folder>] [-DryRun]'
}
if ($Mode -eq 'bypassPermissions') { Fail "refusing bypassPermissions for a worker (TOOLKIT.md Safety: only the owner's own explicit setup)" }
# Absolute paths: both files are used from inside the worktree.
$Safety = (Resolve-Path -LiteralPath $Safety).Path; $BriefFile = (Resolve-Path -LiteralPath $BriefFile).Path

$root = (git -C $Repo rev-parse --show-toplevel)
if ($LASTEXITCODE -ne 0) { Fail "not a git repository: $Repo" }
$wt = Join-Path $(if ($WorktreeRoot) { $WorktreeRoot } else { Join-Path $root '.claude/worktrees' }) $Branch
$from = if ($LaunchFrom) { $LaunchFrom } else { $root }
if (-not (Test-Path -LiteralPath $from -PathType Container)) { Fail "no folder to launch from: $from" }

# Safety settings: the hook path inside the file must exist and pass its self-test.
$text = [IO.File]::ReadAllText($Safety)
$cfg = $text | ConvertFrom-Json
$hookCmd = @($cfg.hooks.PreToolUse | ForEach-Object { $_.hooks } | ForEach-Object { $_.command } |
  Where-Object { $_ -match 'safety-guard\.(ps1|sh)' })[0]
$hook = ''
if ($hookCmd -match '"([^"]*safety-guard\.(ps1|sh))"') { $hook = $Matches[1] }
elseif ($hookCmd -match '(\S*safety-guard\.(ps1|sh))') { $hook = $Matches[1] }
if ($hookCmd -match '\\') { Fail 'safety settings: write the hook path with forward slashes (C:/...): hooks run through Git Bash on Windows, which drops backslashes, and a hook that fails to run blocks nothing' }
if (-not $hook -or -not (Test-Path -LiteralPath $hook -PathType Leaf)) { Fail "safety settings: hook not found at '$hook' (use an absolute path)" }
if (-not $cfg.worktree.bgIsolation) { Fail 'safety settings: add "worktree": {"bgIsolation": "none"}' }
if ($hook.EndsWith('.ps1')) {
  $selftest = & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $hook -SelfTest
} else { $selftest = bash $hook --self-test }
if ("$selftest".Trim() -ne 'safety-guard: OK') { Fail "$selftest" }

function Run([string]$exe, [string[]]$a) {
  if ($DryRun) { "[dry-run] $exe $($a -join ' ')" } else { & $exe @a; if ($LASTEXITCODE -ne 0) { Fail "$exe failed" } }
}

# no origin (a local-only repository, e.g. a state repository without a remote): the local base branch
$origin = git -C $root config --get remote.origin.url
if ($origin) { Run git @('-C', $root, 'fetch', '-q', 'origin', $Base); $start = "origin/$Base" } else { $start = $Base }
if (Test-Path -LiteralPath $wt) { "reusing worktree $wt" }
else {
  git -C $root show-ref -q --verify "refs/heads/$Branch"
  if ($LASTEXITCODE -eq 0) { Run git @('-C', $root, 'worktree', 'add', $wt, $Branch) }
  else { Run git @('-C', $root, 'worktree', 'add', '--no-track', '-b', $Branch, $wt, $start) }
}

$wtFwd = $wt.Replace('\', '/')
$same = (Resolve-Path -LiteralPath $from).Path.Replace('\', '/').TrimEnd('/') -eq (Resolve-Path -LiteralPath $root).Path.Replace('\', '/').TrimEnd('/')
if ($same) {
  $first = "FIRST ACTION, before anything else: use the EnterWorktree tool with path = $wtFwd. Work only inside it; never change files outside it."
} else {
  # launched outside the repository (its root not trusted): EnterWorktree into another repository's
  # worktree asks for permission and the session would wait, so it works there by absolute path
  $rootFwd = $root.Replace('\', '/')
  $first = "YOUR WORKING COPY is $wtFwd, a worktree of $rootFwd. Work in it by absolute path (git -C $wtFwd ..., files under $wtFwd); do not use EnterWorktree; never change files outside it."
}
$first += "`nReport to: the session named `"$ReportTo`" (SendMessage) - your report and your questions."
$brief = $first + "`n`n" + [IO.File]::ReadAllText($BriefFile)
$subscribe = "subscribe: SendMessage(to: `"$Name`", notify_when_idle: true)"
if ($DryRun) { "[dry-run] (cd $from && claude --bg --name `"$Name`" --model $Model --permission-mode $Mode --settings $Safety <working copy $wtFwd, report to `"$ReportTo`", then the brief>)"; $subscribe; exit 0 }
$claude = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claude) { Fail 'claude not found on PATH' }
# A .cmd shim (npm install) cuts a multi-line argument at the first line break.
if ($claude.Source -match '\.(cmd|bat)$') { Fail "claude is a $($Matches[1]) shim ($($claude.Source)): install the native claude.exe, which carries a multi-line brief intact" }
# Windows PowerShell 5.1 (and 7.0-7.2) does not escape quotes inside native arguments: do it here.
if ($PSVersionTable.PSVersion -lt [version]'7.3') { $brief = ($brief -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1' }
Push-Location -LiteralPath $from
try { & $claude.Source --bg --name $Name --model $Model --permission-mode $Mode --settings $Safety $brief }
finally { Pop-Location }
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
# wait (up to 20 s) until the new session is listed, so the subscribe below does not race it
for ($i = 0; $i -lt 20; $i++) {
  if ("$(& $claude.Source agents --json)".Contains('"' + $Name + '"')) { break }
  Start-Sleep -Seconds 1
}
if ($i -ge 20) { [Console]::Error.WriteLine('not listed after 20 s: if the subscribe fails, retry it in a few seconds') }
$subscribe
exit 0
