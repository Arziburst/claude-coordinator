# Clean up after a merged task (Windows; macOS / Linux: cleanup-worker.sh - the same checks and codes):
# stop and remove the worker session, remove its worktree and branch - only if the worktree exists, is
# clean, every commit is on the remote and a merged PR has exactly the pushed head (a reused branch name
# with newer commits does not count) (CORE section 8). Otherwise report and change nothing.
#   powershell -File scripts\cleanup-worker.ps1 -Worktree <path> [-Session <id>] [-DryRun]
# -Session: the short job id (`id` in claude agents --json) or the full sessionId (mapped to its job id).
# Exit codes: 0 cleaned (or would be, with -DryRun); 1 usage error or a failed removal;
# 3 a check failed, nothing changed; 4 SESSION KEPT: claude agents --json --all still lists the session
# after claude rm - the worktree and branch are left as is; 5 SESSION FOREIGN: the listing gives the
# session a working folder outside this project (the repository's main checkout, its .claude/worktrees,
# the worktree itself) - nothing is stopped, removed or changed (CORE section 1.17); a session the
# listing does not have is handled as before.
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
# Agents: claude agents --json --all as one string ($LASTEXITCODE its exit); Objects: one session object
# per item; Field: an object's string value (read as text, the same as cleanup-worker.sh)
function Agents { $r = @(& claude agents --json --all 2>$null | ForEach-Object { "$_" }); $r -join "`n" }
function Objects([string]$json) { @(($json -replace "[`r`n]", '') -split '}') }
function Field([string]$o, [string]$k) { $m = [regex]::Match($o, '"' + $k + '": *"([^"]*)"'); if ($m.Success) { $m.Groups[1].Value } else { '' } }
# a folder in one form for comparing: / separators (a JSON \\ is one \), none trailing, Git Bash's /c/x
# as c:/x, lower case where letter case in paths is ignored (Windows, macOS)
$isWin = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows
$fold = $isWin -or $IsMacOS
function Canon([string]$x) {
  $x = $x.Replace('\\', '/').Replace('\', '/')
  if ($fold) { $x = $x.ToLowerInvariant() }
  while ($x.Length -gt 1 -and $x.EndsWith('/')) { $x = $x.Substring(0, $x.Length - 1) }
  if ($isWin -and $x -cmatch '^/[a-z](/|$)') { $x = $x.Substring(1, 1) + ':' + $x.Substring(2) }
  $x
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

$id = ''
if ($Session) {
  # stop / rm take the short job id (`id` in claude agents --json); they refuse a full sessionId ("No job
  # matching", 2.1.296), so a full one is mapped through the listing, else to its first 8 characters
  $id = $Session
  $listing = Objects (Agents)
  if ($Session -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
    $id = ''
    foreach ($o in $listing) { if ((Field $o 'sessionId') -ceq $Session) { $id = Field $o 'id'; break } }
    if (-not $id) { $id = $Session.Substring(0, 8) }
    "session ${Session}: job id $id"
  }
  # only this project's sessions (CORE section 1.17): a listed session whose working folder is outside
  # the repository's main checkout (its .claude/worktrees included) and the worktree is left alone
  $scwd = ''
  foreach ($o in $listing) { if ((Field $o 'id') -ceq $id) { $scwd = Field $o 'cwd'; break } }
  if ($scwd) {
    $sc = $scwd.Replace('\\', '\'); $own = $false
    # each folder also in its full form (on Windows an 8.3 name in its long form)
    function Full([string]$p) { try { if (Test-Path -LiteralPath $p) { return [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $p).ProviderPath) } } catch { }; '' }
    $top = "$(git -C $Worktree rev-parse --path-format=absolute --show-toplevel 2>$null)".Trim()
    $dirs = @($root, "$root/.claude/worktrees", $top, $Worktree, (Full $root), (Full $Worktree)) | Where-Object { $_ } | ForEach-Object { Canon $_ }
    foreach ($c in @($sc, (Full $sc))) {
      if (-not $c) { continue }
      $c = Canon $c
      foreach ($d in $dirs) { if ("$c/".StartsWith("$d/", [StringComparison]::Ordinal)) { $own = $true; break } }
      if ($own) { break }
    }
    if (-not $own) {
      [Console]::Error.WriteLine("SESSION FOREIGN: $id (${sc}): not this project's session - nothing done")
      exit 5
    }
  }
  # a session stopped already (the order in TOOLKIT *Usage*) may refuse the stop: that is fine
  Run claude @('stop', $id)
  if ($DryRun) { "[dry-run] claude rm $id" }
  else {
    $out = @(& claude rm $id 2>&1 | ForEach-Object { "$_" })
    $rc = $LASTEXITCODE
    if ($out.Count) { $out }
    # removed only when the listing no longer has it; no listing at all: the rm's exit code decides
    $raw = Agents
    $kept = $false
    if ($LASTEXITCODE -eq 0) { foreach ($o in (Objects $raw)) { if ((Field $o 'id') -ceq $id) { $kept = $true; break } } }
    elseif ($rc -ne 0) { $kept = $true }
    if ($kept) {
      if ($rc -eq 0) { $why = 'it exited 0, the session is still listed' }
      else {
        $why = @($out | ForEach-Object { $_.Trim() } | Where-Object { $_ }) | Select-Object -First 1
        if (-not $why) { $why = "exit $rc" }
      }
      [Console]::Error.WriteLine("SESSION KEPT: $id (claude rm failed: $why)")
      [Console]::Error.WriteLine("worktree $Worktree and branch $branch left as is: remove the session (claude rm $id), then run this again")
      exit 4
    }
  }
}
Run git @('-C', $root, 'worktree', 'remove', $Worktree)
if ($LASTEXITCODE -ne 0) { [Console]::Error.WriteLine("REMOVE FAILED: git worktree remove $Worktree"); exit 1 }
Run git @('-C', $root, 'branch', '-d', $branch)
if ($LASTEXITCODE -ne 0) { "branch $branch kept (not fully merged locally)" }
"cleaned: $(if ($id) { $id } else { 'no session' }) $Worktree"
exit 0
} finally { if ($enc0) { try { [Console]::OutputEncoding = $enc0 } catch { } } }
