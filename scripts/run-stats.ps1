# The forecast numbers from a run log (Windows; macOS / Linux: run-stats.sh - same rules, same output, see it).
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-stats.ps1 <RUNS.tsv>                    per kind and model, over tasks
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-stats.ps1 <RUNS.tsv> -Kind <k> -Model <m>   that pair's line only
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-stats.ps1 <RUNS.tsv> -PerRun             per kind, role and model, over rows
# A task is the rows whose task number agrees before its first dot: its cost and time are the sums of the values its
# rows have (a subagent's row, cost `in <parent>`, adds no time); its kind and model are its lead row's, else its first
# worker row's, else its first row's. Per kind and model and per measure, the last 10 tasks with a value count.
# Prints, tab-separated: kind model cost_n cost_median cost_low cost_high time_n time_median time_low time_high
# (median: the mean of the two middle values for an even count; low / high: the 25th and 75th percentile by nearest
# rank from 4 values on, min and max under 4; cost to the cent, time to the minute, half up; no values: 0 and -).
# Exit 1 when the file cannot be read, 2 on a usage error.
param([string]$File, [string]$Kind, [string]$Model, [switch]$PerRun)
$enc0 = $null; try { $enc0 = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
try {
if (-not $File -or ([bool]$Kind -ne [bool]$Model) -or ($PerRun -and $Kind)) {
  Get-Content -LiteralPath $PSCommandPath -TotalCount 11 | ForEach-Object { $_ -creplace '^# ?', '' }; exit 2
}
$ErrorActionPreference = 'Stop'
# numbers as the .sh prints them (6.50, not 6,50 on a Russian or German Windows)
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture
$L = $null
try { if (Test-Path -LiteralPath $File -PathType Leaf) { $L = @([IO.File]::ReadAllLines((Resolve-Path -LiteralPath $File).Path)) } } catch { }
if ($null -eq $L) { [Console]::Error.WriteLine("run-stats: cannot read $File"); exit 1 }

# a value in units of 1/10000 (four decimals, the rest dropped); -1 when it is no number
function Units([string]$v, [string]$unit) {
  $v = $v.Trim(' ', "`t")
  if ($unit -ceq '$') { $v = $v -creplace '^[$]', '' } else { $v = $v -creplace 'm$', '' }
  if ($v -cmatch '^([0-9]+)(?:[.]([0-9]+))?\z') { return [long]$Matches[1] * 10000 + [long](($Matches[2] + '0000').Substring(0, 4)) }
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
$cost = @{}; $time = @{}; $seen = New-Object 'System.Collections.Generic.List[string]'
function Add([string]$g, [long]$c, [long]$a) {
  if (-not $cost.ContainsKey($g)) { $cost[$g] = New-Object 'System.Collections.Generic.List[long]'; $time[$g] = New-Object 'System.Collections.Generic.List[long]'; $seen.Add($g) }
  if ($c -ge 0) { $cost[$g].Add($c) }
  if ($a -ge 0) { $time[$g].Add($a) }
}

$ct = 1; $cr = 2; $ck = 3; $cm = 4; $cc = 8; $ca = 12   # CORE 7's order, 0-based
$order = New-Object 'System.Collections.Generic.List[string]'   # tasks, a task moved to the end at each of its rows
$byTask = @{}
foreach ($line in $L) {
  $line = $line -creplace "`r$", ''
  if ($line -cmatch '^[ \t]*\z' -or $line -cmatch '^#') { continue }
  $f = $line.Split("`t")
  if ($f[0] -ceq 'date') {
    $ct = [Array]::IndexOf($f, 'task'); $cr = [Array]::IndexOf($f, 'role'); $ck = [Array]::IndexOf($f, 'kind')
    $cm = [Array]::IndexOf($f, 'model'); $cc = [Array]::IndexOf($f, 'cost'); $ca = [Array]::IndexOf($f, 'active')
    continue
  }
  $col = { param($i) if ($i -ge 0 -and $i -lt $f.Count) { $f[$i] } else { '' } }
  $k = & $col $ck; $m = & $col $cm; $r = & $col $cr; $cv = & $col $cc
  $c = Units $cv '$'; $a = Units (& $col $ca) 'm'
  if ($PerRun) { if ($k -ne '' -and $m -ne '') { Add "$k`t$r`t$m" $c $a }; continue }
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
    Add "$($x.k)`t$($x.m)" $(if ($x.hc) { $x.c } else { -1 }) $(if ($x.ha) { $x.a } else { -1 })
  }
}
if ($Kind) {
  $g = "$Kind`t$Model"
  "$g`t$(Stats $cost[$g] 100)`t$(Stats $time[$g] 10000)"
  exit 0
}
"$(if ($PerRun) { "kind`trole`tmodel" } else { "kind`tmodel" })`tcost_n`tcost_median`tcost_low`tcost_high`ttime_n`ttime_median`ttime_low`ttime_high"
$keys = [string[]]$seen.ToArray(); [Array]::Sort($keys, [StringComparer]::Ordinal)   # as LC_ALL=C sort
foreach ($g in $keys) { "$g`t$(Stats $cost[$g] 100)`t$(Stats $time[$g] 10000)" }
exit 0
} finally { if ($enc0) { try { [Console]::OutputEncoding = $enc0 } catch { } } }
