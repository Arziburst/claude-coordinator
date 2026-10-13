# The forecast numbers from a run log (Windows; macOS / Linux: run-stats.sh - same rules, same output, see it).
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-stats.ps1 <RUNS.tsv>                    per kind and model, over tasks
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-stats.ps1 <RUNS.tsv> -Kind <k> -Model <m>   that pair's line only
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-stats.ps1 <RUNS.tsv> -PerRun             per kind, role and model, over rows
# A task is the rows whose task number agrees before its first dot: its cost and time are the sums of the values its
# rows have (a subagent's row, cost `in <parent>`, adds no time); its kind and model are its lead row's, else its first
# worker row's, else its first row's; a `task` row (one per finished task, CORE 7) adds nothing to them. Per kind and
# model and per measure, the last 10 tasks with a value count; ready: the wall of the last `task` row of each task. A
# cost cell counts by its leading number (`0.0648 prices` is 0.0648); a verifier's `done` or `pass` is an approval.
# Prints, tab-separated: kind model cost_n cost_median cost_low cost_high time_n time_median time_low time_high
# ready_n ready_median ready_low ready_high (-PerRun: kind role model and the cost and time columns, no task rows)
# (median: the mean of the two middle values for an even count; low / high: the 25th and 75th percentile by nearest
# rank from 4 values on, min and max under 4; cost to the cent, time to the minute, half up; no values: 0 and -).
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-stats.ps1 <RUNS.tsv> -Task <n> [-PrJson <file|->]
#     [-Waits <file>]   the task's `task` row to append: time to ready and owner wait from its runs, the PR's
#     `gh pr view <n> --json statusCheckRollup,mergedAt,createdAt` and the owner-decision intervals of the journal,
#     `<asked UTC> <answered UTC>` per line (the rules: run-stats.sh's top comment; -PrJson:- reads stdin).
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-stats.ps1 -Limits [-Status <file>] [-Spend5h <file|->]
#     [-SpendWeek <file|->] [-Prices <file>] [-Prev5h <%/$>] [-PrevWeek <%/$>] [-Cap5h <%>] [-CapWeek <%>] [-Block <USD>]
#     [-Now <Unix seconds>]   per window (five_hour, seven_day): window used since resets cost ratio basis left left_cap
#     block fit - the limit percent per dollar, the dollars left before 100% and the cap, and whether the block fits
#     (the inputs, the columns and the rounding: run-stats.sh's top comment). Spend: what session-tokens -Since
#     <since> prints; prices: `<model id> <input> <output> <cache read> <cache write> [not-weekly]`, USD per million
#     (assumed: every model, an own-limit one too, spends the 5-hour window - not measured; five_hour sums them all).
# Exit 1 when a file cannot be read (and in -Limits: no rate limits in the JSON, a malformed price line, a spend
# model without a price; in -Task: no rows for the task, no start, not ready, a malformed wait line), 2 on a usage error.
param([string]$File, [string]$Kind, [string]$Model, [switch]$PerRun, [string]$Task, [string]$PrJson, [string]$Waits,
  [switch]$Limits, [string]$Status, [string]$Spend5h, [string]$SpendWeek, [string]$Prices,
  [string]$Prev5h, [string]$PrevWeek, [string]$Cap5h, [string]$CapWeek, [string]$Block, [string]$Now)
$enc0 = $null; try { $enc0 = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
try {
function Show-Usage { Get-Content -LiteralPath $PSCommandPath -TotalCount 26 | ForEach-Object { $_ -creplace '^# ?', '' }; exit 2 }
if ($Limits) {
  if ($File -or $Kind -or $Model -or $PerRun -or $Task -or $PrJson -or $Waits) { Show-Usage }
} elseif ($Task -or $PrJson -or $Waits) {
  if (-not $File -or -not $Task -or $Kind -or $Model -or $PerRun -or $Waits -eq '-') { Show-Usage }
} elseif (-not $File -or ([bool]$Kind -ne [bool]$Model) -or ($PerRun -and $Kind)) { Show-Usage }
$ErrorActionPreference = 'Stop'
# numbers as the .sh prints them (6.50, not 6,50 on a Russian or German Windows)
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture
$inv = [Globalization.CultureInfo]::InvariantCulture

if ($Limits) {
  # a value in units of 1/10000 (four decimals, the rest dropped), `$` first allowed; -1 when it is no number
  function U4([string]$v) {
    $v = $v.Trim(' ', "`t") -creplace '^[$]', ''
    if ($v -cmatch '^([0-9]+)(?:[.]([0-9]+))?\z') { return [long]$Matches[1] * 10000 + [long](($Matches[2] + '0000').Substring(0, 4)) }
    [long]-1
  }
  function IDiv([long]$a, [long]$b) { [long](($a - ($a % $b)) / $b) }   # whole numbers: exact
  function RDiv([long]$a, [long]$b) { IDiv (2 * $a + $b) (2 * $b) }     # a / b rounded half up
  function Usd([long]$c) { '{0}.{1:00}' -f (IDiv $c 100), ($c % 100) }
  function One([long]$x) { '{0}.{1}' -f (IDiv $x 10), ($x % 10) }
  function Iso([long]$t) { [DateTimeOffset]::FromUnixTimeSeconds($t).UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", $inv) }
  function Read-Lines([string]$f) {
    $r = $null
    try { if (Test-Path -LiteralPath $f -PathType Leaf) { $r = @([IO.File]::ReadAllLines((Resolve-Path -LiteralPath $f).Path)) } } catch { }
    if ($null -eq $r) { [Console]::Error.WriteLine("run-stats: cannot read $f"); exit 1 }
    if ($r.Count -gt 0) { $r[0] = $r[0].TrimStart([char]0xFEFF) }
    ,$r
  }
  foreach ($v in @($Prev5h, $PrevWeek, $Cap5h, $CapWeek, $Block)) { if ($v -and $v -cnotmatch '^[$]?[0-9]+([.][0-9]+)?\z') { Show-Usage } }
  if (-not $Now) { $Now = "$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())" } elseif ($Now -cnotmatch '^[0-9]+\z') { Show-Usage }
  if ($Spend5h -eq '-' -and $SpendWeek -eq '-') { Show-Usage }                 # one stdin
  if (($Spend5h -or $SpendWeek) -and -not $Prices) { Show-Usage }              # a spend needs its prices
  if (-not $Status) { $cfg = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }; $Status = Join-Path (Join-Path $cfg 'coordinator') 'statusline.json' }
  foreach ($x in @($Status, $Prices, $Spend5h, $SpendWeek)) {
    if ($x -and $x -ne '-' -and -not (Test-Path -LiteralPath $x -PathType Leaf)) { [Console]::Error.WriteLine("run-stats: cannot read $x"); exit 1 }
  }
  # the windows: used_percentage and resets_at as written (- when absent or not a plain number); the JSON as
  # one line, read as text; each window a flat object after "rate_limits"
  $s = ' ' + ((Read-Lines $Status) -join ' ')
  $UsedOf = @{}; $ResetOf = @{}
  $p = $s.IndexOf('"rate_limits"', [StringComparison]::Ordinal)
  if ($p -ge 0) {
    $s = $s.Substring($p + 13)
    foreach ($w in 'five_hour', 'seven_day') {
      $m = [regex]::Match($s, '"' + $w + '"[ \t]*:[ \t]*[{][^}]*[}]')
      if ($m.Success) {
        foreach ($k in 'used_percentage', 'resets_at') {
          $n = [regex]::Match($m.Value, '"' + $k + '"[ \t]*:[ \t]*([0-9]+(?:[.][0-9]+)?)[ \t]*[,}]')
          $val = if ($n.Success) { $n.Groups[1].Value } else { '-' }
          if ($k -ceq 'used_percentage') { $UsedOf[$w] = $val } else { $ResetOf[$w] = $val }
        }
      }
    }
  }
  if ($UsedOf.Count -eq 0) { [Console]::Error.WriteLine("run-stats: no rate limits in $Status (an API key or an older Claude Code: budget by cost)"); exit 1 }
  # the prices, each in 1/10000 USD per million tokens
  $PL = New-Object 'System.Collections.Generic.List[object]'
  if ($Prices) {
    $i = 0
    foreach ($line in (Read-Lines $Prices)) {
      $i++; $line = $line -creplace "`r$", ''
      if ($line -cmatch '^[ \t]*(#|$)') { continue }
      $f = @(($line -creplace '/', ' ').Trim(' ', "`t") -split '[ \t]+')
      $ok = ($f.Count -eq 5 -or ($f.Count -eq 6 -and $f[5] -ceq 'not-weekly'))
      $pv = @(0, 0, 0, 0, 0, 0)
      for ($j = 1; $j -le 4 -and $ok; $j++) { $pv[$j] = U4 $f[$j]; if ($pv[$j] -lt 0) { $ok = $false } }
      if (-not $ok) { [Console]::Error.WriteLine("run-stats: ${Prices}:${i}: not a price line (<model> <input> <output> <cache read> <cache write> [not-weekly])"); exit 1 }
      $PL.Add(@{ id = $f[0]; pin = [long]$pv[1]; pout = [long]$pv[2]; prd = [long]$pv[3]; pwr = [long]$pv[4]; nw = ($f.Count -eq 6) })
    }
  }
  # a spend in micro-USD: tokens times the price of the model's line; the week leaves not-weekly out
  function Spend([string]$f, [bool]$week) {
    if ($f -eq '-') { $lines = @([Console]::In.ReadToEnd() -split "`r?`n"); if ($lines.Count -gt 0) { $lines[0] = $lines[0].TrimStart([char]0xFEFF) } }
    else { $lines = Read-Lines $f }
    [long]$T = 0
    foreach ($line in $lines) {
      $line = $line -creplace "`r$", ''
      if ($line -cmatch '^[ \t]*(#|$)' -or $line -cnotmatch '[ \t]in=[0-9]') { continue }
      $m = @($line.Trim(' ', "`t") -split '[ \t]+')[0]
      if ($m -ceq 'total' -or $m -ceq 'cost' -or $m -ceq 'time') { continue }
      $b = $null
      foreach ($x in $PL) {
        if ($x.id -ceq $m) { $b = $x; break }
        if ($m.StartsWith($x.id, [StringComparison]::Ordinal) -and ($null -eq $b -or $x.id.Length -gt $b.id.Length)) { $b = $x }
      }
      if ($null -eq $b) { [Console]::Error.WriteLine("run-stats: no price for $m in $Prices"); exit 1 }
      if ($week -and $b.nw) { continue }
      $tok = { param($k) $n = [regex]::Match($line, '(^|[ \t])' + [regex]::Escape($k) + '([0-9]+)'); if ($n.Success) { [long]$n.Groups[2].Value } else { [long]0 } }
      $T += (& $tok 'in=') * $b.pin + (& $tok 'out>=') * $b.pout + (& $tok 'cache_read=') * $b.prd + (& $tok 'cache_write=') * $b.pwr
    }
    IDiv $T 10000
  }
  $CostOf = @{ five_hour = ''; seven_day = '' }
  if ($Spend5h) { $CostOf.five_hour = "$(Spend $Spend5h $false)" }
  if ($SpendWeek) { $CostOf.seven_day = "$(Spend $SpendWeek $true)" }
  $nowS = [long]$Now
  "window`tused`tsince`tresets`tcost`tratio`tbasis`tleft`tleft_cap`tblock`tfit"
  # used in 1/10000 percent, cost c in micro-USD, the ratio r in 1/10000 percent per dollar
  foreach ($x in @(@('five_hour', 18000, $Prev5h, $Cap5h), @('seven_day', 604800, $PrevWeek, $CapWeek))) {
    $w = $x[0]; $len = [long]$x[1]; $prev = $x[2]; $cap = $x[3]; $c = $CostOf[$w]
    if (-not $UsedOf.ContainsKey($w) -or $UsedOf[$w] -eq '-') { "$w`t-`t-`t-`t-`t-`t-`t-`t-`t-`t-"; continue }
    [long]$u = U4 $UsedOf[$w]; $since = '-'; $res = '-'
    if ($ResetOf[$w] -ne '-') { [long]$rs = [Math]::Floor([decimal]::Parse($ResetOf[$w], $inv)) }
    if ($ResetOf[$w] -ne '-' -and $rs -le $nowS) { $u = 0; $c = '' }   # the window has reset since the JSON was written
    elseif ($ResetOf[$w] -ne '-') { $res = Iso $rs; $since = Iso ($rs - $len) }
    $cost = if ($c -eq '') { '-' } else { Usd (RDiv ([long]$c) 10000) }
    [long]$cl = if ($c -eq '') { 0 } else { [long]$c }
    [long]$r = -1; $basis = '-'
    if ($u -ge 100000 -and $cl -gt 0) { $r = RDiv ($u * 1000000) $cl; $basis = 'trusted' }
    elseif ($prev) { $r = U4 $prev; $basis = 'previous' }
    elseif ($u -gt 0 -and $cl -gt 0) { $r = RDiv ($u * 1000000) $cl; $basis = 'guess' }
    $left = '-'; $lc = '-'; $blk = '-'; $fit = '-'
    [long]$L4 = if ($cap) { U4 $cap } else { 1000000 }
    if ($r -gt 0) {
      $left = Usd (IDiv ([Math]::Max([long]0, 1000000 - $u) * 100) $r)
      if ($cap) { $lc = Usd (IDiv ([Math]::Max([long]0, $L4 - $u) * 100) $r) }
    }
    if ($Block -and $r -gt 0) {
      [long]$bc = RDiv (U4 $Block) 100; [long]$pp = $bc * $r   # in 1/1000000 percent
      $blk = One (RDiv $pp 100000); $fit = if (100 * $u + $pp -le 100 * $L4) { 'fits' } else { 'does not fit' }
    }
    $rt = if ($r -lt 0) { '-' } else { '{0}.{1:0000}' -f (IDiv $r 10000), ($r % 10000) }
    "$w`t$(One (RDiv $u 1000))`t$since`t$res`t$cost`t$rt`t$basis`t$left`t$lc`t$blk`t$fit"
  }
  exit 0
}
if ($Task) {
  foreach ($x in @($File, $PrJson, $Waits)) {
    if ($x -and $x -ne '-' -and -not (Test-Path -LiteralPath $x -PathType Leaf)) { [Console]::Error.WriteLine("run-stats: cannot read $x"); exit 1 }
  }
  function IDiv([long]$a, [long]$b) { [long](($a - ($a % $b)) / $b) }   # whole numbers: exact
  function Read-Lines([string]$f) {
    $r = $null
    try { if ($f -eq '-') { $r = @([Console]::In.ReadToEnd() -split "`n") } else { $r = @([IO.File]::ReadAllLines((Resolve-Path -LiteralPath $f).Path)) } } catch { }
    if ($null -eq $r) { [Console]::Error.WriteLine("run-stats: cannot read $f"); exit 1 }
    if ($r.Count -gt 0) { $r[0] = $r[0].TrimStart([char]0xFEFF) }
    ,@($r | ForEach-Object { $_ -creplace "`r$", '' })
  }
  # YYYY-MM-DDTHH:MM:SS[.fraction]Z as Unix seconds (the civil calendar, as the .sh), -1 when it is none
  function Epoch([string]$v) {
    if ($v.Trim(' ', "`t") -cnotmatch '^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})([.][0-9]+)?Z\z') { return [long]-1 }
    [long]$y = $Matches[1]; [long]$m = $Matches[2]; [long]$d = $Matches[3]; [long]$h = $Matches[4]; [long]$mi = $Matches[5]; [long]$s = $Matches[6]
    if ($m -lt 1 -or $m -gt 12 -or $d -lt 1 -or $d -gt 31 -or $h -gt 23 -or $mi -gt 59 -or $s -gt 60) { return [long]-1 }
    if ($m -le 2) { $y-- }
    $e = IDiv $y 400; $yoe = $y - $e * 400
    $mp = if ($m -gt 2) { $m - 3 } else { $m + 9 }
    $doe = $yoe * 365 + (IDiv $yoe 4) - (IDiv $yoe 100) + (IDiv (153 * $mp + 2) 5) + $d - 1
    [long](($e * 146097 + $doe - 719468) * 86400 + $h * 3600 + $mi * 60 + $s)
  }
  function Iso([long]$t) { [DateTimeOffset]::FromUnixTimeSeconds($t).UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", $inv) }
  function Minutes([string]$v) {   # in 1/10000 minute, -1 when it is no number
    $v = $v.Trim(' ', "`t") -creplace 'm\z', ''
    if ($v -cmatch '^([0-9]+)(?:[.]([0-9]+))?\z') { return [long]$Matches[1] * 10000 + [long](($Matches[2] + '0000').Substring(0, 4)) }
    [long]-1
  }
  # the PR: merged, and the checks - per check (its type, workflow and name) the run started last (a tie: the
  # later one in the list); all green: the last completion; the JSON as one line, read as text, each check a flat object
  [long]$MergedAt = -1; $chk = 'none'; [long]$green = -1; $redName = ''; $redState = ''
  if ($PrJson) {
    $s = ' ' + ((Read-Lines $PrJson) -join ' ')
    function Str([string]$o, [string]$k) { $n = [regex]::Match($o, '"' + $k + '"[ \t]*:[ \t]*"([^"]*)"'); if ($n.Success) { $n.Groups[1].Value } else { '' } }
    $MergedAt = Epoch (Str $s 'mergedAt')
    $p = $s.IndexOf('"statusCheckRollup"', [StringComparison]::Ordinal)
    $mm = if ($p -ge 0) { [regex]::Match($s.Substring($p + 19), '^[ \t]*:[ \t]*\[') } else { $null }
    if ($mm -and $mm.Success) {
      $r = $s.Substring($p + 19 + $mm.Length)
      $keys = New-Object 'System.Collections.Generic.List[string]'; $Runs = @{}
      while ($true) {
        $om = [regex]::Match($r, '^[ \t,]*[{][^{}]*[}]'); if (-not $om.Success) { break }
        $o = $om.Value; $r = $r.Substring($om.Length)
        $k = (Str $o '__typename') + "`t" + (Str $o 'workflowName') + "`t" + (Str $o 'name') + (Str $o 'context'); $t = Epoch (Str $o 'startedAt')
        if ($Runs.ContainsKey($k) -and $t -lt $Runs[$k].at) { continue }
        if (-not $Runs.ContainsKey($k)) { $keys.Add($k) }
        $e = Epoch (Str $o 'completedAt')
        if ((Str $o '__typename') -ceq 'StatusContext') { $st = Str $o 'state'; $ok = ($st -ceq 'SUCCESS') }
        else { $st = if ((Str $o 'status') -ceq 'COMPLETED') { Str $o 'conclusion' } else { Str $o 'status' }; $ok = ($st -ceq 'SUCCESS' -or $st -ceq 'NEUTRAL' -or $st -ceq 'SKIPPED') }
        $Runs[$k] = @{ at = $t; fin = $(if ($e -lt 0) { $t } else { $e }); name = (Str $o 'name') + (Str $o 'context'); st = $st; ok = $ok }
      }
      foreach ($k in $keys) {
        $c = $Runs[$k]
        if (-not $c.ok) { $chk = 'red'; $redName = $c.name; $redState = if ($c.st -eq '') { 'unknown' } else { $c.st }; break }
        if ($c.fin -gt $green) { $green = $c.fin }
      }
      if ($chk -ne 'red' -and $green -ge 0) { $chk = 'green' }
    }
  }
  # the owner-decision intervals: `<asked> <answered>` per line, UTC
  $WL = New-Object 'System.Collections.Generic.List[object]'
  if ($Waits) {
    $i = 0
    foreach ($line in (Read-Lines $Waits)) {
      $i++
      if ($line -cmatch '^[ \t]*(#|$)') { continue }
      $f = @($line.Trim(' ', "`t") -split '[ \t]+')
      $a = Epoch $f[0]; $b = if ($f.Count -ge 2) { Epoch $f[1] } else { [long]-1 }
      if ($f.Count -ne 2 -or $a -lt 0 -or $b -lt $a) { [Console]::Error.WriteLine("run-stats: ${Waits}:${i}: not an owner wait (<asked UTC> <answered UTC>)"); exit 1 }
      $WL.Add(@($a, $b))
    }
  }
  $TaskId = $Task -creplace '[.].*$', ''
  function Fail([string]$m) { [Console]::Error.WriteLine("run-stats: task ${TaskId}: $m"); exit 1 }
  $ct = 1; $cr = 2; $ck = 3; $cm = 4; $cc = 8; $cs = 9; $cb = 10; $cw = 11; $ca = 12   # CORE 7's order, 0-based
  $hd = @(); [long]$first = -1; [long]$ver = -1; $hv = $false; [long]$act = 0; $ha = $false; $n = 0; $pr = 0; $tk = ''; $tm = ''
  foreach ($line in (Read-Lines $File)) {
    if ($line -cmatch '^[ \t]*\z' -or $line -cmatch '^#') { continue }
    $f = $line.Split("`t")
    if ($f[0] -ceq 'date') {
      $hd = $f
      $ct = [Array]::IndexOf($f, 'task'); $cr = [Array]::IndexOf($f, 'role'); $ck = [Array]::IndexOf($f, 'kind'); $cm = [Array]::IndexOf($f, 'model')
      $cc = [Array]::IndexOf($f, 'cost'); $cs = [Array]::IndexOf($f, 'result'); $cb = [Array]::IndexOf($f, 'start'); $cw = [Array]::IndexOf($f, 'wall'); $ca = [Array]::IndexOf($f, 'active')
      continue
    }
    $col = { param($i) if ($i -ge 0 -and $i -lt $f.Count) { $f[$i] } else { '' } }
    $t = (& $col $ct) -creplace '[.].*$', ''; $r = & $col $cr
    if ($t -cne $TaskId -or $r -ceq 'task') { continue }
    $n++; $a = Minutes (& $col $ca); $s = Epoch (& $col $cb)
    if ($a -ge 0 -and (& $col $cc) -cnotmatch '^[ \t]*in[ \t]') { $act += $a; $ha = $true }   # a subagent: in its parent
    $p = if ($r -ceq 'lead') { 3 } elseif ($r -ceq 'worker') { 2 } else { 1 }
    if ($p -gt $pr) { $pr = $p; $tk = & $col $ck; $tm = & $col $cm }
    if ($s -ge 0 -and ($first -lt 0 -or $s -lt $first)) { $first = $s }
    # the verifier approved at its run's start + wall; the last approval counts
    if ($r -ceq 'verifier') {
      $hv = $true; $w = Minutes (& $col $cw)
      if ((& $col $cs) -match '^[ \t]*(approved|done([^a-z]|\z)|pass([^a-z]|\z))' -and $s -ge 0 -and $w -ge 0 -and $s + (IDiv ($w * 6) 1000) -gt $ver) { $ver = $s + (IDiv ($w * 6) 1000) }
    }
  }
  if ($n -eq 0) { Fail "no rows in $File" }
  if ($first -lt 0) { Fail 'no run has a start' }
  if ($hv -and $ver -lt 0) { Fail 'not ready - no verifier run approved it' }
  if ($chk -eq 'red') { Fail "not ready - the check $redName is $redState" }
  [long]$g = if ($chk -eq 'green') { $green } else { -1 }
  [long]$ready = [Math]::Max($ver, $g)
  if ($ready -lt 0) { Fail 'not ready - no approved verifier run and no green checks' }
  if ($ready -lt $first) { $ready = $first }
  # the owner waits inside first start .. ready, overlaps once
  $iv = @(foreach ($x in $WL) { $lo = [Math]::Max($x[0], $first); $hi = [Math]::Min($x[1], $ready); if ($hi -gt $lo) { ,@($lo, $hi) } })
  $iv = @($iv | Sort-Object -Property { $_[0] })
  [long]$wait = 0; [long]$e = -1
  foreach ($x in $iv) { $lo = [Math]::Max($x[0], $e); if ($x[1] -gt $lo) { $wait += $x[1] - $lo }; if ($x[1] -gt $e) { $e = $x[1] } }
  $Row = @{ task = $TaskId; role = 'task'; kind = $tk; model = $tm; effort = '-'; estimate = '-'; tokens = '-'; cost = '-'
    start = (Iso $first); wall = "$(IDiv ($ready - $first - $wait + 30) 60)"; active = $(if ($ha) { "$(IDiv ($act + 5000) 10000)" } else { '-' }) }
  if ($MergedAt -ge 0) { $Row.wait = "$(IDiv ([Math]::Max([long]0, $MergedAt - $ready) + $wait + 30) 60)"; $Row.result = 'merged'; $Row.date = (Iso $MergedAt).Substring(0, 10) }
  else { $Row.wait = "$(IDiv ($wait + 30) 60)+"; $Row.result = 'ready'; $Row.date = (Iso $ready).Substring(0, 10) }
  # the header's order (a column it does not name: empty), then the names it lacks in CORE 7's order
  $u = @{}; $out = New-Object 'System.Collections.Generic.List[string]'
  foreach ($h in $hd) { $v = ''; if ($Row.ContainsKey($h) -and -not $u.ContainsKey($h)) { $v = $Row[$h]; $u[$h] = 1 }; $out.Add($v) }
  foreach ($h in 'date', 'task', 'role', 'kind', 'model', 'effort', 'estimate', 'tokens', 'cost', 'result', 'start', 'wall', 'active', 'wait') { if (-not $u.ContainsKey($h)) { $out.Add($Row[$h]) } }
  $out -join "`t"
  exit 0
}
$L = $null
try { if (Test-Path -LiteralPath $File -PathType Leaf) { $L = @([IO.File]::ReadAllLines((Resolve-Path -LiteralPath $File).Path)) } } catch { }
if ($null -eq $L) { [Console]::Error.WriteLine("run-stats: cannot read $File"); exit 1 }

# a value in units of 1/10000 (four decimals, the rest dropped); -1 when it is no number
function Units([string]$v, [string]$unit) {
  $v = $v.Trim(' ', "`t")
  # a cost: its leading number (`0.0648 prices` is 0.0648, `$1.20` 1.20); minutes: the whole value, `m` allowed
  if ($unit -ceq '$') { $v = $v -creplace '^[$]', ''; $re = '^([0-9]+)(?:[.]([0-9]+))?' } else { $v = $v -creplace 'm$', ''; $re = '^([0-9]+)(?:[.]([0-9]+))?\z' }
  if ($v -cmatch $re) { return [long]$Matches[1] * 10000 + [long](($Matches[2] + '0000').Substring(0, 4)) }
  [long]-1
}
function Rank([long]$p, [long]$n) { [long][Math]::Ceiling($p * $n / 100) }
# twice a value in units, rounded half up to the step r: cents as d.cc, minutes as a whole number
function Out([long]$w, [long]$r) {
  $c = [long][Math]::Floor(($w + $r) / (2 * $r))
  if ($r -eq 100) { '{0}.{1:00}' -f [long][Math]::Floor($c / 100), ($c % 100) } else { "$c" }
}
# n, median, low, high of the last 10 values
function Stats($vals, [long]$r) {
  if ($null -eq $vals -or $vals.Count -eq 0) { return "0`t-`t-`t-" }
  $s = [Math]::Max(0, $vals.Count - 10)
  $a = [long[]]@($vals.GetRange($s, $vals.Count - $s)); [Array]::Sort($a); $t = $a.Count
  $med = if ($t % 2) { 2 * $a[($t - 1) / 2] } else { $a[$t / 2 - 1] + $a[$t / 2] }
  $lo = if ($t -lt 4) { $a[0] } else { $a[(Rank 25 $t) - 1] }
  $hi = if ($t -lt 4) { $a[$t - 1] } else { $a[(Rank 75 $t) - 1] }
  "$t`t$(Out $med $r)`t$(Out (2 * $lo) $r)`t$(Out (2 * $hi) $r)"
}
$cost = @{}; $time = @{}; $ready = @{}; $seen = New-Object 'System.Collections.Generic.List[string]'
function Add([string]$g, [long]$c, [long]$a, [long]$w) {
  if (-not $cost.ContainsKey($g)) { $cost[$g] = New-Object 'System.Collections.Generic.List[long]'; $time[$g] = New-Object 'System.Collections.Generic.List[long]'; $ready[$g] = New-Object 'System.Collections.Generic.List[long]'; $seen.Add($g) }
  if ($c -ge 0) { $cost[$g].Add($c) }
  if ($a -ge 0) { $time[$g].Add($a) }
  if ($w -ge 0) { $ready[$g].Add($w) }
}

$ct = 1; $cr = 2; $ck = 3; $cm = 4; $cc = 8; $cw = 11; $ca = 12   # CORE 7's order, 0-based
$order = New-Object 'System.Collections.Generic.List[string]'   # tasks, a task moved to the end at each of its rows
$byTask = @{}
$rorder = New-Object 'System.Collections.Generic.List[string]'; $byReady = @{}   # the task rows, likewise
foreach ($line in $L) {
  $line = $line -creplace "`r$", ''
  if ($line -cmatch '^[ \t]*\z' -or $line -cmatch '^#') { continue }
  $f = $line.Split("`t")
  if ($f[0] -ceq 'date') {
    $ct = [Array]::IndexOf($f, 'task'); $cr = [Array]::IndexOf($f, 'role'); $ck = [Array]::IndexOf($f, 'kind')
    $cm = [Array]::IndexOf($f, 'model'); $cc = [Array]::IndexOf($f, 'cost'); $cw = [Array]::IndexOf($f, 'wall'); $ca = [Array]::IndexOf($f, 'active')
    continue
  }
  $col = { param($i) if ($i -ge 0 -and $i -lt $f.Count) { $f[$i] } else { '' } }
  $k = & $col $ck; $m = & $col $cm; $r = & $col $cr; $cv = & $col $cc
  $c = Units $cv '$'; $a = Units (& $col $ca) 'm'
  # a task row (role task): its wall is the time to ready, the forecast only; the last one of a task counts
  if ($r -ceq 'task') {
    if ($PerRun) { continue }
    $t = (& $col $ct) -creplace '[.].*$', ''
    if ($t -eq '' -or $t -eq '-') { continue }
    [void]$rorder.Remove($t); $rorder.Add($t); $byReady[$t] = @{ k = $k; m = $m; w = (Units (& $col $cw) 'm') }
    continue
  }
  if ($PerRun) { if ($k -ne '' -and $m -ne '') { Add "$k`t$r`t$m" $c $a -1 }; continue }
  $t = (& $col $ct) -creplace '[.].*$', ''
  if ($t -eq '' -or $t -eq '-') { continue }
  if (-not $byTask.ContainsKey($t)) { $byTask[$t] = @{ c = [long]0; hc = $false; a = [long]0; ha = $false; p = 0; k = ''; m = '' } }
  $x = $byTask[$t]; [void]$order.Remove($t); $order.Add($t)
  if ($c -ge 0) { $x.c += $c; $x.hc = $true }
  if ($a -ge 0 -and $cv -cnotmatch '^[ \t]*in[ \t]') { $x.a += $a; $x.ha = $true }   # a subagent: in its parent
  # its kind and model: the lead row, else the first worker row, else the first row
  $p = if ($r -ceq 'lead') { 3 } elseif ($r -ceq 'worker') { 2 } else { 1 }
  if ($p -gt $x.p) { $x.p = $p; $x.k = $k; $x.m = $m }
}
if (-not $PerRun) {
  foreach ($t in $order) {
    $x = $byTask[$t]; if ($x.k -eq '' -or $x.m -eq '') { continue }
    Add "$($x.k)`t$($x.m)" $(if ($x.hc) { $x.c } else { -1 }) $(if ($x.ha) { $x.a } else { -1 }) -1
  }
  # the task rows in the order of each task's last one, under the kind and model they name
  foreach ($t in $rorder) {
    $x = $byReady[$t]; if ($x.k -eq '' -or $x.m -eq '') { continue }
    Add "$($x.k)`t$($x.m)" -1 -1 $x.w
  }
}
$rd = { param($g) if ($PerRun) { '' } else { "`t$(Stats $ready[$g] 10000)" } }
if ($Kind) {
  $g = "$Kind`t$Model"
  "$g`t$(Stats $cost[$g] 100)`t$(Stats $time[$g] 10000)$(& $rd $g)"
  exit 0
}
"$(if ($PerRun) { "kind`trole`tmodel" } else { "kind`tmodel" })`tcost_n`tcost_median`tcost_low`tcost_high`ttime_n`ttime_median`ttime_low`ttime_high$(if (-not $PerRun) { "`tready_n`tready_median`tready_low`tready_high" })"
$keys = [string[]]$seen.ToArray(); [Array]::Sort($keys, [StringComparer]::Ordinal)   # as LC_ALL=C sort
foreach ($g in $keys) { "$g`t$(Stats $cost[$g] 100)`t$(Stats $time[$g] 10000)$(& $rd $g)" }
exit 0
} finally { if ($enc0) { try { [Console]::OutputEncoding = $enc0 } catch { } } }
