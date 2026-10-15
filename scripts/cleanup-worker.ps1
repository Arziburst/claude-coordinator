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
# the worktree itself, the folder whose .claude/worktrees holds it) - nothing is stopped, removed or
# changed (CORE section 1.17); a session the listing does not have is handled as before.
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
# no claude on PATH: nothing can be stopped or removed - the session is reported kept (exit 4), as the .sh
$hasClaude = [bool](Get-Command claude -ErrorAction SilentlyContinue)
function Agents {
  if (-not $hasClaude) { $global:LASTEXITCODE = 127; return '' }
  $r = @(& claude agents --json --all 2>$null | ForEach-Object { "$_" }); $r -join "`n"
}
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
# A path as it lies on disk, as safety-guard.ps1 walks it (#121): links (symlinks, junctions) resolved a
# folder at a time, then the rest as written; PhysDir gives @(<the existing folder>, <the rest>) or $null.
function LinkTarget([string]$p) {
  try { $it = Get-Item -LiteralPath $p -Force -ErrorAction Stop } catch { return '' }
  if (-not $it.LinkType) { return '' }   # another reparse point (a cloud file ...) is a plain folder
  $t = $null
  if ($it.PSObject.Properties['LinkTarget']) { $t = $it.LinkTarget }   # PowerShell 7
  if (-not $t) { $t = @($it.Target)[0] }                                # Windows PowerShell 5.1
  ([string]$t).Replace('\', '/') -replace '^//\?/|^/\?\?/', ''
}
# @(<the existing folder, physical>, <the rest as written>), or $null
function PhysDir([string]$p) {
  $p = $p.Replace('\', '/')
  if ($isWin) { $p = $p -replace '^/(mnt/|cygdrive/)?([A-Za-z])(/|$)', '$2:/' }
  if ($p -notmatch '^([A-Za-z]:|/)') { $p = (Get-Location).ProviderPath.Replace('\', '/') + '/' + $p }
  if ($p -match '^[A-Za-z]:') { $root = $p.Substring(0, 2) + '/'; $p = $p.Substring(2) }
  elseif ($isWin) { return $null } else { $root = '/' }
  $segs = $p.Split('/'); $cur = $root
  for ($i = 0; $i -lt $segs.Count; $i++) {
    $s = $segs[$i]
    if ($s -eq '' -or $s -eq '.') { continue }
    if ($s -eq '..') {
      $k = $cur.LastIndexOf('/'); $cur = if ($k -lt $root.Length) { $root } else { $cur.Substring(0, $k) }
      continue
    }
    $cand = if ($cur.EndsWith('/')) { $cur + $s } else { "$cur/$s" }
    $a = [int][IO.DirectoryInfo]::new($cand).Attributes
    $t = if ($a -ne -1 -and ($a -band 1024)) { LinkTarget $cand } else { '' }   # a reparse point: a symlink or a junction
    if ($t) {
      if (++$script:hops -le 40) {
        if ($t -notmatch '^([A-Za-z]:|/)') { $t = "$cur/$t" }
        $r = PhysDir $t
        if ($null -ne $r -and -not $r[1]) { $cur = $r[0]; continue }
      }
      # a loop, or it does not lead to an existing folder
    } elseif ($a -ne -1 -and ($a -band 16)) {
      # an 8.3 name (RUNNER~1) in its long form, as git and cd -P give it: GetFullPath expands it
      $cur = if ($isWin -and $s.Contains('~')) { [IO.Path]::GetFullPath($cand).Replace('\', '/') } else { $cand }
      continue
    }
    # not there, or not a folder: the rest as written
    return @($cur, ('/' + ($segs[$i..($segs.Count - 1)] -join '/')))
  }
  @($cur, '')
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
  # ids are lower-case hex in the listing: a sessionId or job id typed in upper case is the same session
  if ($Session -match '^[0-9A-Fa-f-]+$') { $Session = $Session.ToLowerInvariant() }
  $id = $Session
  $listing = Objects (Agents)
  if ($Session -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
    $id = ''
    foreach ($o in $listing) { if ((Field $o 'sessionId') -ceq $Session) { $id = Field $o 'id'; break } }
    if (-not $id) { $id = $Session.Substring(0, 8) }
    "session ${Session}: job id $id"
  }
  # only this project's sessions (CORE section 1.17): a listed session whose working folder is outside
  # the repository's main checkout (its .claude/worktrees included) and the worktree (with the folder whose
  # .claude/worktrees holds it) is left alone
  $scwd = ''
  foreach ($o in $listing) { if ((Field $o 'id') -ceq $id) { $scwd = Field $o 'cwd'; break } }
  if ($scwd) {
    $sc = $scwd.Replace('\\', '\'); $own = $false
    # each folder also as it lies on disk: links resolved (Resolve-Path keeps a symlink on macOS and
    # Linux, where the .sh's cd -P resolves it), on Windows an 8.3 name in its long form
    function Full([string]$p) {
      $script:hops = 0; $r = $null
      try { $r = PhysDir $p } catch { }
      if ($null -ne $r -and -not $r[1]) { return $r[0] }
      try { if (Test-Path -LiteralPath $p) { return [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $p).ProviderPath) } } catch { }; ''
    }
    $top = "$(git -C $Worktree rev-parse --path-format=absolute --show-toplevel 2>$null)".Trim()
    $dirs = @()
    foreach ($d in @($root, "$root/.claude/worktrees", $top, $Worktree, (Full $root), (Full $Worktree))) {
      if (-not $d) { continue }
      $d = Canon $d; $dirs += $d
      # the folder whose .claude/worktrees holds the worktree (a state repository's worktree started
      # from the project root, as the self-test does)
      $k = "$d/".IndexOf('/.claude/worktrees/', [StringComparison]::Ordinal)
      if ($k -gt 0 -and "$d/".Length -gt $k + 19) { $dirs += $d.Substring(0, $k) }
    }
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
  if ($hasClaude) { Run claude @('stop', $id) }
  if ($DryRun) { "[dry-run] claude rm $id" }
  else {
    if ($hasClaude) { $out = @(& claude rm $id 2>&1 | ForEach-Object { "$_" }); $rc = $LASTEXITCODE }
    else { $out = @('claude: command not found'); $rc = 127 }
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
