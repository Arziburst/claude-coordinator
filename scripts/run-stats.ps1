# The forecast numbers from a run log (Windows; macOS / Linux: run-stats.sh - same rules, same output, see it).
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-stats.ps1 <RUNS.tsv>                    every kind and model
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-stats.ps1 <RUNS.tsv> -Kind <k> -Model <m>   that pair's line only
# Per kind and model and per measure, the last 10 rows with a value for it (cost in USD, active in minutes; any
# other value skips the row for that measure); columns by the header line (first field `date`), else CORE 7's order.
# Prints, tab-separated: kind model cost_n cost_median cost_low cost_high time_n time_median time_low time_high
# (median: the mean of the two middle values for an even count; low / high: the 25th and 75th percentile by nearest
# rank from 4 values on, min and max under 4; cost to the cent, time to the minute, half up; no values: 0 and -).
# Exit 1 when the file cannot be read, 2 on a usage error.
param([string]$File, [string]$Kind, [string]$Model)
$enc0 = $null; try { $enc0 = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
try {
if (-not $File -or ([bool]$Kind -ne [bool]$Model)) {
  Get-Content -LiteralPath $PSCommandPath -TotalCount 9 | ForEach-Object { $_ -creplace '^# ?', '' }; exit 2
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

$ck = 3; $cm = 4; $cc = 8; $ca = 12   # CORE 7's order, 0-based
$cost = @{}; $time = @{}; $seen = New-Object 'System.Collections.Generic.List[string]'
foreach ($line in $L) {
  $line = $line -creplace "`r$", ''
  if ($line -cmatch '^[ \t]*\z' -or $line -cmatch '^#') { continue }
  $f = $line.Split("`t")
  if ($f[0] -ceq 'date') {
    $ck = [Array]::IndexOf($f, 'kind'); $cm = [Array]::IndexOf($f, 'model'); $cc = [Array]::IndexOf($f, 'cost'); $ca = [Array]::IndexOf($f, 'active')
    continue
  }
  $k = if ($ck -ge 0 -and $ck -lt $f.Count) { $f[$ck] } else { '' }
  $m = if ($cm -ge 0 -and $cm -lt $f.Count) { $f[$cm] } else { '' }
  if ($k -eq '' -or $m -eq '') { continue }
  $g = "$k`t$m"
  if (-not $cost.ContainsKey($g)) { $cost[$g] = New-Object 'System.Collections.Generic.List[long]'; $time[$g] = New-Object 'System.Collections.Generic.List[long]'; $seen.Add($g) }
  if ($cc -ge 0 -and $cc -lt $f.Count) { $u = Units $f[$cc] '$'; if ($u -ge 0) { $cost[$g].Add($u) } }
  if ($ca -ge 0 -and $ca -lt $f.Count) { $u = Units $f[$ca] 'm'; if ($u -ge 0) { $time[$g].Add($u) } }
}
if ($Kind) {
  $g = "$Kind`t$Model"
  "$g`t$(Stats $cost[$g] 100)`t$(Stats $time[$g] 10000)"
  exit 0
}
"kind`tmodel`tcost_n`tcost_median`tcost_low`tcost_high`ttime_n`ttime_median`ttime_low`ttime_high"
$keys = [string[]]$seen.ToArray(); [Array]::Sort($keys, [StringComparer]::Ordinal)   # as LC_ALL=C sort
foreach ($g in $keys) { "$g`t$(Stats $cost[$g] 100)`t$(Stats $time[$g] 10000)" }
exit 0
} finally { if ($enc0) { try { [Console]::OutputEncoding = $enc0 } catch { } } }
