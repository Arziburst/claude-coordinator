# PreToolUse safety hook for coordinator projects (Windows; macOS / Linux: safety-guard.sh - the same
# rules, checked against the same cases: tests/safety-guard/cases.txt).
# Reads the tool call JSON on stdin; exit 2 blocks the call and shows the reason to Claude.
# A safety net only - the real enforcement is branch protection on the code host (CORE section 2);
# deliberate obfuscation (iex, cmd /c, quoting tricks ...) is out of scope (TOOLKIT.md *Safety*).
# Extra project patterns (one regular expression per line, '#' comments; a pattern that cannot be read
# blocks every call): .claude/coordinator-deny.txt
# Self-test: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\hooks\safety-guard.ps1 -SelfTest
# Windows PowerShell 5.1 or PowerShell 7; nothing to install.
param([switch]$SelfTest)

if ($SelfTest) {
  # a push to main must block (exit 2) and a work-branch push must pass (exit 0): a guard that blocks
  # everything is not working either
  $exe = (Get-Process -Id $PID).Path
  '{"tool_input":{"command":"git push --force origin main"}}' |
    & $exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath 2>$null | Out-Null
  $blocked = $LASTEXITCODE
  '{"tool_input":{"command":"git push origin 12-fix"}}' |
    & $exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath 2>$null | Out-Null
  if ($blocked -eq 2 -and $LASTEXITCODE -eq 0) { 'safety-guard: OK'; exit 0 }
  'safety-guard: NOT WORKING - STOP: do not start workers until it is fixed (TOOLKIT.md).'
  exit 0   # stdout reaches the session's context; a non-zero exit would only show it to the user
}

[Console]::InputEncoding = [Text.Encoding]::UTF8
$raw = [Console]::In.ReadToEnd()
# A BOM (or anything else) before the JSON object is dropped. Input that is not a JSON object blocks:
# Claude Code always sends one, and a guard that cannot read the call must not let it through.
$i = $raw.IndexOf('{'); if ($i -gt 0) { $raw = $raw.Substring($i) }
$d = $null; $t = $raw.Trim()
if ($t.StartsWith('{') -and $t.EndsWith('}')) { try { $d = $raw | ConvertFrom-Json } catch { $d = $null } }
if (-not $d) { [Console]::Error.WriteLine('Blocked by safety-guard: the tool call could not be read (not a JSON object). If this is a false positive, ask the owner.'); exit 2 }
$cmd = [string]$d.tool_input.command
$cwd = [string]$d.cwd
$tool = [string]$d.tool_name

# A path in one form for comparing: / separators, none repeated or trailing, lower case (-Keep: the
# letter case kept), . and x/.. taken out (by the text: /a/b/.. is /a; .. above the root stays at the
# root), a drive as c: (C:\x, /c/x, /mnt/c/x and /cygdrive/c/x are all c:/x); / itself is empty.
function Canon([string]$x, [switch]$Keep) {
  if (-not $x) { return '' }   # / with its separator stripped
  $x = $x.Replace('\', '/'); if (-not $Keep) { $x = $x.ToLowerInvariant() }; $r = ''
  if ($x.StartsWith('/')) { $r = '/' } elseif ($x -match '^[a-z]:') { $r = $x.Substring(0, 2) + '/'; $x = $x.Substring(2) }
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($s in $x.Split('/')) {
    if ($s -eq '' -or $s -eq '.') { continue }
    if ($s -eq '..') {
      if ($out.Count -gt 0 -and $out[$out.Count - 1] -ne '..') { $out.RemoveAt($out.Count - 1) } elseif (-not $r) { $out.Add('..') }
      continue
    }
    $out.Add($s)
  }
  $x = $r + ($out -join '/'); if (-not $x) { $x = '.' }
  $x = $x -replace '/+$', ''
  ($x -replace '^/(mnt/|cygdrive/)?([a-z])$', '$2:') -replace '^/(mnt/|cygdrive/)?([a-z])/', '$2:/'
}

# A path as it lies on disk (#121): the part of it that exists, walked a folder at a time with links
# (symlinks, junctions: the item's LinkTarget in PowerShell 7, Target in 5.1) resolved, then the rest as
# written; .. after a link goes to the link target's parent, as cd -P does in safety-guard.sh.
# Physical <path> [-Keep] gives its Canon form, or $null on Windows for a path from / that is not a drive
# (Git Bash's /tmp is not known here). A link is followed only to an existing folder; more than 40 links
# in one path (a loop) end the existing part, so nothing hangs.
$isWin = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows
function LinkTarget([string]$p) {
  try { $it = Get-Item -LiteralPath $p -Force -ErrorAction Stop } catch { return '' }
  if (-not $it.LinkType) { return '' }   # another reparse point (a cloud file ...) is a plain folder
  $t = $null
  if ($it.PSObject.Properties['LinkTarget']) { $t = $it.LinkTarget }   # PowerShell 7
  if (-not $t) { $t = @($it.Target)[0] }                                # Windows PowerShell 5.1
  ([string]$t).Replace('\', '/') -replace '^//\?/|^/\?\?/', ''
}
# @(<the existing folder, physical>, <the rest as written>), or $null
function PhysDir([string]$p) {
  $p = $p.Replace('\', '/')
  if ($isWin) { $p = $p -replace '^/(mnt/|cygdrive/)?([A-Za-z])(/|$)', '$2:/' }
  if ($p -notmatch '^([A-Za-z]:|/)') { $p = (Get-Location).ProviderPath.Replace('\', '/') + '/' + $p }
  if ($p -match '^[A-Za-z]:') { $root = $p.Substring(0, 2) + '/'; $p = $p.Substring(2) }
  elseif ($isWin) { return $null } else { $root = '/' }
  $segs = $p.Split('/'); $cur = $root
  for ($i = 0; $i -lt $segs.Count; $i++) {
    $s = $segs[$i]
    if ($s -eq '' -or $s -eq '.') { continue }
    if ($s -eq '..') {
      $k = $cur.LastIndexOf('/'); $cur = if ($k -lt $root.Length) { $root } else { $cur.Substring(0, $k) }
      continue
    }
    $cand = if ($cur.EndsWith('/')) { $cur + $s } else { "$cur/$s" }
    $a = [int][IO.DirectoryInfo]::new($cand).Attributes
    $t = if ($a -ne -1 -and ($a -band 1024)) { LinkTarget $cand } else { '' }   # a reparse point: a symlink or a junction
    if ($t) {
      if (++$script:hops -le 40) {
        if ($t -notmatch '^([A-Za-z]:|/)') { $t = "$cur/$t" }
        $r = PhysDir $t
        if ($null -ne $r -and -not $r[1]) { $cur = $r[0]; continue }
      }
      # a loop, or it does not lead to an existing folder
    } elseif ($a -ne -1 -and ($a -band 16)) {
      # an 8.3 name (RUNNER~1) in its long form, as git and cd -P give it: GetFullPath expands it
      $cur = if ($isWin -and $s.Contains('~')) { [IO.Path]::GetFullPath($cand).Replace('\', '/') } else { $cand }
      continue
    }
    # not there, or not a folder: the rest as written
    return @($cur, ('/' + ($segs[$i..($segs.Count - 1)] -join '/')))
  }
  @($cur, '')
}
function Physical([string]$p, [switch]$Keep) {
  $script:hops = 0
  $r = PhysDir $p
  if ($null -eq $r) { return $null }
  Canon ($r[0] + $r[1]) -Keep:$Keep
}

# --- the owner's working copy: no edit tool under COORD_PROTECTED_ROOT outside its .claude/worktrees/ ---
# Opt-in: unset or empty changes nothing. A relative path counts from the call's cwd; whole path segments
# are compared (<root>-old is another folder), letter case ignored on Windows and macOS only.
if ($env:COORD_PROTECTED_ROOT -and $tool -cmatch '^(Edit|Write|MultiEdit|NotebookEdit)$') {
  $keep = -not (($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows -or $IsMacOS)
  # the root and each path as written and as they lie on disk (links resolved, #121): either form of the
  # path under either form of the root blocks
  $proots = $null
  foreach ($p in @($d.tool_input.file_path, $d.tool_input.notebook_path)) {
    if ($p -isnot [string] -or -not $p) { continue }
    if ($null -eq $proots) {
      $proots = @(Canon $env:COORD_PROTECTED_ROOT -Keep:$keep)
      $ph = Physical $env:COORD_PROTECTED_ROOT -Keep:$keep; if ($null -ne $ph) { $proots += $ph }
    }
    $full = $p
    if ($full -notmatch '^([/\\]|[A-Za-z]:)') {
      $base = if ($cwd) { $cwd } elseif ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { (Get-Location).Path }
      $full = "$base/$full"
    }
    $forms = @(Canon $full -Keep:$keep)
    $ph = Physical $full -Keep:$keep; if ($null -ne $ph) { $forms += $ph }
    foreach ($f in $forms) {
      $f += '/'
      foreach ($proot in $proots) {
        if ($f.StartsWith("$proot/.claude/worktrees/", [StringComparison]::Ordinal)) { continue }
        if ($f.Length -gt "$proot/".Length -and $f.StartsWith("$proot/", [StringComparison]::Ordinal)) {
          [Console]::Error.WriteLine("Blocked by safety-guard: the owner's working copy is never edited by a worker ($p); work in your worktree. If this is a false positive, ask the owner.")
          exit 2
        }
      }
    }
  }
}
# Line continuations: backslash-newline (bash) and backtick-newline (PowerShell) join the lines.
$cmd = $cmd.Replace("`r`n", "`n").Replace("\`n", '').Replace('`' + "`n", ' ')
# Comment lines (a "#" at the start of a line) do not count for the project patterns.
$lines = @($cmd -split "`n" | Where-Object { $_ -notmatch '^\s*#' })
if (-not ($lines -join '')) { exit 0 }

function Block([string]$why) {
  [Console]::Error.WriteLine("Blocked by safety-guard: $why. If this is a false positive, ask the owner.")
  exit 2
}
# Patterns are tested line by line, like grep: ^ and $ are a line's ends.
function Has([string]$re) { foreach ($l in $lines) { if ($l -match $re) { return $true } }; $false }

# --- split the command into simple commands, each a list of words ---
# Quote-aware: separators (newline ; | & && || ( ) and { } around words) inside quotes do not split,
# quotes are removed.
# $(...) and `...` leave a "$SUBST" marker in the word and become commands of their own; so do the
# inner command of bash -c / pwsh -Command and a heredoc fed to a shell (other heredoc bodies are data).
# An unbalanced quote makes the whole command split again with quotes ignored (stricter, never looser).
$script:segs = New-Object System.Collections.Generic.List[object]
$script:pipes = New-Object System.Collections.Generic.List[bool]   # the command reads the previous one through |
$script:fail = $false
$WRAP = '^([{}!]|then|do|else|elif|if|while|until|time|nohup|command|exec|builtin|noglob|xargs)$'
$ASSIGN = '^[A-Za-z_][A-Za-z0-9_]*='
# wrappers with options of their own: the options that take a value
function OptArg([string]$t) {
  switch ($t) { 'sudo' { '^-[ugpcdrt]$' } 'env' { '^-[usc]$' } 'timeout' { '^-[sk]$' } 'nice' { '^-n$' } 'stdbuf' { '^-[ioe]$' }
    # macOS: caffeinate -i, arch -arm64, script -q <file> <command>
    'caffeinate' { '^-[tw]$' } 'arch' { '^-(arch|e|d)$' } 'script' { '^-[tTc]$' } default { '' } }
}
# the index of the command word: past wrappers (sudo -E, timeout -k 5 30, nice -n 5, stdbuf -oL ...)
# and VAR=value assignments; a wrapper given as a path or with .exe (/usr/bin/env, timeout.exe) counts
function CmdIdx($toks) {
  $j = 0
  while ($j -lt $toks.Count) {
    $t = BaseName $toks[$j]
    if ($t -match '^g(env|timeout|nice|stdbuf)$') { $t = $t.Substring(1) }   # Homebrew coreutils: gtimeout, gnice ...
    if ($t -match $WRAP -or $toks[$j] -match $ASSIGN) { $j++; continue }
    $ao = OptArg $t; if (-not $ao) { break }
    for ($j++; $j -lt $toks.Count -and $toks[$j].StartsWith('-'); $j++) { if ($toks[$j] -eq '--') { $j++; break }; if ($toks[$j] -match $ao) { $j++ } }
    if (($t -eq 'timeout' -or $t -eq 'script') -and $j -lt $toks.Count) { $j++ }   # the duration, or the typescript file of script
  }
  $j
}
$SHELLS = '^(bash|sh|zsh|dash|ksh|pwsh|powershell)$'
# a command word without its folder and .exe: /usr/bin/git, git.exe, C:\x\git.exe -> git
function BaseName([string]$t) { $b = ($t.ToLowerInvariant() -split '[/\\]')[-1]; if ($b.EndsWith('.exe')) { $b = $b.Substring(0, $b.Length - 4) }; $b }
# characters that end a run of ordinary text: in single quotes, in double quotes, unquoted, in ClosePar
$RUN_SQ = [char[]]@([char]39)
$RUN_DQ = [char[]]@([char]34, [char]92, [char]36, [char]96)
$RUN_UQ = [char[]]@(32, 9, 13, 10, 59, 124, 38, 40, 41, 60, 62, 39, 34, 92, 36, 96, 35, 123, 125)
$RUN_CP = [char[]]@(39, 34, 40, 41, 60, 10)
# the number of ordinary characters from i
function RunTo([string]$s, [int]$i, [char[]]$set) { $k = $s.IndexOfAny($set, $i); if ($k -lt 0) { $k = $s.Length }; $k - $i }
function Ch([string]$s, [int]$i) { if ($i -ge 0 -and $i -lt $s.Length) { [string]$s[$i] } else { '' } }
function ClosePar([string]$s, [int]$j) {
  $dep = 1; $q = ''; $hd = ''
  for (; $j -lt $s.Length; $j++) {
    $k = if ($q) { RunTo $s $j ([char[]]@([char]$q)) } else { RunTo $s $j $RUN_CP }; if ($k -gt 0) { $j += $k - 1; continue }
    $c = Ch $s $j
    if ($q) { if ($c -eq $q) { $q = '' }; continue }
    if ($c -eq "`n" -and $hd) { $j = HereEnd $s ($j + 1) $hd $script:hdDash; $hd = ''; continue }
    if ($c -eq "'" -or $c -eq '"') { $q = $c; continue }
    if ($c -eq '<' -and (Ch $s ($j + 1)) -eq '<' -and (Ch $s ($j + 2)) -ne '<') { $hd = HereWord $s ($j + 2); $j = $script:hdJ; continue }
    if ($c -eq '(') { $dep++ } elseif ($c -eq ')') { $dep--; if ($dep -eq 0) { return $j } }
  }
  $s.Length
}
function CloseTick([string]$s, [int]$j) {
  while ($true) {
    $j = $s.IndexOf([char]96, $j); if ($j -lt 0) { return $s.Length }
    if ((Ch $s ($j - 1)) -ne '\') { return $j }
    $j++
  }
}
# heredoc word after "<<": sets hdJ (its last index) and hdDash; returns the delimiter
function HereWord([string]$s, [int]$j) {
  $script:hdDash = $false; $w = ''
  if ((Ch $s $j) -eq '-') { $script:hdDash = $true; $j++ }
  while ((Ch $s $j) -eq ' ' -or (Ch $s $j) -eq "`t") { $j++ }
  for (; $j -lt $s.Length; $j++) {
    $c = Ch $s $j
    if ($c -match '[ \t\r\n;|&()<>]') { break }
    if ($c -ne "'" -and $c -ne '"' -and $c -ne '\') { $w += $c }
  }
  $script:hdJ = $j - 1; $w
}
# heredoc body from j up to the delimiter line: sets hdBody; returns the index of that line's newline
function HereEnd([string]$s, [int]$j, [string]$delim, [bool]$dash) {
  $st = $j
  while ($j -lt $s.Length) {
    $k = $s.IndexOf("`n", $j); if ($k -lt 0) { $k = $s.Length }
    $line = $s.Substring($j, $k - $j); if ($dash) { $line = $line -replace '^\t+', '' }; $line = $line -replace '\r$', ''
    if ($line -ceq $delim) { $script:hdBody = $s.Substring($st, $j - $st); return $k }
    $j = $k + 1
  }
  $script:hdBody = $s.Substring([Math]::Min($st, $s.Length)); $s.Length - 1
}
function IsShell($toks) {
  $j = CmdIdx $toks
  $script:shJ = $j
  ($j -lt $toks.Count) -and ((BaseName $toks[$j]) -match $SHELLS)
}
function Seg($list, [int]$depth, [bool]$qm, [bool]$pp) {
  $toks = @($list)
  if ($toks.Count -eq 0) { return }
  $clean = New-Object string[] $toks.Count
  for ($j = 0; $j -lt $toks.Count; $j++) { $clean[$j] = $toks[$j] -replace '[\t\r\n]', ' ' }
  $script:segs.Add($clean); $script:pipes.Add($pp)
  if (-not (IsShell $toks)) { return }
  for ($k = $script:shJ + 1; $k -lt $toks.Count; $k++) { $lt = $toks[$k].ToLowerInvariant(); if ($lt -match '^-[a-z]*c$' -or $lt -match '^-com(m(a(n(d)?)?)?)?$') { break } }
  if ($k -lt $toks.Count - 1 -and $toks[$k + 1] -eq '--') { $k++ }
  if ($k -ge $toks.Count - 1) { return }
  Scan ($toks[($k + 1)..($toks.Count - 1)] -join ' ') ($depth + 1) $qm
}
function Scan([string]$s, [int]$depth, [bool]$qm) {
  if ($depth -gt 8) { return }
  $n = $s.Length; $q = ''; $tok = ''; $st = $false; $hd = ''; $hdd = $false; $hdsh = $false; $bd = 0; $pp = $false
  $toks = New-Object System.Collections.Generic.List[string]
  for ($i = 0; $i -lt $n; $i++) {
    $set = if ($q -eq "'") { $RUN_SQ } elseif ($q) { $RUN_DQ } else { $RUN_UQ }
    $k = RunTo $s $i $set
    if ($k -gt 0) { $tok += $s.Substring($i, $k); $i += $k - 1; continue }
    $c = [string]$s[$i]; $d = if ($i + 1 -lt $n) { [string]$s[$i + 1] } else { '' }; $p = if ($i -gt 0) { [string]$s[$i - 1] } else { '' }
    if ($q -eq "'") { if ($c -eq "'") { $q = '' } else { $tok += $c }; continue }
    if ($q -eq '"') {
      if ($c -eq '\' -and ($d -eq '"' -or $d -eq '\' -or $d -eq '$' -or $d -eq '`')) { $tok += $d; $i++; continue }
      if ($c -eq '"') { $q = ''; continue }
      if ($c -eq '$' -and $d -eq '(') { $k = ClosePar $s ($i + 2); Scan $s.Substring($i + 2, $k - $i - 2) ($depth + 1) $qm; $tok += '$SUBST'; $i = $k; continue }
      if ($c -eq '`') { $k = CloseTick $s ($i + 1); Scan $s.Substring($i + 1, $k - $i - 1) ($depth + 1) $qm; $tok += '$SUBST'; $i = $k; continue }
      $tok += $c; continue
    }
    if ($qm -and $c -eq '\' -and ($d -eq '"' -or $d -eq "'" -or $d -eq '\')) { $tok += $d; $st = $true; $i++; continue }
    if ($c -eq "'" -or $c -eq '"') { if ($qm) { $q = $c; $st = $true }; continue }
    if ($c -eq '$' -and $d -eq '(') { $k = ClosePar $s ($i + 2); Scan $s.Substring($i + 2, $k - $i - 2) ($depth + 1) $qm; $tok += '$SUBST'; $st = $true; $i = $k; continue }
    if ($c -eq '`') { $k = CloseTick $s ($i + 1); Scan $s.Substring($i + 1, $k - $i - 1) ($depth + 1) $qm; $tok += '$SUBST'; $st = $true; $i = $k; continue }
    if ($c -eq ' ' -or $c -eq "`t" -or $c -eq "`r") { if ($tok) { $toks.Add($tok) }; $tok = ''; $st = $false; $bd = 0; continue }
    if ($c -eq '#' -and -not $tok -and -not $st) { while ($i -lt $n - 1 -and (Ch $s ($i + 1)) -ne "`n") { $i++ }; continue }
    if ($c -eq '<' -and $d -eq '<' -and (Ch $s ($i + 2)) -ne '<') {
      if ($tok) { $toks.Add($tok) }; $tok = ''; $st = $false; $bd = 0
      $hdsh = IsShell $toks; $hd = HereWord $s ($i + 2); $hdd = $script:hdDash; $i = $script:hdJ; continue
    }
    if ($c -eq '>' -or $c -eq '<') {
      if ($tok -and $tok -notmatch '^[0-9]+$' -and $tok -ne '&' -and $tok -ne '*' -and $tok -notmatch '[<>]$') { $toks.Add($tok); $tok = ''; $bd = 0 }
      $tok += $c; $st = $true; continue
    }
    if ($c -eq '&' -and ($p -eq '>' -or $p -eq '<' -or $d -eq '>')) { $tok += $c; $st = $true; continue }
    # { and } around words are groups and script blocks (& {git push}, % { ... }); inside a word they
    # are data (${HOME}, @{0}, refs/heads/main^{})
    if ($c -eq '{' -and $tok) { $bd++; $tok += $c; continue }
    if ($c -eq '}' -and $bd -gt 0) { $bd--; $tok += $c; continue }
    if ($c -eq "`n" -or $c -eq ';' -or $c -eq '|' -or $c -eq '&' -or $c -eq '(' -or $c -eq ')' -or $c -eq '{' -or $c -eq '}') {
      if ($tok) { $toks.Add($tok) }; $tok = ''; $st = $false; $bd = 0; $e = ($toks.Count -eq 0)
      Seg $toks $depth $qm $pp; $toks = New-Object System.Collections.Generic.List[string]
      $pp = ($c -eq '|' -and $d -ne '|' -and $p -ne '|') -or ($e -and $pp)
      if ($c -eq "`n" -and $hd) { $k = HereEnd $s ($i + 1) $hd $hdd; $body = $script:hdBody; $hd = ''; if ($hdsh) { Scan $body ($depth + 1) $false }; $i = $k }
      continue
    }
    $tok += $c
  }
  if ($q) { $script:fail = $true }
  if ($tok) { $toks.Add($tok) }
  Seg $toks $depth $qm $pp
}
$joined = $cmd
Scan $joined 0 $true
if ($script:fail) { $script:segs.Clear(); $script:pipes.Clear(); Scan $joined 0 $false }

# --- helpers (case-insensitive matching: GIT PUSH ORIGIN MAIN counts) ---
$REDIR = '^[0-9*]*&?[<>]'
$REDIR_OP = '^[0-9*]*&?[<>]+[&|]?$'
$RMREC = '^-[rfvidp]*r[rfvidp]*$'
$PSREC = '^-r(e(c(u(r(se?)?)?)?)?)?(:\$?true)?$'
$WT = '(^|[/\\])\.claude([/\\]worktrees([/\\][^/\\]+)?)?$'   # a worktree, the worktrees' folder, .claude

$script:dir = if ($cwd) { $cwd } elseif ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { '.' }
$script:ovDir = ''; $script:ovBranch = ''   # a checkout / switch earlier in this command: dir and branch

function IsProtected([string]$x) { $x -match '^(main|master)$' }
# A path relative to a base; "?" when it cannot be known (variables). . and ./ are the base itself.
function Compose([string]$b, [string]$p) {
  while ($p.StartsWith('./') -or $p.StartsWith('.\')) { $p = $p.Substring(2) }
  if ($p -eq '.') { $p = '' }
  if (-not $p) { return $b }
  if ($p.Contains('$') -or $p.Contains('%')) { return '?' }
  if ($p -eq '~' -or $p.StartsWith('~/') -or $p.StartsWith('~\')) { return $HOME + $p.Substring(1) }
  if ($p -match '^([/\\]|[A-Za-z]:)') { return $p }
  if ($b -eq '?') { return '?' }
  "$b/$p"
}
# Canon: above, with the edit-tool check
function BranchIn([string]$dd) {
  if ($dd -ceq $script:ovDir) { return $script:ovBranch }
  if ($dd -eq '?') { return '' }
  $b = git -C $dd symbolic-ref --short -q HEAD 2>$null
  if ($LASTEXITCODE -eq 0) { "$b".Trim() } else { '' }
}
# refs/heads/main^{} , heads/main , main~0 , HEAD@{0} -> the branch name
function NormRef([string]$x) {
  $x = $x -creplace '(\^\{[^}]*\}|[~^][0-9]*|@\{[^}]*\})+$', ''
  if ($x -match '^refs/heads/') { $x = $x.Substring(11) } elseif ($x -match '^heads/') { $x = $x.Substring(6) }
  $x
}
function IsCurrent([string]$x) { $x -eq '' -or $x -eq 'HEAD' -or $x -eq '@' -or $x.Contains('$') }

# --- git push: protected targets, every-branch pushes, pushes resolving to a protected current branch ---
# Work branches may be pushed, force-pushed (e.g. after a rebase) and deleted freely.
function PushSeg([string]$dd, [string[]]$a) {
  $remote = $false; $refs = 0; $cur = $false; $tags = $false; $skip = $false
  foreach ($t in $a) {
    if ($skip) { $skip = $false; continue }
    if ($t -eq '--mirror') { Block 'mirror push (overwrites every branch, incl. protected ones)' }
    if ($t -eq '--all' -or $t -eq '--branches') { Block 'push of every branch (incl. protected ones)' }
    if ($t -eq '--tags') { $tags = $true; continue }
    if ($t -like '--repo=*') { $remote = $true; continue }
    if ($t -eq '--repo') { $remote = $true; $skip = $true; continue }
    if ($t -eq '-o' -or $t -eq '--push-option' -or $t -eq '--receive-pack' -or $t -eq '--exec') { $skip = $true; continue }
    if ($t.StartsWith('-')) { continue }
    if (-not $remote) { $remote = $true; continue }
    $refs++
    $r = if ($t.StartsWith('+')) { $t.Substring(1) } else { $t }
    if ($r -eq '' -or $r -eq ':') { Block 'push of all matching branches (incl. protected ones)' }
    if ($r.Contains(':')) { $dst = $r.Substring($r.IndexOf(':') + 1); if (-not $dst) { $dst = $r.Substring(0, $r.IndexOf(':')) } } else { $dst = $r }
    $dst = NormRef $dst
    if (IsProtected $dst) { Block 'push to a protected branch' }
    if (IsCurrent $dst) { $cur = $true }
  }
  if ($refs -eq 0 -and $tags) { return }   # tags only: not a branch push
  if ($refs -eq 0 -or $cur) {
    $br = BranchIn $dd
    if (IsProtected $br) { Block "push while on $br" }
  }
}
# --- deleting a protected branch (any delete flag, the name anywhere in the arguments) ---
function BranchSeg([string[]]$a) {
  $del = $false; $names = @()
  foreach ($t in $a) {
    if ($t -eq '--delete') { $del = $true } elseif ($t.StartsWith('--')) { } elseif ($t.StartsWith('-')) { if ($t -match 'd') { $del = $true } } else { $names += $t }
  }
  if (-not $del) { return }
  foreach ($t in $names) { if (IsProtected (NormRef $t)) { Block 'deleting a protected branch' } }
}
function UpdRefSeg([string[]]$a) {
  $del = $false; $names = @()
  foreach ($t in $a) { if ($t -eq '-d' -or $t -eq '--delete') { $del = $true } elseif (-not $t.StartsWith('-')) { $names += $t } }
  if (-not $del) { return }
  foreach ($t in $names) { if (IsProtected (NormRef $t)) { Block 'deleting a protected branch' } }
}
# git checkout / switch: a later bare push in the same directory pushes that branch.
function CheckoutSeg([string]$dd, [string[]]$a) {
  $newb = ''; $first = ''; $nx = $false; $track = $false; $nargs = 0
  foreach ($t in $a) {
    if ($nx) { $newb = $t; $nx = $false; continue }
    if ($t -eq '--') { return }
    if ($t -eq '-b' -or $t -eq '-c' -or $t -eq '--create' -or $t -eq '--force-create' -or $t -eq '--orphan') { $nx = $true }
    elseif ($t -eq '--detach') { $newb = '(detached)' }
    elseif ($t -eq '-t' -or $t -eq '--track' -or $t -like '--track=*') { $track = $true }
    elseif ($t -eq '-') { $nargs++; if (-not $first) { $first = '-' } }
    elseif ($t.StartsWith('-')) { }
    else { $nargs++; if (-not $first) { $first = $t } }
  }
  if ($newb) { $script:ovDir = $dd; $script:ovBranch = $newb; return }
  if (-not $first) { return }
  if ($nargs -gt 1) { return }   # git checkout <branch> <file>: restores a file, the branch stays
  # git checkout - : the previous branch (after a checkout earlier in this command: the current one)
  if ($first -eq '-') {
    if ($dd -eq '?') { return }
    if ($dd -ceq $script:ovDir) { $prev = git -C $dd symbolic-ref --short -q HEAD 2>$null }
    else { $prev = git -C $dd rev-parse --abbrev-ref '@{-1}' 2>$null }
    $prev = "$prev".Trim()
    if ($LASTEXITCODE -eq 0 -and $prev) { $script:ovDir = $dd; $script:ovBranch = $prev }
    return
  }
  # --track origin/main creates and checks out main
  if ($track -and $first.Contains('/')) { $script:ovDir = $dd; $script:ovBranch = $first.Substring($first.IndexOf('/') + 1); return }
  $known = IsProtected (NormRef $first)
  if (-not $known -and $dd -ne '?') { git -C $dd show-ref -q --verify "refs/heads/$first" 2>$null | Out-Null; $known = ($LASTEXITCODE -eq 0) }
  if ($known) { $script:ovDir = $dd; $script:ovBranch = $first }
}
function GitSeg([string[]]$a) {
  $eff = $script:dir; $i = 0
  while ($i -lt $a.Count) {
    $t = $a[$i]
    if ($t -ceq '-C') { $v = if ($i + 1 -lt $a.Count) { $a[$i + 1] } else { '' }; $eff = Compose $eff $v; $i += 2; continue }
    if ($t -match '^(-c|--git-dir|--work-tree|--namespace|--config-env|--super-prefix)$') { $i += 2; continue }
    if ($t.StartsWith('-')) { $i++; continue }
    break
  }
  if ($i -ge $a.Count) { return }
  $sub = $a[$i]; $rest = @(if ($i + 1 -lt $a.Count) { $a[($i + 1)..($a.Count - 1)] })
  switch ($sub.ToLowerInvariant()) {
    'push' { PushSeg $eff $rest }
    'branch' { BranchSeg $rest }
    'update-ref' { UpdRefSeg $rest }
    'checkout' { CheckoutSeg $eff $rest }
    'switch' { CheckoutSeg $eff $rest }
    'worktree' { WorktreeSeg $rest }
  }
}
# git worktree remove --force throws away what the worktree holds: the cleanup script checks first
function WorktreeSeg([string[]]$a) {
  if ($a.Count -eq 0 -or $a[0] -ne 'remove') { return }
  foreach ($t in $a) { if ($t -match '^(--force|-f|-ff)$') { Block 'removing a worktree by force (use the cleanup script)' } }
}
function CdSeg([string[]]$a) {
  $x = ''
  foreach ($t in $a) { if (-not $t.StartsWith('-')) { $x = $t; break } }
  if (-not $x) { $x = '~' }
  if ($x -eq '-') { $script:dir = '?'; return }
  $script:dir = Compose $script:dir $x
}
# --- irreversible removals: / , a drive, home, or a worktree by hand ---
function StripAll([string]$x) {   # x/* , x/** , x/. and trailing separators -> x
  while ($true) {
    if ($x -match '[/\\]\*\*$') { $x = $x.Substring(0, $x.Length - 1) }
    elseif ($x -match '[/\\][*.]$') { $x = $x.Substring(0, $x.Length - 2) }
    elseif ($x -match '[/\\]$') { $x = $x.Substring(0, $x.Length - 1) }
    else { break }
  }
  $x
}
# home and the project's folders (CLAUDE_PROJECT_DIR, the top of the repository the session works in and
# that repository's main checkout, from a worktree), each in canon form as written and as it lies on disk
# (links resolved); read once, on the first removal
$script:roots = $null; $script:homes = $null
function ProtectedForms {
  if ($null -ne $script:roots) { return }
  $script:roots = @(); $script:homes = @()
  $hs = @(); foreach ($h in @($HOME, $env:USERPROFILE, $env:HOME)) { if ($h) { $hs += $h } }
  $rs = @()
  if ($env:CLAUDE_PROJECT_DIR) { $rs += $env:CLAUDE_PROJECT_DIR }
  $c = if ($cwd) { $cwd } else { $env:CLAUDE_PROJECT_DIR }
  if ($c) {
    $out = @(git -C $c rev-parse --path-format=absolute --show-toplevel --git-common-dir 2>$null)
    if ($LASTEXITCODE -eq 0 -and $out.Count -ge 2) {
      $rs += $out[0]
      if ($out[1] -match '/\.git$') { $rs += $out[1].Substring(0, $out[1].Length - 5) }
    }
  }
  # the same folder in several forms (C:\Users\x and /c/Users/x; CLAUDE_PROJECT_DIR and the repository's
  # top) is resolved once
  $seen = @()
  foreach ($h in $hs) {
    $c = Canon $h; if ($seen -ccontains $c) { continue }; $seen += $c
    $script:homes += $c; $ph = Physical $h; if ($null -ne $ph) { $script:homes += $ph }
  }
  $seen = @()
  foreach ($r in $rs) {
    $c = Canon $r; if ($seen -ccontains $c) { continue }; $seen += $c
    $script:roots += $c; $ph = Physical $r; if ($null -ne $ph) { $script:roots += $ph }
  }
}
# a path and the folders that hold it: is $full one of them
function Holds([string]$full, [string]$p) { "$p/".StartsWith("$full/", [StringComparison]::Ordinal) }
function RmTarget([string]$t, [bool]$proj = $true) {
  $x = StripAll $t
  if ($x -match $WT) { Block 'removing a worktree by hand (use the cleanup script)' }
  if ($x -match '^(|~|\$HOME|\$\{HOME\}|\$env:USERPROFILE|\$\{env:USERPROFILE\}|\$env:HOME|\$env:HOMEDRIVE|\$env:SystemDrive|%USERPROFILE%|%HOMEDRIVE%|%SystemDrive%|[A-Za-z]:)$') {
    Block 'recursive removal of /, a drive or home'
  }
  # ~name: a user's home (~ followed by a name, nothing after it but /, /* or /**) - in bash; the
  # PowerShell tool does not expand it (Remove-Item ~tmp is a folder named ~tmp)
  if ($tool -cne 'PowerShell' -and $x -match '^~[^/\\]+$') { Block 'recursive removal of /, a drive or home' }
  # the full path: relative targets (., *, .., x) from the directory a cd led to; home given literally
  # (/c/Users/x, C:\Users\x), a drive as /c, /mnt/c or /cygdrive/c; . and x/.. taken out
  $fr = Compose $script:dir $t
  if ($fr -eq '?') { return }
  $fr = StripAll $fr
  $full = Canon $fr
  if ($full -match '^([a-z]:)?$') { Block 'recursive removal of /, a drive or home' }
  # . or * inside a worktree (after a cd to it, or with it as the working folder), .. up to one
  if ($full -match $WT) { Block 'removing a worktree by hand (use the cleanup script)' }
  # the same checks on the path as it lies on disk (a link to the project, home or a worktree, #121)
  $forms = @($full)
  $ph = Physical $fr; if ($null -ne $ph) { $forms += $ph }
  ProtectedForms
  foreach ($f in $forms) {
    if ($f -match '^([a-z]:)?$') { Block 'recursive removal of /, a drive or home' }
    if ($f -match $WT) { Block 'removing a worktree by hand (use the cleanup script)' }
    # home or a folder that holds it
    foreach ($h in $script:homes) { if (Holds $f $h) { Block 'recursive removal of /, a drive or home' } }
  }
  if (-not $proj) { return }
  # the project's folder or a folder that holds it
  foreach ($f in $forms) {
    foreach ($r in $script:roots) { if (Holds $f $r) { Block 'recursive removal of the project or a folder that holds it' } }
  }
}
function RmSeg([string]$b, [string[]]$a) {
  $rec = $false; $dd = $false; $tg = @()
  foreach ($t in $a) {
    if ($dd) { $tg += $t; continue }
    if ($t -eq '--') { $dd = $true; continue }
    if ($t -eq '--recursive') { $rec = $true; continue }
    if ($t.StartsWith('--')) { continue }
    $cmdStyle = $b -match '^(rd|rmdir|del|erase)$'
    if ($t -eq '/s' -and $cmdStyle) { $rec = $true; continue }
    if (($t -eq '/q' -or $t -eq '/f') -and $cmdStyle) { continue }
    if ($t.StartsWith('-')) { if ($t -match $RMREC -or $t -match $PSREC) { $rec = $true }; continue }
    $tg += $t
  }
  if (-not $rec) { return }
  # Get-ChildItem C:\ | Remove-Item -Recurse : the paths come through the pipe
  if ($tg.Count -eq 0 -and $script:piped) { $tg = @($script:prevTg) }
  foreach ($t in $tg) { RmTarget $t }
}
# the paths a listing (Get-ChildItem, ls, dir) hands on through a pipe; none: the current directory
function ListSeg([string[]]$a) {
  $l = @(); foreach ($t in $a) { if (-not $t.StartsWith('-')) { $l += $t } }
  if ($l.Count -eq 0) { $l = @('.') }
  $script:curTg = $l
}
# find <path> -delete: the paths before the first expression; with a test (-name ...) it deletes what
# matches, so the project's folder may be its path
function FindSeg([string[]]$a) {
  $del = $false; $on = $true; $all = $true; $tg = @()
  foreach ($t in $a) {
    if ($t -eq '-delete') { $del = $true } elseif ($t -eq '-depth') { $on = $false }
    elseif ($t.StartsWith('-') -or $t -eq '!') { $on = $false; $all = $false } elseif ($on) { $tg += $t } else { $all = $false }
  }
  if (-not $del) { return }
  foreach ($t in $tg) { RmTarget $t $all }
}

$script:curTg = @()
for ($si = 0; $si -lt $script:segs.Count; $si++) {
  $segT = $script:segs[$si]
  $script:prevTg = $script:curTg; $script:curTg = @()
  $script:piped = $script:pipes[$si]
  # redirections (2>&1, > out.txt) are not arguments
  $words = @(); $skip = $false
  foreach ($t in $segT) {
    if ($skip) { $skip = $false; continue }
    if ($t -match $REDIR) { if ($t -match $REDIR_OP) { $skip = $true }; continue }
    $words += $t
  }
  # the command word: after wrappers ({ ( ! then do sudo env ...), their options (sudo -E,
  # timeout -k 5 30, nice -n 5, stdbuf -oL ...) and VAR=value assignments
  $i = CmdIdx $words
  if ($i -ge $words.Count) { continue }
  $cw = BaseName $words[$i]
  $rest = @(if ($i + 1 -lt $words.Count) { $words[($i + 1)..($words.Count - 1)] })
  switch -regex ($cw) {
    '^git$' { GitSeg $rest }
    '^(cd|pushd|chdir|set-location|sl|push-location)$' { CdSeg $rest }
    '^(rm|remove-item|ri|del|erase|rd|rmdir)$' { RmSeg $cw $rest }
    '^find$' { FindSeg $rest }
    '^(get-childitem|gci|ls|dir|get-item|gi)$' { ListSeg $rest }
  }
}

# --- project-specific patterns: one per line, trimmed; blank lines and # comments skipped ---
# (POSIX classes such as [[:space:]] work in both scripts)
$proj = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { '.' }
$denyFile = Join-Path $proj '.claude/coordinator-deny.txt'
if (Test-Path -LiteralPath $denyFile) {
  # a deny file that is there but cannot be read (no read permission, a folder) blocks every call
  $denyBytes = $null
  try {
    if (-not (Test-Path -LiteralPath $denyFile -PathType Leaf)) { throw 'not a file' }
    $denyBytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $denyFile).Path)
  } catch { Block 'project rule file cannot be read: .claude/coordinator-deny.txt' }
  # UTF-16 (what Windows PowerShell 5.1's > writes: a FF FE or FE FF BOM, NUL bytes) blocks every call
  # until it is saved as UTF-8, as in safety-guard.sh, which cannot read it
  if (($denyBytes.Length -ge 2 -and (($denyBytes[0] -eq 0xFF -and $denyBytes[1] -eq 0xFE) -or ($denyBytes[0] -eq 0xFE -and $denyBytes[1] -eq 0xFF))) -or
      [Array]::IndexOf($denyBytes, [byte]0) -ge 0) {
    Block 'project rule file cannot be read: .claude/coordinator-deny.txt (not UTF-8: re-save it as UTF-8)'
  }
  $denyText = (New-Object System.Text.UTF8Encoding $false).GetString($denyBytes)
  if ($denyText.StartsWith([string][char]0xFEFF)) { $denyText = $denyText.Substring(1) }   # a UTF-8 BOM
  $denyLines = $denyText -split "`r?`n"
  foreach ($line in $denyLines) {
    $p = $line.Trim()
    if (-not $p -or $p.StartsWith('#')) { continue }
    $re = $p.Replace('[:space:]', '\s').Replace('[:alnum:]', 'A-Za-z0-9').Replace('[:alpha:]', 'A-Za-z').Replace('[:digit:]', '0-9')
    try { [void][regex]::new($re) } catch { Block "project rule cannot be read: $p" }
    if (Has $re) { Block "project rule: $p" }
  }
}
exit 0
