# A run's row in the run log, and the finished runs that have none (#332; Windows; macOS / Linux: runs.sh -
# the same rules, output and exit codes, see its top comment).
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/runs.ps1 add -Log <RUNS.tsv> -Session <id> -Task <n>
#     -Role <role> -Kind <kind> -Model <m> -Effort <e> -Estimate <cost|-> -EstimateTime <t|-> -Result <word> [-Date <YYYY-MM-DD>]
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/runs.ps1 add -Log <RUNS.tsv> -In <parent> -Tokens <n> -Task ...
#     -Result <word> [-Date ...]   a subagent's row (a tester or verifier run as a subagent): no -Session
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/runs.ps1 check -Log <RUNS.tsv> -Root <project root>
#     [-Self <session id>] [-Since <YYYY-MM-DD>]   (or: pwsh -File ...)
# A value `-` goes as -Estimate:- -EstimateTime:- (Windows PowerShell 5.1 -File refuses a bare `-` value).
# add appends exactly one row (CORE 7) and prints it: its cells by the file's header, else CORE 7's order; tokens, cost,
# start, wall and active from scripts/session-tokens <id>, never typed by hand; result one of approved done pass
# `rework <n>` escalated failed dropped ready (exit 2 otherwise); no transcript: exit 1; a second row of the same start
# and role: exit 1, except role assistant; the file keeps its BOM and line ends; a log that is no file or cannot be
# read or written: exit 1, a line `runs:`, no row printed. check lists the project's finished sessions (the process
# ended: state done, stopped or failed and no status field) with no row - `MISSING <short id> <name> <start>` each,
# else `ALL LOGGED` - and only reads (a log it cannot read: exit 1, never read as empty).
# Exit 0, 1 as runs.sh says or when claude agents fails, 2 on a usage error.
param([Parameter(Position = 0)][string]$Command, [string]$Log, [string]$Session, [string]$Task, [string]$Role,
  [string]$Kind, [string]$Model, [string]$Effort, [string]$Estimate, [string]$EstimateTime, [string]$Result,
  [string]$Date, [string]$In, [string]$Tokens, [string]$Root, [string]$Self, [string]$Since)
$enc0 = $null; try { $enc0 = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
try {
function Show-Usage { Get-Content -LiteralPath $PSCommandPath -TotalCount 17| ForEach-Object { [Console]::Error.WriteLine(($_ -creplace '^# ?', '')) }; exit 2 }
function Die([int]$Code, [string]$Msg) { [Console]::Error.WriteLine("runs: $Msg"); exit $Code }
$Names = @('date', 'task', 'role', 'kind', 'model', 'effort', 'estimate', 'tokens', 'cost', 'result', 'start', 'wall', 'active', 'wait', 'estimate_time')
# Plain <file>: its lines without the BOM and the CRs
function Plain([string]$f) {
  try { $t = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $f).Path, (New-Object System.Text.UTF8Encoding $false)) }
  catch { Die 1 "cannot read the run log $f" }
  if ($t.Length -and $t[0] -eq [char]0xFEFF) { $t = $t.Substring(1) }
  $l = @($t -split "`n" | ForEach-Object { $_ -replace "`r$", '' })
  if ($l.Count -eq 1 -and $l[0] -eq '') { $l = @() }
  elseif ($l.Count -gt 1 -and $l[$l.Count - 1] -eq '') { $l = @($l[0..($l.Count - 2)]) }
  , $l
}
# CanOpen <file> <access>: a file that opens for that access (Read, or Write: nothing written), else exit 1 -
# a directory, a missing file, a read-only one or one held open without sharing; never read as empty
function CanOpen([string]$f, [string]$a) {
  if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { Die 1 "no run log at $f (no such file)" }
  try { $fs = [IO.File]::Open((Resolve-Path -LiteralPath $f).Path, 'Open', $a, 'ReadWrite'); $fs.Close() }
  catch { if ($a -eq 'Write') { Die 1 "cannot write the run log $f" } else { Die 1 "cannot read the run log $f" } }
}
function IsHeader([string]$line) { $h = 0; foreach ($x in ($line -split "`t")) { if ($x -ceq 'date' -or $x -ceq 'role') { $h++ } }; $h -ge 2 }
# Cols <lines>: the column names in the file's order (its header, else CORE 7's)
function Cols($l) { if ($l.Count -and (IsHeader $l[0])) { , @($l[0] -split "`t") } else { , $Names } }
# RowsOf <lines>: the data rows split into cells (the header, comments and empty lines left out)
function RowsOf($l) {
  $r = New-Object System.Collections.ArrayList
  for ($i = 0; $i -lt $l.Count; $i++) {
    if ($i -eq 0 -and (IsHeader $l[0])) { continue }
    if ($l[$i] -eq '' -or $l[$i].StartsWith('#')) { continue }
    [void]$r.Add([string[]]($l[$i] -split "`t"))
  }
  , $r.ToArray()
}
function ColNo($c, [string]$n) { for ($i = 0; $i -lt $c.Count; $i++) { if ($c[$i] -ceq $n) { return $i } }; -1 }
function Cell($row, [int]$i) { if ($i -ge 0 -and $i -lt $row.Count) { $row[$i] } else { '' } }
# Tokens <id>: what session-tokens.ps1 prints for the session, as lines; $null when it fails
function SessionTokens([string]$id) {
  $global:LASTEXITCODE = 0
  $o = @(& (Join-Path $PSScriptRoot 'session-tokens.ps1') $id 2>$null)
  if ($LASTEXITCODE -ne 0) { return $null }
  , @($o | ForEach-Object { [string]$_ })
}
function TimeKv([string]$tl, [string]$w) {
  foreach ($x in ($tl -split '\s+')) { $n = $x.IndexOf('='); if ($n -gt 0 -and $x.Substring(0, $n) -ceq $w) { return ($x.Substring($n + 1) -replace 'm$', '') } }
  ''
}
$bound = @($PSBoundParameters.Keys | Where-Object { $_ -ne 'Command' })
if ($Command -cne 'add' -and $Command -cne 'check') { Show-Usage }
if (-not $Log) { Show-Usage }
$inv = [Globalization.CultureInfo]::InvariantCulture

if ($Command -ceq 'add') {
  foreach ($b in $bound) { if ('Root', 'Self', 'Since' -contains $b) { Show-Usage } }
  if (-not ($Task -and $Role -and $Kind -and $Model -and $Effort -and $Estimate -and $EstimateTime -and $Result)) { Show-Usage }
  if ($Session) { if ($In -or $Tokens) { Show-Usage } }
  else {
    if (-not ($In -and $Tokens)) { Show-Usage }
    if ($Tokens -notmatch '^[0-9]+$') { Die 2 "--tokens must be a number: $Tokens" }
  }
  if ($Result -cnotmatch '^(approved|done|pass|rework [0-9]+|escalated|failed|dropped|ready)$') {
    Die 2 "result '$Result' is not one of: approved done pass 'rework <n>' escalated failed dropped ready"
  }
  if (-not $Date) { $Date = [DateTime]::UtcNow.ToString('yyyy-MM-dd', $inv) }
  if ($Date -notmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}$') { Die 2 "--date must be YYYY-MM-DD: $Date" }
  foreach ($v in $Task, $Role, $Kind, $Model, $Effort, $Estimate, $EstimateTime, $Date, $In, $Session) {
    if ($v -match "[`t`r`n]") { Die 2 'a cell may not hold a tab or a line break' }
  }
  CanOpen $Log 'Read'; CanOpen $Log 'Write'
  $lines = Plain $Log; $c = Cols $lines
  $Row = @{ date = $Date; task = $Task; role = $Role; kind = $Kind; model = $Model; effort = $Effort; estimate = $Estimate
    tokens = $Tokens; cost = ''; result = $Result; start = ''; wall = ''; active = ''; wait = ''; estimate_time = $EstimateTime }
  if ($Session) {
    $st = SessionTokens $Session
    if ($null -eq $st) { Die 1 "no transcript for session $Session (session-tokens failed)" }
    $tot = ''; $tl = ''; $cost = ''
    foreach ($x in $st) {
      $f = @($x -split '\s+')
      if ($f[0] -ceq 'total' -and -not $tot) { $tot = $f[1] }
      elseif ($f[0] -ceq 'time' -and -not $tl) { $tl = $x }
      elseif ($f[0] -ceq 'cost' -and -not $cost) { $cost = $f[1] -replace '^\$', '' }
    }
    if (-not $tot -or -not $tl) { Die 1 "no transcript for session $Session (no total or time line)" }
    $Row.tokens = $tot; $Row.start = TimeKv $tl 'start'; $Row.wall = TimeKv $tl 'wall'; $Row.active = TimeKv $tl 'active'
    $ns = ColNo $c 'start'; $nr = ColNo $c 'role'; $nc = ColNo $c 'cost'; $nt = ColNo $c 'task'
    $rows = RowsOf $lines
    if ($Role -cne 'assistant') {
      if ($ns -ge 0 -and $nr -ge 0) {
        foreach ($r in $rows) { if ((Cell $r $ns) -ceq $Row.start -and (Cell $r $nr) -ceq $Role) { Die 1 "a row for session start $($Row.start) and role $Role is already in $Log" } }
      }
    } elseif ($cost -and $ns -ge 0 -and $nc -ge 0 -and $nt -ge 0) {
      # the cost since this assistant's previous row: less the earlier rows' of its name and this start
      $p = 0.0
      foreach ($r in $rows) {
        if ((Cell $r $ns) -ceq $Row.start -and (Cell $r $nt) -ceq $Task -and (Cell $r $nr) -ceq 'assistant') {
          $m = [regex]::Match((Cell $r $nc), '^\$?([0-9]+(\.[0-9]+)?)'); if ($m.Success) { $p += [double]::Parse($m.Groups[1].Value, $inv) }
        }
      }
      $x = [double]::Parse($cost, $inv) - $p; if ($x -lt 0) { $x = 0 }
      $cost = ($x + 1e-12).ToString('0.0000', $inv)
    }
    $Row.cost = $cost
    if (-not $cost) { [Console]::Error.WriteLine("runs: session-tokens printed no cost line for $Session; the cost cell is left empty") }
  } else { $Row.cost = "in $In" }
  # the header's order (a column it does not name: empty), then the names it lacks in CORE 7's order
  $u = @{}; $out = New-Object 'System.Collections.Generic.List[string]'
  foreach ($h in $c) { $v = ''; if ($Row.ContainsKey($h) -and -not $u.ContainsKey($h)) { $v = $Row[$h]; $u[$h] = 1 }; $out.Add($v) }
  foreach ($h in $Names) { if (-not $u.ContainsKey($h)) { $out.Add($Row[$h]) } }
  $line = $out -join "`t"
  # the row as the file's last line, in its line ends; a last line without its end gets one first
  try {
    $p = (Resolve-Path -LiteralPath $Log).Path; $t = [IO.File]::ReadAllText($p)
    $nl = if ($t.Contains("`r")) { "`r`n" } else { "`n" }
    $pre = if ($t.Length -and -not $t.EndsWith("`n")) { $nl } else { '' }
    [IO.File]::AppendAllText($p, $pre + $line + $nl, (New-Object System.Text.UTF8Encoding $false))
  } catch { Die 1 "cannot write the run log $Log" }
  $line
  exit 0
}

# check
foreach ($b in $bound) { if ('Log', 'Root', 'Self', 'Since' -notcontains $b) { Show-Usage } }
if (-not $Root) { Show-Usage }
if ($Since -and $Since -notmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}$') { Die 2 "--since must be YYYY-MM-DD: $Since" }
CanOpen $Log 'Read'
# Canon <path>: the path to compare - its full form when it exists, forward slashes, no trailing slash, a drive
# letter in lower case (C:\x and C:/x the same)
function Canon([string]$p) {
  if ($p -and (Test-Path -LiteralPath $p -PathType Container)) { try { $p = (Get-Item -LiteralPath $p -Force).FullName } catch { } }
  $p = ($p -replace '\\', '/') -replace '/+$', ''
  if ($p -match '^[A-Za-z]:') { $p = $p.Substring(0, 1).ToLowerInvariant() + $p.Substring(1) }
  $p
}
$isWin = [IO.Path]::DirectorySeparatorChar -eq [char]'\'
$roots = New-Object System.Collections.ArrayList
[void]$roots.Add((Canon $Root))
$wl = @()
try { $wl = @(& git -C $Root worktree list --porcelain 2>$null) } catch { }
foreach ($x in $wl) { if ([string]$x -match '^worktree (.+)$') { [void]$roots.Add((Canon ($Matches[1] -replace "`r$", ''))) } }
# one call of claude agents --json --all, as PATH gives claude: a .ps1 through this PowerShell, a .cmd / .bat
# through cmd, else the program itself
$cm = Get-Command claude -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $cm) { Die 1 'claude agents --json --all failed: claude: command not found' }
$json = ''; $rc = 0
try {
  $global:LASTEXITCODE = 0
  if ($cm.CommandType -eq 'ExternalScript') { $o = & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $cm.Path agents --json --all 2>$null }
  else { $o = & $cm.Path agents --json --all 2>$null }
  $rc = $LASTEXITCODE; $json = (@($o) | ForEach-Object { [string]$_ }) -join "`n"
} catch { $rc = 1 }
if ($rc -ne 0 -or -not $json.Contains('[')) { Die 1 "claude agents --json --all failed (exit $rc)" }
# the finished sessions: @(id, sessionId, cwd, name) per session object (string values unescaped as
# watch-sessions does: a control escape as a blank, \u left as written)
$fin = New-Object System.Collections.ArrayList
$d = 0; $q = $false; $after = $false; $k = ''; $tb = New-Object System.Text.StringBuilder; $v = @{}; $s = $json
for ($i = 0; $i -lt $s.Length; $i++) {
  $ch = $s[$i]
  if ($q) {
    if ($ch -eq [char]'\') {
      $i++; if ($i -ge $s.Length) { break }; $ch = $s[$i]
      if ('nrtbf'.IndexOf($ch) -ge 0) { [void]$tb.Append(' ') } elseif ($ch -eq [char]'u') { [void]$tb.Append('\u') } else { [void]$tb.Append($ch) }
      continue
    }
    if ($ch -eq [char]'"') {
      $q = $false
      if ($d -eq 2) { if ($after) { $v[$k] = $tb.ToString(); $after = $false } else { $k = $tb.ToString() } }
      continue
    }
    [void]$tb.Append($ch); continue
  }
  if ($ch -eq [char]'"') { $q = $true; [void]$tb.Clear() }
  elseif ($ch -eq [char]':') { if ($d -eq 2) { $after = $true } }
  elseif ($ch -eq [char]',') { if ($d -eq 2) { $after = $false } }
  elseif ($ch -eq [char]'{' -or $ch -eq [char]'[') { if ($d -eq 2) { $after = $false }; $d++ }
  elseif ($ch -eq [char]'}' -or $ch -eq [char]']') {
    if ($d -eq 2 -and $ch -eq [char]'}' -and $v['id']) {
      $sv = [string]$v['state']
      if (($sv -ceq 'done' -or $sv -ceq 'stopped' -or $sv -ceq 'failed') -and -not $v.ContainsKey('status')) {
        [void]$fin.Add(@([string]$v['id'], [string]$v['sessionId'], [string]$v['cwd'], [string]$v['name']))
      }
    }
    if ($d -eq 2) { $v = @{} }
    $d--
  }
}
$lines = Plain $Log; $c = Cols $lines; $ns = ColNo $c 'start'
$starts = @{}
if ($ns -ge 0) { foreach ($r in (RowsOf $lines)) { $x = Cell $r $ns; if ($x) { $starts[$x] = 1 } } }
$missing = New-Object 'System.Collections.Generic.List[string]'
foreach ($e in $fin) {
  $id = $e[0]; $sid = $e[1]; $name = $e[3]
  if ($Self -and ($Self -ceq $id -or $Self -ceq $sid)) { continue }
  if ($name.StartsWith('assistant:')) { continue }
  $p = Canon $e[2]; $inside = $false
  foreach ($r in $roots) {
    if (-not $r) { continue }
    if ($isWin -or $r -match '^[a-z]:') { $cmp = [StringComparison]::OrdinalIgnoreCase } else { $cmp = [StringComparison]::Ordinal }
    if ($p.Equals($r, $cmp) -or $p.StartsWith($r + '/', $cmp)) { $inside = $true; break }
  }
  if (-not $inside) { continue }
  $sidOrId = if ($sid) { $sid } else { $id }
  $st = SessionTokens $sidOrId
  if ($null -eq $st) { continue }
  $start = ''
  foreach ($x in $st) { if ($x.StartsWith('time')) { $start = TimeKv $x 'start'; break } }
  if (-not $start) { continue }
  if ($Since -and [string]::CompareOrdinal($start.Substring(0, [Math]::Min(10, $start.Length)), $Since) -lt 0) { continue }
  if ($starts.ContainsKey($start)) { continue }
  $missing.Add("MISSING $id $name $start")
}
if ($missing.Count) { $missing } else { 'ALL LOGGED' }
exit 0
} catch {
  # no exception ends in exit 0
  [Console]::Error.WriteLine("runs: " + $_.Exception.Message); exit 1
} finally { if ($enc0) { try { [Console]::OutputEncoding = $enc0 } catch { } } }
