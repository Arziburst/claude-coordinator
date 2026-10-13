# What a Claude Code session used (Windows; macOS / Linux: session-tokens.sh - same lines, see it).
#   powershell -File scripts/session-tokens.ps1 <session-id | id prefix | a subagent's agentId | transcript.jsonl>   (or: pwsh -File ...)
#   powershell -File scripts/session-tokens.ps1 -Since 2026-10-05T17:00:00Z   every session on the account, from then on (UTC; or Unix seconds as resets_at)
#   powershell -File scripts/session-tokens.ps1 -Prune    delete status files older than 7 days, the status line's statusline.*.tmp older than an hour
# One line per model and a "total" line, summed from the transcripts and their subagents, each message
# once (output is a LOWER BOUND); for one session (not a subagent) a "cost" line from ~/.claude/coordinator/sessions/<id>.json
# (cumulative, list price). The status file's token fields are the last request's, so they are ignored.
# Last, for one session or subagent: "time wall=<m>m active=<m>m start=<UTC> end=<UTC>" from the records' timestamps
# (the transcript and its subagents' as one set; active leaves out every gap over 5 minutes, but a gap inside a tool call
# is work up to 30 minutes and one inside only a question to a person, a tool named *AskUserQuestion, is idle at any
# length; minutes rounded, a half up).
# Exit 1 when nothing is found or a prefix is ambiguous, 2 on a usage error. Reads the JSON as text, as the .sh.
param([string]$Session, [string]$Since, [switch]$Prune)
# native output (git, bash) is read and this script's own output written as UTF-8, whatever the console's
# code page (cp866 on a Russian Windows garbles a non-ASCII path or a section sign); no console: left as is.
# The caller's console gets its own encoding back on every way out (the end, any exit N, a terminating
# error): the body below runs inside try, the encoding is restored in finally.
$enc0 = $null; try { $enc0 = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
try {
if (-not $Session -and -not $Since -and -not $Prune) {
  Get-Content -LiteralPath $PSCommandPath -TotalCount 12 | ForEach-Object { $_ -replace '^# ?', '' }; exit 2
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
  # the status line's temp file older than an hour, left when it was killed between writing and moving it
  $co = Join-Path $cfg 'coordinator'
  if (Test-Path -LiteralPath $co) {
    Get-ChildItem -LiteralPath $co -Filter 'statusline.*.tmp' -File | Where-Object { $_.Name -like 'statusline.*.tmp' -and $_.LastWriteTime -lt (Get-Date).AddHours(-1) } |
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
# over every file as one set, sorted; wall = last - first, active = wall minus the idle gaps: a gap
# inside a tool call (from a tool_use to its own tool_result, matched by id: the id's first tool_use
# record to its last record naming it in tool_use_id) is work up to 30 minutes, the rest idle; a gap
# inside only a call of a tool that asks a person (a name ending in AskUserQuestion) is idle at any
# length; any other gap over 5 minutes is idle. Minutes rounded to the nearest, a half up; nothing when
# no record has a timestamp
$reStamp = [regex]'^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(?:[.]([0-9]+))?'
$reUse = [regex]'"type":[ \t]*"tool_use",[ \t]*"id":[ \t]*("[^"]*")(,[ \t]*"name":[ \t]*"[^"]*AskUserQuestion")?'
$reResult = [regex]'"tool_use_id":[ \t]*("[^"]*")'
function Span([string[]]$Files) {
  $t = New-Object 'System.Collections.Generic.List[long]'; $first = [long]::MaxValue; $last = [long]::MinValue; $start = ''; $end = ''
  $use = New-Object 'System.Collections.Generic.Dictionary[string,long]' ([StringComparer]::Ordinal)
  $res = New-Object 'System.Collections.Generic.Dictionary[string,long]' ([StringComparer]::Ordinal)
  $ask = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
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
      # the tool calls this record starts (parallel ones too) and the results it carries
      if ($line.Contains('"tool_use"')) {
        foreach ($u in $reUse.Matches($line)) {
          $id = $u.Groups[1].Value; if (-not $use.ContainsKey($id) -or $ms -lt $use[$id]) { $use[$id] = $ms }
          if ($u.Groups[2].Success) { [void]$ask.Add($id) }   # a tool that asks a person
        }
      }
      if ($line.Contains('"tool_use_id"')) {
        foreach ($u in $reResult.Matches($line)) { $id = $u.Groups[1].Value; if (-not $res.ContainsKey($id) -or $ms -gt $res[$id]) { $res[$id] = $ms } }
      }
    }
  }
  if (-not $t.Count) { return }
  # the calls' starts and ends, each sorted, work ($cs, $ce) and questions to a person ($qs, $qe) apart;
  # a gap from $t[k-1] to $t[k] is inside a call when more of them started than ended at or before
  # $t[k-1] (every start and end is itself a record's time)
  $cs = New-Object 'System.Collections.Generic.List[long]'; $ce = New-Object 'System.Collections.Generic.List[long]'
  $qs = New-Object 'System.Collections.Generic.List[long]'; $qe = New-Object 'System.Collections.Generic.List[long]'
  foreach ($id in $use.Keys) {
    if ($res.ContainsKey($id) -and $res[$id] -gt $use[$id]) {
      if ($ask.Contains($id)) { $qs.Add($use[$id]); $qe.Add($res[$id]) } else { $cs.Add($use[$id]); $ce.Add($res[$id]) }
    }
  }
  $cs.Sort(); $ce.Sort(); $qs.Sort(); $qe.Sort(); $si = 0; $ei = 0; $qi = 0; $qj = 0
  $t.Sort(); $idle = [long]0
  for ($k = 1; $k -lt $t.Count; $k++) {
    $p = $t[$k - 1]
    while ($si -lt $cs.Count -and $cs[$si] -le $p) { $si++ }
    while ($ei -lt $ce.Count -and $ce[$ei] -le $p) { $ei++ }
    while ($qi -lt $qs.Count -and $qs[$qi] -le $p) { $qi++ }
    while ($qj -lt $qe.Count -and $qe[$qj] -le $p) { $qj++ }
    $gap = $t[$k] - $p
    if ($si -gt $ei) { if ($gap -gt 1800000) { $idle += $gap - 1800000 } }   # a tool call: work, up to 30 minutes a gap
    elseif ($qi -gt $qj) { $idle += $gap }                                   # waiting for the owner, at any length
    elseif ($gap -gt 300000) { $idle += $gap }                               # over 5 minutes, no call: nobody worked
  }
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
