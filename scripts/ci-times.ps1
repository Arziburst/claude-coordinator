# Seconds per step per OS of a check-core run (#373; Windows PowerShell 5.1 and pwsh; macOS / Linux: ci-times.sh - the same lines and codes).
#   scripts/ci-times.ps1 [--baseline <file>] <run id | file>     the JSON of `gh run view <id> --json jobs`, or a file holding it
# Lines: `wall <s>` (the latest job's end - the earliest job's start), `total <os> <s>` (the sum of its counted steps),
# `step <os> <s> <name>` (a step completed and not skipped; the shards of an OS summed, by first appearance); with
# --baseline `over <os> <s> <limit> <name>` for a step over max(floor(b * 1.3), b + 60) of its line `<os><TAB><b><TAB><name>`
# (# lines ignored). A job counts when named `shard-<os> (...)`, or `check (<os>-latest)` when the run has no shard-<os>
# job; every job counts for wall. Exit 0 (also with over lines), 2 usage, 1 `ci-times: cannot read <what>` (a missing
# run or baseline, gh failing).
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
function Usage { (Get-Content -LiteralPath $PSCommandPath)[1..2] -replace '^# ?', '' | ForEach-Object { [Console]::Error.WriteLine($_) }; exit 2 }
$base = ''; $run = ''; $a = @($Rest | Where-Object { $null -ne $_ })
for ($i = 0; $i -lt $a.Count; $i++) {
  if ($a[$i] -eq '--baseline') { if ($i + 1 -ge $a.Count) { Usage }; $base = $a[$i + 1]; $i++ }
  elseif ($a[$i] -like '-*') { Usage } elseif ($run -ne '') { Usage } else { $run = $a[$i] }
}
if ($run -eq '') { Usage }
if ($run -match '^[0-9]+$') {
  try { $raw = (& gh run view $run --json jobs 2>$null) -join "`n" } catch { $raw = '' }
  if ($LASTEXITCODE -ne 0 -or -not $raw) { "ci-times: cannot read $run"; exit 1 }
} elseif (Test-Path -LiteralPath $run -PathType Leaf) { $raw = [IO.File]::ReadAllText((Convert-Path -LiteralPath $run)) } else { "ci-times: cannot read $run"; exit 1 }
if ($base -ne '' -and -not (Test-Path -LiteralPath $base -PathType Leaf)) { "ci-times: cannot read $base"; exit 1 }
# a time stays a string (pwsh would read an ISO date as a local DateTime): its T becomes a space, read below as UTC
$raw = $raw -replace '"(\d{4}-\d\d-\d\d)T(\d\d:\d\d:\d\d)[^"]*"', '"$1 $2"'
try { $d = $raw | ConvertFrom-Json } catch { "ci-times: cannot read $run"; exit 1 }
function Sec($t) {   # "YYYY-MM-DD HH:MM:SS" as UTC seconds; $null when not set (0001-01-01) or absent
  if ("$t" -eq '' -or "$t" -like '0001-*') { return $null }
  $p = [datetime]::ParseExact("$t", 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]'AssumeUniversal, AdjustToUniversal')
  return [int64]($p - [datetime]::new(1970, 1, 1)).TotalSeconds
}
$jobs = @($d.jobs); $shard = @{}; $jos = @{}; $kind = @{}; $first = $null; $last = $null
for ($i = 0; $i -lt $jobs.Count; $i++) { $j = $jobs[$i]; $jos[$i] = ''; $kind[$i] = ''
  if ("$($j.name)" -match '^shard-(ubuntu|macos|windows) ') { $jos[$i] = $Matches[1]; $kind[$i] = 'shard'; $shard[$Matches[1]] = 1 }
  elseif ("$($j.name)" -match '^check \((ubuntu|macos|windows)-latest\)$') { $jos[$i] = $Matches[1]; $kind[$i] = 'check' }
  $s = Sec $j.startedAt; $e = Sec $j.completedAt
  if ($null -ne $s -and ($null -eq $first -or $s -lt $first)) { $first = $s }
  if ($null -ne $e -and ($null -eq $last -or $e -gt $last)) { $last = $e }
}
$sum = @{}; $ord = @{}; $tot = @{}; $counted = @{}
for ($i = 0; $i -lt $jobs.Count; $i++) { $o = $jos[$i]
  if ($o -eq '' -or ($kind[$i] -eq 'check' -and $shard.ContainsKey($o))) { continue }
  $counted[$o] = 1; if (-not $ord.ContainsKey($o)) { $ord[$o] = New-Object Collections.Generic.List[string] }
  foreach ($st in @($jobs[$i].steps)) {
    if ($null -eq $st -or "$($st.status)" -ne 'completed' -or "$($st.conclusion)" -eq 'skipped') { continue }
    $s = Sec $st.startedAt; $e = Sec $st.completedAt; if ($null -eq $s -or $null -eq $e) { continue }
    $key = "$o`t$($st.name)"; if (-not $sum.ContainsKey($key)) { $sum[$key] = [int64]0; $ord[$o].Add("$($st.name)") }
    $sum[$key] += $e - $s; $tot[$o] = [int64]$tot[$o] + ($e - $s)
  }
}
$bl = @{}
if ($base -ne '') { foreach ($l in [IO.File]::ReadAllLines((Convert-Path -LiteralPath $base))) {
  if ($l -match '^#') { continue }; $f = $l.Split("`t"); if ($f.Count -ge 3 -and $f[1] -match '^[0-9]+$') { $bl["$($f[0])`t$($f[2])"] = [int64]$f[1] } } }
$out = New-Object Collections.Generic.List[string]; $L = 'ubuntu', 'macos', 'windows'
if ($null -ne $first -and $null -ne $last) { $out.Add("wall $($last - $first)") }
foreach ($o in $L) { if ($counted.ContainsKey($o)) { $out.Add("total $o $([int64]$tot[$o])") } }
foreach ($o in $L) { if ($ord.ContainsKey($o)) { foreach ($nm in $ord[$o]) { $out.Add("step $o $($sum["$o`t$nm"]) $nm") } } }
foreach ($o in $L) { if (-not $ord.ContainsKey($o)) { continue }
  foreach ($nm in $ord[$o]) { $key = "$o`t$nm"; if (-not $bl.ContainsKey($key)) { continue }
    $b = $bl[$key]; $lim = [int64][math]::Floor($b * 13 / 10); if ($b + 60 -gt $lim) { $lim = $b + 60 }
    if ($sum[$key] -gt $lim) { $out.Add("over $o $($sum[$key]) $lim $nm") } } }
$out | ForEach-Object { $_ }
exit 0
