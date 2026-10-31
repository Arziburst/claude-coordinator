# Watch the sessions a report is awaited from, in place of subscribing to their idle notices (#342)
# (Windows; macOS / Linux: watch-sessions.sh - the same output and exit codes): run as one background
# command, it polls `claude agents --json --all` and ends - waking its caller once - only when a listed
# session stopped, vanished or went quiet without its report.
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\watch-sessions.ps1 -List <file> [-Interval <s>]
#     [-QuietMinutes <m>] [-QuietSeconds <s>] [-AgentsTimeout <s>] [-Once]
# The list file: one awaited session per line, its short id (`id` in claude agents --json) or its whole
# name; blank lines and comments ignored - a comment is a line whose first non-blank `#` is followed by a
# blank or the line's end (`#12 worker: Fix` is a name); a UTF-8 BOM at its start is not part of the
# first line. A line may end with its own quiet limit, ` @<n>` minutes (` @<n>s`: seconds), in place of
# the global one (e.g. a lead waiting for its workers: `<id> @120`); the entry is the line without that
# end (a name may hold blanks). An entry matches a session by the whole id or the whole name, never a
# part of it; a name several sessions have: the one at work, else a quiet one, else a stopped one. The
# file is read again on every poll (it is edited while the watcher runs).
# States, as measured: the listing gives `state`, and `status` (busy / idle) only while the session's
# process lives - a live session between turns is `done` + `idle`, an exited one `done` with no status.
# State working or status busy = at work, nothing printed; state stopped / failed (any status), or done
# with no status = STOPPED; done + idle and any other state (idle, blocked, waiting - a permission
# prompt or a limit), with or without a status = quiet: QUIET once it stayed quiet for its limit
# (-QuietMinutes, default 20; -QuietSeconds in its place, for tests; or the line's own), counted by
# the watcher from the first poll that saw it quiet and started again after a poll that saw it at work.
# Output (stdout): the findings of one poll, one line each, then the end -
#   STOPPED <id> <name> | GONE <entry> (claude does not list it) | QUIET <id> <name> <minutes>
#   EMPTY: the list file is missing or holds no session (nothing to watch: it does not run)
#   ERROR <first line of claude's stderr, or the timeout>: claude agents failed on two polls in a row
#   (one failure is retried on the next poll; with -Once there is no next poll)
# -Interval: seconds between polls (default 120). -AgentsTimeout: seconds one claude agents call may
# take (default 60); past it the one process the watcher started is killed by its own handle - nothing
# under it, nothing else - and the poll failed. -Once: one poll, then the end (tests, a manual check).
# Exit codes: 0 a finding, EMPTY, or -Once with nothing found (nothing printed); 1 ERROR; 2 usage error.
# The only files it touches: two temp files per call ([IO.Path]::GetTempFileName) holding claude's
# stdout and stderr - read from files, not a pipe, so a process left under a killed claude cannot hang
# the watcher - removed as soon as they are read and on every way out. It never stops, messages or
# changes a session.
param([string]$List, [string]$Interval = '120', [string]$QuietMinutes = '20', [string]$QuietSeconds = '',
  [string]$AgentsTimeout = '60', [switch]$Once)
# a name is written as UTF-8, whatever the console's code page; the caller's console gets its own encoding
# back on every way out (the body runs inside try, the encoding is restored in finally)
$enc0 = $null; try { $enc0 = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
try {
$usage = 'usage: -List <file> [-Interval <s>] [-QuietMinutes <m>] [-QuietSeconds <s>] [-AgentsTimeout <s>] [-Once]'
function Usage([string]$m) { [Console]::Error.WriteLine("$m; $usage"); exit 2 }
if (-not $List) { Usage 'missing -List' }
foreach ($p in @(@('-Interval', $Interval), @('-QuietMinutes', $QuietMinutes), @('-QuietSeconds', $QuietSeconds), @('-AgentsTimeout', $AgentsTimeout))) {
  if ($p[1] -ne '' -and $p[1] -notmatch '^[0-9]+$') { Usage "$($p[0]) takes a whole number (got $($p[1]))" }
}
if ($Interval -eq '') { Usage 'missing value for -Interval' }
if ($AgentsTimeout -eq '' -or [int64]$AgentsTimeout -le 0) { Usage '-AgentsTimeout must be above 0' }
$limit = [int64]$QuietMinutes * 60; if ($QuietSeconds -ne '') { $limit = [int64]$QuietSeconds }
$t00 = [DateTime]::UtcNow

# Entries: the list file's sessions as @(<own limit in seconds, or -1>, <entry>), the blanks around each
# trimmed (Get-Content -Encoding UTF8 drops a BOM)
function Entries {
  if (-not (Test-Path -LiteralPath $List -PathType Leaf)) { return , @() }
  $r = @()
  foreach ($l in @(Get-Content -LiteralPath $List -Encoding UTF8)) {
    $x = ([string]$l).TrimStart([char]0xFEFF).Trim(" `t`r")
    if ($x -eq '' -or $x -match '^#([ \t]|$)') { continue }
    $lim = [int64]-1
    $m = [regex]::Match($x, '[ \t]+@([0-9]+)(s?)$')
    if ($m.Success) {
      $lim = [int64]$m.Groups[1].Value; if ($m.Groups[2].Value -ne 's') { $lim = $lim * 60 }
      $x = $x.Substring(0, $m.Index)
    }
    $r += , @($lim, $x)
  }
  , $r
}
# The one place the watcher writes: two temp files per call ([IO.Path]::GetTempFileName) for claude's
# stdout and stderr (a pipe would stay open while anything under a killed claude still holds it, and the
# watcher would hang on it); read once the call ends or is killed, and removed at once - on every way out
# too (the finally at the end)
$script:tmpFiles = @()
function RemoveTmp { foreach ($f in $script:tmpFiles) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }; $script:tmpFiles = @() }
function ReadShared([string]$f) {
  try {
    $fs = New-Object System.IO.FileStream($f, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
    $sr = New-Object System.IO.StreamReader($fs, (New-Object System.Text.UTF8Encoding $false))
    try { $sr.ReadToEnd() } finally { $sr.Dispose() }
  } catch { '' }
}
# Agents: one call of claude agents --json --all; sets rc, json (its stdout) and err (the first line of
# its stderr, or the timeout). Past -AgentsTimeout only the process the watcher started is killed, by its
# own handle - nothing under it, nothing looked up by name or id. claude as PATH gives it: a .ps1 through
# this PowerShell, a .cmd / .bat through cmd, else the program itself.
function Agents {
  $script:json = ''; $script:err = ''; $script:rc = 0
  $c = Get-Command claude -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $c) { $script:rc = 127; $script:err = 'claude: command not found'; return }
  $a = 'agents --json --all'
  if ($c.CommandType -eq 'ExternalScript') {
    $exe = (Get-Process -Id $PID).Path; $al = '-NoProfile -ExecutionPolicy Bypass -File "' + $c.Path + '" ' + $a
  } elseif ($c.Path -match '\.(cmd|bat)$') {
    $exe = $env:ComSpec; $al = '/d /s /c ""' + $c.Path + '" ' + $a + '"'
  } else { $exe = $c.Path; $al = $a }
  $timed = $false
  try {
    $out = [System.IO.Path]::GetTempFileName(); $script:tmpFiles += $out
    $er = [System.IO.Path]::GetTempFileName(); $script:tmpFiles += $er
    try {
      $p = Start-Process -FilePath $exe -ArgumentList $al -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $er -ErrorAction Stop
    } catch { $script:rc = 127; $script:err = ($_.Exception.Message -split "`r?`n")[0]; return }
    $null = $p.Handle   # keeps its exit code readable after it ends
    if ($p.WaitForExit([int]([int64]$AgentsTimeout * 1000))) { $p.WaitForExit(); $script:rc = $p.ExitCode }
    else { $timed = $true; try { $p.Kill() } catch { }; try { [void]$p.WaitForExit(5000) } catch { } }
    $script:json = ReadShared $out
    foreach ($x in ((ReadShared $er) -split "`r?`n")) { if ($x -ne '') { $script:err = $x; break } }
  } finally { RemoveTmp }
  if ($timed) { $script:rc = 124; $script:err = "claude agents --json --all did not answer in $AgentsTimeout s" }
  elseif ($script:rc -eq 0 -and -not $script:json.Contains('[')) { $script:rc = 1; $script:err = 'claude agents --json --all printed no JSON list' }
  if ($script:err -eq '') { $script:err = "claude agents --json --all exited with $($script:rc)" }
}
# Sessions <json>: @(id, class, name) per session object of the list - class work, stop or quiet from
# state and status as the header says (string values unescaped as watch-sessions.sh does: a control
# escape as a blank, \u left as written)
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
      if ($d -eq 2 -and $c -eq [char]'}' -and $v['id']) {
        $st = [string]$v['state']; $su = [string]$v['status']
        if ($st -ceq 'working' -or $su -ceq 'busy') { $cl = 'work' }
        elseif ($st -ceq 'stopped' -or $st -ceq 'failed' -or ($st -ceq 'done' -and $su -eq '')) { $cl = 'stop' }
        else { $cl = 'quiet' }
        [void]$r.Add(@([string]$v['id'], $cl, [string]$v['name']))
      }
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
    if ($x[1] -eq 'work') { $p = 3 } elseif ($x[1] -eq 'stop') { $p = 1 }
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
  foreach ($en in $ents) {
    $lim = $en[0]; $e = $en[1]; if ($lim -lt 0) { $lim = $limit }
    $m = Pick $sess $e
    if ($null -eq $m) { $found += "GONE $e"; continue }
    $id = $m[0]; $cl = $m[1]; $nm = $m[2]
    if ($cl -eq 'work') { continue }
    if ($cl -eq 'stop') { $found += "STOPPED $id $nm"; continue }
    $t0 = $now; if ($timers.ContainsKey($e)) { $t0 = $timers[$e] }
    $quiet[$e] = $t0
    if ($now - $t0 -ge $lim) { $found += "QUIET $id $nm $([Math]::Floor(($now - $t0) / 60))" }
  }
  $timers = $quiet
  if ($found.Count -gt 0) { $found; exit 0 }
  if ($Once) { exit 0 }
  Start-Sleep -Seconds ([int]$Interval)
}
} finally {
  foreach ($f in @($script:tmpFiles)) { if ($f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } }
  if ($enc0) { try { [Console]::OutputEncoding = $enc0 } catch { } } }
