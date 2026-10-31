# Watch the sessions a report is awaited from, in place of subscribing to their idle notices (#342)
# (Windows; macOS / Linux: watch-sessions.sh - the same output and exit codes): run as one background
# command, it polls `claude agents --json --all` and ends - waking its caller once - only when a listed
# session stopped, vanished or went quiet without its report.
#   powershell -File scripts\watch-sessions.ps1 -List <file> [-Interval <s>] [-QuietMinutes <m>] [-QuietSeconds <s>] [-Once]
# The list file: one awaited session per line, its short id (`id` in claude agents --json) or its whole
# name; blank lines and comments ignored - a comment is a line whose first non-blank `#` is followed by a
# blank or the line's end (`#12 worker: Fix` is a name). A line matches a session by the whole id or the
# whole name, never a part of it; a name several sessions have: the one at work, else a quiet one, else
# a stopped one. The file is read again on every poll (it is edited while the watcher runs).
# States: working / busy = at work, nothing printed; stopped / failed / done = STOPPED; any other state
# (idle, blocked, waiting - a permission prompt or a limit) = quiet: QUIET once it stayed quiet for
# -QuietMinutes (default 20; -QuietSeconds in its place, for tests), counted by the watcher from the
# first poll that saw it quiet and started again after a poll that saw it at work.
# Output (stdout): the findings of one poll, one line each, then the end -
#   STOPPED <id> <name> | GONE <id or name as listed> (claude does not list it) | QUIET <id> <name> <minutes>
#   EMPTY: the list file is missing or holds no session (nothing to watch: it does not run)
#   ERROR <first line of claude's stderr>: claude agents failed on two polls in a row (one failure is
#   retried on the next poll; with -Once there is no next poll)
# -Interval: seconds between polls (default 120). -Once: one poll, then the end (tests, a manual check).
# Exit codes: 0 a finding, EMPTY, or -Once with nothing found (nothing printed); 1 ERROR; 2 usage error.
# It writes no file and never stops, messages or changes a session.
param([string]$List, [string]$Interval = '120', [string]$QuietMinutes = '20', [string]$QuietSeconds = '', [switch]$Once)
# a name is written as UTF-8, whatever the console's code page; the caller's console gets its own encoding
# back on every way out (the body runs inside try, the encoding is restored in finally)
$enc0 = $null; try { $enc0 = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
try {
$usage = 'usage: -List <file> [-Interval <s>] [-QuietMinutes <m>] [-QuietSeconds <s>] [-Once]'
function Usage([string]$m) { [Console]::Error.WriteLine("$m; $usage"); exit 2 }
if (-not $List) { Usage 'missing -List' }
foreach ($p in @(@('-Interval', $Interval), @('-QuietMinutes', $QuietMinutes), @('-QuietSeconds', $QuietSeconds))) {
  if ($p[1] -ne '' -and $p[1] -notmatch '^[0-9]+$') { Usage "$($p[0]) takes a whole number (got $($p[1]))" }
}
if ($Interval -eq '') { Usage 'missing value for -Interval' }
$limit = [int64]$QuietMinutes * 60; if ($QuietSeconds -ne '') { $limit = [int64]$QuietSeconds }
$t00 = [DateTime]::UtcNow

# Entries: the list file's sessions, the blanks around each trimmed
function Entries {
  if (-not (Test-Path -LiteralPath $List -PathType Leaf)) { return @() }
  $r = @()
  foreach ($l in @(Get-Content -LiteralPath $List -Encoding UTF8)) {
    $x = ([string]$l).Trim(" `t`r")
    if ($x -eq '' -or $x -match '^#([ \t]|$)') { continue }
    $r += $x
  }
  , $r
}
# Agents: one call of claude agents --json --all; sets rc, json (its stdout) and err (the first line of
# its stderr), no file written
function Agents {
  $script:json = ''; $script:err = ''
  try {
    $out = @(& claude agents --json --all 2>&1)
    $script:rc = $LASTEXITCODE
  } catch { $out = @($_); $script:rc = 127 }
  $o = @(); $e = @()
  foreach ($x in $out) { if ($x -is [System.Management.Automation.ErrorRecord]) { $e += "$x" } else { $o += "$x" } }
  $script:json = $o -join "`n"
  foreach ($x in $e) { if ($x -ne '') { $script:err = ($x -split "`r?`n")[0]; break } }
  if ($script:rc -eq 0 -and -not $script:json.Contains('[')) { $script:rc = 1; $script:err = 'claude agents --json --all printed no JSON list' }
  if ($script:err -eq '') { $script:err = "claude agents --json --all exited with $($script:rc)" }
}
# Sessions <json>: @(id, state, name) per session object of the list (string values unescaped as
# watch-sessions.sh does: a control escape as a blank, \u left as written)
function Sessions([string]$s) {
  $r = New-Object System.Collections.ArrayList
  $d = 0; $q = $false; $after = $false; $k = ''; $t = New-Object System.Text.StringBuilder; $v = @{}
  for ($i = 0; $i -lt $s.Length; $i++) {
    $c = $s[$i]
    if ($q) {
      if ($c -eq [char]'\') {
        $i++; if ($i -ge $s.Length) { break }; $c = $s[$i]
        if ('nrtbf'.IndexOf($c) -ge 0) { [void]$t.Append(' ') } elseif ($c -eq [char]'u') { [void]$t.Append('\u') } else { [void]$t.Append($c) }
        continue
      }
      if ($c -eq [char]'"') {
        $q = $false
        if ($d -eq 2) { if ($after) { $v[$k] = $t.ToString(); $after = $false } else { $k = $t.ToString() } }
        continue
      }
      [void]$t.Append($c); continue
    }
    if ($c -eq [char]'"') { $q = $true; [void]$t.Clear() }
    elseif ($c -eq [char]':') { if ($d -eq 2) { $after = $true } }
    elseif ($c -eq [char]',') { if ($d -eq 2) { $after = $false } }
    elseif ($c -eq [char]'{' -or $c -eq [char]'[') { if ($d -eq 2) { $after = $false }; $d++ }
    elseif ($c -eq [char]'}' -or $c -eq [char]']') {
      if ($d -eq 2 -and $c -eq [char]'}' -and $v['id']) { [void]$r.Add(@([string]$v['id'], [string]$v['state'], [string]$v['name'])) }
      if ($d -eq 2) { $v = @{} }
      $d--
    }
  }
  , $r.ToArray()
}
# Pick <sessions> <entry>: the session the entry names (by the whole id or the whole name), at work first
function Pick($ss, [string]$e) {
  $best = 0; $line = $null
  foreach ($x in $ss) {
    if ($x[0] -cne $e -and $x[2] -cne $e) { continue }
    $p = 2
    if ($x[1] -ceq 'working' -or $x[1] -ceq 'busy') { $p = 3 }
    elseif ($x[1] -ceq 'stopped' -or $x[1] -ceq 'failed' -or $x[1] -ceq 'done') { $p = 1 }
    if ($p -gt $best) { $best = $p; $line = $x }
  }
  , $line
}

$fails = 0; $timers = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
while ($true) {
  $ents = Entries
  if ($ents.Count -eq 0) { 'EMPTY'; exit 0 }
  Agents
  if ($rc -ne 0) {
    $fails++
    if ($fails -ge 2 -or $Once) { "ERROR $err"; exit 1 }
    Start-Sleep -Seconds ([int]$Interval); continue
  }
  $fails = 0
  $sess = Sessions $json
  # whole seconds since the start, as bash's SECONDS
  $now = [int64][Math]::Floor(([DateTime]::UtcNow - $t00).TotalSeconds)
  $found = @(); $quiet = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
  foreach ($e in $ents) {
    $m = Pick $sess $e
    if ($null -eq $m) { $found += "GONE $e"; continue }
    $id = $m[0]; $st = $m[1]; $nm = $m[2]
    if ($st -ceq 'working' -or $st -ceq 'busy') { continue }
    if ($st -ceq 'stopped' -or $st -ceq 'failed' -or $st -ceq 'done') { $found += "STOPPED $id $nm"; continue }
    $t0 = $now; if ($timers.ContainsKey($e)) { $t0 = $timers[$e] }
    $quiet[$e] = $t0
    if ($now - $t0 -ge $limit) { $found += "QUIET $id $nm $([Math]::Floor(($now - $t0) / 60))" }
  }
  $timers = $quiet
  if ($found.Count -gt 0) { $found; exit 0 }
  if ($Once) { exit 0 }
  Start-Sleep -Seconds ([int]$Interval)
}
} finally { if ($enc0) { try { [Console]::OutputEncoding = $enc0 } catch { } } }
