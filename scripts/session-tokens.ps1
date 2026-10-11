# Tokens a Claude Code session used, read from its transcript (Windows; macOS / Linux: session-tokens.sh).
#   pwsh -File scripts/session-tokens.ps1 <session-id | transcript.jsonl>
# Prints one line for RUNS.tsv (CORE §7):  <total>  in=<n> out=<n> cache_read=<n> cache_write=<n>
# Sums every assistant message once (a message spans several transcript lines with the same usage),
# including the session's own subagents (<session>/subagents/*.jsonl).
param([Parameter(Mandatory)][string]$Session)
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $Session -PathType Leaf) { $main = $Session } else {
  $main = Get-ChildItem -Path (Join-Path $HOME '.claude/projects') -Filter "$Session.jsonl" -Recurse -Depth 1 -File |
    Select-Object -First 1 -ExpandProperty FullName
  if (-not $main) { Write-Error "no transcript for $Session under ~/.claude/projects"; exit 1 }
}
$files = @($main)
$sub = Join-Path ($main -replace '\.jsonl$', '') 'subagents'
if (Test-Path $sub) { $files += Get-ChildItem -Path $sub -Filter '*.jsonl' -File | ForEach-Object FullName }
$seen = @{}; $i = 0; $o = 0; $r = 0; $w = 0
foreach ($f in $files) {
  foreach ($line in [IO.File]::ReadLines($f)) {
    if (-not $line) { continue }
    $d = $line | ConvertFrom-Json
    if ($d.type -ne 'assistant' -or -not $d.message.usage) { continue }
    if ($seen.ContainsKey($d.message.id)) { continue }
    $seen[$d.message.id] = $true; $u = $d.message.usage
    $i += [long]$u.input_tokens; $o += [long]$u.output_tokens
    $r += [long]$u.cache_read_input_tokens; $w += [long]$u.cache_creation_input_tokens
  }
}
"{0}`tin={1} out={2} cache_read={3} cache_write={4}" -f ($i + $o + $r + $w), $i, $o, $r, $w
