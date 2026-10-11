# What a Claude Code session used (Windows; macOS / Linux: session-tokens.sh - same lines, see it).
#   powershell -File scripts/session-tokens.ps1 <session-id | id prefix | transcript.jsonl>     (or: pwsh -File ...)
#   powershell -File scripts/session-tokens.ps1 -Since 2026-10-05T17:00:00Z   every session on the account, from then on (UTC)
#   powershell -File scripts/session-tokens.ps1 -Prune    delete status files older than 7 days
# One line per model and a "total" line, summed from the transcripts and their subagents, each message
# once (output is a LOWER BOUND); for one session a "cost" line from ~/.claude/coordinator/sessions/<id>.json
# (cumulative, list price). The status file's token fields are the last request's, so they are ignored.
# Exit 1 when nothing is found or a prefix is ambiguous.
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
    Get-ChildItem -LiteralPath $dir -Filter '*.json' -File | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
      ForEach-Object { $_.FullName; Remove-Item -LiteralPath $_.FullName }
  }
  exit 0
}
if ($Since -and $Since -notmatch '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d') {
  [Console]::Error.WriteLine("-Since needs YYYY-MM-DDTHH:MM:SS in UTC, got $Since"); exit 2
}
$cut = if ($Since) { $Since.Substring(0, 19) } else { '' }

# sums assistant messages per model, each message id once (its largest output count); with -Since,
# only messages whose timestamp is at or after it (compared to the second, UTC)
function CountUsage([string[]]$Files) {
  $best = @{}
  foreach ($file in $Files) {
    foreach ($line in [IO.File]::ReadLines($file)) {
      if (-not $line -or -not $line.Contains('"usage"')) { continue }
      $d = $line | ConvertFrom-Json
      if ($d.type -ne 'assistant' -or -not $d.message.usage) { continue }
      if ($cut) {
        $ts = $d.timestamp
        if ($null -eq $ts) { continue }
        # PowerShell 7 turns ISO strings into dates; 5.1 keeps the string
        if ($ts -is [datetime]) {
          if ($ts.Kind -eq [DateTimeKind]::Local) { $ts = $ts.ToUniversalTime() }
          $ts = $ts.ToString('yyyy-MM-ddTHH:mm:ss')
        } else { $ts = ([string]$ts).PadRight(19).Substring(0, 19) }
        if ([string]::CompareOrdinal($ts, $cut) -lt 0) { continue }
      }
      if ($d.message.model -eq '<synthetic>') { continue }   # the CLI's own placeholder messages, all zeros
      $u = $d.message.usage; $id = $d.message.id
      if (-not $best.ContainsKey($id) -or [long]$u.output_tokens -gt [long]$best[$id].u.output_tokens) {
        $m = if ($d.message.model) { [string]$d.message.model } else { 'unknown' }
        $best[$id] = @{ u = $u; m = $m }
      }
    }
  }
  $per = @{}; $t = [long[]]@(0, 0, 0, 0)
  foreach ($b in $best.Values) {
    $u = $b.u
    $v = [long[]]@([long]$u.input_tokens, [long]$u.output_tokens, [long]$u.cache_read_input_tokens, [long]$u.cache_creation_input_tokens)
    if (-not $per.ContainsKey($b.m)) { $per[$b.m] = [long[]]@(0, 0, 0, 0) }
    $p = $per[$b.m]
    for ($k = 0; $k -lt 4; $k++) { $p[$k] += $v[$k]; $t[$k] += $v[$k] }
  }
  $names = [string[]]@($per.Keys); [Array]::Sort($names, [StringComparer]::Ordinal)   # as LC_ALL=C sort
  foreach ($n in $names) { Line $n $per[$n] }
  Line 'total' $t
}
function Line($n, $v) { "{0}`t{1}`tin={2} out>={3} cache_read={4} cache_write={5}" -f $n, ($v[0] + $v[1] + $v[2] + $v[3]), $v[0], $v[1], $v[2], $v[3] }

if ($Since) {
  if (-not (Test-Path -LiteralPath $projects)) { [Console]::Error.WriteLine("no transcripts in $projects"); exit 1 }
  CountUsage @(Get-ChildItem -Path $projects -Filter '*.jsonl' -Recurse -File | ForEach-Object { $_.FullName })
  exit 0
}
$main = $null
if (Test-Path -LiteralPath $Session -PathType Leaf) { $main = $Session } elseif (Test-Path -LiteralPath $projects) {
  # the full id, else a unique prefix (claude --bg and claude agents print 8 characters)
  $main = Get-ChildItem -Path $projects -Filter "$Session.jsonl" -Recurse -Depth 1 -File |
    Select-Object -First 1 -ExpandProperty FullName
  if (-not $main) {
    $found = @(Get-ChildItem -Path $projects -Filter "$Session*.jsonl" -Recurse -Depth 1 -File | ForEach-Object { $_.FullName })
    if ($found.Count -gt 1) {
      # ids only: the folder names would show other projects
      $ids = [string[]]@($found | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) }); [Array]::Sort($ids, [StringComparer]::Ordinal)
      [Console]::Error.WriteLine("ambiguous id ${Session}:"); foreach ($x in $ids) { [Console]::Error.WriteLine($x) }; exit 1
    }
    if ($found.Count -eq 1) { $main = $found[0] }
  }
}
if ($main) { $sid = [IO.Path]::GetFileNameWithoutExtension($main) } else {
  $sid = $Session
  if (Test-Path -LiteralPath $dir) {
    $f = Get-ChildItem -LiteralPath $dir -Filter "$Session*.json" -File | Select-Object -First 1
    if ($f) { $sid = $f.BaseName }
  }
}
$status = Join-Path $dir "$sid.json"
if ($main) {
  $files = @($main)
  $sub = Join-Path ($main -replace '\.jsonl$', '') 'subagents'
  if (Test-Path $sub) { $files += Get-ChildItem -Path $sub -Filter '*.jsonl' -File | ForEach-Object { $_.FullName } }
  CountUsage $files
} elseif (-not (Test-Path -LiteralPath $status)) { [Console]::Error.WriteLine("no transcript or status file for $Session"); exit 1 }
if (Test-Path -LiteralPath $status) {
  $c = (Get-Content -Raw -LiteralPath $status | ConvertFrom-Json).cost.total_cost_usd
  if ($null -ne $c) { "cost`t`${0:0.0000}" -f [double]$c }
}
