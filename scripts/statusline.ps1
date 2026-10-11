# Status line for coordinator machines (Windows; macOS / Linux: statusline.sh). Prints
#   Opus 5.5 (high) · ctx 837k/1M (84%) · 5h 14% · week 92%
# — model (effort) · context used in this chat · 5-hour and weekly limits (claude.ai Pro / Max only) —
# and saves Claude Code's status JSON to ~/.claude/coordinator/statusline.json for the coordinator.
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$raw = [Console]::In.ReadToEnd()
$dir = Join-Path $HOME '.claude/coordinator'
New-Item -ItemType Directory -Force $dir | Out-Null
$tmp = Join-Path $dir ("statusline.{0}.tmp" -f $PID)
Set-Content -Path $tmp -Value $raw -Encoding utf8 -NoNewline
Move-Item -Force $tmp (Join-Path $dir 'statusline.json')
# A copy per session, so the coordinator reads each worker's own numbers (the file above is the last
# session to draw its status line, whichever that was).
if ($raw -match '"session_id"\s*:\s*"([^"]+)"') {
  $sdir = Join-Path $dir 'sessions'; New-Item -ItemType Directory -Force $sdir | Out-Null
  Set-Content -Path (Join-Path $sdir ($Matches[1] + '.json')) -Value $raw -Encoding utf8 -NoNewline
}

try { $j = $raw | ConvertFrom-Json } catch { 'Claude'; exit 0 }

function Format-Tokens([double]$n) {
	if ($n -ge 1e6) { '{0}M' -f ([math]::Floor($n / 1e5) / 10) } elseif ($n -ge 1e3) { '{0}k' -f [math]::Floor($n / 1e3) } else { "$n" }
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
if ($rl.five_hour) { $parts += ('5h {0}%' -f [math]::Floor([double]$rl.five_hour.used_percentage)) }
if ($rl.seven_day) { $parts += ('week {0}%' -f [math]::Floor([double]$rl.seven_day.used_percentage)) }

$parts -join " $([char]0x00B7) "
