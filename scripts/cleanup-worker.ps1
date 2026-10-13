# Clean up after a merged task (Windows; macOS / Linux: cleanup-worker.sh - the same checks and codes):
# stop and remove the worker session, remove its worktree and branch - only if the worktree exists, is
# clean, every commit is on the remote and a merged PR has exactly the pushed head (a reused branch name
# with newer commits does not count) (CORE section 8). Otherwise report and change nothing.
#   powershell -File scripts\cleanup-worker.ps1 -Worktree <path> [-Session <id>] [-DryRun]
# Exit codes: 0 cleaned (or would be, with -DryRun); 1 usage error or a failed removal;
# 3 a check failed, nothing changed.
param([string]$Worktree, [string]$Session, [switch]$DryRun)
# native output (git, bash) is read and this script's own output written as UTF-8, whatever the console's
# code page (cp866 on a Russian Windows garbles a non-ASCII path or a section sign); no console: left as is.
# The caller's console gets its own encoding back on every way out (the end, any exit N, a terminating
# error): the body below runs inside try, the encoding is restored in finally.
$enc0 = $null; try { $enc0 = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
try {
function StopHere([string]$m) { [Console]::Error.WriteLine("$m - left as is"); exit 3 }
function Run([string]$exe, [string[]]$a) {
  if ($DryRun) { "[dry-run] $exe $($a -join ' ')"; $global:LASTEXITCODE = 0 } else { & $exe @a }
}
if (-not $Worktree) { [Console]::Error.WriteLine('usage: -Worktree <path> [-Session <id>] [-DryRun]'); exit 1 }
# a flag where a value belongs (-Session --dry-run): a usage error, never a session or path of that name
foreach ($v in @(@('Worktree', $Worktree), @('Session', $Session))) {
  if ("$($v[1])".StartsWith('-')) { [Console]::Error.WriteLine("missing value for -$($v[0]) (got the flag $($v[1])); usage: -Worktree <path> [-Session <id>] [-DryRun]"); exit 1 }
}

# The main repository is found from the worktree itself, so this runs from any folder.
if (-not (Test-Path -LiteralPath $Worktree -PathType Container)) { StopHere "NO WORKTREE: $Worktree does not exist (check the path)" }
$common = git -C $Worktree rev-parse --path-format=absolute --git-common-dir 2>$null
if ($LASTEXITCODE -ne 0) { StopHere "NOT A WORKTREE: $Worktree is not a git working copy" }
$gitdir = git -C $Worktree rev-parse --path-format=absolute --git-dir
if ("$gitdir" -eq "$common") { StopHere "MAIN CHECKOUT: $Worktree is the repository itself, not a worker worktree" }
$root = Split-Path -Parent $common
if (git -C $Worktree status --porcelain) { StopHere "NOT CLEAN: $Worktree has uncommitted changes" }
$branch = (git -C $Worktree rev-parse --abbrev-ref HEAD)
git -C $Worktree fetch -q
if ($LASTEXITCODE -ne 0) { StopHere "FETCH FAILED: cannot confirm $branch is on the remote" }
# its remote branch: the upstream, or origin/<branch> when it was pushed without -u; none when it was
# deleted after the merge and a fetch pruned it (fetch.prune) - then only a merged PR's head can show
# that every commit is on the remote
$u = ''
git -C $Worktree rev-parse -q --verify '@{u}' *> $null
if ($LASTEXITCODE -eq 0) { $u = '@{u}' }
else {
  git -C $Worktree rev-parse -q --verify "refs/remotes/origin/$branch" *> $null
  if ($LASTEXITCODE -eq 0) { $u = "origin/$branch" }
}
if ($u) {
  if (git -C $Worktree log --oneline "$u..") { StopHere "UNPUSHED: $branch has commits not on its remote" }
  $up = "$(git -C $Worktree rev-parse $u)".Trim()
} else { $up = "$(git -C $Worktree rev-parse HEAD)".Trim() }
$short = $up.Substring(0, [Math]::Min(7, $up.Length))
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { StopHere "NO gh: cannot verify the PR for $branch is merged" }
Push-Location -LiteralPath $Worktree
$heads = @(gh pr list --head $branch --state merged --json headRefOid --jq '.[].headRefOid' 2>$null)
$ghExit = $LASTEXITCODE
Pop-Location
if ($ghExit -ne 0) { StopHere "UNKNOWN: could not check the PR for $branch" }
$heads = @($heads | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
if (-not $heads.Count) {
  if ($u) { StopHere "NOT MERGED: no merged PR for $branch" }
  StopHere "NO UPSTREAM: $branch was never pushed"
}
if ($heads -notcontains $up) {
  # a server-side commit on top of the pushed head (gh pr update-branch merges the base into the PR):
  # the merged PR's head then has the pushed head as an ancestor; a reused name with newer commits does not
  $found = ''
  foreach ($h in $heads) {
    git -C $Worktree cat-file -e "$h^{commit}" *> $null
    if ($LASTEXITCODE -ne 0) { git -C $Worktree fetch -q origin $h *> $null }
    git -C $Worktree merge-base --is-ancestor $up $h *> $null
    if ($LASTEXITCODE -eq 0) { $found = $h; break }
  }
  if (-not $found) {
    if ($u) { StopHere "NOT MERGED: no merged PR for $branch has its pushed head $short (branch name reused?)" }
    StopHere "UNPUSHED: $branch is on no remote branch, and no merged PR for it contains its head $short"
  }
  "merged as $($found.Substring(0, 7)): the PR's head has a server-side commit on top of the pushed head $short"
}
if (-not $u) { "its remote branch is gone (deleted after the merge): the merged PR's head contains $short" }

if ($Session) {
  Run claude @('stop', $Session)
  Run claude @('rm', $Session)
}
Run git @('-C', $root, 'worktree', 'remove', $Worktree)
if ($LASTEXITCODE -ne 0) { [Console]::Error.WriteLine("REMOVE FAILED: git worktree remove $Worktree"); exit 1 }
Run git @('-C', $root, 'branch', '-d', $branch)
if ($LASTEXITCODE -ne 0) { "branch $branch kept (not fully merged locally)" }
"cleaned: $(if ($Session) { $Session } else { 'no session' }) $Worktree"
exit 0
} finally { if ($enc0) { try { [Console]::OutputEncoding = $enc0 } catch { } } }
