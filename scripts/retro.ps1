# The weekly retro (procedures/RETRO.md; Windows; macOS / Linux: retro.sh - the same rules and output, see its top
# comment): the coordinator measured on cost, speed, quality, predictability and stability, this week against the
# previous one. Reads only; sends nothing.
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/retro.ps1 <RUNS.tsv> [-Week <YYYY-MM-DD>] [-Project <folder>]
#     [-Journal <LOG.md>] [-Escapes <ESCAPES.tsv>] [-NoInsights]       the local report (or: pwsh -File ...)
#   ... <RUNS.tsv> ... -Public -Id <anonymous id>                         the anonymous summary (Markdown), checked first
#   ... -CheckPublic <file> [-Project <folder>]                           a summary body against its allowlist
#   ... -CheckProposal <file> [-Project <folder>]                         a proposal body against its template
#   ... -NewId                                                            a new random anonymous id (12 hex)
# The week: Monday to Sunday UTC holding -Week (default: the last complete week); the transcripts through
# session-insights -Since <week> -Until <week end> -SkipTests -Project <folder>; an em dash where the data is too little.
# Exit 1 when a file cannot be read or a check fails, 2 on a usage error.
param([string]$RunLog, [string]$Week, [string]$Project, [string]$Journal, [string]$Escapes, [switch]$NoInsights,
  [switch]$Public, [string]$Id, [string]$CheckPublic, [string]$CheckProposal, [switch]$NewId)
$enc0 = $null; try { $enc0 = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
try {
function Show-Usage { Get-Content -LiteralPath $PSCommandPath -TotalCount 12 | ForEach-Object { $_ -creplace '^# ?', '' }; exit 2 }
$ErrorActionPreference = 'Stop'
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture
$ORD = [StringComparison]::Ordinal
$DASH = [string][char]0x2014   # the em dash: too little data
# the template's fixed lines (the summary, the proposal) and the allowlist - the same as retro.sh's
$FL = @('<!-- self-improvement summary, format 1 -->',
  "**Coordinator self-improvement: weekly summary.** Numbers only, made by the core's retro script: no code, file names, paths, branches, task text or names leave the project.",
  '| Field | Value |', '|---|---|', '| Axis | Measure | Week | Previous |', '|---|---|---|---|',
  '| Kind | Tasks | Rework | Escalated | Failed |', '|---|---|---|---|---|',
  '| Guard reason | Blocks | Retried | Around | Changed | Stopped |', '|---|---|---|---|---|---|',
  '| Refusal | Count | Retried | Around | Changed | Stopped |',
  "$DASH too little data: under 3 tasks, merged tasks or forecasts, under 100 tool calls, or no transcripts, journal or escapes file.",
  "Data for proposals, not a bug report: the maintainer acts on it only after the owner's discussion and yes.",
  '<!-- self-improvement proposal, format 1 -->',
  "**Coordinator self-improvement: proposal** from one project's weekly numbers, in the core's own terms: no code, file names, paths, branches, task text or names of the project.",
  "A proposal, not a bug report: the maintainer acts on it only after the owner's discussion and yes.")
$AXES = 'cost speed quality predictability stability'.Split(' ')
$MEAS = ('cost:tasks cost:merged cost:median_per_task cost:total cost:coordinator cost:per_merged_task speed:ready_median ' +
  'speed:work_median speed:owner_wait_median speed:owner_wait_open quality:rework_rate quality:escalated_rate quality:failed_rate ' +
  'quality:escapes quality:escapes_per_10_merged predictability:cost_forecasts predictability:cost_in_range ' +
  'predictability:cost_ratio_median predictability:work_forecasts predictability:work_in_range predictability:work_ratio_median ' +
  'predictability:ready_forecasts predictability:ready_in_range predictability:ready_ratio_median stability:failed_runs ' +
  'stability:guard_blocks stability:deny_rule_blocks stability:guard_around stability:guard_false_positives stability:guard_errors ' +
  'stability:refusals stability:tool_errors stability:tool_calls stability:tool_error_rate stability:cache_rewrites ' +
  'stability:cache_rewrites_per_task stability:waiting_minutes stability:rereads').Split(' ')
$KINDS = 'trivial ordinary hard hardest other'.Split(' ')
$GUARD = ('unreadable-call owner-copy-edit mirror-push push-all-branches push-matching push-protected push-while-on-protected ' +
  'delete-protected worktree-force worktree-by-hand remove-root remove-project project-rules-unreadable project-rule-unreadable ' +
  'project-rule deny-rule other').Split(' ')
$REFUSAL = 'guard-error other-hook classifier safety-check user other'.Split(' ')
$FIELDS = 'project:week of:previous week of:format:signature:axis:measure:week:previous:risk:core file:low:medium:high'.Split(':')
function NewSet { New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal) }
$VOC = NewSet; $FIX = NewSet
foreach ($w in $AXES + $KINDS + $GUARD + $REFUSAL + $FIELDS) { [void]$VOC.Add($w) }
foreach ($m in $MEAS) { [void]$VOC.Add($m.Substring($m.IndexOf(':') + 1)) }
foreach ($l in $FL) { [void]$FIX.Add($l) }

function IDiv([long]$a, [long]$b) { [long](($a - ($a % $b)) / $b) }   # whole numbers: exact
# lower case for ASCII letters only (as awk under LC_ALL=C)
$reUpper = [regex]'[A-Z]+'
$lower = [Text.RegularExpressions.MatchEvaluator] { param($m) $m.Value.ToLowerInvariant() }
function Lower([string]$s) { $reUpper.Replace($s, $lower) }
# $w in $s as a whole word: no letter, digit or _ right before or after it
$reWordC = [regex]'^[a-z0-9_]$'
function Word([string]$s, [string]$w) {
  $p = 0
  while ($true) {
    $i = $s.IndexOf($w, $p, $ORD); if ($i -lt 0) { return $false }
    $b = if ($i -gt 0) { [string]$s[$i - 1] } else { '' }
    $a = if ($i + $w.Length -lt $s.Length) { [string]$s[$i + $w.Length] } else { '' }
    if (-not $reWordC.IsMatch($b) -and -not $reWordC.IsMatch($a)) { return $true }
    $p = $i + 1
  }
}
function BaseName([string]$p) { $p = ($p.Replace('\', '/')) -creplace '/+$', ''; $i = $p.LastIndexOf('/'); if ($i -ge 0) { $p = $p.Substring($i + 1) }; Lower $p }
function IsVal([string]$c) {
  $c -ceq $DASH -or $c -cmatch '^[0-9]+\z' -or $c -cmatch '^[0-9]+[.][0-9][0-9]?\z' -or $c -cmatch '^[0-9]+%\z' -or
    $c -cmatch '^[0-9]+[.][0-9]%\z' -or $c -cmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}\z' -or ($c.Length -eq 12 -and $c -cmatch '^[0-9a-f]+\z')
}
function Read-Lines([string]$f) {
  $r = $null
  try { if (Test-Path -LiteralPath $f -PathType Leaf) { $r = @([IO.File]::ReadAllLines((Resolve-Path -LiteralPath $f).Path)) } } catch { }
  if ($null -eq $r) { [Console]::Error.WriteLine("retro: cannot read $f"); exit 1 }
  if ($r.Count -gt 0) { $r[0] = $r[0].TrimStart([char]0xFEFF) }
  , $r
}
# the core's own files and folders (not .git, not .claude), as paths relative to the core with /
function CoreFiles([string]$dir, [string]$rel, $set) {
  foreach ($e in [IO.Directory]::EnumerateFileSystemEntries($dir)) {
    $name = [IO.Path]::GetFileName($e); if ($name -ceq '.git' -or $name -ceq '.claude') { continue }
    $r = if ($rel) { "$rel/$name" } else { $name }; [void]$set.Add($r)
    if ([IO.Directory]::Exists($e)) { CoreFiles $e $r $set }
  }
}
# a body (its lines) against its template and allowlist; $true when it passes, else the reason on stderr
$reBad = [regex]'#[0-9]|(^|[ (`"])[A-Za-z]:/|(^|[ (`"])/'
$reTrim = [regex]'^[(`"]+|[)`".,;:]+$'
function Check([string]$kind, [string[]]$lines, [string]$p) {
  $CF = NewSet; $CB = NewSet
  if ($kind -eq 'proposal') {
    CoreFiles (Split-Path -Parent $PSScriptRoot) '' $CF
    foreach ($x in $CF) { $i = $x.LastIndexOf('/'); [void]$CB.Add($(if ($i -ge 0) { $x.Substring($i + 1) } else { $x })) }
  }
  $name = if ($p) { BaseName $p } else { '' }
  if ($VOC.Contains($name) -or (IsVal $name) -or $name -cnotmatch '[a-z]') { $name = '' }
  $count = 0; $free = NewSet; $why = $null; $ln = 0
  foreach ($L in $lines) {
    $ln++
    if ($L -ceq '') { continue }
    if ($FIX.Contains($L)) { $count++; continue }
    if ($kind -eq 'proposal' -and $L -cmatch '^(Change|Expected gain): .') {
      $count++; $k = $L.Substring(0, $L.IndexOf(':'))
      if (-not $free.Add($k)) { $why = "a second $k line"; break }
      if ($name -and (Word (Lower $L) $name)) { $why = "the project folder's name"; break }
      $s = $L.Substring($L.IndexOf(':') + 2)
      if ($s.Contains('\') -or $s.Contains('://') -or $s.Contains('~') -or $s.Contains('@') -or $reBad.IsMatch($s)) { $why = 'a path, a link, an address or a task number in the text'; break }
      foreach ($w in $s.Split([char[]]@(' ', "`t"), [StringSplitOptions]::RemoveEmptyEntries)) {
        $w = $reTrim.Replace($w, '')
        if ($w.Contains('/') -and -not $CF.Contains($w)) { $why = "a path that is not the core's"; break }
      }
      if ($why) { break }
      continue
    }
    # a table row: | <label> | <cell> | ... | - every cell a word of the allowlist or a value; a proposal's core
    # file (a path of the core) is the only cell that may hold a /
    $count++; $C = @(); $tbl = $L -cmatch '^[|] .* [|]\z'
    if ($tbl) { $C = [regex]::Split($L.Substring(2, $L.Length - 4), ' [|] ') }
    $isCore = $kind -eq 'proposal' -and $C.Count -eq 2 -and $C[0] -ceq 'core file'
    if (-not $isCore -and ($L.Contains('/') -or $L.Contains('\'))) { $why = 'a path separator'; break }
    if (-not $tbl) { $why = 'not a line of the template'; break }
    if ($name -and (Word (Lower $L) $name)) { $why = "the project folder's name"; break }
    if ($isCore) { if (-not $CF.Contains($C[1])) { $why = 'a core file that is not in the core'; break }; continue }
    if ($kind -eq 'proposal' -and $C.Count -eq 2 -and $C[0] -ceq 'signature') {
      $S = $C[1].Split(':')
      if ($S.Count -ne 3 -or -not $VOC.Contains($S[0]) -or -not $VOC.Contains($S[1]) -or -not $CB.Contains($S[2])) { $why = 'a signature outside <axis>:<measure>:<core file name>'; break }
      continue
    }
    if (-not $VOC.Contains($C[0])) { $why = 'a row label outside the allowlist'; break }
    for ($i = 1; $i -lt $C.Count; $i++) { if (-not $VOC.Contains($C[$i]) -and -not (IsVal $C[$i])) { $why = 'a cell outside the allowlist'; break } }
    if ($why) { break }
  }
  if ($why) { [Console]::Error.WriteLine("retro: the $kind body fails its check: line ${ln}: $why"); return $false }
  if (-not $count) { [Console]::Error.WriteLine("retro: the $kind body is empty"); return $false }
  if ($kind -eq 'proposal' -and (-not $free.Contains('Change') -or -not $free.Contains('Expected gain'))) { [Console]::Error.WriteLine('retro: the proposal body lacks its Change or Expected gain line'); return $false }
  $true
}

if ($NewId) {
  if ($RunLog -or $Week -or $Project -or $Journal -or $Escapes -or $NoInsights -or $Public -or $Id -or $CheckPublic -or $CheckProposal) { Show-Usage }
  $b = New-Object byte[] 6; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
  ($b | ForEach-Object { $_.ToString('x2') }) -join ''
  exit 0
}
if ($CheckPublic -or $CheckProposal) {
  if (($CheckPublic -and $CheckProposal) -or $RunLog -or $Week -or $Journal -or $Escapes -or $NoInsights -or $Public -or $Id) { Show-Usage }
  $k = if ($CheckPublic) { 'summary' } else { 'proposal' }
  $f = if ($CheckPublic) { $CheckPublic } else { $CheckProposal }
  if (Check $k (Read-Lines $f) $Project) { exit 0 } else { exit 1 }
}
if (-not $RunLog -or $RunLog.StartsWith('-')) { Show-Usage }
if ([bool]$Public -ne [bool]$Id) { Show-Usage }
if ($Id -and $Id -cnotmatch '^[0-9a-f]{12}\z') { Show-Usage }
if ($Week -and $Week -cnotmatch '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])\z') { Show-Usage }
# (PowerShell's variable names ignore case: every name below is distinct from the others in any case)
$RunLines = Read-Lines $RunLog
$dir = Split-Path -Parent (Resolve-Path -LiteralPath $RunLog).Path
if (-not $Project) { $Project = Split-Path -Parent $dir }
# absolute as the .sh takes it: rooted, or a drive letter (C:/x is a Windows root even in pwsh on Linux)
if (-not ([IO.Path]::IsPathRooted($Project) -or $Project -cmatch '^[A-Za-z]:')) { $Project = Join-Path (Get-Location).Path $Project }
if (-not $PSBoundParameters.ContainsKey('Journal') -and (Test-Path -LiteralPath (Join-Path $dir 'LOG.md') -PathType Leaf)) { $Journal = Join-Path $dir 'LOG.md' }
if (-not $PSBoundParameters.ContainsKey('Escapes') -and (Test-Path -LiteralPath (Join-Path $dir 'ESCAPES.tsv') -PathType Leaf)) { $Escapes = Join-Path $dir 'ESCAPES.tsv' }
$JournalLines = @(); $EscapeLines = @()
if ($Journal) { $JournalLines = Read-Lines $Journal }
if ($Escapes) { $EscapeLines = Read-Lines $Escapes }

# the weeks: this one's Monday and Sunday, the previous one's, and the next Monday (the -Until of this one)
function Days([long]$y, [long]$m, [long]$d) {
  if ($m -le 2) { $y-- }
  $e = IDiv $y 400; $yoe = $y - $e * 400
  $doy = (IDiv (153 * $(if ($m -gt 2) { $m - 3 } else { $m + 9 }) + 2) 5) + $d - 1
  $e * 146097 + $yoe * 365 + (IDiv $yoe 4) - (IDiv $yoe 100) + $doy - 719468
}
function Civil([long]$n) {
  $z = $n + 719468; $e = IDiv $z 146097; $doe = $z - $e * 146097
  $yoe = IDiv ($doe - (IDiv $doe 1460) + (IDiv $doe 36524) - (IDiv $doe 146096)) 365
  $doy = $doe - (365 * $yoe + (IDiv $yoe 4) - (IDiv $yoe 100)); $mp = IDiv (5 * $doy + 2) 153
  $d = $doy - (IDiv (153 * $mp + 2) 5) + 1; $m = if ($mp -lt 10) { $mp + 3 } else { $mp - 9 }; $y = $yoe + $e * 400 + $(if ($m -le 2) { 1 } else { 0 })
  '{0:0000}-{1:00}-{2:00}' -f $y, $m, $d
}
$day = if ($Week) { $Week } else { [DateTime]::UtcNow.ToString('yyyy-MM-dd') }
$n0 = Days ([long]$day.Substring(0, 4)) ([long]$day.Substring(5, 2)) ([long]$day.Substring(8, 2))
if (-not $Week) { $n0 -= 7 }
$s0 = $n0 - (($n0 + 3) % 7)
$WS = Civil $s0; $WE = Civil ($s0 + 6); $PS0 = Civil ($s0 - 7); $PE = Civil ($s0 - 1); $WN = Civil ($s0 + 7)
function InWeek([string]$d) {
  if (-not $d) { return '' }
  if ([string]::CompareOrdinal($d, $WS) -ge 0 -and [string]::CompareOrdinal($d, $WE) -le 0) { return 'W' }
  if ([string]::CompareOrdinal($d, $PS0) -ge 0 -and [string]::CompareOrdinal($d, $PE) -le 0) { return 'P' }
  ''
}

# the transcripts of each week: session-insights in its own process, as the .sh runs it; none when it fails
$Ins = @{}
if (-not $NoInsights) {
  $exe = (Get-Process -Id $PID).Path; $si = Join-Path $PSScriptRoot 'session-insights.ps1'
  foreach ($span in @(@('W', $WS, $WN), @('P', $PS0, $WS))) {
    $got = @(& { $ErrorActionPreference = 'Continue'; & $exe -NoProfile -ExecutionPolicy Bypass -File $si -Since "$($span[1])T00:00:00Z" -Until "$($span[2])T00:00:00Z" -SkipTests -Project $Project 2>$null })
    if ($LASTEXITCODE -eq 0) { $Ins[$span[0]] = $got }
  }
}
# the journal's guard false positives and the escapes, per week (none: no file)
$reDate = [regex]'[0-9]{4}-[0-9]{2}-[0-9]{2}'
$JN = @{}; $EN = @{}
if ($Journal) {
  $JN.W = 0; $JN.P = 0; $lastDate = ''
  foreach ($line in $JournalLines) {
    $d = ''; $mt = $reDate.Match($line); if ($mt.Success) { $d = $mt.Value }
    if ((Lower $line).Contains('guard false positive:')) { $wk = InWeek $(if ($d) { $d } else { $lastDate }); if ($wk) { $JN[$wk] += 1 } }
    if ($d) { $lastDate = $d }
  }
}
if ($Escapes) {
  $EN.W = 0; $EN.P = 0
  foreach ($line in $EscapeLines) {
    if ($line -cmatch '^[ \t]*\z' -or $line.StartsWith('#')) { continue }
    $f0 = $line.Split("`t")[0]; if ($f0 -ceq 'date') { continue }
    $wk = InWeek $(if ($f0.Length -gt 10) { $f0.Substring(0, 10) } else { $f0 }); if ($wk) { $EN[$wk] += 1 }
  }
}

# a value in units of 1/10000 (four decimals, the rest dropped); -1 when it is no number (as run-stats)
function Units([string]$v, [string]$unit) {
  $v = $v.Trim(' ', "`t")
  if ($unit -ceq '$') { $v = $v -creplace '^[$]', '' } else { $v = $v -creplace 'm$', '' }
  if ($v -cmatch '^([0-9]+)(?:[.]([0-9]+))?\z') { return [long]$Matches[1] * 10000 + [long](($Matches[2] + '0000').Substring(0, 4)) }
  [long]-1
}
function Kv([string]$s, [string]$k) { $mt = [regex]::Match($s, '(^| )' + $k + '=([0-9]+)'); if ($mt.Success) { [long]$mt.Groups[2].Value } else { [long]0 } }
# the guard reasons and refusal sources as the fixed keys of the public body
function GKey([string]$r) {
  switch -CaseSensitive ($r) {
    'deny rule' { return 'deny-rule' }
    'the tool call could not be read (not a JSON object)' { return 'unreadable-call' }
    "the owner's working copy is never edited by a worker (<path>); work in your worktree" { return 'owner-copy-edit' }
    'mirror push (overwrites every branch, incl. protected ones)' { return 'mirror-push' }
    'push of every branch (incl. protected ones)' { return 'push-all-branches' }
    'push of all matching branches (incl. protected ones)' { return 'push-matching' }
    'push to a protected branch' { return 'push-protected' }
    'deleting a protected branch' { return 'delete-protected' }
    'removing a worktree by force (use the cleanup script)' { return 'worktree-force' }
    'removing a worktree by hand (use the cleanup script)' { return 'worktree-by-hand' }
    'recursive removal of /, a drive or home' { return 'remove-root' }
    'recursive removal of the project or a folder that holds it' { return 'remove-project' }
  }
  if ($r.StartsWith('push while on ', $ORD)) { return 'push-while-on-protected' }
  if ($r.StartsWith('project rule file cannot be read', $ORD)) { return 'project-rules-unreadable' }
  if ($r.StartsWith('project rule cannot be read', $ORD)) { return 'project-rule-unreadable' }
  if ($r.StartsWith('project rule: ', $ORD)) { return 'project-rule' }
  'other'
}
function RKey([string]$s) {
  if ($s.StartsWith('hook safety-guard', $ORD)) { return 'guard-error' }
  if ($s -ceq 'hook' -or $s.StartsWith('hook ', $ORD)) { return 'other-hook' }
  if ($s -ceq 'classifier' -or $s -ceq 'user') { return $s }
  if ($s -ceq 'safety check') { return 'safety-check' }
  'other'
}
function PKind([string]$k) { $k = Lower $k; if ($k -ceq 'trivial' -or $k -ceq 'ordinary' -or $k -ceq 'hard' -or $k -ceq 'hardest') { $k } else { 'other' } }
function NewMap { New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal) }
function Get0($map, [string]$k) { if ($map.ContainsKey($k)) { $map[$k] } else { [long]0 } }
function Inc($map, [string]$k, [long]$n) { if ($map.ContainsKey($k)) { $map[$k] += $n } else { $map[$k] = $n } }
function Counter { @{ c = [long]0; r = [long]0; a = [long]0; h = [long]0; s = [long]0 } }

# one week of session-insights lines
$Acc = @{}
$GK = NewMap; $QK = NewMap; $LOC = New-Object 'System.Collections.Generic.List[string]'
foreach ($wk in 'W', 'P') {
  if (-not $Ins.ContainsKey($wk)) { continue }
  $acc1 = @{ gb = [long]0; deny = [long]0; ga = [long]0; gerr = [long]0; ref = [long]0; te = [long]0; wmin = [long]0; crw = [long]0; rrf = [long]0; calls = [long]0 }
  foreach ($line in @($Ins[$wk])) {
    $fs = ([string]$line).Split("`t"); $f1 = if ($fs.Count -gt 1) { $fs[1] } else { '' }; $f2 = if ($fs.Count -gt 2) { $fs[2] } else { '' }
    if ($fs[0] -ceq 'block') {
      $cn = Kv $f2 'count'; if ($f1 -ceq 'deny rule') { $acc1.deny += $cn } else { $acc1.gb += $cn; $acc1.ga += (Kv $f2 'around') }
      if ($wk -eq 'W') { $g = GKey $f1; if (-not $GK.ContainsKey($g)) { $GK[$g] = Counter }
        $e = $GK[$g]; $e.c += $cn; $e.r += (Kv $f2 'retried'); $e.a += (Kv $f2 'around'); $e.h += (Kv $f2 'changed'); $e.s += (Kv $f2 'stopped'); $LOC.Add([string]$line) }
    } elseif ($fs[0] -ceq 'refusal') {
      $cn = Kv $f2 'count'; $g = RKey $f1; if ($g -ceq 'guard-error') { $acc1.gerr += $cn } else { $acc1.ref += $cn }
      if ($wk -eq 'W') { if (-not $QK.ContainsKey($g)) { $QK[$g] = Counter }
        $e = $QK[$g]; $e.c += $cn; $e.r += (Kv $f2 'retried'); $e.a += (Kv $f2 'around'); $e.h += (Kv $f2 'changed'); $e.s += (Kv $f2 'stopped'); $LOC.Add([string]$line) }
    }
    elseif ($fs[0] -ceq 'tool_error') { $acc1.te += (Kv $f2 'count') }
    elseif ($fs[0] -ceq 'waiting') { $acc1.wmin = Kv $f1 'minutes' }
    elseif ($fs[0] -ceq 'cache') { $acc1.crw = Kv $f1 'rewrites' }
    elseif ($fs[0] -ceq 'reread') { $acc1.rrf = Kv $f1 'files' }
    elseif ($fs[0] -ceq 'turns') { $acc1.calls = Kv $f1 'tool_calls' }
  }
  $Acc[$wk] = $acc1
}

# the run log: columns by its header, else in CORE 7's order (0-based)
$cd = 0; $ct = 1; $cr = 2; $ck = 3; $cm = 4; $cc = 8; $cs = 9; $cw = 11; $ca = 12; $cx = 13
$Order = New-Object 'System.Collections.Generic.List[string]'; $Tasks = NewMap   # the tasks in order; per task its record
$coord = @{ W = [long]0; P = [long]0 }; $frun = @{ W = [long]0; P = [long]0 }
$row = 0
foreach ($line in $RunLines) {
  if ($line -cmatch '^[ \t]*\z' -or $line.StartsWith('#')) { continue }
  $fs = $line.Split("`t")
  if ($fs[0] -ceq 'date') {
    $cd = [Array]::IndexOf($fs, 'date'); $ct = [Array]::IndexOf($fs, 'task'); $cr = [Array]::IndexOf($fs, 'role'); $ck = [Array]::IndexOf($fs, 'kind')
    $cm = [Array]::IndexOf($fs, 'model'); $cc = [Array]::IndexOf($fs, 'cost'); $cs = [Array]::IndexOf($fs, 'result'); $cw = [Array]::IndexOf($fs, 'wall')
    $ca = [Array]::IndexOf($fs, 'active'); $cx = [Array]::IndexOf($fs, 'wait')
    continue
  }
  $row++
  $col = { param($i) if ($i -ge 0 -and $i -lt $fs.Count) { $fs[$i] } else { '' } }
  $tid = (& $col $ct) -creplace '[.].*$', ''; $kind = & $col $ck; $model = & $col $cm; $role = & $col $cr
  $lt = Lower $tid
  if ($lt -cmatch '^#?st[0-9]' -or $lt -ceq '0' -or $lt -ceq '#0' -or (Lower "$kind $role") -cmatch 'probe|selftest|self-test') { continue }   # a probe or a self-test
  $d = & $col $cd; if ($d.Length -gt 10) { $d = $d.Substring(0, 10) }; if ($d -cnotmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}\z') { $d = '' }
  $cv = & $col $cc; $cost = Units $cv '$'; $wk = InWeek $d
  if ($tid -eq '' -or $tid -eq '-') { if ($wk -and $cost -ge 0) { $coord[$wk] += $cost }; continue }   # the coordinator's own line
  if (-not $Tasks.ContainsKey($tid)) {
    $Tasks[$tid] = @{ fa = $row; md = ''; tr = -1; lr = -1; nrun = 0; hc = $false; tc = [long]0; ha = $false; ta = [long]0; p = 0; tk = ''; tm = ''
      trk = ''; trm = ''; trw = [long]-1; trx = ''; trs = ''; rw = $false; es = $false; fl = $false }
    $Order.Add($tid)
  }
  $rec = $Tasks[$tid]
  if ([string]::CompareOrdinal($d, $rec.md) -gt 0) { $rec.md = $d }
  if ($role -ceq 'task') { $rec.tr = $row; $rec.trk = $kind; $rec.trm = $model; $rec.trw = Units (& $col $cw) 'm'; $rec.trx = & $col $cx; $rec.trs = Lower (& $col $cs); continue }
  $rec.lr = $row; $rec.nrun += 1
  if ($cost -ge 0) { $rec.tc += $cost; $rec.hc = $true }
  $act = Units (& $col $ca) 'm'; if ($act -ge 0 -and $cv -cnotmatch '^[ \t]*in[ \t]') { $rec.ta += $act; $rec.ha = $true }   # a subagent: in its parent
  $pri = if ($role -ceq 'lead') { 3 } elseif ($role -ceq 'worker') { 2 } else { 1 }
  if ($pri -gt $rec.p) { $rec.p = $pri; $rec.tk = $kind; $rec.tm = $model }
  $res = (Lower (& $col $cs)).TrimStart(' ', "`t")
  if ($res.StartsWith('rework', $ORD)) { $rec.rw = $true }; if ($res.StartsWith('escalated', $ORD)) { $rec.es = $true }
  if ($res.StartsWith('failed', $ORD)) { $rec.fl = $true; if ($wk) { $frun[$wk] += 1 } }
}

$Lists = NewMap
function Add([string]$k, [long]$v) { if (-not $Lists.ContainsKey($k)) { $Lists[$k] = New-Object 'System.Collections.Generic.List[long]' }; $Lists[$k].Add($v) }
function LN([string]$k) { if ($Lists.ContainsKey($k)) { $Lists[$k].Count } else { 0 } }
function Rank([long]$p, [long]$n) { [long][Math]::Ceiling($p * $n / 100) }
# twice the median of a list
function Med2([string]$k) { $a = [long[]]$Lists[$k].ToArray(); [Array]::Sort($a); $n = $a.Count; if ($n % 2) { 2 * $a[($n - 1) / 2] } else { $a[$n / 2 - 1] + $a[$n / 2] } }
function Cents([long]$c) { '{0}.{1:00}' -f (IDiv $c 100), ($c % 100) }   # hundredths as d.dd
function Dec1([long]$n) { '{0}.{1}' -f (IDiv $n 10), ($n % 10) }        # tenths as d.d
function Pct([long]$a, [long]$b) { "$(IDiv (200 * $a + $b) (2 * $b))%" }
$Forecasts = NewMap; $InRange = NewMap
# the forecast of a task for a measure (c cost, a work, r ready) from the earlier tasks of its kind and model, as
# run-stats gave it before the task: 3 or more of them, the last 10, by their last row before the task's first row
function Fcast([string]$tid, [string]$wk, [string]$ms) {
  $me = $Tasks[$tid]
  if ($ms -eq 'c') { if (-not $me.hc) { return }; $val = $me.tc } elseif ($ms -eq 'a') { if (-not $me.ha) { return }; $val = $me.ta }
  else { if ($me.tr -lt 0 -or $me.trw -lt 0) { return }; $val = $me.trw }
  $keys = New-Object 'System.Collections.Generic.List[long]'; $vals = New-Object 'System.Collections.Generic.List[long]'
  foreach ($u in $Order) {
    if ($u -ceq $tid) { continue }; $y = $Tasks[$u]
    if ($ms -eq 'r') { if ($y.tr -lt 0 -or $y.trw -lt 0 -or $y.trk -cne $me.trk -or $y.trm -cne $me.trm -or $y.tr -ge $me.fa) { continue }; $keys.Add($y.tr); $vals.Add($y.trw) }
    else {
      if ($y.lr -lt 0 -or $y.tk -cne $me.tk -or $y.tm -cne $me.tm -or $y.lr -ge $me.fa) { continue }
      if ($ms -eq 'c') { if (-not $y.hc) { continue }; $keys.Add($y.lr); $vals.Add($y.tc) } else { if (-not $y.ha) { continue }; $keys.Add($y.lr); $vals.Add($y.ta) }
    }
  }
  if ($vals.Count -lt 3) { return }
  $ok = $keys.ToArray(); $ov = $vals.ToArray(); [Array]::Sort($ok, $ov)
  $st = [Math]::Max(0, $ov.Count - 10); $a = [long[]]@($ov[$st..($ov.Count - 1)]); [Array]::Sort($a); $k = $a.Count
  $m2 = if ($k % 2) { 2 * $a[($k - 1) / 2] } else { $a[$k / 2 - 1] + $a[$k / 2] }
  $lo = if ($k -lt 4) { $a[0] } else { $a[(Rank 25 $k) - 1] }; $hi = if ($k -lt 4) { $a[$k - 1] } else { $a[(Rank 75 $k) - 1] }
  Inc $Forecasts "$wk$ms" 1; if ($val -ge $lo -and $val -le $hi) { Inc $InRange "$wk$ms" 1 }
  if ($m2 -gt 0) { Add "$wk${ms}q" (IDiv (400 * $val + $m2) (2 * $m2)) }
}
$NT = @{ W = 0; P = 0 }; $MG = @{ W = 0; P = 0 }; $TOT = @{ W = [long]0; P = [long]0 }; $OPEN = @{ W = 0; P = 0 }
$NR = @{ W = 0; P = 0 }; $NRW = @{ W = 0; P = 0 }; $NES = @{ W = 0; P = 0 }; $NFL = @{ W = 0; P = 0 }
$KN = NewMap; $UN = NewMap
function Tally($map, [string]$k, $rec) {
  if (-not $map.ContainsKey($k)) { $map[$k] = @{ n = 0; r = 0; e = 0; f = 0 } }
  $q = $map[$k]; $q.n += 1; if ($rec.rw) { $q.r += 1 }; if ($rec.es) { $q.e += 1 }; if ($rec.fl) { $q.f += 1 }
}
foreach ($tid in $Order) {
  $rec = $Tasks[$tid]; if ($rec.p -eq 0) { $rec.tk = $rec.trk; $rec.tm = $rec.trm }
  $wk = InWeek $rec.md; if (-not $wk) { continue }
  $NT[$wk] += 1
  if ($rec.tr -ge 0 -and $rec.trs -cmatch '^[ \t]*merged') { $MG[$wk] += 1 }
  if ($rec.hc) { Add "${wk}c" $rec.tc; $TOT[$wk] += $rec.tc }
  if ($rec.ha) { Add "${wk}a" $rec.ta }
  if ($rec.tr -ge 0 -and $rec.trw -ge 0) { Add "${wk}r" $rec.trw }
  if ($rec.tr -ge 0) { if ($rec.trx -cmatch '[+][ \t]*\z') { $OPEN[$wk] += 1 } else { $xv = Units $rec.trx 'm'; if ($xv -ge 0) { Add "${wk}x" $xv } } }
  if ($rec.nrun -gt 0) {
    $NR[$wk] += 1; if ($rec.rw) { $NRW[$wk] += 1 }; if ($rec.es) { $NES[$wk] += 1 }; if ($rec.fl) { $NFL[$wk] += 1 }
    if ($wk -eq 'W') { $kn1 = if ($rec.tk -eq '') { '-' } else { $rec.tk }; Tally $KN $kn1 $rec; Tally $UN (PKind $kn1) $rec }
  }
  Fcast $tid $wk 'c'; Fcast $tid $wk 'a'; Fcast $tid $wk 'r'
}
$Val = @{}
foreach ($wk in 'W', 'P') {
  $cell = NewMap; $Val[$wk] = $cell
  $cell['tasks'] = "$($NT[$wk])"; $cell['merged'] = "$($MG[$wk])"
  $cell['median_per_task'] = if ((LN "${wk}c") -ge 3) { Cents (IDiv ((Med2 "${wk}c") + 100) 200) } else { $DASH }
  $cell['total'] = Cents (IDiv (2 * ($TOT[$wk] + $coord[$wk]) + 100) 200); $cell['coordinator'] = Cents (IDiv (2 * $coord[$wk] + 100) 200)
  $cell['per_merged_task'] = if ($MG[$wk] -ge 3) { Cents (IDiv (2 * ($TOT[$wk] + $coord[$wk]) + 100 * $MG[$wk]) (200 * $MG[$wk])) } else { $DASH }
  $cell['ready_median'] = if ((LN "${wk}r") -ge 3) { "$(IDiv ((Med2 "${wk}r") + 10000) 20000)" } else { $DASH }
  $cell['work_median'] = if ((LN "${wk}a") -ge 3) { "$(IDiv ((Med2 "${wk}a") + 10000) 20000)" } else { $DASH }
  $cell['owner_wait_median'] = if ((LN "${wk}x") -ge 3) { "$(IDiv ((Med2 "${wk}x") + 10000) 20000)" } else { $DASH }
  $cell['owner_wait_open'] = "$($OPEN[$wk])"
  $cell['rework_rate'] = if ($NR[$wk] -ge 3) { Pct $NRW[$wk] $NR[$wk] } else { $DASH }
  $cell['escalated_rate'] = if ($NR[$wk] -ge 3) { Pct $NES[$wk] $NR[$wk] } else { $DASH }
  $cell['failed_rate'] = if ($NR[$wk] -ge 3) { Pct $NFL[$wk] $NR[$wk] } else { $DASH }
  $cell['escapes'] = if ($EN.ContainsKey($wk)) { "$($EN[$wk])" } else { $DASH }
  $cell['escapes_per_10_merged'] = if (-not $EN.ContainsKey($wk) -or $MG[$wk] -lt 3) { $DASH } else { Dec1 (IDiv (200 * $EN[$wk] + $MG[$wk]) (2 * $MG[$wk])) }
  foreach ($j in @(@('c', 'cost'), @('a', 'work'), @('r', 'ready'))) {
    $ms = $j[0]; $mn = $j[1]; $nfc = Get0 $Forecasts "$wk$ms"
    $cell["${mn}_forecasts"] = "$nfc"
    $cell["${mn}_in_range"] = if ($nfc -ge 3) { Pct (Get0 $InRange "$wk$ms") $nfc } else { $DASH }
    $cell["${mn}_ratio_median"] = if ((LN "$wk${ms}q") -ge 3) { "$(IDiv ((Med2 "$wk${ms}q") + 1) 2)%" } else { $DASH }
  }
  $cell['failed_runs'] = "$($frun[$wk])"
  $cell['guard_false_positives'] = if ($JN.ContainsKey($wk)) { "$($JN[$wk])" } else { $DASH }
  if ($Acc.ContainsKey($wk)) {
    $i1 = $Acc[$wk]
    $cell['guard_blocks'] = "$($i1.gb)"; $cell['deny_rule_blocks'] = "$($i1.deny)"; $cell['guard_around'] = "$($i1.ga)"; $cell['guard_errors'] = "$($i1.gerr)"
    $cell['refusals'] = "$($i1.ref)"; $cell['tool_errors'] = "$($i1.te)"; $cell['tool_calls'] = "$($i1.calls)"
    $cell['tool_error_rate'] = if ($i1.calls -ge 100) { "$(Dec1 (IDiv (2000 * $i1.te + $i1.calls) (2 * $i1.calls)))%" } else { $DASH }
    $cell['cache_rewrites'] = "$($i1.crw)"
    $cell['cache_rewrites_per_task'] = if ($NT[$wk] -ge 3) { Cents (IDiv (200 * $i1.crw + $NT[$wk]) (2 * $NT[$wk])) } else { $DASH }
    $cell['waiting_minutes'] = "$($i1.wmin)"; $cell['rereads'] = "$($i1.rrf)"
  } else {
    foreach ($z in 'guard_blocks deny_rule_blocks guard_around guard_errors refusals tool_errors tool_calls tool_error_rate cache_rewrites cache_rewrites_per_task waiting_minutes rereads'.Split(' ')) { $cell[$z] = $DASH }
  }
}
function Rates($q) { if ($q.n -ge 3) { @((Pct $q.r $q.n), (Pct $q.e $q.n), (Pct $q.f $q.n)) } else { @($DASH, $DASH, $DASH) } }
$out = New-Object 'System.Collections.Generic.List[string]'
if (-not $Public) {
  $out.Add("retro`tweek of $WS`tprevious week of $PS0"); $out.Add("axis`tmeasure`tweek`tprevious")
  foreach ($mm in $MEAS) { $ax = $mm.Substring(0, $mm.IndexOf(':')); $nm = $mm.Substring($mm.IndexOf(':') + 1); $out.Add("$ax`t$nm`t$($Val.W[$nm])`t$($Val.P[$nm])") }
  $out.Add("kind`tname`ttasks`trework`tescalated`tfailed")
  $kl = [string[]]@(foreach ($kk in $KN.Keys) { $q3 = Rates $KN[$kk]; "kind`t$kk`t$($KN[$kk].n)`t$($q3[0])`t$($q3[1])`t$($q3[2])" })
  [Array]::Sort($kl, [StringComparer]::Ordinal); foreach ($l1 in $kl) { $out.Add($l1) }
  foreach ($l1 in $LOC) { $out.Add($l1) }
  $out.Add("note`t$DASH too little data: under 3 tasks, merged tasks or forecasts, under 100 tool calls, or no transcripts, journal or escapes file")
  $out
  exit 0
}
# the anonymous body: the template's fixed lines, the allowlisted labels, the numbers
$out.Add($FL[0]); $out.Add($FL[1]); $out.Add(''); $out.Add($FL[2]); $out.Add($FL[3])
$out.Add("| project | $Id |"); $out.Add("| week of | $WS |"); $out.Add("| previous week of | $PS0 |"); $out.Add('| format | 1 |'); $out.Add('')
$out.Add($FL[4]); $out.Add($FL[5])
foreach ($mm in $MEAS) { $ax = $mm.Substring(0, $mm.IndexOf(':')); $nm = $mm.Substring($mm.IndexOf(':') + 1); $out.Add("| $ax | $nm | $($Val.W[$nm]) | $($Val.P[$nm]) |") }
if ($UN.Count) {
  $out.Add(''); $out.Add($FL[6]); $out.Add($FL[7])
  foreach ($kk in $KINDS) { if ($UN.ContainsKey($kk)) { $q3 = Rates $UN[$kk]; $out.Add("| $kk | $($UN[$kk].n) | $($q3[0]) | $($q3[1]) | $($q3[2]) |") } }
}
if ($GK.Count) {
  $out.Add(''); $out.Add($FL[8]); $out.Add($FL[9])
  foreach ($kk in $GUARD) { if ($GK.ContainsKey($kk)) { $e = $GK[$kk]; $out.Add("| $kk | $($e.c) | $($e.r) | $($e.a) | $($e.h) | $($e.s) |") } }
}
if ($QK.Count) {
  $out.Add(''); $out.Add($FL[10]); $out.Add($FL[9])
  foreach ($kk in $REFUSAL) { if ($QK.ContainsKey($kk)) { $e = $QK[$kk]; $out.Add("| $kk | $($e.c) | $($e.r) | $($e.a) | $($e.h) | $($e.s) |") } }
}
$out.Add(''); $out.Add($FL[11]); $out.Add($FL[12])
# checked as -CheckPublic does, and printed only when it passes
if (-not (Check 'summary' ([string[]]$out.ToArray()) $Project)) { exit 1 }
$out
exit 0
} finally { if ($enc0) { try { [Console]::OutputEncoding = $enc0 } catch { } } }
