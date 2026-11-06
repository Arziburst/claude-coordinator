# Status line for coordinator machines (Windows; macOS / Linux: statusline.sh). Prints bars with their text inside
#   Opus 5.5 high . 837k/1M 83% . 5h limit 14% . week 92% . reset 50% . #449 W 7/12$   (the separator is U+00B7, a middle dot)
# - model effort, context used against the threshold set | 5-hour and weekly limits (claude.ai Pro / Max only); in a
# coordinator's session also a newer core and the tasks at work - and saves Claude Code's status JSON to
# ~/.claude/coordinator/statusline.json for the coordinator.
#   statusline.ps1 -Install    copies this script to <config>/coordinator/statusline/, unless the same or a newer version is there
#   statusline.ps1 -SessionStart    a coordinator's SessionStart hook: records the window this session starts with (TOOLKIT *Usage*)
# statusline-version: 5
param([switch]$Install, [switch]$SessionStart)
$ErrorActionPreference = 'SilentlyContinue'
function Get-ScriptVersion([string]$f) {
  $m = Select-String -LiteralPath $f -Pattern '^# statusline-version: (\d+)\s*$' | Select-Object -First 1
  if ($m) { [long]$m.Matches[0].Groups[1].Value } else { -1 }
}
$cfg = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
if ($Install) {
  $to = Join-Path (Join-Path $cfg 'coordinator') 'statusline'; $copy = Join-Path $to (Split-Path -Leaf $PSCommandPath)
  if ((Get-ScriptVersion $copy) -lt (Get-ScriptVersion $PSCommandPath)) {
    $null = [IO.Directory]::CreateDirectory($to); [IO.File]::Copy($PSCommandPath, $copy, $true)
  }
  exit 0
}
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$raw = [Console]::In.ReadToEnd()
$i = $raw.IndexOf('{'); if ($i -gt 0) { $raw = $raw.Substring($i) }   # a BOM before the JSON breaks it
$dir = Join-Path $cfg 'coordinator'
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
if (-not $SessionStart) {
  Save (Join-Path $dir 'statusline.json')
  # A copy per session, so the coordinator reads each worker's own numbers (the file above is the last
  # session to draw its status line, whichever that was).
  if ($raw -match '"session_id"\s*:\s*"([^"]+)"') {
    $sdir = Join-Path $dir 'sessions'; New-Item -ItemType Directory -Force $sdir | Out-Null
    Save (Join-Path $sdir ($Matches[1] + '.json'))
  }
}

try { $j = $raw | ConvertFrom-Json } catch { if ($SessionStart) { exit 0 }; 'Claude'; exit 0 }

# Invariant culture: 1.2M, not 1,2M on a German or Russian Windows.
$inv = [Globalization.CultureInfo]::InvariantCulture
function Format-Tokens([double]$n) {
	if ($n -ge 1e6) { ([math]::Floor($n / 1e5) / 10).ToString($inv) + 'M' } elseif ($n -ge 1e3) { [math]::Floor($n / 1e3).ToString($inv) + 'k' } else { [math]::Floor($n).ToString($inv) }
}
# The nearest whole number, a half up: the same in the .sh's jq ([math]::Round rounds a half to even).
function Get-Nearest([double]$x) { [math]::Floor($x + 0.5) }

$root = if ($j.workspace.project_dir) { "$($j.workspace.project_dir)" } else { "$($j.cwd)" }
if ($SessionStart -and $env:CLAUDE_PROJECT_DIR) { $root = $env:CLAUDE_PROJECT_DIR }
$isCoordinator = "$($j.session_name)" -cmatch 'Coordinator'
# The core's public home (the same value as README, procedures/CORE-FINDINGS.md): this copy lives outside any repository.
$coreUrl = 'https://github.com/Arziburst/claude-coordinator'

# The threshold actually set: local project settings, project settings, the account's; else the model's window.
function Get-Threshold($fallback) {
	$files = @()
	if ($root) { $files += (Join-Path $root '.claude/settings.local.json'), (Join-Path $root '.claude/settings.json') }
	$files += Join-Path (Split-Path $dir -Parent) 'settings.json'
	foreach ($f in $files) {
		if (-not (Test-Path -LiteralPath $f)) { continue }
		try { $v = (Get-Content -LiteralPath $f -Raw | ConvertFrom-Json).autoCompactWindow; if ($v -is [ValueType] -and $v -isnot [bool] -and [double]$v -gt 0) { return [double]$v } } catch { }
	}
	return [double]$fallback
}

# A session keeps the window it started with (measured, #499): a process's start reads the file, a start and a resume;
# an edit, /clear and a compaction do not. So only those two write the record, and /clear, which changes the id, leaves none.
$set = Get-Threshold 0
$windowText = if ($set -gt 0) { $set.ToString($inv) } else { '' }
$sid = "$($j.session_id)"
$windows = Join-Path $dir 'windows'
if ($SessionStart) {
	if ($sid -cmatch '^[0-9a-zA-Z-]+$' -and "$($j.source)" -cin 'startup', 'resume') {
		$null = [IO.Directory]::CreateDirectory($windows)
		$rec = Join-Path $windows $sid; $tmp = "$rec.$PID"
		[IO.File]::WriteAllText($tmp, $windowText)
		Move-Item -Force -LiteralPath $tmp -Destination $rec
		if (Test-Path -LiteralPath $tmp) { Remove-Item -Force -LiteralPath $tmp }
		Get-ChildItem -LiteralPath $windows -File | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | Remove-Item -Force
	}
	exit 0
}
# Does this session need a restart for the window? The record differs from the file; or none is there and the project has
# the hook: the session started before it. No hook in the project: an older core, a restart would change nothing.
function Test-WindowStale {
	$rec = if ($sid -cmatch '^[0-9a-zA-Z-]+$') { Join-Path $windows $sid } else { '' }
	if ($rec -and (Test-Path -LiteralPath $rec)) { return "$(Get-Content -LiteralPath $rec -Raw)".Trim() -cne $windowText }
	foreach ($f in '.claude/settings.local.json', '.claude/settings.json') {
		$p = Join-Path $root $f
		if ((Test-Path -LiteralPath $p) -and (Select-String -LiteralPath $p -CaseSensitive -Quiet -Pattern 'statusline\.(sh|ps1).*(--session-start|-SessionStart)')) { return $true }
	}
	return $false
}

$e = [char]27
$off = "$e[48;2;48;54;61m$e[38;2;201;209;217m"
function Get-Base([string]$c) { switch ($c) { 'green' { '63;185;80' } 'yellow' { '227;179;65' } 'red' { '248;81;73' } default { '88;166;255' } } }
function Get-On([string]$c) { "$e[48;2;$(Get-Base $c)m$e[38;2;13;17;23m" }
function Get-Label([string]$text, [int]$width) {
	$pad = [math]::Max(0, $width - $text.Length)
	(' ' * [math]::Floor($pad / 2)) + $text + (' ' * [math]::Ceiling($pad / 2))
}
function Get-Cells([string]$label, [double]$pct) { [int][math]::Min($label.Length, (Get-Nearest ($label.Length * $pct / 100))) }
# The text inside the bar; the filled part on the colour, the rest on dark grey.
function Format-Bar([string]$text, [double]$pct, [int]$width, [string]$colour) {
	$label = Get-Label $text $width
	$fill = Get-Cells $label $pct
	"$(Get-On $colour)$($label.Substring(0, $fill))$off$($label.Substring($fill))$e[0m"
}
# One bar for the week. The week gone is always blue; the limit is green when it is behind or level with the time, and past the time its excess is yellow, or red over 10 points.
function Format-WeekBar([string]$text, [double]$w, [double]$gone, [int]$width) {
	$label = Get-Label $text $width
	$a = Get-Cells $label ([math]::Min($w, $gone))
	$b = Get-Cells $label ([math]::Max($w, $gone))
	if ($w -le $gone) { $first = Get-On 'green'; $mid = Get-On 'blue' }
	else { $first = Get-On 'blue'; $mid = if ($w -le $gone + 10) { Get-On 'yellow' } else { Get-On 'red' } }
	"$first$($label.Substring(0, $a))$mid$($label.Substring($a, $b - $a))$off$($label.Substring($b))$e[0m"
}
function Get-LevelColour([double]$pct) { if ($pct -lt 70) { 'green' } elseif ($pct -lt 90) { 'yellow' } else { 'red' } }
function Get-Mod([double]$x, [double]$m) { $x - $m * [math]::Floor($x / $m) }

# Each letter its own colour, red through orange to yellow, the wave moving with the clock at every refresh.
function Format-Gradient([string]$text) {
	$s = (Get-Mod ($now / 5) 8) / 8
	$out = ''
	for ($k = 0; $k -lt $text.Length; $k++) {
		$t = 1 - [math]::Abs(2 * (Get-Mod ($k / $text.Length + $s) 1) - 1)
		$out += "$e[1;38;2;255;$(Get-Nearest (80 + 140 * $t));$(Get-Nearest (80 - 20 * $t))m$($text[$k])"
	}
	"$out$e[0m"
}

# A newer core: upstream's tag stable, else main, read at most once in 12 hours by a detached git ls-remote into a file (the status line
# itself never waits for the network), against the commit PROJECT.md records. Line 2 of the file: the record it was read
# against; when that differs (an update) the mark is hidden and the file read again, at most every 10 minutes (#516).
function Test-CoreBehind {
	$file = Join-Path $dir 'core-upstream.txt'
	$item = Get-Item -LiteralPath $file
	$row = Select-String -LiteralPath (Join-Path $root 'coordinator/PROJECT.md') -Pattern '^\| Core \(CORE .*commit `([0-9a-f]{7,40})`' -ErrorAction SilentlyContinue | Select-Object -First 1
	$rec = if ($row) { $row.Matches[0].Groups[1].Value } else { '' }
	$lines = if ($item) { @((Get-Content -LiteralPath $file -Raw) -split "`r?`n") } else { @() }
	$had = if ($lines.Count -gt 1) { $lines[1] } else { '' }
	if (-not $item -or $item.LastWriteTime -lt (Get-Date).AddHours(-12) -or ($had -ne $rec -and $item.LastWriteTime -lt (Get-Date).AddMinutes(-10))) {
		[IO.File]::AppendAllText($file, ''); [IO.File]::SetLastWriteTime($file, (Get-Date))   # one reader at a time
		$q = $file -replace "'", "''"
		# the tag stable when upstream has it, else main; a project's row Core source `main`: main (#495)
		$refs = if (Select-String -LiteralPath (Join-Path $root 'coordinator/PROJECT.md') -Pattern '^\| Core source[^|]*\| `main` \|' -ErrorAction SilentlyContinue) { 'refs/heads/main' } else { 'refs/heads/main refs/tags/stable' }
		$cmd = "`$r = @(git ls-remote $coreUrl $refs); `$l = @(`$r -match 'refs/tags/stable$') + @(`$r -match 'refs/heads/main$'); if (`$l) { Set-Content -LiteralPath '$q' -Value (`$l[0] + [char]10 + '$rec') -NoNewline -Encoding ascii }"
		$code = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
		$exe = (Get-Process -Id $PID).Path
		if ($env:OS -eq 'Windows_NT') { Start-Process -WindowStyle Hidden -FilePath $exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $code) }
		else { & sh -c "'$exe' -NoProfile -EncodedCommand $code </dev/null >/dev/null 2>&1 &" }
	}
	if ($had -ne $rec -or -not $rec) { return $false }
	$head = (Get-Content -LiteralPath $file -Raw)
	if ($head -notmatch '^([0-9a-f]{40})') { return $false }
	return -not $Matches[1].StartsWith($rec)
}

$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$parts = @()
if ($isCoordinator -and $root) { try { if (Test-CoreBehind) { $parts += Format-Gradient "core $([char]0x2191)" } } catch { } }

$model = if ($j.model.display_name) { "$($j.model.display_name)" } else { 'Claude' }
if ($j.effort.level) { $model += " $($j.effort.level)" }

# Beside the number: the window in force is not the one shown. Past 100% is itself a sign: a compaction comes before it, or one large turn after.
$restart = $false
if ($isCoordinator -and $root) { try { $restart = Test-WindowStale } catch { } }
$cw = $j.context_window
if ($cw -and $null -ne $cw.used_percentage) {
	$u = $cw.current_usage
	$used = [double]$u.input_tokens + [double]$u.cache_read_input_tokens + [double]$u.cache_creation_input_tokens
	$limit = if ($set -gt 0) { $set } else { [double]$cw.context_window_size }
	$pct = if ($limit -gt 0) { $used * 100 / $limit } else { 0 }
	if ($isCoordinator -and $root -and $set -gt 0 -and $used -gt $limit) { $restart = $true }
	if ($restart) { $parts += Format-Gradient 'restart' }
	$parts += Format-Bar ('{0} {1} {2}/{3} {4}%' -f $model, [char]0x00B7, (Format-Tokens $used), (Format-Tokens $limit), [math]::Floor($pct)) $pct 34 (Get-LevelColour $pct)   # 34 holds the longest: Sonnet 5.5 medium, three-digit tokens, three-digit percent
} else { if ($restart) { $parts += Format-Gradient 'restart' }; $parts += $model }

$rl = $j.rate_limits
# The 5-hour limit only where Claude Code passes it (a plan with one): by its level.
if ($rl.five_hour -and $null -ne $rl.five_hour.used_percentage) {
	$h = [double]$rl.five_hour.used_percentage
	$parts += Format-Bar ('5h limit {0}%' -f [math]::Floor($h)) $h 14 (Get-LevelColour $h)
}
# The week's limit, coloured against the share of the calendar week gone: green not ahead of time, yellow up to 10 points ahead, red past that.
if ($rl.seven_day -and $null -ne $rl.seven_day.used_percentage) {
	$w = [double]$rl.seven_day.used_percentage
	if ($rl.seven_day.resets_at) {
		$gone = [math]::Max(0, [math]::Min(100, 100 - ([double]$rl.seven_day.resets_at - $now) * 100 / 604800))
		$parts += Format-WeekBar ('week {0}% {1} reset {2}%' -f [math]::Floor($w), [char]0x00B7, (Get-Nearest $gone)) $w $gone 26
	} else { $parts += Format-Bar ('week {0}%' -f [math]::Floor($w)) $w 16 (Get-LevelColour $w) }
}

# A working task's bar: a soft lighter wave moves through the fill at every redraw, in the colour its budget has now.
function Format-WaveBar([string]$text, [double]$pct, [int]$width, [string]$colour) {
	$base = (Get-Base $colour) -split ';' | ForEach-Object { [double]$_ }
	$label = Get-Label $text $width
	$fill = Get-Cells $label $pct
	$out = ''
	for ($k = 0; $k -lt $label.Length; $k++) {
		if ($k -lt $fill) {
			$v = 1 - [math]::Abs(2 * (Get-Mod ($k - $now / 2) $fill) / $fill - 1)
			$bg = 0..2 | ForEach-Object { Get-Nearest ($base[$_] + (255 - $base[$_]) * 0.45 * $v * $v) }
			$out += "$e[48;2;$($bg[0]);$($bg[1]);$($bg[2])m$e[38;2;13;17;23m$($label[$k])"
		} else { $out += "$off$($label[$k])" }
	}
	"$out$e[0m"
}
function Get-Slashed([string]$p) { ($p -replace '\\', '/').TrimEnd('/') }
# The first timestamp in a transcript, to the second, with Z: a session's start, as `runs check` reads it.
function Get-SessionStart([string]$path) {
	foreach ($l in [IO.File]::ReadLines($path)) { if ($l -match '"timestamp"\s*:\s*"(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)') { return "$($Matches[1])Z" } }
}
# What a session was started with, its kept brief: the first `cost:` under a `budget:` line; 0 when none (#505).
function Get-KeptBudget([string]$path) { $on = $false
	try { foreach ($l in [IO.File]::ReadLines($path)) {
		if ($l -match '^[ \t]*budget:') { $on = $true; continue }
		if ($on -and $l -match '^[ \t]+cost:') { if ($l -match '[0-9.]+') { return [double]::Parse($Matches[0], $inv) }; return 0.0 }
		if ($on -and $l -match '^[^ \t]') { $on = $false }
	} } catch { }
	return 0.0
}

# The tasks at work: only this project's folder, only tasks with a session at work now.
# Spent = the task's rows of RUNS.tsv + what its live sessions spent, idle ones too. A live session and its finished row
# count once, the live value: a row is that session's when its start cell equals the transcript's first timestamp (`runs check`).
function Get-TaskLine {
	$state = Join-Path $root 'coordinator'
	$letters = @{ tester = 'T'; worker = 'W'; verifier = 'V'; lead = 'L'; researcher = 'R' }
	$tasks = @{}
	$agents = (& claude agents --json 2>$null) -join "`n" | ConvertFrom-Json
	$base = Get-Slashed $root
	foreach ($a in @($agents | Sort-Object startedAt)) {
		$c = Get-Slashed "$($a.cwd)"
		if ($c -ne $base -and -not $c.StartsWith("$base/", [StringComparison]::OrdinalIgnoreCase)) { continue }
		if ("$($a.name)" -notmatch '^#(\d+)(\.\d+)?\s+(\w+):') { continue }
		$n = $Matches[1]; $role = $Matches[3]; $sub = $Matches[2]
		if (-not $tasks[$n]) { $tasks[$n] = @{ spent = 0.0; stage = '?'; lead = $false; working = $false; live = @{}; kept = @() } }
		$t = $tasks[$n]
		if (-not $sub) { $t.kept += "$($a.sessionId)" }   # a lead's #<task>.<n> session has its own budget
		if ($role -eq 'lead') { $t.lead = $true }
		if ($a.status) {
			try {
				$s = Get-Content -LiteralPath (Join-Path (Join-Path $dir 'sessions') "$($a.sessionId).json") -Raw | ConvertFrom-Json
				$t.spent += [double]$s.cost.total_cost_usd
				$st = Get-SessionStart "$($s.transcript_path)"
				if ($st) { $t.live[$st] = $true }
			} catch { }
		}
		if ("$($a.state)" -in 'working', 'blocked') { $t.working = $true; $t.stage = if ($letters[$role]) { $letters[$role] } else { $role.Substring(0, 1).ToUpper() } }
	}
	foreach ($n in @($tasks.Keys)) { if (-not $tasks[$n].working) { $tasks.Remove($n) } }
	if (-not $tasks.Count) { return $null }
	# The finished runs: a cost cell read by its leading number; a subagent's `in <parent>` and a task row add nothing.
	$rows = @(Get-Content -LiteralPath (Join-Path $state 'RUNS.tsv'))
	if ($rows.Count) {
		$head = $rows[0] -split "`t"
		$ci = [array]::IndexOf($head, 'cost'); $ti = [array]::IndexOf($head, 'task'); $ri = [array]::IndexOf($head, 'role'); $si = [array]::IndexOf($head, 'start')
		foreach ($r in ($rows | Select-Object -Skip 1)) {
			$c = $r -split "`t"
			if ($ci -lt 0 -or $ti -lt 0 -or $ri -lt 0 -or $c.Count -le $ci -or $c[$ri] -eq 'task') { continue }
			$n = ($c[$ti] -split '\.')[0]
			if (-not $tasks[$n]) { continue }
			if ($si -ge 0 -and $si -lt $c.Count -and $c[$si] -and $tasks[$n].live[$c[$si]]) { continue }
			if ($c[$ci] -match '^[0-9.]+') { $tasks[$n].spent += [double]::Parse($Matches[0], $inv) }
		}
	}
	foreach ($n in ($tasks.Keys | Sort-Object { [int]$_ })) {
		$t = $tasks[$n]
		$budget = 0.0
		$m = Select-String -LiteralPath (Join-Path $state "briefs/$n-contract.md") -Pattern '^\s+cost:\s*([0-9.]+)' | Select-Object -First 1
		if ($m) { $budget = [double]::Parse($m.Matches[0].Groups[1].Value, $inv) }
		else { foreach ($id in $t.kept) { $budget = Get-KeptBudget (Join-Path $dir "briefs/$id.md"); if ($budget -gt 0) { break } } }
		$stage = if ($t.lead) { 'L' } else { $t.stage }
		$spent = Get-Nearest $t.spent
		if ($budget -gt 0) {
			$p = $t.spent * 100 / $budget
			$whole = Get-Nearest $p
			$colour = if ($whole -lt 80) { 'green' } elseif ($whole -le 100) { 'yellow' } else { 'red' }   # red only past the budget
			Format-WaveBar ('#{0} {1} {2}/{3}$' -f $n, $stage, $spent, $budget.ToString($inv)) $p 17 $colour
		} else { Format-Bar ('#{0} {1} {2}$' -f $n, $stage, $spent) 100 17 'neutral' }
	}
}
if ($isCoordinator -and $root) { try { $taskBars = @(Get-TaskLine); if ($taskBars) { $parts += $taskBars } } catch { } }

# [Console]::Out: pwsh strips colour codes from its ordinary output when stdout is a pipe, and a status line's stdout is one.
# One line while it fits; past the width a whole bar moves to the next line, never cut. Claude Code sets COLUMNS for a status line; 4 for its own margins.
$sep = " $([char]0x00B7) "
$room = 0; if ([int]::TryParse("$env:COLUMNS", [ref]$room) -and $room -gt 4) { $room -= 4 } else { $room = [int]::MaxValue }
$line = ''; $at = 0
foreach ($p in $parts) {
	$w = ($p -replace "$e\[[0-9;]*m", '').Length
	if ($at -gt 0 -and $at + $sep.Length + $w -gt $room) { [Console]::Out.WriteLine($line); $line = ''; $at = 0 }
	if ($at -gt 0) { $line += $sep; $at += $sep.Length }
	$line += $p; $at += $w
}
[Console]::Out.WriteLine($line)
