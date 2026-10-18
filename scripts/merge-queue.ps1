# Land approved PRs one at a time, in the order given (Windows; macOS / Linux: merge-queue.sh - the same
# steps, lines and codes; CORE section 4a): parallel work, serial merging - each PR merges main once, when
# its turn comes, never after every other merge.
#   powershell -File scripts\merge-queue.ps1 land -Pr <pr>[@<approved sha>],... [-Method squash|merge|rebase]
#                    [-Shared <glob>,...] [-Poll <seconds>] [-Timeout <minutes>] [-DryRun]
#   powershell -File scripts\merge-queue.ps1 status [-Shared <glob>,...]
# land, per PR in order: open and not a draft; its head the approved commit (when @<sha> is given); runs of
# its branch on an older head cancelled; behind its base -> `gh pr update-branch` (GitHub merges the base
# in), and when the base brought changes to files the PR changes too (outside -Shared), it stops for a
# re-review of that merge; the checks of the current head waited for (all pass or skipped); a failure
# re-runs the failed runs once, a second failure stops; then `gh pr merge --<method>
# --match-head-commit <head>` and the remote branch deleted (never the local one: the worker's worktree
# stays for cleanup-worker; a branch other open PRs are based on is kept, #229), and every open PR that
# changes a file the merged one changed is printed
# as AFFECTED. The queue never resolves a conflict and never merges a commit it was not given or did not
# make itself. -Shared: a file the project lets every task append to or regenerate (PROJECT.md *Shared
# files*); a glob, `*` crosses folders. status: each open PR's merge state, the CONFLICTING ones (CI does
# not run on them) and the pairs of open PRs that change the same files outside -Shared.
# Lines (wrappers read them), each `<TAG> #<pr>: ...`: MERGED, AFFECTED, SKIP, NOT APPROVED, CONFLICT,
# REVIEW, HEAD MOVED, FAILED, NO CHECKS, TIMEOUT, MERGE FAILED; status: CONFLICTING, OVERLAP.
# Exit codes: 0 every PR merged (status: always 0); 1 usage error or gh failed; 3 a PR was left (its line
# says why; the queue goes on with the next). Only gh is called, never git.
param([Parameter(Position = 0)][string]$Mode, [string]$Pr, [string]$Method = 'squash', [string]$Shared,
      [string]$Poll = '60', [string]$Timeout = '120', [switch]$DryRun)
# native output (gh) is read and this script's own output written as UTF-8, whatever the console's code
# page; the caller's console gets its own encoding back on every way out
$enc0 = $null; try { $enc0 = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
try {
$usage = 'usage: land -Pr <pr>[@<sha>],... [-Method squash|merge|rebase] [-Shared <glob>,...] [-Poll <s>] [-Timeout <min>] [-DryRun] | status [-Shared <glob>,...]'
function Usage([string]$m) { [Console]::Error.WriteLine($(if ($m) { "$m; $usage" } else { $usage })); exit 1 }
if ($Mode -ne 'land' -and $Mode -ne 'status') { Usage '' }
if ($Method -notin @('squash', 'merge', 'rebase')) { Usage '-Method: squash, merge or rebase' }
if ($Poll -notmatch '^[0-9]+$' -or $Timeout -notmatch '^[0-9]+$') { Usage '-Poll and -Timeout take whole numbers' }
$prs = @(if ($Pr) { $Pr -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } })
$globs = @(if ($Shared) { $Shared -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } })
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
$T_PR = "{{.state}} {{.isDraft}} {{.headRefOid}} {{.headRefName}} {{.baseRefName}}`n"
$T_FILES = "{{range .files}}{{.path}}`n{{end}}"
$T_CMPFILES = "{{range .files}}{{.filename}}`n{{end}}"
$T_CHECKS = "{{range .}}{{.bucket}}`n{{end}}"
$T_RUNS = "{{range .}}{{.url}} {{.headSha}} {{.status}} {{.conclusion}}`n{{end}}"
$T_LIST = "{{range .}}{{.number}}`t{{.mergeable}}`t{{.mergeStateStatus}}`t{{.headRefName}}{{range .files}}`t{{.path}}{{end}}`n{{end}}"
# Q <gh args>: gh's non-empty output lines; a failed gh stops the run (exit 1)
function Q([string[]]$a) {
  $o = @(& gh @a 2>&1 | ForEach-Object { "$_" })
  if ($LASTEXITCODE -ne 0) { [Console]::Error.WriteLine("gh $($a[0]) $($a[1]) failed: $($o -join "`n")"); exit 1 }
  @($o | ForEach-Object { $_ -split "`r?`n" } | Where-Object { $_ -ne '' })
}
function GhRc([string[]]$a) { $null = & gh @a 2>&1; $LASTEXITCODE }
function PrView([string]$n) { -split (@(Q @('pr', 'view', $n, '--json', 'state,isDraft,headRefOid,headRefName,baseRefName', '--template', $T_PR)) -join ' ') }
function Behind([string]$x, [string]$y) { "$(@(Q @('api', "repos/{owner}/{repo}/compare/$x...$y", '--template', '{{.behind_by}}')) -join '')" }
function OpenPrs { Q @('pr', 'list', '--state', 'open', '--limit', '200', '--json', 'number,mergeable,mergeStateStatus,headRefName,files', '--template', $T_LIST) }
function IsShared([string]$f) { foreach ($g in $globs) { if ($f -like $g) { return $true } }; $false }
# Meet <a> <b> [all]: the items of a also in b (outside -Shared unless all), joined by ", "
function Meet([string[]]$a, [string[]]$b, [switch]$All) {
  (@($a | Where-Object { $_ -and ($All -or -not (IsShared $_)) -and ($b -ccontains $_) }) -join ', ')
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
  "merge-queue status: $($list.Count) open, $nc conflicting, $np overlapping pairs"
  exit 0
}

$merged = 0; $left = @()
function Leave([string]$n, [string]$tag, [string]$m) { "$tag #${n}: $m"; $script:left += "#$n ($tag)" }
foreach ($item in $prs) {
  $pr, $want = $item -split '@', 2; if ($want) { $want = $want.ToLowerInvariant() }
  $state, $draft, $head, $branch, $base = PrView $pr
  if ($state -ne 'OPEN') { Leave $pr 'SKIP' "$state, not open"; continue }
  if ($draft -eq 'true') { Leave $pr 'SKIP' 'a draft'; continue }
  if ($want -and -not $head.StartsWith($want)) {
    Leave $pr 'NOT APPROVED' "its head $(Short $head) is not the approved $(Short $want) - verify the new commit, then queue $pr@$(Short $head)"; continue
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
    $b = @(& gh pr checks $pr --json bucket --template $T_CHECKS 2>$null | ForEach-Object { "$_" } | Where-Object { $_ -ne '' })
    if (-not $b.Count) {
      $empty++; if ($empty -ge 5) { $tag = 'NO CHECKS'; $msg = "no check ran on $(Short $head)"; break }
    } elseif ($b -contains 'pending') { $seen = $true }
    elseif ($b -contains 'fail' -or $b -contains 'cancel') {
      if (-not $retried) {
        $ids = @(Q @('run', 'list', '--commit', $head, '--limit', '50', '--json', 'url,headSha,status,conclusion', '--template', $T_RUNS) |
          Where-Object { (-split $_)[3] -match '^(failure|cancelled|timed_out|startup_failure)$' } | ForEach-Object { ((-split $_)[0] -split '/')[-1] })
        if (-not $ids.Count) { $tag = 'FAILED'; $msg = "a check failed on $(Short $head) and no run of it can be re-run"; break }
        if ($DryRun) { foreach ($id in $ids) { "[dry-run] gh run rerun $id --failed" }; $tag = 'SKIP'; $msg = 'dry run - a check failed, would re-run it once'; break }
        foreach ($id in $ids) { $null = GhRc @('run', 'rerun', $id, '--failed') }
        "re-ran #$pr's failed runs once: $($ids -join ' ')"; $retried = $true; $seen = $false; $rpoll = 0
      } elseif ($seen -or $rpoll -ge 3) {
        $tag = 'FAILED'; $msg = "its checks failed twice on $(Short $head) - read the log before anything else"; break
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
  if ($deps) { "kept the remote branch ${branch}: $deps use it as their base" }
  elseif ((GhRc @('api', '-X', 'DELETE', "repos/{owner}/{repo}/git/refs/heads/$branch")) -eq 0) { "deleted the remote branch $branch" }
  # the open PRs that change a file this one changed (shared ones too): their workers merge main now
  foreach ($l in @(OpenPrs)) {
    $f = $l -split "`t"; if ($f[0] -eq $pr) { continue }
    $both = Meet (PrFiles $l) $files -All
    if ($both) { "AFFECTED #$($f[0]): $($f[3]) - merge $base now: $both" }
  }
}
"merge-queue: $merged merged$(if ($left.Count) { ", left: $($left -join ', ')" })"
if ($left.Count) { exit 3 }
exit 0
} finally { if ($enc0) { try { [Console]::OutputEncoding = $enc0 } catch { } } }
