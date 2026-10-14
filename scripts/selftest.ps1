# The scripted steps of the coordinator's self-test (procedures/SELFTEST.md; macOS / Linux: selftest.sh -
# the same steps and output). The steps with real sessions are run by the coordinator, not here.
#   powershell -File scripts/selftest.ps1 scripts                 1: the core's checks and scripts on fixtures
#   powershell -File scripts/selftest.ps1 env [-Repo <owner/name>]   2: claude, git and gh versions; read-only GitHub
# In a project (procedures/SELFTEST.md, the normal case) - the state repository, evidence kept:
#   powershell -File scripts/selftest.ps1 prepare -Project <root> -State <coordinator dir> -Core <commit>
#                                                    3: the project's git ignores .claude/worktrees;
#                                                       branch selftest/<commit>/base from the state branch
#   powershell -File scripts/selftest.ps1 verify -Project <root> -State <coordinator dir> -Core <commit> [-StateRepo <owner/name>]
#                                                    6: no session or worktree left; the evidence is there
#                                                       (base, st1 merged into it, the merged PR); nothing deleted
# The safety guard as Claude Code runs it (TOOLKIT Safety; a hook that fails to run blocks nothing):
#   powershell -File scripts/selftest.ps1 hooks -Settings <settings.json>   the guard hook's command: forward slashes,
#                                                       no $env:, no PowerShell shell that turns its exit 2 into 1;
#                                                       env COORD_PROTECTED_ROOT: a folder, edit tools matched
#   powershell -File scripts/selftest.ps1 hookcheck -Session <id> [-Expect edit]   a session told to push to main
#                                                       (with edit: to Write into the protected root): its transcript
#                                                       shows the block, not a non-blocking hook error
# For the core itself (the maintainer, CI) - a sandbox, kept between runs or removed:
#   powershell -File scripts/selftest.ps1 sandbox [-In <folder>]   3: a repository with a local bare origin,
#                                                       at <folder>/coordinator-selftest (default: home): a fixed
#                                                       path, so the owner trusts its repo once per machine;
#                                                       a sandbox kept by clean -Keep is reused
#   powershell -File scripts/selftest.ps1 clean -Sandbox <dir> [-Keep] [-StateRepo <owner/name>]
#                                                    6: no worktree, branch, session or selftest/* branch
#                                                       left; then the sandbox folder is removed - or, with
#                                                       -Keep, kept: only main, at the sandbox's first commit
# Prints `PASS|FAIL|SKIP <step>: <what>` per check, then `selftest <step>: <p> pass, <f> fail, <s> skipped`.
# Step 1 runs the .ps1 scripts under every PowerShell on the machine (Windows PowerShell 5.1 and pwsh).
# Exit 1 on any FAIL, 2 on a usage error.
param([Parameter(Position = 0)][string]$Step, [string]$Repo, [string]$Sandbox, [string]$StateRepo, [string]$In,
      [string]$Project, [string]$State, [string]$Core, [string]$Settings, [string]$Session, [string]$Expect, [switch]$Keep,
      [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
# native output (git, bash) is read and this script's own output written as UTF-8, whatever the console's
# code page (cp866 on a Russian Windows garbles a non-ASCII path or a section sign); no console: left as is.
# The caller's console gets its own encoding back on every way out (the end, any exit N, a terminating
# error): the body below runs inside try, the encoding is restored in finally.
$enc0 = $null; try { $enc0 = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
try {
# Native commands report on stderr (the hook's block message, git): never a terminating error, whatever
# the caller set (GitHub's powershell shell runs with Stop)
$ErrorActionPreference = 'Continue'
# What is piped to the scripts goes as UTF-8 without a BOM, as Claude Code sends it (a BOM breaks their JSON)
$OutputEncoding = New-Object System.Text.UTF8Encoding $false
$coreDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
function Usage { Get-Content -LiteralPath $PSCommandPath -TotalCount 30 | ForEach-Object { $_ -replace '^# ?', '' }; exit 2 }
if (-not $Step) { Usage }
# a step takes only its own parameters: anything else (another step's, an unknown one, a stray word) is a
# usage error, as in selftest.sh
$given = @($PSBoundParameters.Keys | Where-Object { $_ -ne 'Step' -and $_ -ne 'Rest' })
function Only([string[]]$ok) { if ($Rest) { Usage }; foreach ($k in $given) { if ($ok -notcontains $k) { Usage } } }
$script:p = 0; $script:f = 0; $script:s = 0
function Pass([string]$m) { "PASS ${Step}: $m"; $script:p++ }
function Fail([string]$m) { "FAIL ${Step}: $m"; $script:f++ }
function Skip([string]$m) { "SKIP ${Step}: $m"; $script:s++ }
function Finish { "selftest ${Step}: $($script:p) pass, $($script:f) fail, $($script:s) skipped"; if ($script:f -gt 0) { exit 1 }; exit 0 }
function G { & git -c user.email=selftest@localhost -c user.name=selftest @args }
$marker = '.coordinator-selftest'
# the sandbox's first commit, which sandbox records in the marker as `initial <commit>` (outside the
# repository, where no git command in the sandbox can move it); empty for a sandbox from an older core
function Initial([string]$d) {
  $m = Join-Path $d $marker
  if (-not (Test-Path -LiteralPath $m -PathType Leaf)) { return '' }
  $x = [regex]::Match("$(Get-Content -LiteralPath $m -Raw)", '(?m)^initial ([0-9a-f]{40,})\r?$')
  if ($x.Success) { $x.Groups[1].Value } else { '' }
}
# the untracked and ignored files of a repository, except .claude/settings.local.json: the permissions
# the owner gave its sessions there, kept with the sandbox like the trust
function Untracked([string]$r) {
  @(& git -C $r status --porcelain --ignored --untracked-files=all | Where-Object { $_ -cne '?? .claude/settings.local.json' -and $_ -cne '!! .claude/settings.local.json' })
}
# KeptWhy <sandbox>: nothing when it is a kept sandbox ready for the next run (only main, at the first
# commit, in the repo and in its origin; no worktree; nothing untracked), else why it is not
function KeptWhy([string]$d) {
  $r = Join-Path $d 'repo'; $o = Join-Path $d 'remote.git'
  $i = Initial $d
  if (-not $i) { return "no first commit recorded in its $marker" }
  if ("$(& git -C $r rev-parse --git-dir 2>$null)" -cne '.git' -or "$(& git -C $o rev-parse --is-bare-repository 2>$null)" -cne 'true') { return 'no repo and remote.git' }
  if (@(& git -C $r worktree list --porcelain | Where-Object { $_ -like 'worktree *' }).Count -gt 1) { return 'worktrees left' }
  if ("$(& git -C $r for-each-ref --format='%(refname)' refs/heads)" -cne 'refs/heads/main' -or
      "$(& git -C $o for-each-ref --format='%(refname)' refs/heads)" -cne 'refs/heads/main') { return 'branches other than main' }
  if ("$(& git -C $r symbolic-ref -q HEAD)" -cne 'refs/heads/main' -or "$(& git -C $r rev-parse -q --verify refs/heads/main)" -cne $i -or
      "$(& git -C $o rev-parse -q --verify refs/heads/main)" -cne $i) { return 'main is not at the first commit' }
  if (@(Untracked $r).Count -gt 0) { return 'changed or untracked files in the repo' }
  ''
}
# the self-test sessions claude agents --json --all still lists, in any state (a done one too): a name
# with `selftest` or `probe:`, or starting with `#st`; `<name> (<id>)` joined by `, `, '' when none
function StSessions {
  $json = (@(& claude agents --json --all 2>$null | ForEach-Object { "$_" }) -join '') -replace "[`r`n]", ''
  $n = foreach ($o in ($json -split '}')) {
    $m = [regex]::Match($o, '"name": *"([^"]*)"')
    if (-not $m.Success) { continue }
    $nm = $m.Groups[1].Value
    if ($nm.StartsWith('#st', [StringComparison]::Ordinal) -or $nm.Contains('selftest') -or $nm.Contains('probe:')) {
      "$nm ($([regex]::Match($o, '"id": *"([^"]*)"').Groups[1].Value))"
    }
  }
  @($n) -join ', '
}
function NewTemp([string]$parent) { if (-not $parent) { $parent = [IO.Path]::GetTempPath() }; $d = Join-Path $parent ('coordinator-selftest.' + [IO.Path]::GetRandomFileName().Replace('.', '')); New-Item -ItemType Directory -Path $d | Out-Null; $d }

switch ($Step) {
'scripts' {
  Only @()
  $shells = @()
  foreach ($c in @(@('powershell', '5.1'), @('pwsh', '7'))) {
    $cmd = Get-Command $c[0] -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { $shells += , @($cmd.Source, $c[1]) }
  }
  if ($shells.Count -eq 0) { $shells = @(, @((Get-Process -Id $PID).Path, '')) }
  $want = ([IO.File]::ReadAllText((Join-Path $coreDir 'tests/session-tokens/expected.txt')) -replace "`r", '').TrimEnd("`n")
  # a local copy must not hold the core's CLAUDE.md: Claude Code loads it into every session that reads
  # the copy's files, telling workers they are the coordinator. Only the maintainer's own checkout has
  # .github/ (a project's copy leaves it out), so a copy made by git clone (with .git) counts too
  if ((Test-Path -LiteralPath (Join-Path $coreDir 'CLAUDE.md') -PathType Leaf) -and -not (Test-Path -LiteralPath (Join-Path $coreDir '.github') -PathType Container)) {
    Fail 'the local core copy holds CLAUDE.md: remove it (it tells every worker it is the coordinator)'
  } else { Pass 'no CLAUDE.md in a local core copy' }
  $old = $env:CLAUDE_CONFIG_DIR
  foreach ($sh in $shells) {
    $exe = $sh[0]; $tag = if ($shells.Count -gt 1) { " ($($sh[1]))" } else { '' }
    function Run([string]$script) { $input | & $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $coreDir $script) @args }
    # stdin from a file, not a PowerShell pipe: 5.1 piping into pwsh sometimes delivers nothing
    function Feed([string]$file, [string]$script) {
      if ($env:OS -eq 'Windows_NT') { & cmd /d /s /c "`"$exe`" -NoProfile -ExecutionPolicy Bypass -File `"$script`" < `"$file`" 2>nul" }
      else { Get-Content -Raw -LiteralPath $file | & $exe -NoProfile -File $script 2>$null }
    }
    $null = Run 'scripts/check-core.ps1' $coreDir; if ($LASTEXITCODE -eq 0) { Pass "check-core$tag" } else { Fail "check-core$tag" }
    $null = Run 'scripts/check-scripts.ps1' (Join-Path $coreDir 'scripts'); if ($LASTEXITCODE -eq 0) { Pass "check-scripts$tag" } else { Fail "check-scripts$tag" }
    $null = Run 'scripts/check-contract.ps1' (Join-Path $coreDir 'tests/selftest/contract.md')
    if ($LASTEXITCODE -eq 0) { Pass "check-contract on the fixture$tag" } else { Fail "check-contract on the fixture$tag" }
    $t = NewTemp
    $env:CLAUDE_CONFIG_DIR = $t
    $out = "$(Feed (Join-Path $coreDir 'tests/selftest/status.json') (Join-Path $coreDir 'scripts/statusline.ps1'))"
    if ($out -notmatch '5h 14%.*week 92%') { Fail "statusline$tag`: printed '$out'" }
    elseif (-not (Test-Path -LiteralPath (Join-Path $t 'coordinator/sessions/selftest-fixture.json'))) { Fail "statusline$tag`: no session file" }
    else { Pass "statusline$tag" }
    Remove-Item -LiteralPath $t -Recurse
    $env:CLAUDE_CONFIG_DIR = Join-Path $coreDir 'tests/session-tokens/claude'
    $got = (@(Run 'scripts/session-tokens.ps1' 's1') -join "`n")
    if ($got -eq $want) { Pass "session-tokens$tag" } else { Fail "session-tokens$tag`: differs from tests/session-tokens/expected.txt" }
    $env:CLAUDE_CONFIG_DIR = $old
    $hook = Join-Path $coreDir 'scripts/hooks/safety-guard.ps1'
    $jf = Join-Path ([IO.Path]::GetTempPath()) ('selftest-hook.' + [IO.Path]::GetRandomFileName() + '.json')
    function Hook([string]$cmd) { [IO.File]::WriteAllText($jf, '{"tool_input":{"command":"' + $cmd + '"}}'); $null = Feed $jf $hook; $LASTEXITCODE }
    if ("$(& $exe -NoProfile -ExecutionPolicy Bypass -File $hook -SelfTest)".Trim() -eq 'safety-guard: OK') { Pass "safety-guard self-test$tag" } else { Fail "safety-guard self-test$tag" }
    if ((Hook 'git push -u origin selftest/task-1') -eq 0) { Pass "safety-guard allows selftest/*$tag" } else { Fail "safety-guard blocks selftest/*$tag" }
    if ((Hook 'git push origin main') -eq 2 -and (Hook 'git push origin master') -eq 2) { Pass "safety-guard blocks main and master$tag" }
    else { Fail "safety-guard lets a push to main or master through$tag" }
    Remove-Item -LiteralPath $jf -ErrorAction SilentlyContinue
  }
  Finish
}
'env' {
  Only @('Repo')
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
  Only @('In')
  if ($In -and -not (Test-Path -LiteralPath $In -PathType Container)) { Fail "no folder $In"; Finish }
  # a relative -In made absolute: the repo's origin URL is stored from it, and a relative one breaks
  # every git command run from another folder (a reused sandbox's fetch); an absolute one is kept as given
  if ($In -and -not ($In -match '^(/|\\|[A-Za-z]:[/\\])')) { $In = (Resolve-Path -LiteralPath $In).ProviderPath }
  $d = Join-Path $(if ($In) { $In } else { $HOME }) 'coordinator-selftest'
  if (Test-Path -LiteralPath $d) {
    # a sandbox kept by clean -Keep is reused (its repo's path keeps the owner's trust); nothing else is
    if (-not (Test-Path -LiteralPath (Join-Path $d $marker) -PathType Leaf)) { Fail "$d already exists and is not a self-test sandbox (no $marker): nothing changed"; Finish }
    $why = KeptWhy $d
    if ($why) { Fail "$d already exists and is not clean ($why): run selftest clean -Sandbox $d [-Keep] first"; Finish }
    Pass "reusing the kept sandbox $d"
  } else {
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
      [IO.File]::WriteAllText((Join-Path $r 'README.md'), "Coordinator self-test sandbox: reset or removed by ``selftest clean``.`n")
      & git -C $r add README.md 2>$null; $ok = $LASTEXITCODE -eq 0
      if ($ok) { G -C $r commit -q -m 'selftest: sandbox'; $ok = $LASTEXITCODE -eq 0 }
      if ($ok) { & git -C $r remote add origin $remote; $ok = $LASTEXITCODE -eq 0 }
      if ($ok) { & git -C $r push -q -u origin main 2>$null; $ok = $LASTEXITCODE -eq 0 }
      if ($ok) {
        $i = "$(& git -C $r rev-parse HEAD)"; $ok = $LASTEXITCODE -eq 0
        if ($ok) { [IO.File]::WriteAllText((Resolve-Path -LiteralPath (Join-Path $d $marker)).Path, "initial $i`n") }
      }
    }
    if ($ok) { Pass 'repository with a local bare origin, branch main' } else { Fail 'could not set up the repositories' }
  }
  "sandbox: $d"
  'started: ' + (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
  Finish
}
'clean' {
  Only @('Sandbox', 'StateRepo', 'Keep'); if (-not $Sandbox) { Usage }
  $d = $Sandbox
  if (-not (Test-Path -LiteralPath (Join-Path $d $marker) -PathType Leaf)) { Fail "$d is not a self-test sandbox (no $marker): nothing removed"; Finish }
  $r = Join-Path $d 'repo'; $o = Join-Path $d 'remote.git'
  if ($Keep) {
    # -Keep resets the sandbox to its first commit (the marker records it), so it needs both repositories
    $i = Initial $d
    if (-not $i) {
      # a sandbox kept by an older core records no first commit: main's single root commit, when its
      # origin has it too, is that commit - recorded now, so the sandbox is reset and kept, not removed
      $roots = @(& git -C $r rev-list --max-parents=0 main 2>$null | Where-Object { $_ })
      $found = $false
      if ($roots.Count -eq 1) { & git -C $o cat-file -e "$($roots[0])^{commit}" 2>$null; $found = $LASTEXITCODE -eq 0 }
      if ($found) {
        $i = $roots[0]
        try { [IO.File]::WriteAllText((Resolve-Path -LiteralPath (Join-Path $d $marker)).Path, "initial $i`n") } catch { Fail "cannot write $d/$marker"; Finish }
        Pass "recorded the first commit $(& git -C $r rev-parse --short $i) of a sandbox from an older core"
      } else {
        Fail "no first commit recorded in $d/$marker and none found (a sandbox from an older core): run selftest clean -Sandbox $d without -Keep"; Finish
      }
    }
    $ok = "$(& git -C $r rev-parse --git-dir 2>$null)" -ceq '.git' -and "$(& git -C $o rev-parse --is-bare-repository 2>$null)" -ceq 'true'
    if ($ok) { & git -C $r cat-file -e "$i^{commit}" 2>$null; $ok = $LASTEXITCODE -eq 0 }
    if (-not $ok) { Fail "$d has no repo and remote.git with its first commit ${i}: nothing changed"; Finish }
  }
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
  # the origin's branches go too (deleted by -Keep, removed with the folder otherwise), so each must be
  # merged into the repo's main (the guard blocks pushing main: the origin's own main may lag behind)
  $b = ''
  $heads = @(if (Test-Path -LiteralPath $o -PathType Container) { & git -C $o for-each-ref --format='%(refname:short)' refs/heads 2>$null })
  foreach ($x in $heads) {
    if ($x -ceq 'main') { continue }
    $sha = "$(& git -C $o rev-parse "refs/heads/$x")"
    & git -C $r merge-base --is-ancestor $sha main 2>$null
    if ($LASTEXITCODE -ne 0) { $b += " $x" }
  }
  if (-not $b) { Pass 'every branch on the origin is merged into main' } else { Fail "branches on the origin not merged into main:$b" }
  if (Get-Command claude -ErrorAction SilentlyContinue) {
    $n = StSessions
    if (-not $n) { Pass 'no self-test session left' } else { Fail "sessions left (claude rm <id> each): $n" }
  } else { Skip 'no claude: sessions not checked' }
  if ($StateRepo) {
    $n = @(& gh api "repos/$StateRepo/branches" --paginate --jq '.[].name' 2>$null)
    if ($LASTEXITCODE -ne 0) { Fail "cannot list the branches of $StateRepo" }
    else {
      $n = @($n | Where-Object { $_ -like 'selftest/*' })
      if ($n.Count -eq 0) { Pass "no selftest/* branch on $StateRepo" } else { Fail "branches left on ${StateRepo}: $($n -join ' ')" }
    }
  } else { Skip 'state repository: not checked (no -StateRepo)' }
  if ($script:f -ne 0) { "sandbox kept for inspection: $d" }
  elseif ($Keep) {
    # the folder, its marker, the repo's path (Claude Code trusts a folder by its path) and the origin
    # stay; every other branch goes, main of both goes back to the first commit, untracked files go
    # (git clean on the repo only)
    foreach ($x in @(& git -C $o for-each-ref --format='%(refname)' refs/heads)) {
      if ($x -cne 'refs/heads/main') { & git -C $o update-ref -d $x }
    }
    & git -C $o update-ref refs/heads/main $i; $ok = $LASTEXITCODE -eq 0
    foreach ($a in @(
        @('-C', $o, 'symbolic-ref', 'HEAD', 'refs/heads/main'), @('-C', $r, 'checkout', '-q', '-f', 'main'),
        @('-C', $r, 'reset', '-q', '--hard', $i), @('-C', $r, 'fetch', '-q', '--prune', 'origin'),
        @('-C', $r, 'worktree', 'prune'), @('-C', $r, 'clean', '-q', '-ffdx', '-e', '.claude/settings.local.json'))) {
      if ($ok) { & git @a 2>$null; $ok = $LASTEXITCODE -eq 0 }
    }
    $why = KeptWhy $d; if (-not $ok -and -not $why) { $why = 'a git command failed' }
    if (-not $why) {
      Pass "only main, at the first commit $(& git -C $r rev-parse --short $i), in the repo and its origin; nothing untracked"
      "sandbox kept for the next run: $d"
    } else { Fail "could not reset ${d}: $why" }
  } else {
    try { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction Stop; Pass 'sandbox removed' } catch { Fail "could not remove $d" }
  }
  Finish
}
'hooks' {
  Only @('Settings'); if (-not $Settings) { Usage }
  if (-not (Test-Path -LiteralPath $Settings -PathType Leaf)) { Fail "no settings file $Settings"; Finish }
  # Claude Code loads a settings file only when it is valid JSON. ConvertFrom-Json alone is not that test:
  # PowerShell 7 takes a trailing comma, a comment or a single-quoted string that 5.1 and Claude Code
  # refuse. So once its strings are blanked, the text must hold only JSON's punctuation, numbers, true,
  # false and null, and no comma before a closing bracket or after an opening one or another comma.
  $text = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Settings).Path)
  $bare = [regex]::Replace($text, '"(?:[^"\\]|\\.)*"', '""')
  $cfg = $null
  if ($bare -cnotmatch ',[ \t\r\n]*[}\]]|[\[{,][ \t\r\n]*,' -and
      ($bare -creplace '-?[0-9]+(?:\.[0-9]+)?(?:[eE][-+]?[0-9]+)?|true|false|null', '') -cnotmatch '[^ \t\r\n{}\[\],:"]') {
    try { $cfg = $text | ConvertFrom-Json -ErrorAction Stop } catch { $cfg = $null }
  }
  if ($cfg -isnot [Management.Automation.PSCustomObject]) { Fail 'the settings file is not valid JSON (Claude Code would not load it)'; Finish }
  # the guard's PreToolUse command (its SessionStart self-test line carries -SelfTest / --self-test), and
  # the matcher of that hook's own entry (none, or not a string: every tool)
  $h = $null; $matcher = ''
  $entries = @(if ($cfg.hooks -is [Management.Automation.PSCustomObject] -and $cfg.hooks.PreToolUse -is [array]) { $cfg.hooks.PreToolUse })
  foreach ($entry in $entries) {
    if ($entry -isnot [Management.Automation.PSCustomObject] -or $entry.hooks -isnot [array]) { continue }
    $x = @($entry.hooks | Where-Object { $_ -is [Management.Automation.PSCustomObject] -and $_.command -is [string] -and
      $_.command -match 'safety-guard\.' -and $_.command -notmatch '-SelfTest|--self-test' })[0]
    if ($x) { $h = $x; if ($entry.matcher -is [string]) { $matcher = $entry.matcher }; break }
  }
  if (-not $h) { Fail 'no safety-guard hook in the file'; Finish }
  Pass 'a safety-guard hook'
  # one line, as selftest.sh reads it: line breaks and tabs count as spaces
  $cmd = $h.command -replace '[\r\n\t]', ' '
  # after JSON decoding a path backslash is a single \ (an escaped quote is just ")
  if ($cmd.Contains('\')) { Fail 'its path has backslashes: Git Bash drops them and the hook never runs' } else { Pass 'its path uses forward slashes' }
  if ($cmd.Contains('$env:')) { Fail 'its command uses $env: - bash reads it as $env and the path breaks' } else { Pass 'no $env: in its command' }
  # an unquoted path must be one word: a space splits it and the hook never runs
  if ($cmd -match '"[^"]*safety-guard\.(sh|ps1)"' -or $cmd -match "'[^']*safety-guard\.(sh|ps1)'") { Pass 'its path is quoted or has no space' }
  else {
    $word = (($cmd -replace 'safety-guard\..*$', '') -split ' ')[-1]
    if ($word -match '^(/|[A-Za-z]:|\$|~)') { Pass 'its path is quoted or has no space' }
    else { Fail 'its path has a space and is not quoted: the hook never runs' }
  }
  if ($h.shell -is [string] -and $h.shell -ceq 'powershell') {
    if ($cmd.Contains('exit $LASTEXITCODE')) { Pass 'a PowerShell shell, with exit $LASTEXITCODE passing the block through' }
    else { Fail 'a PowerShell shell without "; exit $LASTEXITCODE": the block (exit 2) reaches Claude Code as a non-blocking error (1)' }
  } else { Pass 'no PowerShell shell around it' }
  # its entry's matcher must take in the PowerShell tool too: none, "", "*" and ".*" match every tool
  if ($matcher -ceq '' -or $matcher -ceq '*' -or $matcher -ceq '.*' -or $matcher.Contains('PowerShell')) { Pass 'its matcher covers the PowerShell tool' }
  else { Fail 'its matcher leaves out PowerShell: the PowerShell tool runs unguarded' }
  # a hook that fails to run (a wrong path, a crash, a timeout) lets the call through unless it blocks on failure
  if ($h.onFailure -is [string] -and $h.onFailure -ceq 'block') { Pass 'onFailure "block": a guard that fails to run blocks' }
  else { Fail 'no "onFailure": "block": a guard that fails to run lets every call through (Claude Code 2.1.295+)' }
  # the owner's working copy (TOOLKIT Safety): with env COORD_PROTECTED_ROOT the guard keeps the edit
  # tools out of it - so the root is an absolute path to a folder here, and the matcher takes in each
  # edit tool (none, "", "*" and ".*" match every tool; otherwise the whole name must match it)
  $root = ''
  if ($cfg.env -is [Management.Automation.PSCustomObject] -and $cfg.env.COORD_PROTECTED_ROOT -is [string]) { $root = $cfg.env.COORD_PROTECTED_ROOT -replace '[\r\n\t]', ' ' }
  if (-not $root) { Skip 'COORD_PROTECTED_ROOT not set: the working copy is not protected from edit tools' }
  else {
    if ($root -match '^(/|\\|[A-Za-z]:[/\\])') {
      # on Windows Claude Code passes C:\... file paths, so the root is a drive path: C:/... or C:\..., or
      # Git Bash's /c/... (/mnt/c/..., /cygdrive/c/...), which the guard reads as C:/...
      $win = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows
      $dir = $root
      if ($win) { $dir = $dir -replace '^/(mnt/|cygdrive/)?([A-Za-z])(/|$)', '$2:/' }
      if ($win -and $dir -notmatch '^[A-Za-z]:[/\\]') { Fail "COORD_PROTECTED_ROOT is not a drive path (C:/... or C:\...): $root - Claude Code passes C:\... file paths on Windows" }
      elseif (Test-Path -LiteralPath $dir -PathType Container) { Pass 'COORD_PROTECTED_ROOT is an absolute path to a folder' }
      else { Fail "COORD_PROTECTED_ROOT is not a folder on this machine: $root" }
    } else { Fail "COORD_PROTECTED_ROOT is not an absolute path: $root" }
    $miss = @()
    foreach ($t in @('Edit', 'Write', 'MultiEdit', 'NotebookEdit')) {
      if ($matcher -ceq '' -or $matcher -ceq '*' -or $matcher -ceq '.*') { continue }
      $hit = $false; try { $hit = $t -cmatch "^(?:$matcher)$" } catch { $hit = $false }
      if (-not $hit) { $miss += $t }
    }
    if ($miss.Count -eq 0) { Pass 'its matcher covers Edit, Write, MultiEdit and NotebookEdit' }
    else { Fail "its matcher leaves out $($miss -join ', '): those edit tools reach the working copy unguarded" }
  }
  Finish
}
'hookcheck' {
  Only @('Session', 'Expect'); if (-not $Session) { Usage }
  if (-not $PSBoundParameters.ContainsKey('Expect')) { $Expect = 'push' }
  if ($Expect -cne 'push' -and $Expect -cne 'edit') { Usage }
  $base = Join-Path $(if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }) 'projects'
  # the id is a prefix, not a pattern; a prefix of several sessions names none of them
  if ($Session -match '[\[\]*?/\\]') { Fail "the session id $Session holds a pattern or path character"; Finish }
  $all = @(Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue | ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -File -Filter "$Session*.jsonl" -ErrorAction SilentlyContinue })
  if (-not $all.Count) { Fail "no transcript for session $Session"; Finish }
  if ($all.Count -gt 1) {
    $ids = [string[]]@($all | ForEach-Object { $_.Name -replace '\.jsonl$', '' }); [Array]::Sort($ids, [StringComparer]::Ordinal)
    Fail "ambiguous session ${Session}: $($ids -join ' ')"; Finish
  }
  $tf = $all[0]
  $lines = [IO.File]::ReadAllLines($tf.FullName)
  if (@($lines | Where-Object { $_.Contains('"hook_non_blocking_error"') -and $_.Contains('safety-guard') }).Count) {
    Fail 'the guard blocked, but Claude Code got it as a non-blocking error: a shell wrapper turns exit 2 into 1'
  } elseif ($Expect -ceq 'edit') {
    # the edit probe: a Write into the root (COORD_PROTECTED_ROOT) - only the guard's working-copy
    # block counts, which it gives for Edit / Write / MultiEdit / NotebookEdit calls only
    if (@($lines | Where-Object { $_.Contains("Blocked by safety-guard: the owner's working copy is never edited by a worker") }).Count) {
      Pass "the edit tool's write into the working copy was blocked through Claude Code"
    } elseif (@($lines | Where-Object { $_.Contains('File created successfully at') -or $_.Contains('has been updated successfully') }).Count) {
      Fail "the write into the working copy went through: COORD_PROTECTED_ROOT is not in the settings' env, or its matcher leaves out the edit tools"
    } else { Fail 'no working-copy block in the transcript: the hook did not run (its matcher, COORD_PROTECTED_ROOT, or the settings were not loaded)' }
  } elseif (@($lines | Where-Object { $_.Contains('Blocked by safety-guard') -and -not $_.Contains("the owner's working copy is never edited") }).Count) { Pass 'the push to a protected branch was blocked through Claude Code' }
  else { Fail 'no block in the transcript: the hook did not run (its path, its shell, or the settings were not loaded)' }
  Finish
}
{ $_ -eq 'prepare' -or $_ -eq 'verify' } {
  if ($Step -eq 'prepare') { Only @('Project', 'State', 'Core') } else { Only @('Project', 'State', 'Core', 'StateRepo') }
  if (-not ($Project -and $State -and $Core)) { Usage }
  $null = & git -C $Project rev-parse --show-toplevel 2>$null
  if ($LASTEXITCODE -ne 0) { Fail "not a git repository: $Project"; Finish }
  $null = & git -C $State rev-parse --git-dir 2>$null
  if ($LASTEXITCODE -ne 0) { Fail "no state repository at $State"; Finish }
  $base = "selftest/$Core/base"; $st1 = "selftest/$Core/st1"
  if ($Step -eq 'prepare') {
    # the state repository's worktrees live under the project's trusted root; its git must not see them
    & git -C $Project check-ignore -q .claude/worktrees/selftest
    if ($LASTEXITCODE -eq 0) { Pass "the project's git ignores .claude/worktrees" }
    else {
      Push-Location -LiteralPath $Project; $ex = & git rev-parse --git-path info/exclude; Pop-Location
      if (-not [IO.Path]::IsPathRooted($ex)) { $ex = Join-Path $Project $ex }
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ex) | Out-Null
      [IO.File]::AppendAllText($ex, ".claude/worktrees/`n")
      & git -C $Project check-ignore -q .claude/worktrees/selftest
      if ($LASTEXITCODE -eq 0) { Pass "added .claude/worktrees/ to the project's info/exclude" } else { Fail "the project's git does not ignore .claude/worktrees" }
    }
    # the record of the core's own failures (procedures/CORE-FINDINGS.md) in the template's format
    $fnd = Join-Path $State 'CORE-FINDINGS.md'
    if (-not (Test-Path -LiteralPath $fnd -PathType Leaf)) { Fail 'no CORE-FINDINGS.md in the state repository (INIT 3.4, CORE-FINDINGS.template.md)' }
    else {
      # a UTF-8 BOM and CRLF are fine; UTF-16 (Windows PowerShell 5.1's Out-File) is not read as text at all
      $fb = [IO.File]::ReadAllBytes($fnd)
      if ($fb.Length -ge 2 -and (($fb[0] -eq 0xFF -and $fb[1] -eq 0xFE) -or ($fb[0] -eq 0xFE -and $fb[1] -eq 0xFF))) {
        Fail 'CORE-FINDINGS.md is not UTF-8 (re-save it as UTF-8)'
      } else {
        $fl = @([IO.File]::ReadAllLines($fnd, (New-Object System.Text.UTF8Encoding $false)) | ForEach-Object { $_.TrimEnd("`r") })
        if ($fl -cnotcontains '| id | date | core | trigger | what happened (evidence) | workaround | status |') { Fail "CORE-FINDINGS.md lacks the template's table header" }
        else {
          # the status cell, case-sensitive; an empty one is unknown too
          $bad = @($fl | Where-Object { $_.StartsWith('|') -and -not $_.StartsWith('| id |') -and -not $_.StartsWith('|---') } | ForEach-Object {
            $c = $_.Split('|'); $c[$c.Count - 2].Trim(' ', "`t") } | Where-Object { $_ -cnotmatch '^(new|discussed|sent|fixed|dropped|not core)' } |
            ForEach-Object { if ($_ -eq '') { '<empty>' } else { $_ } })
          if ($bad.Count -eq 0) { Pass "CORE-FINDINGS.md in the template's format" } else { Fail "CORE-FINDINGS.md: unknown status '$($bad[0])'" }
        }
      }
    }
    & git -C $State show-ref -q --verify "refs/heads/$base"
    $tested = $LASTEXITCODE -eq 0
    # a fresh clone of the state repository (another machine) has the base on the remote only
    if (-not $tested -and (& git -C $State config --get remote.origin.url)) {
      & git -C $State fetch -q origin 2>$null
      if ($LASTEXITCODE -ne 0) { Fail "could not fetch origin: cannot tell whether core $Core was tested on another machine"; Finish }
      & git -C $State show-ref -q --verify "refs/remotes/origin/$base"
      $tested = $LASTEXITCODE -eq 0
    }
    if ($tested) { Fail "$base exists: core $Core was tested here already - its branches are the evidence, nothing is deleted"; Finish }
    $from = & git -C $State rev-parse --abbrev-ref HEAD
    & git -C $State branch $base HEAD
    if ($LASTEXITCODE -eq 0) { Pass "branch $base from $from" } else { Fail "could not create $base" }
    if (& git -C $State config --get remote.origin.url) {
      & git -C $State push -q -u origin $base 2>$null
      if ($LASTEXITCODE -eq 0) { Pass "pushed $base" } else { Fail "could not push $base" }
      'remote: yes'
    } else { 'remote: no - local branches and a local merge' }
    'worktrees: ' + (Join-Path (Resolve-Path -LiteralPath $Project).Path '.claude/worktrees')
    "base: $base"
    'started: ' + (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
    Finish
  }
  # verify: worktrees of the state repository (the first listed is the repository itself) that are
  # clean and merged into the base are removed; branches never are - they are the evidence
  $wts = @(& git -C $State worktree list --porcelain | Where-Object { $_ -like 'worktree *' } | ForEach-Object { $_.Substring(9) })
  foreach ($w in ($wts | Select-Object -Skip 1)) {
    $dirty = & git -C $w status --porcelain 2>$null
    if ($LASTEXITCODE -ne 0 -or $dirty) { continue }
    $head = & git -C $w rev-parse HEAD
    & git -C $State merge-base --is-ancestor $head $base 2>$null
    if ($LASTEXITCODE -eq 0) { & git -C $State worktree remove $w }
  }
  $left = @(& git -C $State worktree list --porcelain | Where-Object { $_ -like 'worktree *' }).Count
  if ($left -le 1) { Pass 'no worktree left' } else { Fail "$($left - 1) worktree(s) left: not clean or not merged into $base" }
  foreach ($b in @($base, $st1)) {
    & git -C $State show-ref -q --verify "refs/heads/$b"
    if ($LASTEXITCODE -eq 0) { Pass "evidence: $b" } else { Fail "missing: $b" }
  }
  & git -C $State merge-base --is-ancestor $st1 $base 2>$null
  if ($LASTEXITCODE -eq 0) { Pass "$st1 is merged into $base" } else { Fail "$st1 is not merged into $base" }
  if ($StateRepo) {
    $n = & gh pr list -R $StateRepo --state merged --head "selftest/$Core/task-1" --base $base --json number --jq '.[0].number' 2>$null
    if ($n) { Pass "PR #$n merged into $base" } else { Fail "no merged PR from selftest/$Core/task-1 into $base" }
  } else { Skip 'PR flow: not checked (no -StateRepo)' }
  if (Get-Command claude -ErrorAction SilentlyContinue) {
    $n = StSessions
    if (-not $n) { Pass 'no self-test session left' } else { Fail "sessions left (claude rm <id> each): $n" }
  } else { Skip 'no claude: sessions not checked' }
  Finish
}
default { Usage }
}
} finally { if ($enc0) { try { [Console]::OutputEncoding = $enc0 } catch { } } }
