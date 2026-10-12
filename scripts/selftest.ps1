# The scripted steps of the coordinator's self-test (procedures/SELFTEST.md; macOS / Linux: selftest.sh -
# the same steps and output). The steps with real sessions are run by the coordinator, not here.
#   powershell -File scripts/selftest.ps1 scripts                 1: the core's checks and scripts on fixtures
#   powershell -File scripts/selftest.ps1 env [-Repo <owner/name>]   2: claude, git and gh versions; read-only GitHub
#   powershell -File scripts/selftest.ps1 sandbox [-In <folder>]   3: a throwaway repository with a local bare origin,
#                                                       at <folder>/coordinator-selftest (default: home): a fixed
#                                                       path, so the owner trusts its repo once per machine
#   powershell -File scripts/selftest.ps1 clean -Sandbox <dir> [-StateRepo <owner/name>]
#                                                    6: no worktree, branch, session or selftest/* branch
#                                                       left; then the sandbox folder is removed
# Prints `PASS|FAIL|SKIP <step>: <what>` per check, then `selftest <step>: <p> pass, <f> fail, <s> skipped`.
# Step 1 runs the .ps1 scripts under every PowerShell on the machine (Windows PowerShell 5.1 and pwsh).
# Exit 1 on any FAIL, 2 on a usage error.
param([Parameter(Position = 0)][string]$Step, [string]$Repo, [string]$Sandbox, [string]$StateRepo, [string]$In)
# Native commands report on stderr (the hook's block message, git): never a terminating error, whatever
# the caller set (GitHub's powershell shell runs with Stop)
$ErrorActionPreference = 'Continue'
$core = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
function Usage { Get-Content -LiteralPath $PSCommandPath -TotalCount 13 | ForEach-Object { $_ -replace '^# ?', '' }; exit 2 }
if (-not $Step) { Usage }
$script:p = 0; $script:f = 0; $script:s = 0
function Pass([string]$m) { "PASS ${Step}: $m"; $script:p++ }
function Fail([string]$m) { "FAIL ${Step}: $m"; $script:f++ }
function Skip([string]$m) { "SKIP ${Step}: $m"; $script:s++ }
function Finish { "selftest ${Step}: $($script:p) pass, $($script:f) fail, $($script:s) skipped"; if ($script:f -gt 0) { exit 1 }; exit 0 }
function G { & git -c user.email=selftest@localhost -c user.name=selftest @args }
$marker = '.coordinator-selftest'
function NewTemp([string]$parent) { if (-not $parent) { $parent = [IO.Path]::GetTempPath() }; $d = Join-Path $parent ('coordinator-selftest.' + [IO.Path]::GetRandomFileName().Replace('.', '')); New-Item -ItemType Directory -Path $d | Out-Null; $d }

switch ($Step) {
'scripts' {
  if ($Repo -or $Sandbox -or $StateRepo -or $In) { Usage }
  $shells = @()
  foreach ($c in @(@('powershell', '5.1'), @('pwsh', '7'))) {
    $cmd = Get-Command $c[0] -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { $shells += , @($cmd.Source, $c[1]) }
  }
  if ($shells.Count -eq 0) { $shells = @(, @((Get-Process -Id $PID).Path, '')) }
  $want = ([IO.File]::ReadAllText((Join-Path $core 'tests/session-tokens/expected.txt')) -replace "`r", '').TrimEnd("`n")
  $old = $env:CLAUDE_CONFIG_DIR
  foreach ($sh in $shells) {
    $exe = $sh[0]; $tag = if ($shells.Count -gt 1) { " ($($sh[1]))" } else { '' }
    function Run([string]$script) { $input | & $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $core $script) @args }
    $null = Run 'scripts/check-core.ps1' $core; if ($LASTEXITCODE -eq 0) { Pass "check-core$tag" } else { Fail "check-core$tag" }
    $null = Run 'scripts/check-scripts.ps1' (Join-Path $core 'scripts'); if ($LASTEXITCODE -eq 0) { Pass "check-scripts$tag" } else { Fail "check-scripts$tag" }
    $null = Run 'scripts/check-contract.ps1' (Join-Path $core 'tests/selftest/contract.md')
    if ($LASTEXITCODE -eq 0) { Pass "check-contract on the fixture$tag" } else { Fail "check-contract on the fixture$tag" }
    $t = NewTemp
    $env:CLAUDE_CONFIG_DIR = $t
    $out = "$([IO.File]::ReadAllText((Join-Path $core 'tests/selftest/status.json')) | Run 'scripts/statusline.ps1')"
    if ($out -notmatch '5h 14%.*week 92%') { Fail "statusline$tag`: printed '$out'" }
    elseif (-not (Test-Path -LiteralPath (Join-Path $t 'coordinator/sessions/selftest-fixture.json'))) { Fail "statusline$tag`: no session file" }
    else { Pass "statusline$tag" }
    Remove-Item -LiteralPath $t -Recurse
    $env:CLAUDE_CONFIG_DIR = Join-Path $core 'tests/session-tokens/claude'
    $got = (@(Run 'scripts/session-tokens.ps1' 's1') -join "`n")
    if ($got -eq $want) { Pass "session-tokens$tag" } else { Fail "session-tokens$tag`: differs from tests/session-tokens/expected.txt" }
    $env:CLAUDE_CONFIG_DIR = $old
    $hook = Join-Path $core 'scripts/hooks/safety-guard.ps1'
    function Hook([string]$cmd) { $null = ('{"tool_input":{"command":"' + $cmd + '"}}') | & $exe -NoProfile -ExecutionPolicy Bypass -File $hook 2>$null; $LASTEXITCODE }
    if ("$(& $exe -NoProfile -ExecutionPolicy Bypass -File $hook -SelfTest)".Trim() -eq 'safety-guard: OK') { Pass "safety-guard self-test$tag" } else { Fail "safety-guard self-test$tag" }
    if ((Hook 'git push -u origin selftest/task-1') -eq 0) { Pass "safety-guard allows selftest/*$tag" } else { Fail "safety-guard blocks selftest/*$tag" }
    if ((Hook 'git push origin main') -eq 2 -and (Hook 'git push origin master') -eq 2) { Pass "safety-guard blocks main and master$tag" }
    else { Fail "safety-guard lets a push to main or master through$tag" }
  }
  Finish
}
'env' {
  if ($Sandbox -or $StateRepo -or $In) { Usage }
  foreach ($c in @('claude', 'git')) {
    $v = $null
    if (Get-Command $c -ErrorAction SilentlyContinue) { $v = @(& $c --version 2>$null)[0] }
    if ($v) { Pass ("$c " + ($v -replace "^$c version ", '')) } else { Fail "$c not found" }
  }
  $v = $null
  if (Get-Command gh -ErrorAction SilentlyContinue) { $v = @(& gh --version 2>$null)[0] }
  if ($v) { Pass ('gh ' + ($v -replace '^gh version ', '')) } else { Skip 'gh not installed: no PR flow'; $Repo = '' }
  if (-not $Repo) { Skip 'GitHub: n/a (no -Repo)' }
  else {
    $null = & gh auth status 2>&1; if ($LASTEXITCODE -eq 0) { Pass 'gh auth status' } else { Fail 'gh auth status' }
    $null = & gh repo view $Repo --json name 2>&1; if ($LASTEXITCODE -eq 0) { Pass "gh repo view $Repo" } else { Fail "gh repo view $Repo" }
    $null = & gh pr list -R $Repo -L 1 2>&1; if ($LASTEXITCODE -eq 0) { Pass "gh pr list $Repo" } else { Fail "gh pr list $Repo" }
  }
  Finish
}
'sandbox' {
  if ($Repo -or $Sandbox -or $StateRepo) { Usage }
  if ($In -and -not (Test-Path -LiteralPath $In -PathType Container)) { Fail "no folder $In"; Finish }
  $d = Join-Path $(if ($In) { $In } else { $HOME }) 'coordinator-selftest'
  if (Test-Path -LiteralPath $d) { Fail "$d already exists: a previous run left it (selftest clean -Sandbox $d)"; Finish }
  New-Item -ItemType Directory -Path $d | Out-Null
  New-Item -ItemType File -Path (Join-Path $d $marker) | Out-Null
  $remote = Join-Path $d 'remote.git'; $r = Join-Path $d 'repo'
  $ok = $true
  foreach ($a in @(
      @('init', '-q', '--bare', $remote), @('-C', $remote, 'symbolic-ref', 'HEAD', 'refs/heads/main'),
      @('init', '-q', $r), @('-C', $r, 'symbolic-ref', 'HEAD', 'refs/heads/main'))) {
    if ($ok) { & git @a; $ok = $LASTEXITCODE -eq 0 }
  }
  if ($ok) {
    [IO.File]::WriteAllText((Join-Path $r 'README.md'), "Coordinator self-test sandbox: throwaway, removed by ``selftest clean``.`n")
    & git -C $r add README.md 2>$null; $ok = $LASTEXITCODE -eq 0
    if ($ok) { G -C $r commit -q -m 'selftest: sandbox'; $ok = $LASTEXITCODE -eq 0 }
    if ($ok) { & git -C $r remote add origin $remote; $ok = $LASTEXITCODE -eq 0 }
    if ($ok) { & git -C $r push -q -u origin main 2>$null; $ok = $LASTEXITCODE -eq 0 }
  }
  if ($ok) { Pass 'repository with a local bare origin, branch main' } else { Fail 'could not set up the repositories' }
  "sandbox: $d"
  'started: ' + (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
  Finish
}
'clean' {
  if (-not $Sandbox -or $Repo -or $In) { Usage }
  $d = $Sandbox
  if (-not (Test-Path -LiteralPath (Join-Path $d $marker) -PathType Leaf)) { Fail "$d is not a self-test sandbox (no $marker): nothing removed"; Finish }
  $r = Join-Path $d 'repo'
  # worktrees (the first one listed is the repository itself): removed only when clean and merged into main
  $wts = @(& git -C $r worktree list --porcelain | Where-Object { $_ -like 'worktree *' } | ForEach-Object { $_.Substring(9) })
  foreach ($w in ($wts | Select-Object -Skip 1)) {
    $dirty = & git -C $w status --porcelain 2>$null
    if ($LASTEXITCODE -ne 0 -or $dirty) { continue }
    $head = & git -C $w rev-parse HEAD
    & git -C $r merge-base --is-ancestor $head main
    if ($LASTEXITCODE -eq 0) { & git -C $r worktree remove $w }
  }
  $left = @(& git -C $r worktree list --porcelain | Where-Object { $_ -like 'worktree *' }).Count
  if ($left -le 1) { Pass 'no worktree left' } else { Fail "$($left - 1) worktree(s) left: not clean or not merged into main" }
  foreach ($b in @(& git -C $r for-each-ref --format='%(refname:short)' refs/heads)) {
    if ($b -eq 'main') { continue }
    & git -C $r merge-base --is-ancestor $b main
    if ($LASTEXITCODE -eq 0) { & git -C $r branch -q -d $b }
  }
  $b = @(& git -C $r for-each-ref --format='%(refname:short)' refs/heads | Where-Object { $_ -ne 'main' })
  if ($b.Count -eq 0) { Pass 'no branch left' } else { Fail "branches not merged into main: $($b -join ' ')" }
  if (Get-Command claude -ErrorAction SilentlyContinue) {
    $json = "$(& claude agents --json 2>$null)"
    $n = @([regex]::Matches($json, '"name":\s*"([^"]*selftest[^"]*)"') | ForEach-Object { $_.Groups[1].Value })
    if ($n.Count -eq 0) { Pass 'no self-test session left' } else { Fail "sessions left: $($n -join ' ')" }
  } else { Skip 'no claude: sessions not checked' }
  if ($StateRepo) {
    $n = @(& gh api "repos/$StateRepo/branches" --paginate --jq '.[].name' 2>$null)
    if ($LASTEXITCODE -ne 0) { Fail "cannot list the branches of $StateRepo" }
    else {
      $n = @($n | Where-Object { $_ -like 'selftest/*' })
      if ($n.Count -eq 0) { Pass "no selftest/* branch on $StateRepo" } else { Fail "branches left on ${StateRepo}: $($n -join ' ')" }
    }
  } else { Skip 'state repository: not checked (no -StateRepo)' }
  if ($script:f -eq 0) {
    try { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction Stop; Pass 'sandbox removed' } catch { Fail "could not remove $d" }
  } else { "sandbox kept for inspection: $d" }
  Finish
}
default { Usage }
}
