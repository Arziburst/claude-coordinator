# Status line for coordinator machines (Windows; macOS / Linux: statusline.sh). Prints
#   Opus 5.5 (high) . ctx 837k/1M (84%) . 5h 14% . week 92%   (the separator is U+00B7, a middle dot)
# - model (effort) | context used in this chat | 5-hour and weekly limits (claude.ai Pro / Max only) -
# and saves Claude Code's status JSON to ~/.claude/coordinator/statusline.json for the coordinator.
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$raw = [Console]::In.ReadToEnd()
$i = $raw.IndexOf('{'); if ($i -gt 0) { $raw = $raw.Substring($i) }   # a BOM before the JSON breaks it
$dir = Join-Path $(if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }) 'coordinator'
New-Item -ItemType Directory -Force $dir | Out-Null
# Each file is written to a temp file and moved over, so a reader never sees half a file - nor an empty
# one: Set-Content on the file itself empties it first, and a write that then fails (another status
# line holds it: Claude Code draws several at once) left it empty. Move-Item -Force deletes the target,
# then moves: another status line moving its own copy in between, or a reader holding the file open,
# fails the move. Three tries 20 ms apart, then the old file stays for this tick (a move fails only
# when another run's copy is there, so the first write always leaves one); the temp file is removed
# whatever happened (one left by a kill mid-write is deleted by session-tokens -Prune after an hour).
function Save([string]$path) {
  $tmp = Join-Path $dir ("statusline.{0}.tmp" -f $PID)
  try {
    Set-Content -LiteralPath $tmp -Value $raw -Encoding utf8 -NoNewline -ErrorAction Stop
    for ($n = 0; $n -lt 3; $n++) {
      try { Move-Item -Force -LiteralPath $tmp -Destination $path -ErrorAction Stop; break }
      catch { if ($n -lt 2) { Start-Sleep -Milliseconds 20 } }
    }
  } catch { } finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -Force -LiteralPath $tmp } }
}
Save (Join-Path $dir 'statusline.json')
# A copy per session, so the coordinator reads each worker's own numbers (the file above is the last
# session to draw its status line, whichever that was).
if ($raw -match '"session_id"\s*:\s*"([^"]+)"') {
  $sdir = Join-Path $dir 'sessions'; New-Item -ItemType Directory -Force $sdir | Out-Null
  Save (Join-Path $sdir ($Matches[1] + '.json'))
}

try { $j = $raw | ConvertFrom-Json } catch { 'Claude'; exit 0 }

# Invariant culture: 1.2M, not 1,2M on a German or Russian Windows.
$inv = [Globalization.CultureInfo]::InvariantCulture
function Format-Tokens([double]$n) {
	if ($n -ge 1e6) { ([math]::Floor($n / 1e5) / 10).ToString($inv) + 'M' } elseif ($n -ge 1e3) { [math]::Floor($n / 1e3).ToString($inv) + 'k' } else { [math]::Floor($n).ToString($inv) }
}

$parts = @()

$model = if ($j.model.display_name) { "$($j.model.display_name)" } else { 'Claude' }
if ($j.effort.level) { $model += " ($($j.effort.level))" }
$parts += $model

$cw = $j.context_window
if ($cw -and $null -ne $cw.used_percentage) {
	$u = $cw.current_usage
	$used = [double]$u.input_tokens + [double]$u.cache_read_input_tokens + [double]$u.cache_creation_input_tokens
	$parts += ('ctx {0}/{1} ({2}%)' -f (Format-Tokens $used), (Format-Tokens $cw.context_window_size), [math]::Floor([double]$cw.used_percentage))
}

$rl = $j.rate_limits
if ($rl.five_hour -and $null -ne $rl.five_hour.used_percentage) { $parts += ('5h {0}%' -f [math]::Floor([double]$rl.five_hour.used_percentage)) }
if ($rl.seven_day -and $null -ne $rl.seven_day.used_percentage) { $parts += ('week {0}%' -f [math]::Floor([double]$rl.seven_day.used_percentage)) }

$parts -join " $([char]0x00B7) "
