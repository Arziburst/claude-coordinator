# What a Claude Code session used (Windows; macOS / Linux: session-tokens.sh - same lines, see it).
#   powershell -File scripts/session-tokens.ps1 <session-id | id prefix | a subagent's agentId | transcript.jsonl>   (or: pwsh -File ...)
#   powershell -File scripts/session-tokens.ps1 -Since 2026-10-05T17:00:00Z   every session on the account, from then on (UTC; or Unix seconds as resets_at)
#   powershell -File scripts/session-tokens.ps1 -Prune    delete status files older than 7 days
# One line per model and a "total" line, summed from the transcripts and their subagents, each message
# once (output is a LOWER BOUND); for one session (not a subagent) a "cost" line from ~/.claude/coordinator/sessions/<id>.json
# (cumulative, list price). The status file's token fields are the last request's, so they are ignored.
# Exit 1 when nothing is found or a prefix is ambiguous, 2 on a usage error. Reads the JSON as text, as the .sh.
param([string]$Session, [string]$Since, [switch]$Prune)
if (-not $Session -and -not $Since -and -not $Prune) {
  Get-Content -LiteralPath $PSCommandPath -TotalCount 8 | ForEach-Object { $_ -replace '^# ?', '' }; exit 2
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
        # the record timestamp, outside "message": the first on the line when it comes before
        # "message" (Claude Code 2.1.296 writes it there), else the last; a tool input inside the
        # message may carry others
        $f = $reTime.Match($line)
        if (-not $f.Success) { continue }
        $p = $line.IndexOf('"message":', $O)
        if ($p -ge 0 -and $f.Index -lt $p) { $ts = $f.Groups[1].Value } else {
          $a = $line.LastIndexOf('"timestamp":"', $O); $e = if ($a -ge 0) { $line.IndexOf('"', $a + 13) } else { -1 }
          if ($a -ge 0 -and $e -ge 0 -and $line.LastIndexOf('"timestamp":', $O) -eq $a) { $ts = $line.Substring($a + 13, $e - $a - 13) }
          else { $all = $reTime.Matches($line); $ts = $all[$all.Count - 1].Groups[1].Value }
        }
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
