# Land approved PRs one at a time, in the order given (Windows; macOS / Linux: merge-queue.sh - the same
# steps, lines and codes; CORE section 4a): parallel work, serial merging - each PR merges main once, when
# its turn comes, never after every other merge.
#   powershell -File scripts\merge-queue.ps1 land -Pr <pr>[@<approved sha>],... [-Method squash|merge|rebase]
#                    [-Shared <glob>,...] [-Poll <seconds>] [-Timeout <minutes>] [-OverBoundsOk <pr>:<the owner's words>] [-Runs <log>] [-DryRun]
# -Runs: the run log (as check-contract takes it, #525) the finished sessions are judged by and the AFTER MERGE run-stats line names; default coordinator/RUNS.tsv.
#   powershell -File scripts\merge-queue.ps1 status [-Shared <glob>,...] [-Touches <path or glob>,...]
# land, per PR in order: open and not a draft; its head the approved commit (when @<sha> is given); runs of
# its branch on an older head cancelled; behind its base -> `gh pr update-branch` (GitHub merges the base
# in), and when the base brought changes to files the PR changes too (outside -Shared), it stops for a
# re-review of that merge; the checks of the current head waited for (all pass or skipped); a failure
# re-runs the failed runs once, a second failure stops; then `gh pr merge --<method>
# --match-head-commit <head>` and the remote branch deleted (never the local one: the worker's worktree
# stays for cleanup-worker; a branch other open PRs are based on is kept, #229; a fork's PR deletes nothing there, #392), and every open PR that
# changes a file the merged one changed is printed
# as AFFECTED, then the AFTER MERGE lines: the merge row of CORE section 4's event table, one thing a line with the PR's values, so its duties have
# a trigger (#242). The queue never resolves a conflict and never merges a commit it was not given or did
# not make itself. -Shared: a file the project lets every task append to or regenerate (PROJECT.md
# *Shared files*); a glob, `*` crosses folders. status: each open PR's merge state, the CONFLICTING ones
# (CI does not run on them) and the pairs of open PRs that change the same files outside -Shared; with
# -Touches (a task's `touches`: a file, a folder or a glob), the open PRs changing anything under them,
# as TOUCHES - the conflict foresight before a task (CORE section 4a; start-worker runs it).
# Lines (wrappers read them), each `<TAG> #<pr>: ...`: MERGED, AFFECTED, AFTER MERGE, SKIP, NOT APPROVED,
# CONFLICT, REVIEW, HEAD MOVED, FAILED, NO CHECKS, TIMEOUT, MERGE FAILED; status: CONFLICTING, OVERLAP,
# TOUCHES.
# The bounds (#381, #387), land: the contract at coordinator/briefs/<head branch, / as ->-contract.md (start-worker saves it there), else by the id its branch starts with (coordinator/briefs/<id>-contract.md),
# scripts/check-bounds on origin/<base>...<head>. OVER on a bound whose glob matches or holds an important glob (#419; check-contract's list, its -Important): `OVER BOUNDS <pr> <glob> <added>/<max>`, left; any other OVER: `bounds over, not important: <pr> <glob> <added>/<max>`, it goes on. Its exit 2: `BOUNDS #<pr>: check-bounds ...`, left,
# fail-closed. No contract: `BOUNDS #<pr>: no contract ...`, no stop. -OverBoundsOk passes that PR's stopping OVER, its words printed; -File does not repeat a parameter, two PRs go in two runs.
# The folder (#387), land and -DryRun, checked before any PR merges: the cwd is a repository's root whose origin has each open PR's branch (`git ls-remote`; a fork's PR has no branch there, so only the root holds for it), else a usage error naming the folder,
# exit 1. Origin unreadable: exit 1, a line saying so, never read as a missing branch. A limit: another repository whose origin has a branch of the same name passes. status: no folder check.
# Exit codes: 0 every PR merged (status: always 0); 1 usage error or gh failed; 3 a PR was left (its line
# says why; the queue goes on with the next). gh is called, and git only to read the folder and origin and to fetch the head check-bounds reads, and `claude agents` once after a merge for the sessions line.
param([Parameter(Position = 0)][string]$Mode, [string]$Pr, [string]$Method = 'squash', [string]$Shared,
      [string]$Touches, [string]$Poll = '60', [string]$Timeout = '120', [string]$OverBoundsOk = '', [string]$Runs = 'coordinator/RUNS.tsv', [switch]$DryRun)
# native output (gh) is read and this script's own output written as UTF-8, whatever the console's code
# page; the caller's console gets its own encoding back on every way out
$enc0 = $null; try { $enc0 = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
try {
$usage = 'usage: land -Pr <pr>[@<sha>],... [-Method squash|merge|rebase] [-Shared <glob>,...] [-Poll <s>] [-Timeout <min>] [-OverBoundsOk <pr>:<words>] [-Runs <log>] [-DryRun] | status [-Shared <glob>,...] [-Touches <path>,...]'
function Usage([string]$m) { [Console]::Error.WriteLine($(if ($m) { "$m; $usage" } else { $usage })); exit 1 }
if ($Mode -ne 'land' -and $Mode -ne 'status') { Usage '' }
if ($Method -notin @('squash', 'merge', 'rebase')) { Usage '-Method: squash, merge or rebase' }
if ($Poll -notmatch '^[0-9]+$' -or $Timeout -notmatch '^[0-9]+$') { Usage '-Poll and -Timeout take whole numbers' }
$okPr = ''; $okW = ''
if ($PSBoundParameters.ContainsKey('OverBoundsOk')) { if ($OverBoundsOk -cnotmatch '^([0-9]+):(.*\S.*)$') { Usage "-OverBoundsOk takes <pr>:<the owner's words>" }; $okPr = $Matches[1]; $okW = $Matches[2] }
$prs = @(if ($Pr) { $Pr -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } })
$globs = @(if ($Shared) { $Shared -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } })
$tl = @(if ($Touches) { $Touches -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } })
$sect = [string][char]0x00A7   # not a literal: Windows PowerShell 5.1 reads a BOM-less script as ANSI
if ($Mode -eq 'status' -and $prs.Count) { Usage 'status takes no PR' }
if ($Mode -eq 'land' -and -not $prs.Count) { Usage '' }
foreach ($item in $prs) {
  $p, $s = $item -split '@', 2; if ($null -eq $s) { $s = '0' }
  if ($p -notmatch '^[0-9]+$') { Usage "not a PR number: $item" }
  if ($s -notmatch '^[0-9a-fA-F]+$') { Usage "not a commit: $item" }
}
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { [Console]::Error.WriteLine('gh: command not found'); exit 1 }

# gh's --template prints plain lines (no JSON to read); a literal newline or tab, never a quoted "\n", so
# Windows PowerShell 5.1 hands gh the same template
$T_PR = "{{.state}} {{.isDraft}} {{.headRefOid}} {{.headRefName}} {{.baseRefName}} {{.isCrossRepository}}`n"
$T_FILES = "{{range .files}}{{.path}}`n{{end}}"
$T_CMPFILES = "{{range .files}}{{.filename}}`n{{end}}"
# a check name can run more than once on one head (a pull_request run and a later workflow_dispatch run):
# only the newest of each name counts, a run not started yet being the newest (#234)
$T_CHECKS = "{{range .}}{{.name}}`t{{.startedAt}}`t{{.bucket}}`n{{end}}"
$T_RUNS = "{{range .}}{{.url}} {{.headSha}} {{.status}} {{.conclusion}}`n{{end}}"
$T_LIST = "{{range .}}{{.number}}`t{{.mergeable}}`t{{.mergeStateStatus}}`t{{.headRefName}}{{range .files}}`t{{.path}}{{end}}`n{{end}}"
# Q <gh args>: gh's non-empty output lines; a failed gh stops the run (exit 1)
function Q([string[]]$a) {
  $o = @(& gh @a 2>&1 | ForEach-Object { "$_" })
  if ($LASTEXITCODE -ne 0) { [Console]::Error.WriteLine("gh $($a[0]) $($a[1]) failed$(if ($here) { " (folder $here)" }): $($o -join "`n")"); exit 1 }
  @($o | ForEach-Object { $_ -split "`r?`n" } | Where-Object { $_ -ne '' })
}
function GhRc([string[]]$a) { $null = & gh @a 2>&1; $LASTEXITCODE }
function PrView([string]$n) { -split (@(Q @('pr', 'view', $n, '--json', 'state,isDraft,headRefOid,headRefName,baseRefName,isCrossRepository', '--template', $T_PR)) -join ' ') }
function Behind([string]$x, [string]$y) { "$(@(Q @('api', "repos/{owner}/{repo}/compare/$x...$y", '--template', '{{.behind_by}}')) -join '')" }
function OpenPrs { Q @('pr', 'list', '--state', 'open', '--limit', '200', '--json', 'number,mergeable,mergeStateStatus,headRefName,files', '--template', $T_LIST) }
function IsShared([string]$f) { foreach ($g in $globs) { if ($f -like $g) { return $true } }; $false }
# Meet <a> <b> [all]: the items of a also in b (outside -Shared unless all), joined by ", "
function Meet([string[]]$a, [string[]]$b, [switch]$All) {
  (@($a | Where-Object { $_ -and ($All -or -not (IsShared $_)) -and ($b -ccontains $_) }) -join ', ')
}
# Under <file>: inside one of -Touches - the path itself, a file below it, or a match of it as a glob
function Under([string]$f) {
  foreach ($t in $tl) { $b = $t.TrimEnd('/'); if ($f -ceq $b -or $f.StartsWith("$b/", [StringComparison]::Ordinal) -or $f -clike $t) { return $true } }
  $false
}
function PrFiles([string]$l) { @(($l -split "`t") | Select-Object -Skip 4) }
function Short([string]$x) { if ($x.Length -gt 7) { $x.Substring(0, 7) } else { $x } }

if ($Mode -eq 'status') {
  $list = @(OpenPrs); $nc = 0; $np = 0
  foreach ($l in $list) {
    $f = $l -split "`t"; "#$($f[0]) $($f[2]) $($f[3])"
    if ($f[1] -eq 'CONFLICTING') { $nc++; "CONFLICTING #$($f[0]): $($f[3]) - its worker merges main by hand, CI does not run on it" }
  }
  for ($i = 0; $i -lt $list.Count; $i++) { for ($j = $i + 1; $j -lt $list.Count; $j++) {
    $both = Meet (PrFiles $list[$i]) (PrFiles $list[$j])
    if ($both) { $np++; "OVERLAP #$(($list[$i] -split "`t")[0]) #$(($list[$j] -split "`t")[0]): $both" }
  } }
  $nt = 0
  if ($tl.Count) { foreach ($l in $list) {
    $hit = @(PrFiles $l | Where-Object { $_ -and (Under $_) }) -join ', '
    if ($hit) { $nt++; $f = $l -split "`t"; "TOUCHES #$($f[0]): $($f[3]) - $hit" }
  } }
  "merge-queue status: $($list.Count) open, $nc conflicting, $np overlapping pairs$(if ($tl.Count) { ", $nt touching the task" })"
  exit 0
}

$here = (Get-Location).Path; $rp = & { $ErrorActionPreference = 'Continue'; "$(& git rev-parse --show-prefix 2>$null)".Trim() }; if ($LASTEXITCODE -ne 0 -or $rp) { Usage "land: folder $here is not the root of a repository (a subfolder, or no repository) - land runs from the root of the repository holding the PR's branch" }
foreach ($item in $prs) { $n = ($item -split '@')[0]; $st, $null, $null, $br, $null, $fork = PrView $n; if ($st -ne 'OPEN' -or $fork -eq 'true') { continue }
  $e = @(& { $ErrorActionPreference = 'Continue'; & git ls-remote -q --exit-code origin "refs/heads/$br" 2>&1 } | ForEach-Object { "$_" }); $lrc = $LASTEXITCODE
  if ($lrc -eq 2) { Usage "land: folder $here - its origin has no branch $br of #${n}: land runs from the root of the repository holding the PR's branch" }
  if ($lrc -ne 0) { [Console]::Error.WriteLine("land: origin could not be read from folder $here for #$n's branch ${br}: $(@($e)[0])"); exit 1 }
}; $here = ''
$merged = 0; $left = @()
function Leave([string]$n, [string]$tag, [string]$m) { "$tag #${n}: $m"; $script:left += "#$n ($tag)" }
foreach ($item in $prs) {
  $pr, $want = $item -split '@', 2; if ($want) { $want = $want.ToLowerInvariant() }
  $state, $draft, $head, $branch, $base, $fork = PrView $pr
  if ($state -ne 'OPEN') { Leave $pr 'SKIP' "$state, not open"; continue }
  if ($draft -eq 'true') { Leave $pr 'SKIP' 'a draft'; continue }
  if ($want -and -not $head.StartsWith($want)) {
    Leave $pr 'NOT APPROVED' "its head $(Short $head) is not the approved $(Short $want) - verify the new commit, then queue $pr@$(Short $head)"; continue
  }
  # the contract's bounds (#381, the header)
  $bc = "coordinator/briefs/$($branch.Replace('/', '-'))-contract.md"; if (-not (Test-Path -LiteralPath $bc)) { $bc = "coordinator/briefs/$(($branch -split '-')[0])-contract.md" }
  if (-not (Test-Path -LiteralPath $bc)) { "BOUNDS #${pr}: no contract at $bc - not checked" }
  else { & { $ErrorActionPreference = 'Continue'; & git fetch -q origin $base 2>&1 | Out-Null; & git fetch -q origin $branch 2>&1 | Out-Null }
    $bo = @(& { $ErrorActionPreference = 'Continue'; & (Join-Path $PSScriptRoot 'check-bounds.ps1') $bc "origin/$base...$head" 2>&1 } | ForEach-Object { "$_" }); $brc = $LASTEXITCODE
    $bover = @($bo | Where-Object { $_ -clike 'check-bounds: OVER *' } | ForEach-Object { $_.Substring(19) })
    if ($brc -eq 1) {   # which OVER stops (#419, the header); the list unreadable: every OVER stops
      $bimp = @(& { $ErrorActionPreference = 'Continue'; & (Join-Path $PSScriptRoot 'check-contract.ps1') -Important 2>&1 } | ForEach-Object { "$_" }); if ($LASTEXITCODE -ne 0) { $bimp = @() }
      $bstop = @(); foreach ($bl in $bover) { $bg = $bl.Substring(0, $bl.LastIndexOf(' '))
        if (-not $bimp -or @($bimp | Where-Object { $_ -clike $bg -or $bg -clike $_ }).Count) { $bstop += $bl } else { "bounds over, not important: $pr $bl" } }
      $bover = $bstop; if (-not $bover) { $brc = 0 } }
    if ($brc -eq 1 -and $okPr -ceq $pr) { "BOUNDS #${pr}: over its bounds ($($bover -join ' ')) - passed on the owner's words: $okW" }
    elseif ($brc -eq 1) { $bover | ForEach-Object { "OVER BOUNDS $pr $_" }; $left += "#$pr (OVER BOUNDS)"; continue }
    elseif ($brc -ne 0) { Leave $pr 'BOUNDS' "check-bounds exit ${brc}: $($bo | Select-Object -First 1)"; continue }
  }
  $files = @(Q @('pr', 'view', $pr, '--json', 'files', '--template', $T_FILES))
  # runs of this branch on an older head: superseded, they only hold the runners. A run's id is the end of
  # its url: gh's template prints the numeric databaseId as a float (3.88e+10)
  foreach ($r in @(Q @('run', 'list', '--branch', $branch, '--limit', '50', '--json', 'url,headSha,status,conclusion', '--template', $T_RUNS))) {
    $id, $sha, $st = -split $r; $id = ($id -split '/')[-1]
    if (-not $id -or $st -eq 'completed' -or $sha -eq $head) { continue }
    if ($DryRun) { "[dry-run] gh run cancel $id" } else { $null = GhRc @('run', 'cancel', $id); "cancelled run $id ($(Short $sha), superseded)" }
  }
  $k = Behind $base $head
  if ($k -and $k -ne '0') {
    if ($DryRun) { "[dry-run] gh pr update-branch $pr"; Leave $pr 'SKIP' "dry run - $k behind $base, would update its branch and wait for its checks"; continue }
    $ub = @(& gh pr update-branch $pr 2>&1 | ForEach-Object { "$_" })
    if ($LASTEXITCODE -ne 0) {
      Leave $pr 'CONFLICT' "$branch - $base did not merge in ($(($ub | Where-Object { $_ }) -join ' ')); its worker merges $base by hand, runs its checks and pushes, then queue it again"; continue
    }
    # GitHub answers before the PR shows its new head: read it again until it moves (about 90 s)
    $new = $head; $n = 0
    while ($new -eq $head -and $n -lt 18) {
      if ($n -gt 0) { Start-Sleep -Seconds ([Math]::Min([int]$Poll, 5)) }; $n++
      $new = (PrView $pr)[2]
    }
    if ($new -eq $head) { Leave $pr 'TIMEOUT' 'its branch was updated, but its head did not move within 90 s - queue it again'; continue }
    $k = Behind $base $new
    if ($k -and $k -ne '0') {
      Leave $pr 'CONFLICT' "$branch - $base did not merge in; its worker merges $base by hand, runs its checks and pushes, then queue it again"; continue
    }
    $came = @(Q @('api', "repos/{owner}/{repo}/compare/$head...$new", '--template', $T_CMPFILES))
    $both = Meet $files $came
    if ($both) {
      Leave $pr 'REVIEW' "$base changed files this PR changes too: $both - re-review the merge (git diff $(Short $head) $(Short $new)), then queue $pr@$(Short $new)"; continue
    }
    "updated #${pr}: $(Short $head) -> $(Short $new), $base merged in without touching the PR's files"; $head = $new
  }
  # the checks of the current head: all pass or skipped -> green; a failure re-runs the failed runs once;
  # after the re-run a failure counts again once a check went pending (or after three polls)
  $start = Get-Date; $retried = $false; $seen = $false; $rpoll = 0; $empty = 0; $tag = ''; $msg = ''
  while ($true) {
    $now = (PrView $pr)[2]
    if ($now -ne $head) { $tag = 'HEAD MOVED'; $msg = "$(Short $head) -> $(Short $now) while it waited - verify the new commit, then queue $pr@$(Short $now)"; break }
    $best = @{}
    foreach ($l in @(& gh pr checks $pr --json name,startedAt,bucket --template $T_CHECKS 2>$null | ForEach-Object { "$_" })) {
      $f = $l -split "`t"; if ($f.Count -lt 3) { continue }
      $t = if (-not $f[1] -or $f[1].StartsWith('0001-')) { '9999' } else { $f[1] }
      if (-not $best.ContainsKey($f[0]) -or [string]::CompareOrdinal($t, $best[$f[0]][0]) -ge 0) { $best[$f[0]] = @($t, $f[2]) }
    }
    $b = @($best.Values | ForEach-Object { $_[1] })
    if (-not $b.Count) {
      $empty++; if ($empty -ge 5) { $tag = 'NO CHECKS'; $msg = "no check ran on $(Short $head)"; break }
    } elseif ($b -contains 'pending') { $seen = $true }
    elseif ($b -contains 'fail' -or $b -contains 'cancel') {
      if (-not $retried) {
        $ids = @(Q @('run', 'list', '--commit', $head, '--limit', '50', '--json', 'url,headSha,status,conclusion', '--template', $T_RUNS) |
          Where-Object { (-split $_)[3] -match '^(failure|cancelled|timed_out|startup_failure)$' } | ForEach-Object { ((-split $_)[0] -split '/')[-1] })
        if (-not $ids.Count) { $tag = 'FAILED'; $msg = "a check failed on $(Short $head) and no run of it can be re-run - classify it from its log (CORE ${sect}4 step 4), never merge over it"; break }
        if ($DryRun) { foreach ($id in $ids) { "[dry-run] gh run rerun $id --failed" }; $tag = 'SKIP'; $msg = 'dry run - a check failed, would re-run it once'; break }
        foreach ($id in $ids) { $null = GhRc @('run', 'rerun', $id, '--failed') }
        "re-ran #$pr's failed runs once: $($ids -join ' ')"; $retried = $true; $seen = $false; $rpoll = 0
      } elseif ($seen -or $rpoll -ge 3) {
        $tag = 'FAILED'; $msg = "its checks failed twice on $(Short $head) - read the log before anything else: the queue re-ran them once, so a flake is a flake bug; classify it (CORE ${sect}4 step 4), never merge over it"; break
      } else { $rpoll++ }
    } else { break }
    if ($DryRun) { $tag = 'SKIP'; $msg = 'dry run - its checks are pending'; break }
    if (((Get-Date) - $start).TotalSeconds -ge [int]$Timeout * 60) { $tag = 'TIMEOUT'; $msg = "its checks still pending after $Timeout min"; break }
    Start-Sleep -Seconds ([int]$Poll)
  }
  if ($tag) { Leave $pr $tag $msg; continue }
  if ($DryRun) { "[dry-run] gh pr merge $pr --$Method --match-head-commit $head"; Leave $pr 'SKIP' 'dry run - green, would merge'; continue }
  # no --delete-branch: gh would also delete the local branch and with it the worker's worktree, past
  # cleanup-worker's checks (CORE section 8); only the remote branch goes, cleanup-worker removes the rest
  $out = @(& gh pr merge $pr "--$Method" --match-head-commit $head 2>&1 | ForEach-Object { "$_" })
  if ($LASTEXITCODE -ne 0) { Leave $pr 'MERGE FAILED' (($out | Where-Object { $_ }) -join ' '); continue }
  $merged++; "MERGED #${pr}: $(Short $head)"
  # a branch other open PRs are based on stays: GitHub closes a PR whose base is deleted (#229)
  $deps = (@(& gh pr list --state open --base $branch --json number --template '{{range .}}#{{.number}} {{end}}' 2>$null) -join '').Trim()
  # a fork's PR: its branch is not on origin, and that name there may be someone else's branch (#392)
  if ($fork -eq 'true') { "left the fork's branch ${branch}: #$pr is a fork's PR, nothing deleted on origin" }
  elseif ($deps) { "kept the remote branch ${branch}: $deps use it as their base" }
  elseif ((GhRc @('api', '-X', 'DELETE', "repos/{owner}/{repo}/git/refs/heads/$branch")) -eq 0) { "deleted the remote branch $branch" }
  # the open PRs that change a file this one changed (shared ones too): their workers merge main now
  foreach ($l in @(OpenPrs)) {
    $f = $l -split "`t"; if ($f[0] -eq $pr) { continue }
    $both = Meet (PrFiles $l) $files -All
    if ($both) { "AFFECTED #$($f[0]): $($f[3]) - merge $base now: $both" }
  }
  # the merge row of CORE section 4's event table, one thing a line, filled in; printed only, nothing here runs a duty (#242, #466)
  $n = if ($branch -match '^([0-9]+)-') { $Matches[1] } else { '<n>' }
  # the task's finished sessions of this project (#493, #521): listed with their launch folder only (measured), so the brief kept by the sessionId
  # names the task's worktree (any id), else (no brief kept) the name `#<n> ` or `#<n>.`; with a run row (runs check) removed, the rest named with
  # their rm; a failing listing or none found: no line
  $fin = @(); $rmd = @(); $ms = $null; $root = ($pwd.ProviderPath -replace '\\+', '/').TrimEnd('/')
  $bd = "$(if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' })/coordinator/briefs"
  try { $ls = @(& { $ErrorActionPreference = 'Continue'; & claude agents --json --all 2>$null } | ForEach-Object { "$_" }) -join "`n"
    if ($LASTEXITCODE -eq 0) { $js = $ls | ConvertFrom-Json; foreach ($s in @($js | ForEach-Object { $_ })) { $cw = ("$($s.cwd)" -replace '\\+', '/').TrimEnd('/'); $nm = "$($s.name)"; $kb = "$bd/$($s.sessionId).md"
      if (-not ($s.id -and $s.state -in @('done', 'stopped', 'failed') -and -not ($s.PSObject.Properties.Name -contains 'status') -and ($cw -ieq $root -or $cw.StartsWith("$root/", [StringComparison]::OrdinalIgnoreCase)))) { continue }
      if (Test-Path -LiteralPath $kb -PathType Leaf) { $f1 = "$(@(Get-Content -LiteralPath $kb -TotalCount 1))"; if (-not ($f1.Contains("/$branch. ") -or $f1.Contains("/$branch, "))) { continue } }
      elseif ($n -eq '<n>' -or -not ($nm.StartsWith("#$n ") -or $nm.StartsWith("#$n."))) { continue }
      if ($null -eq $ms) { $ms = @(& { $ErrorActionPreference = 'Continue'; & (Join-Path $PSScriptRoot 'runs.ps1') check -Log ([IO.Path]::Combine($pwd.ProviderPath, $Runs)) -Root $root 2>$null } | ForEach-Object { "$_" }); if ($LASTEXITCODE -ne 0) { $ms = @('-') } }
      $rc = 1; if ($ms[0] -ne '-' -and -not @($ms | Where-Object { $_.StartsWith("MISSING $($s.id) ") }).Count) { $null = & { $ErrorActionPreference = 'Continue'; & claude rm $s.id 2>&1 }; $rc = $LASTEXITCODE }
      if ($rc -eq 0) { $rmd += "$($s.id) ($nm)" } else { $fin += "claude rm $($s.id) ($nm)" } } } } catch { }
  foreach ($l in @(
    "cleanup-worker -Worktree .claude/worktrees/$branch (CORE ${sect}8)",
    "the run rows of task $n (branch $branch), then runs check, and the journal line (CORE ${sect}7)",
    $(if ($rmd.Count) { "removed the finished sessions of this task whose run rows are written: $($rmd -join '; ')" }),
    $(if ($fin.Count) { "other finished sessions of task $n are still listed; claude rm only after the run rows above: $($fin -join '; ')" }),
    "close issue #$n and move it on the board, by the project's words (PROJECT.md) where it has none",
    "the task row, from the product repository: gh pr view $pr --json statusCheckRollup,mergedAt,createdAt | run-stats $Runs -Task $n -PrJson:- -Append",
    "tell each AFFECTED PR's session to merge $base (CORE ${sect}4a)",
    "did a rule or number in the project's own files move? did a core rule or check fail us, the verifier's core_findings too (CORE ${sect}10)? an escape (CORE ${sect}12)?",
    "the project's own after-merge duties (PROJECT.md)"
  )) { if ($l) { "AFTER MERGE #${pr}: $l" } }
}
"merge-queue: $merged merged$(if ($left.Count) { ", left: $($left -join ', ')" })"
if ($left.Count) { exit 3 }
exit 0
} finally { if ($enc0) { try { [Console]::OutputEncoding = $enc0 } catch { } } }
