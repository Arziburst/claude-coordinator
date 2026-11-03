# A real reset of a project's coordinator (#446; Windows; macOS / Linux: reset-coordinator.sh - the same arguments, messages, codes; its header says what it does).
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\reset-coordinator.ps1 --root <project root> --confirm <the project folder's name> --core-from <a clean clone of claude-coordinator>
$enc0 = $null; try { $enc0 = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
$t = ''; $a0 = @($args)
try {
foreach ($v in 'GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_OBJECT_DIRECTORY', 'GIT_COMMON_DIR') { Remove-Item "Env:$v" -ErrorAction SilentlyContinue }
function No([string]$m) { [Console]::Error.WriteLine("reset-coordinator: refused: $m"); exit 1 }
function Failed([string]$m) { [Console]::Error.WriteLine("reset-coordinator: FAILED: $m"); exit 1 }
function Usage { [Console]::Error.WriteLine("usage: scripts/reset-coordinator --root <project root> --confirm <the project folder's name> --core-from <a clean clone of claude-coordinator>"); exit 2 }
function W([string]$p) { (Resolve-Path -LiteralPath $p).Path -replace '\\', '/' }
function IsFile([string]$p) { Test-Path -LiteralPath $p -PathType Leaf }
$root = ''; $confirm = ''; $from = ''
for ($i = 0; $i -lt $a0.Count; $i += 2) { if ($i + 1 -ge $a0.Count) { Usage }
  switch -CaseSensitive ("$($a0[$i])") { '--root' { $root = "$($a0[$i + 1])" } '--confirm' { $confirm = "$($a0[$i + 1])" } '--core-from' { $from = "$($a0[$i + 1])" } default { Usage } } }
if (-not $root) { Usage }; if (-not (Test-Path -LiteralPath $root -PathType Container)) { No "--root is not a folder: $root" }
$root = W $root; $name = Split-Path -Leaf $root
# THE GUARD: first, read from files, whatever was typed
if ((IsFile "$root/CORE.md") -and (IsFile "$root/scripts/check-core.sh")) { No "$root is the core's own repository (it holds CORE.md and scripts/check-core.sh): it is never reset" }
if ($confirm -cne $name) { No "--confirm must be this project's folder name, $name" }
$st = "$root/coordinator"
if (-not (Test-Path -LiteralPath "$st/.git")) { No "no state repository: $st/.git is missing" }
if (@(Get-ChildItem -LiteralPath "$st/assistants" -Force -ErrorAction SilentlyContinue).Count -gt 0) { No "coordinator/assistants is not empty: only the owner's word naming an assistant removes it (coord-assistant) (CORE section 8)" }
if (-not $from -or -not (Test-Path -LiteralPath $from -PathType Container)) { No "--core-from must be a clean clone of claude-coordinator: $from" }
$from = W $from; $notClone = "--core-from must be a clean clone of claude-coordinator: $from"
if ("$from/".StartsWith("$st/", [StringComparison]::OrdinalIgnoreCase)) { No "--core-from must be a clean clone outside coordinator/: $from" }
if (-not ((Test-Path -LiteralPath "$from/.git") -and (IsFile "$from/CORE.md") -and (IsFile "$from/scripts/check-core.sh"))) { No $notClone }
$sha = "$(& git -C $from rev-parse HEAD 2>$null)".Trim(); if ($LASTEXITCODE -ne 0 -or -not $sha) { No $notClone }
$d = "$(& git -C $from status --porcelain 2>$null)"; if ($LASTEXITCODE -ne 0 -or $d) { No $notClone }
# From here the cwd is the root: never a folder this replaces, and gh reads the project's repository. No remote of its own: no PR can exist
Set-Location -LiteralPath $root; [Environment]::CurrentDirectory = $root
function Cap([string]$exe, [string[]]$a) { $global:LASTEXITCODE = 0; try { $o = @(& $exe @a 2>$null | ForEach-Object { "$_" }) -join "`n"; $script:capRc = $LASTEXITCODE } catch { $o = ''; $script:capRc = 127 }; $o }
function IsList([string]$s) { ($s -replace '\s', '') -match '^\[.*\]$' }
$prs = Cap 'gh' @('pr', 'list', '--json', 'number')
if ($script:capRc -ne 0) { if ("$(& git remote 2>$null)") { No "cannot read the project's open PRs: gh failed" }; $prs = '[]' }
if (-not (IsList $prs)) { No "cannot read the project's open PRs: gh printed no JSON list" }
$open = @([regex]::Matches($prs, '"number": *([0-9]+)') | ForEach-Object { '#' + $_.Groups[1].Value }) -join ' '
if ($open) { No "open PR of the project: $open" }
$sess = Cap 'claude' @('agents', '--json', '--all')
if ($script:capRc -ne 0 -or -not (IsList $sess)) { No "cannot read the running sessions: claude agents failed" }
try { $list = $sess | ConvertFrom-Json } catch { No "cannot read the running sessions: claude agents failed" }
$win = $env:OS -eq 'Windows_NT'; $r = if ($win) { $root.ToLowerInvariant() } else { $root }
# running = state working, or a status field
$running = @(foreach ($o in @($list)) { if ($null -eq $o -or -not $o.id -or $o.sessionId -ceq $env:CLAUDE_CODE_SESSION_ID -or ($o.state -cne 'working' -and -not $o.status)) { continue }
  $c = "$($o.cwd)" -replace '\\', '/'; if ($win) { $c = $c.ToLowerInvariant() }
  if ($c -ceq $r -or $c.StartsWith("$r/", [StringComparison]::Ordinal)) { $o.id } }) -join ' '
if ($running) { No "running session of the project: $running" }
function G { $o = & git -C $st @args 2>$null; $script:rc = $LASTEXITCODE; "$o".Trim() }
$tag = "before-reset-$(Get-Date -Format 'yyyy-MM-dd')"
$parent = G rev-parse -q --verify HEAD; if ($script:rc -ne 0) { No "the state repository has no commit: $st" }
$null = G rev-parse -q --verify "refs/tags/$tag"; if ($script:rc -eq 0) { No "the tag $tag already exists: one reset a day" }
$rs = @(& git -C $st remote 2>$null); $remote = if ($rs -ccontains 'origin') { 'origin' } elseif ($rs.Count) { "$($rs[0])" } else { '' }
if ($remote) { $null = G push --dry-run -q $remote HEAD; if ($script:rc -ne 0) { No "the state repository's remote $remote cannot be reached or does not take its branch" }
  if (G ls-remote --tags $remote "refs/tags/$tag") { No "the tag $tag already exists on the remote: one reset a day" } }
# The tag's commit, on no branch until the push went through; raw bytes as in the .sh: a throwaway git dir's info/attributes, a new index
$t = (Join-Path ([IO.Path]::GetTempPath()) ("reset-" + [guid]::NewGuid())) -replace '\\', '/'
$gd = G rev-parse --absolute-git-dir; $grc = $script:rc; & git init -q --template= "$t/g" *> $null; if ($grc -ne 0 -or $LASTEXITCODE -ne 0) { No "cannot prepare the tag" }
$null = New-Item -ItemType Directory -Force -Path "$t/g/.git/info"; [IO.File]::WriteAllText("$t/g/.git/info/attributes", "* -text`n")
function TreeOf([string]$wt, [string]$ix) { $env:GIT_DIR = "$t/g/.git"; $env:GIT_WORK_TREE = $wt; $env:GIT_OBJECT_DIRECTORY = "$gd/objects"; $env:GIT_INDEX_FILE = $ix; $x = ''
  & git -C $wt -c core.autocrlf=false add -A -f . *> $null; if ($LASTEXITCODE -eq 0) { $x = "$(& git write-tree 2>$null)".Trim() }
  Remove-Item Env:GIT_DIR, Env:GIT_WORK_TREE, Env:GIT_OBJECT_DIRECTORY, Env:GIT_INDEX_FILE; $x }
if (-not (TreeOf $st "$t/i")) { No "the tag ${tag}: cannot read coordinator/" }
$cfg = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } elseif ($env:USERPROFILE) { "$env:USERPROFILE/.claude" } else { "$env:HOME/.claude" }
$pdir = "$cfg/projects/$($root -creplace '[^A-Za-z0-9]', '-')"; $mem = "$pdir/memory"
if (@(Get-ChildItem -LiteralPath $mem -Force -ErrorAction SilentlyContinue).Count -gt 0) {
  $mt = TreeOf $mem "$t/m"; $env:GIT_INDEX_FILE = "$t/i"; $null = G read-tree --prefix=before-reset-memory/ $mt; $rm = $script:rc; Remove-Item Env:GIT_INDEX_FILE
  if (-not $mt -or $rm -ne 0) { No "the tag ${tag}: cannot read the memory folder $mem" } }
$env:GIT_INDEX_FILE = "$t/i"; $tree = G write-tree; $rc1 = $script:rc; Remove-Item Env:GIT_INDEX_FILE
$commit = G commit-tree $tree -p $parent -m "before reset: $tag"; if ($rc1 -ne 0 -or $script:rc -ne 0 -or -not $commit) { No "the tag ${tag}: cannot commit (git's user set?)" }
$null = G tag $tag $commit; if ($script:rc -ne 0) { No "the tag $tag cannot be made" }
if ($remote) { $null = G push -q $remote "refs/tags/$tag"; if ($script:rc -ne 0) { $null = G tag -d $tag; No "the tag $tag cannot be pushed to $remote" } }
# Parked first, by rename, as the .sh: a held file or folder stops it here with everything put back. PowerShell has read this script whole.
$old = "$st/.reset-old"; $parked = @(); try { $null = New-Item -ItemType Directory -Path $old -ErrorAction Stop } catch { Failed "cannot make $old; the tag $tag is made" }
foreach ($e in @(Get-ChildItem -LiteralPath $st -Force | ForEach-Object { $_.Name })) { if ($e -ceq '.git' -or $e -ceq '.reset-old') { continue }
  try { Move-Item -LiteralPath "$st/$e" -Destination "$old/$e" -ErrorAction Stop; $parked += $e } catch {
    foreach ($p in $parked) { Move-Item -LiteralPath "$old/$p" -Destination "$st/$p" }; Remove-Item -LiteralPath $old -Force; $null = G tag -d $tag
    if ($remote) { $null = G push -q $remote ":refs/tags/$tag" }
    No "coordinator/$e is held by another process: nothing removed, the tag taken back" } }
$null = G update-ref HEAD $commit; if ($script:rc -ne 0) { Failed "cannot move the state branch; everything is in $old and behind the tag $tag" }
try { Remove-Item -LiteralPath $old -Recurse -Force -ErrorAction Stop; if (Test-Path -LiteralPath $mem) { Remove-Item -LiteralPath $mem -Recurse -Force -ErrorAction Stop } } catch { Failed "cannot remove $old or $mem; everything is behind the tag $tag" }; if (Test-Path -LiteralPath $pdir) { $null = New-Item -ItemType Directory -Force -Path $mem }
try { $null = New-Item -ItemType Directory -Path "$st/core" -ErrorAction Stop
  Get-ChildItem -LiteralPath $from -Force | Where-Object { $_.Name -cne '.git' -and $_.Name -cne '.github' -and $_.Name -cne 'CLAUDE.md' } | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination "$st/core" -Recurse -Force -ErrorAction Stop } } catch { Failed "cannot copy the core from $from; everything is behind the tag $tag" }
$null = G read-tree --empty; $b = $script:rc; $null = G add -A; $b += $script:rc; $tree = G write-tree; $b += $script:rc; $c2 = G commit-tree $tree -p $commit -m "reset of the coordinator: tag=$tag core=$sha"; $b += $script:rc; $null = G update-ref HEAD $c2; $b += $script:rc
if ($b -ne 0) { Failed "cannot commit the new state in $st; everything is behind the tag $tag" }
if ($remote) { $null = G push -q $remote HEAD; if ($script:rc -ne 0) { "reset-coordinator: the state branch is not pushed yet: git -C coordinator push $remote HEAD" } } else { "reset-coordinator: no remote: the tag is local only" }
"reset-coordinator: done tag=$tag core=$sha"
} finally { if ($t -and (Test-Path -LiteralPath $t)) { Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue }
  if ($null -ne $enc0) { try { [Console]::OutputEncoding = $enc0 } catch { } } }
