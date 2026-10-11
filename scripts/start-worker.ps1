# Start a named worker session in its own git worktree, with the safety settings applied
# (Windows; macOS / Linux: start-worker.sh - the same steps and checks).
#   powershell -File scripts\start-worker.ps1 -Repo <project repo path> -Name "#12 worker: Fix login" `
#       -Branch 12-fix-login -Model opus -BriefFile brief.md -Safety <worker settings .json> [-Mode auto] [-Base main]
#       [-LaunchFrom <folder>] [-DryRun]
# -Safety: a settings file for the worker (from settings.example.windows.json) with the deny rules, the
#          PreToolUse hook at an ABSOLUTE path and "worktree": {"bgIsolation": "none"}. The hook's
#          self-test must pass, or no worker starts. -Model is required (CORE section 7). Default mode auto;
#          acceptEdits for the cautious level; bypassPermissions is refused. Exit 1 on any failed check.
# The session starts in the repository root (-LaunchFrom overrides it), which the owner trusts once:
# Claude Code refuses --bg in a folder nobody trusted, and a new worktree never is (trust is not
# inherited from a parent). The brief's first line sends it into its worktree (EnterWorktree).
# The hook path in -Safety uses forward slashes: hooks run through Git Bash on Windows, which drops
# backslashes, and a hook that fails to run blocks nothing.
# The brief is passed as the session's first prompt argument. Run with -DryRun first on a new machine.
param([string]$Repo, [string]$Name, [string]$Branch, [string]$Model, [string]$BriefFile, [string]$Safety,
      [string]$Mode = 'auto', [string]$Base = 'main', [string]$LaunchFrom = '', [switch]$DryRun)
$ErrorActionPreference = 'Stop'
function Fail([string]$m) { [Console]::Error.WriteLine($m); exit 1 }

if (-not ($Repo -and $Name -and $Branch -and $Model -and $BriefFile -and $Safety) -or
    -not (Test-Path -LiteralPath $BriefFile -PathType Leaf) -or -not (Test-Path -LiteralPath $Safety -PathType Leaf)) {
  Fail 'usage: -Repo <path> -Name <session name> -Branch <branch> -Model <model> -BriefFile <file> -Safety <settings.json> [-Mode auto] [-Base main] [-LaunchFrom <folder>] [-DryRun]'
}
if ($Mode -eq 'bypassPermissions') { Fail "refusing bypassPermissions for a worker (TOOLKIT.md Safety: only the owner's own explicit setup)" }
# Absolute paths: both files are used from inside the worktree.
$Safety = (Resolve-Path -LiteralPath $Safety).Path; $BriefFile = (Resolve-Path -LiteralPath $BriefFile).Path

$root = (git -C $Repo rev-parse --show-toplevel)
if ($LASTEXITCODE -ne 0) { Fail "not a git repository: $Repo" }
$wt = Join-Path $root ".claude/worktrees/$Branch"
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

Run git @('-C', $root, 'fetch', '-q', 'origin', $Base)
if (Test-Path -LiteralPath $wt) { "reusing worktree $wt" }
else {
  git -C $root show-ref -q --verify "refs/heads/$Branch"
  if ($LASTEXITCODE -eq 0) { Run git @('-C', $root, 'worktree', 'add', $wt, $Branch) }
  else { Run git @('-C', $root, 'worktree', 'add', '--no-track', '-b', $Branch, $wt, "origin/$Base") }
}

$wtFwd = $wt.Replace('\', '/')
$first = "FIRST ACTION, before anything else: use the EnterWorktree tool with path = $wtFwd. Work only inside it; never change files outside it."
$brief = $first + "`n`n" + [IO.File]::ReadAllText($BriefFile)
if ($DryRun) { "[dry-run] (cd $from && claude --bg --name `"$Name`" --model $Model --permission-mode $Mode --settings $Safety <EnterWorktree $wtFwd, then the brief>)"; exit 0 }
$claude = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claude) { Fail 'claude not found on PATH' }
# A .cmd shim (npm install) cuts a multi-line argument at the first line break.
if ($claude.Source -match '\.(cmd|bat)$') { Fail "claude is a $($Matches[1]) shim ($($claude.Source)): install the native claude.exe, which carries a multi-line brief intact" }
# Windows PowerShell 5.1 (and 7.0-7.2) does not escape quotes inside native arguments: do it here.
if ($PSVersionTable.PSVersion -lt [version]'7.3') { $brief = ($brief -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1' }
Push-Location -LiteralPath $from
try { & $claude.Source --bg --name $Name --model $Model --permission-mode $Mode --settings $Safety $brief }
finally { Pop-Location }
exit $LASTEXITCODE
