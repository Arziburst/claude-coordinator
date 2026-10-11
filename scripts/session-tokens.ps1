# Tokens a Claude Code session used (Windows; macOS / Linux: session-tokens.sh - same lines, see it).
#   powershell -File scripts/session-tokens.ps1 <session-id | transcript.jsonl>     (or: pwsh -File ...)
# "status" line: the CLI's own totals from ~/.claude/coordinator/sessions/<id>.json (preferred).
# "transcript" line: summed from the transcript and its subagents; output is a LOWER BOUND.
# Exit 1 when neither exists.
param([string]$Session)
if (-not $Session) { Get-Content -LiteralPath $PSCommandPath -TotalCount 5 | ForEach-Object { $_ -replace '^# ?', '' }; exit 2 }
$ErrorActionPreference = 'Stop'
$cfg = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }   # Claude Code's override
# numbers as RUNS.tsv expects them (1.23, not 1,23 on a Russian or German Windows)
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture
if (Test-Path -LiteralPath $Session -PathType Leaf) { $main = $Session } else {
  $main = Get-ChildItem -Path (Join-Path $cfg 'projects') -Filter "$Session.jsonl" -Recurse -Depth 1 -File |
    Select-Object -First 1 -ExpandProperty FullName
}
$sid = if ($main) { [IO.Path]::GetFileNameWithoutExtension($main) } else { $Session }
$status = Join-Path $cfg "coordinator/sessions/$sid.json"
if (Test-Path $status) {
  $s = Get-Content -Raw $status | ConvertFrom-Json
  $si = $s.context_window.total_input_tokens; $so = $s.context_window.total_output_tokens
  $c = $s.cost.total_cost_usd
  function Or-Q($v) { if ($null -eq $v) { '?' } else { $v } }   # PowerShell 5 has no ??
  "status`t{0}`tin={1} out={2} cost=`${3}" -f ([long]$si + [long]$so), (Or-Q $si), (Or-Q $so), (Or-Q $c)
}
if ($main) {
  $files = @($main)
  $sub = Join-Path ($main -replace '\.jsonl$', '') 'subagents'
  if (Test-Path $sub) { $files += Get-ChildItem -Path $sub -Filter '*.jsonl' -File | ForEach-Object FullName }
  $best = @{}
  foreach ($f in $files) {
    foreach ($line in [IO.File]::ReadLines($f)) {
      if (-not $line) { continue }
      $d = $line | ConvertFrom-Json
      if ($d.type -ne 'assistant' -or -not $d.message.usage) { continue }
      $u = $d.message.usage; $id = $d.message.id
      if (-not $best.ContainsKey($id) -or [long]$u.output_tokens -gt [long]$best[$id].output_tokens) { $best[$id] = $u }
    }
  }
  $i = 0; $o = 0; $r = 0; $w = 0
  foreach ($u in $best.Values) {
    $i += [long]$u.input_tokens; $o += [long]$u.output_tokens
    $r += [long]$u.cache_read_input_tokens; $w += [long]$u.cache_creation_input_tokens
  }
  "transcript`t{0}`tin={1} out>={2} cache_read={3} cache_write={4}" -f ($i + $o + $r + $w), $i, $o, $r, $w
} elseif (-not (Test-Path $status)) { [Console]::Error.WriteLine("no transcript or status file for $Session"); exit 1 }
