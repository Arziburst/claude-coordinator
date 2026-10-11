# Clean up after a merged task (Windows; macOS / Linux: cleanup-worker.sh - the same checks): stop and
# remove the worker session, remove its worktree and branch - only if its PR is merged, the worktree is
# clean and every commit is on the remote (CORE section 8). Otherwise report, change nothing, exit 3.
#   powershell -File scripts\cleanup-worker.ps1 -Worktree <path> [-Session <id>] [-DryRun]
param([string]$Worktree, [string]$Session, [switch]$DryRun)
function StopHere([string]$m) { [Console]::Error.WriteLine("$m - left as is"); exit 3 }
function Run([string]$exe, [string[]]$a) { if ($DryRun) { "[dry-run] $exe $($a -join ' ')" } else { & $exe @a } }
if (-not $Worktree) { [Console]::Error.WriteLine('usage: -Worktree <path> [-Session <id>] [-DryRun]'); exit 1 }

# The main repository is found from the worktree itself, so this runs from any folder.
$root = ''; $branch = ''
if (Test-Path -LiteralPath $Worktree) {
  $root = Split-Path -Parent (git -C $Worktree rev-parse --path-format=absolute --git-common-dir)
  if (git -C $Worktree status --porcelain) { StopHere "NOT CLEAN: $Worktree has uncommitted changes" }
  $branch = (git -C $Worktree rev-parse --abbrev-ref HEAD)
  git -C $Worktree rev-parse -q --verify '@{u}' *> $null
  if ($LASTEXITCODE -ne 0) { StopHere "NO UPSTREAM: $branch was never pushed" }
  git -C $Worktree fetch -q
  if ($LASTEXITCODE -ne 0) { StopHere "FETCH FAILED: cannot confirm $branch is on the remote" }
  if (git -C $Worktree log --oneline '@{u}..') { StopHere "UNPUSHED: $branch has commits not on its remote" }
  if (Get-Command gh -ErrorAction SilentlyContinue) {
    Push-Location -LiteralPath $Worktree
    $merged = gh pr list --head $branch --state merged --json number --jq 'length' 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $merged) { $merged = '?' }
    Pop-Location
    if ("$merged".Trim() -eq '0') { StopHere "NOT MERGED: no merged PR for $branch" }
    if ("$merged".Trim() -eq '?') { StopHere "UNKNOWN: could not check the PR for $branch" }
  } else { StopHere "NO gh: cannot verify the PR for $branch is merged" }
}

if ($Session) {
  Run claude @('stop', $Session)
  Run claude @('rm', $Session)
}
if (Test-Path -LiteralPath $Worktree) {
  Run git @('-C', $root, 'worktree', 'remove', $Worktree)
  Run git @('-C', $root, 'branch', '-d', $branch)
  if (-not $DryRun -and $LASTEXITCODE -ne 0) { "branch $branch kept (not fully merged locally)" }
}
"cleaned: $(if ($Session) { $Session } else { 'no session' }) $Worktree"
