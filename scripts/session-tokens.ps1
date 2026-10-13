# What a Claude Code session used (Windows; macOS / Linux: session-tokens.sh - same lines, see it).
#   powershell -File scripts/session-tokens.ps1 <session-id | id prefix | a subagent's agentId | transcript.jsonl>   (or: pwsh -File ...)
#   powershell -File scripts/session-tokens.ps1 -Since 2026-10-05T17:00:00Z   every session on the account, from then on (UTC; or Unix seconds as resets_at)
#   powershell -File scripts/session-tokens.ps1 -Prune    delete status files older than 7 days
# One line per model and a "total" line, summed from the transcripts and their subagents, each message
# once (output is a LOWER BOUND); for one session (not a subagent) a "cost" line from ~/.claude/coordinator/sessions/<id>.json
# (cumulative, list price). The status file's token fields are the last request's, so they are ignored.
# Last, for one session or subagent: "time wall=<m>m active=<m>m start=<UTC> end=<UTC>" from the records' timestamps
# (the transcript and its subagents' as one set; active leaves out every gap over 5 minutes; minutes rounded, a half up).
# Exit 1 when nothing is found or a prefix is ambiguous, 2 on a usage error. Reads the JSON as text, as the .sh.
param([string]$Session, [string]$Since, [switch]$Prune)
# native output (git, bash) is read and this script's own output written as UTF-8, whatever the console's
# code page (cp866 on a Russian Windows garbles a non-ASCII path or a section sign); no console: left as is.
# The caller's console gets its own encoding back on every way out (the end, any exit N, a terminating
# error): the body below runs inside try, the encoding is restored in finally.
$enc0 = $null; try { $enc0 = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
try {
if (-not $Session -and -not $Since -and -not $Prune) {
  Get-Content -LiteralPath $PSCommandPath -TotalCount 10 | ForEach-Object { $_ -replace '^# ?', '' }; exit 2
}
$ErrorActionPreference = 'Stop'
$cfg = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }   # Claude Code's override
$dir = Join-Path $cfg 'coordinator/sessions'
$projects = Join-Path $cfg 'projects'
# numbers as RUNS.tsv expects them (1.23, not 1,23 on a Russian or German Windows)
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture
if ($Prune) {
  if (Test-Path -LiteralPath $dir) {
    # older than exactly 7 x 24 hours, as the .sh
    Get-ChildItem -LiteralPath $dir -Filter '*.json' -File | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
      ForEach-Object { $_.FullName; Remove-Item -LiteralPath $_.FullName }
  }
  exit 0
}
$cut = ''
if ($Since) {
  $bad = "-Since needs YYYY-MM-DDTHH:MM:SS in UTC (Z or nothing after it) or Unix seconds, got $Since"
  if ($Since -cmatch '^[0-9]+\z') {
    # Unix seconds (the status line's resets_at)
    if ($Since.Length -gt 10) { [Console]::Error.WriteLine($bad); exit 2 }
    $cut = [DateTimeOffset]::FromUnixTimeSeconds([long]$Since).UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ss')
  } elseif ($Since -cmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]+)?Z?\z') {   # no other offset
    $cut = $Since.Substring(0, 19)
  } else { [Console]::Error.WriteLine($bad); exit 2 }
}

# sums assistant messages per model, each message id once (its largest output count); with -Since,
# only messages whose timestamp is at or after it (compared to the second, UTC). Each line is read as
# text with the .sh's patterns, not parsed: a tool input may hold keys that differ only by case, which
# ConvertFrom-Json refuses, and the record's fields must be found where the .sh finds them.
# A regex scan of a whole long line is slow under PowerShell 7, so the loop looks for the compact form
# ("key":value) with plain searches first, and uses the regex only when the key also appears in another
# form - which gives the regex's own answer.
$O = [StringComparison]::Ordinal
$reAssistant = [regex]'"type":[ \t]*"assistant"'
$reUsage = [regex]'"usage":[ \t]*[{]'
$reTime = [regex]'"timestamp":[ \t]*"([^"]*)"'
$reId = [regex]'"id":[ \t]*"(msg_[^"]*)"'
$reModel = [regex]'"model":[ \t]*"([^"]*)"'
$reNum = @('input_tokens', 'output_tokens', 'cache_read_input_tokens', 'cache_creation_input_tokens') |
  ForEach-Object { [regex]('"' + $_ + '":[ \t]*([0-9]+)') }
# the record's own timestamp, outside "message": the first on the line when it comes before "message"
# (Claude Code 2.1.296 writes it there), else the last; a tool input inside the message may carry
# others. $null when the line has none. The compact form is read with plain searches, any other with
# the regex, which gives the .sh's answer either way.
function RecTime([string]$line) {
  $i = $line.IndexOf('"timestamp":', $O); if ($i -lt 0) { return $null }
  $p = $line.IndexOf('"message":', $O)
  if ($p -ge 0) {
    $fi = -1; $fv = $null; $e = if ($line.Length -gt $i + 12 -and $line[$i + 12] -eq '"') { $line.IndexOf('"', $i + 13) } else { -1 }
    if ($e -ge 0) { $fi = $i; $fv = $line.Substring($i + 13, $e - $i - 13) }
    else { $f = $reTime.Match($line); if ($f.Success) { $fi = $f.Index; $fv = $f.Groups[1].Value } }
    if ($fi -ge 0 -and $fi -lt $p) { return $fv }
  }
  $a = $line.LastIndexOf('"timestamp":"', $O); $e = if ($a -ge 0) { $line.IndexOf('"', $a + 13) } else { -1 }
  if ($a -ge 0 -and $e -ge 0 -and $line.LastIndexOf('"timestamp":', $O) -eq $a) { return $line.Substring($a + 13, $e - $a - 13) }
  $all = $reTime.Matches($line); if ($all.Count) { return $all[$all.Count - 1].Groups[1].Value }
  $null
}
# days since 1970-01-01 of a date (the civil calendar), the .sh's arithmetic
function Days([long]$y, [long]$m, [long]$d) {
  if ($m -le 2) { $y-- }
  $e = [Math]::Floor($y / 400); $yoe = $y - $e * 400
  $mp = if ($m -gt 2) { $m - 3 } else { $m + 9 }
  [long]($e * 146097 + $yoe * 365 + [Math]::Floor($yoe / 4) - [Math]::Floor($yoe / 100) + [Math]::Floor((153 * $mp + 2) / 5) + $d - 1 - 719468)
}
# the time line: each record's own timestamp (YYYY-MM-DDTHH:MM:SS[.fff], read as UTC) in milliseconds,
# over every file as one set, sorted; wall = last - first, active = wall minus every gap over 5 minutes;
# minutes rounded to the nearest, a half up; nothing when no record has a timestamp
$reStamp = [regex]'^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(?:[.]([0-9]+))?'
function Span([string[]]$Files) {
  $t = New-Object 'System.Collections.Generic.List[long]'; $first = [long]::MaxValue; $last = [long]::MinValue; $start = ''; $end = ''
  foreach ($file in $Files) {
    foreach ($line in [IO.File]::ReadLines($file)) {
      if (-not $line) { continue }
      $ts = RecTime $line; if (-not $ts) { continue }
      $m = $reStamp.Match($ts); if (-not $m.Success) { continue }
      $n = $m.Groups
      $ms = ((((Days $n[1].Value $n[2].Value $n[3].Value) * 24 + [long]$n[4].Value) * 60 + [long]$n[5].Value) * 60 + [long]$n[6].Value) * 1000 + [long](($n[7].Value + '000').Substring(0, 3))
      $t.Add($ms)
      if ($ms -lt $first) { $first = $ms; $start = $ts.Substring(0, 19) }
      if ($ms -gt $last) { $last = $ms; $end = $ts.Substring(0, 19) }
    }
  }
  if (-not $t.Count) { return }
  $t.Sort(); $idle = [long]0
  for ($k = 1; $k -lt $t.Count; $k++) { $gap = $t[$k] - $t[$k - 1]; if ($gap -gt 300000) { $idle += $gap } }   # nobody worked
  $wall = $last - $first
  "time`twall={0}m active={1}m start={2}Z end={3}Z" -f [long][Math]::Floor(($wall + 30000) / 60000), [long][Math]::Floor(($wall - $idle + 30000) / 60000), $start, $end
}
function CountUsage([string[]]$Files) {
  $best = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
  foreach ($file in $Files) {
    foreach ($line in [IO.File]::ReadLines($file)) {
      if (-not $line -or -not $line.Contains('"assistant"') -or -not $line.Contains('"usage"')) { continue }
      if (-not $line.Contains('"type":"assistant"') -and -not $reAssistant.IsMatch($line)) { continue }
      # the message usage is the last on the line (a tool input in its content may hold another)
      $iu = $line.LastIndexOf('"usage":{', $O)
      if ($line.LastIndexOf('"usage":', $O) -ne $iu) { $all = $reUsage.Matches($line); $iu = if ($all.Count) { $all[$all.Count - 1].Index } else { -1 } }
      if ($iu -lt 0) { continue }
      if ($cut) {
        $ts = RecTime $line
        if ($null -eq $ts) { continue }
        if ($ts.Length -gt 19) { $ts = $ts.Substring(0, 19) }
        if ([string]::CompareOrdinal($ts, $cut) -lt 0) { continue }
      }
      $g = $reId.Match($line); if (-not $g.Success) { continue }
      $id = $g.Groups[1].Value
      $m = 'unknown'; $g = $reModel.Match($line); if ($g.Success) { $m = $g.Groups[1].Value }
      if ($m -ceq '<synthetic>') { continue }   # the CLI's own placeholder messages, all zeros
      $u = $line.Substring($iu); $v = [long[]]@(0, 0, 0, 0)
      for ($k = 0; $k -lt 4; $k++) { $g = $reNum[$k].Match($u); if ($g.Success) { $v[$k] = [long]$g.Groups[1].Value } }
      if (-not $best.ContainsKey($id) -or $v[1] -gt $best[$id].v[1]) { $best[$id] = @{ m = $m; v = $v } }
    }
  }
  $per = New-Object 'System.Collections.Generic.Dictionary[string,long[]]' ([StringComparer]::Ordinal)
  $t = [long[]]@(0, 0, 0, 0)
  foreach ($b in $best.Values) {
    if (-not $per.ContainsKey($b.m)) { $per[$b.m] = [long[]]@(0, 0, 0, 0) }
    $p = $per[$b.m]
    for ($k = 0; $k -lt 4; $k++) { $p[$k] += $b.v[$k]; $t[$k] += $b.v[$k] }
  }
  $names = [string[]]@($per.Keys); [Array]::Sort($names, [StringComparer]::Ordinal)   # as LC_ALL=C sort
  foreach ($n in $names) { Line $n $per[$n] }
  Line 'total' $t
}
function Line($n, $v) { "{0}`t{1}`tin={2} out>={3} cache_read={4} cache_write={5}" -f $n, ($v[0] + $v[1] + $v[2] + $v[3]), $v[0], $v[1], $v[2], $v[3] }

if ($Since) {
  if (-not (Test-Path -LiteralPath $projects)) { [Console]::Error.WriteLine("no transcripts in $projects"); exit 1 }
  CountUsage @(Get-ChildItem -LiteralPath $projects -Filter '*.jsonl' -Recurse -File | ForEach-Object { $_.FullName })
  exit 0
}
$main = $null
if (Test-Path -LiteralPath $Session -PathType Leaf) { $main = $Session } elseif (Test-Path -LiteralPath $projects) {
  # the full id, else a unique prefix (claude --bg and claude agents print 8 characters)
  $main = Get-ChildItem -LiteralPath $projects -Filter "$Session.jsonl" -Recurse -Depth 1 -File |
    Select-Object -First 1 -ExpandProperty FullName
  if (-not $main) {
    $found = @(Get-ChildItem -LiteralPath $projects -Filter "$Session*.jsonl" -Recurse -Depth 1 -File | ForEach-Object { $_.FullName })
    if ($found.Count -gt 1) {
      # ids only: the folder names would show other projects
      $ids = [string[]]@($found | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) }); [Array]::Sort($ids, [StringComparer]::Ordinal)
      [Console]::Error.WriteLine("ambiguous id ${Session}:"); foreach ($x in $ids) { [Console]::Error.WriteLine($x) }; exit 1
    }
    if ($found.Count -eq 1) { $main = $found[0] }
  }
  if (-not $main) {
    # a subagent's agentId (the Agent tool's result): its transcript sits in its parent's subagents/ folder
    $found = @(Get-ChildItem -LiteralPath $projects -Filter "agent-$Session*.jsonl" -Recurse -Depth 3 -File |
      Where-Object { $_.Directory.Name -eq 'subagents' -and $_.Directory.Parent.Parent.Parent.FullName -eq (Get-Item -LiteralPath $projects).FullName } |
      ForEach-Object { $_.FullName })
    if ($found.Count -gt 1) {
      $ids = [string[]]@($found | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) -replace '^agent-', '' }); [Array]::Sort($ids, [StringComparer]::Ordinal)
      [Console]::Error.WriteLine("ambiguous id ${Session}:"); foreach ($x in $ids) { [Console]::Error.WriteLine($x) }; exit 1
    }
    if ($found.Count -eq 1) { $main = $found[0] }
  }
}
$sid = $Session
if ($main) { $sid = [IO.Path]::GetFileNameWithoutExtension($main) }
elseif (-not (Test-Path -LiteralPath (Join-Path $dir "$Session.json") -PathType Leaf) -and (Test-Path -LiteralPath $dir)) {
  # no transcript: a status file by a unique prefix
  $found = @(Get-ChildItem -LiteralPath $dir -Filter "$Session*.json" -File | ForEach-Object { $_.BaseName })
  if ($found.Count -gt 1) {
    $ids = [string[]]$found; [Array]::Sort($ids, [StringComparer]::Ordinal)
    [Console]::Error.WriteLine("ambiguous id ${Session}:"); foreach ($x in $ids) { [Console]::Error.WriteLine($x) }; exit 1
  }
  if ($found.Count -eq 1) { $sid = $found[0] }
}
$status = Join-Path $dir "$sid.json"
if ($main) {
  $files = @($main)
  $sub = Join-Path ($main -replace '\.jsonl$', '') 'subagents'
  if (Test-Path -LiteralPath $sub) { $files += Get-ChildItem -LiteralPath $sub -Filter '*.jsonl' -File | ForEach-Object { $_.FullName } }
  CountUsage $files
} elseif (-not (Test-Path -LiteralPath $status)) { [Console]::Error.WriteLine("no transcript or status file for $Session"); exit 1 }
if (Test-Path -LiteralPath $status) {
  $c = (Get-Content -Raw -LiteralPath $status | ConvertFrom-Json).cost.total_cost_usd
  if ($null -ne $c) { "cost`t`${0:0.0000}" -f [double]$c }
}
if ($main) { Span $files }
} finally { if ($enc0) { try { [Console]::OutputEncoding = $enc0 } catch { } } }
