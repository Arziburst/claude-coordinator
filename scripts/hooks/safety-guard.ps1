# PreToolUse safety hook for coordinator projects (Windows; macOS / Linux: safety-guard.sh - the same
# rules, checked against the same cases: tests/safety-guard/cases.txt).
# With COORD_ASSISTANT_DIR set (the assistant mode, #281): the edit tools only inside that folder, git and
# gh only a known read (an allowlist).
# Reads the tool call JSON on stdin; exit 2 blocks the call and shows the reason to Claude.
# A safety net only - the real enforcement is branch protection on the code host (CORE section 2);
# deliberate obfuscation (iex, cmd /c, quoting tricks ...) is out of scope (TOOLKIT.md *Safety*).
# Extra project patterns (one regular expression per line, '#' comments; a pattern that cannot be read
# blocks every call): .claude/coordinator-deny.txt
# Self-test: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\hooks\safety-guard.ps1 -SelfTest
# Windows PowerShell 5.1 or PowerShell 7; nothing to install.
param([switch]$SelfTest)

# The protected branches: main, master and the names in COORD_PROTECTED_BRANCHES (separated by spaces
# and/or commas; TOOLKIT.md *Safety*) - a list adds to main and master, never replaces them. Each is
# compared whole and literally (no patterns: . + * / are plain characters), letter case ignored.
$PROT = @('main', 'master')
foreach ($b in @("$env:COORD_PROTECTED_BRANCHES" -split '[ \t\n,]+' | Where-Object { $_ })) {   # as safety-guard.sh splits them
  if ($PROT -notcontains $b) { $PROT += $b }   # once each (-notcontains ignores letter case)
}

if ($SelfTest) {
  # a push to main must block (exit 2) and a work-branch push must pass (exit 0): a guard that blocks
  # everything is not working either. Both with the assistant mode off (it refuses every push); in an
  # assistant's session (#281) also its own: a commit blocks, a log passes
  $exe = (Get-Process -Id $PID).Path
  $ad = $env:COORD_ASSISTANT_DIR; $env:COORD_ASSISTANT_DIR = $null
  '{"tool_input":{"command":"git push --force origin main"}}' |
    & $exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath 2>$null | Out-Null
  $blocked = $LASTEXITCODE
  '{"tool_input":{"command":"git push origin 12-fix"}}' |
    & $exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath 2>$null | Out-Null
  $ok = $LASTEXITCODE -eq 0
  $env:COORD_ASSISTANT_DIR = $ad
  if ($ad) {
    '{"tool_input":{"command":"git commit -m x"}}' |
      & $exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath 2>$null | Out-Null
    if ($LASTEXITCODE -ne 2) { $ok = $false }
    '{"tool_input":{"command":"git log -1"}}' |
      & $exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { $ok = $false }
  }
  if ($blocked -eq 2 -and $ok) { 'safety-guard: OK'; exit 0 }
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
$to = if ($d.tool_input.to -is [string]) { $d.tool_input.to -replace '[\r\n]', ' ' } else { '' }

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

# --- own sessions only (CORE section 1.17): claude stop / rm / respawn / attach <id>, claude --resume
# <id> and the SendMessage tool are blocked for a session whose working folder is outside the project ---
# The sessions come from `claude agents --json --all`, read only for those calls; a session it does not
# list, or a listing that cannot be read, passes (nothing to tell it by). The project's folders:
# CLAUDE_PROJECT_DIR, the top of the repository the call works in and that repository's main checkout
# (their .claude/worktrees inside them), and the worktree roots of <folder>/coordinator/PROJECT.md
# (its Settings row "Worktree roots", as scripts/retro reads it); each as written and as it lies on disk,
# whole path segments compared (<root>-old is another folder), letter case ignored on Windows and macOS.
$smKeep = -not (($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows -or $IsMacOS)
$script:agents = $null
function ReadAgents {   # each session as @(id, sessionId, cwd, name)
  if ($null -ne $script:agents) { return }
  $script:agents = @()
  if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { return }
  # its output is UTF-8 (a folder or a name in Cyrillic), whatever the console's code page
  $enc = $null; try { $enc = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
  try { $out = @(& claude agents --json --all 2>$null | ForEach-Object { "$_" }); $rc = $LASTEXITCODE }
  catch { $rc = 1 }
  finally { if ($enc) { try { [Console]::OutputEncoding = $enc } catch { } } }
  if ($rc -ne 0) { return }
  # a line before the JSON (a notice, a BOM) is skipped, as the .sh reader skips it
  $txt = ($out -join "`n").TrimStart([char]0xFEFF); $k = $txt.IndexOfAny([char[]]@('[', '{')); if ($k -gt 0) { $txt = $txt.Substring($k) }
  try { $list = ConvertFrom-Json -InputObject $txt -ErrorAction Stop } catch { return }
  foreach ($s in $list) { if ($null -ne $s) { $script:agents += , @([string]$s.id, [string]$s.sessionId, [string]$s.cwd, [string]$s.name) } }
}
$script:owns = $null
function OwnForms {
  if ($null -ne $script:owns) { return }
  $script:owns = @(); $rs = @()
  if ($env:CLAUDE_PROJECT_DIR) { $rs += $env:CLAUDE_PROJECT_DIR }
  $c = if ($cwd) { $cwd } else { $env:CLAUDE_PROJECT_DIR }
  if ($c) {
    $out = @(git -C $c rev-parse --path-format=absolute --show-toplevel --git-common-dir 2>$null)
    if ($LASTEXITCODE -eq 0 -and $out.Count -ge 2) {
      $rs += $out[0]
      if ($out[1] -match '/\.git$') { $rs += $out[1].Substring(0, $out[1].Length - 5) }
    }
  }
  $script:wtRel = @()   # the declared worktree roots as written (also for #263 below)
  foreach ($r in $rs) {
    $pm = "$r/coordinator/PROJECT.md"
    if (-not (Test-Path -LiteralPath $pm -PathType Leaf)) { continue }
    $b = $r.Replace('\', '/').TrimEnd('/')
    foreach ($line in [IO.File]::ReadAllLines($pm)) {
      $cells = $line.Split('|'); if ($cells.Count -lt 3 -or $cells[1] -cnotmatch '^[ \t]*[*]*Worktree roots[*]*[ \t]*\z') { continue }
      foreach ($x in $cells[2].Replace('`', '').Split([char[]]@(',', ';'))) {
        $x = $x.Trim(' ', "`t"); $y = $x.ToLowerInvariant()
        if (-not $x -or $x -eq '-' -or $y -ceq 'none' -or $y -ceq 'n/a' -or $x -cmatch '^<.*>\z') { continue }
        $w = $x.Replace('\', '/')
        if ($w -notmatch '^(/|[A-Za-z]:)') { $w = "$b/$w" }   # .. is taken out by Canon
        $script:wtRel += $w
      }
    }
  }
  foreach ($r in ($rs + $script:wtRel)) {
    $f = Canon $r -Keep:$smKeep; if ($f -and $f -ne '.') { $script:owns += $f }   # / or nothing is no project folder
    $ph = Physical $r -Keep:$smKeep; if ($ph -and $ph -ne '.') { $script:owns += $ph }
  }
}
function IsOwn([string]$p) {   # a session's cwd inside one of the project's folders
  $forms = @(Canon $p -Keep:$smKeep); $ph = Physical $p -Keep:$smKeep; if ($null -ne $ph) { $forms += $ph }
  foreach ($f in $forms) {
    if (-not $f) { continue }
    foreach ($o in $script:owns) { if ("$f/".StartsWith("$o/", [StringComparison]::Ordinal)) { return $true } }
  }
  $false
}
# SessionCheck <what> <address> <id | send>: id - a UUID is a sessionId, anything else a short id; send -
# a name (also without a trailing " [ref]"), an id or a sessionId. Blocks when the sessions it names are
# all outside the project; a name is blocked when any session of another project has it, an own one too
# (a message to a shared name may reach both: #201)
function SessionCheck([string]$what, [string]$a, [string]$how) {
  if (-not $a) { return }
  $nm = ''; if ($how -eq 'send' -and $a -cmatch '^(.*) \[.*\]\z') { $nm = $Matches[1] }
  $uuid = $a -cmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z'
  ReadAgents
  $own = $false; $foreign = ''
  foreach ($s in $script:agents) {
    if ($how -eq 'send') { $hit = ($s[3] -ceq $a) -or ($s[0] -ceq $a) -or ($s[1] -ceq $a) -or ($nm -and $s[3] -ceq $nm) }
    elseif ($uuid) { $hit = $s[1] -eq $a } else { $hit = $s[0] -eq $a }   # ids are hex: either letter case
    if (-not $hit) { continue }
    OwnForms
    if ($script:owns.Count -eq 0) { return }   # no project folder known: nothing to tell it by
    if ($s[2] -and -not (IsOwn $s[2])) { $foreign = $s[2] } else { $own = $true }
  }
  if ($own -and $foreign -and $how -eq 'send') {
    [Console]::Error.WriteLine("Blocked by safety-guard: $what a name a session of another project has too ($foreign): it may reach that session. Give this project's session a name of its own.")
    exit 2
  }
  if (-not $own -and $foreign) {
    [Console]::Error.WriteLine("Blocked by safety-guard: $what a session of another project ($foreign). Ask the owner.")
    exit 2
  }
}
# claude stop | rm | respawn | attach <id>..., claude ... --resume <id> (-r <id>, --resume=<id>)
# gh pr create into another repository: the worker safety file allows `gh pr create --draft *` past
# Claude Code's classifier (#261), and the * would take in any repository the token reaches. Blocked:
# --repo / --repo=x, a single-dash group with an R (-R, -Rx, -dR x: gh reads grouped short flags), the
# same before `pr` (gh -R x pr create), and GH_REPO= before gh. With letter case: -r is gh's --reviewer.
function GhRepoFlag([string]$t) {
  $k = ($t -split '=', 2)[0]
  if ($k -ceq '--repo') { return $true }
  if ($k.StartsWith('--', [StringComparison]::Ordinal)) { return $false }
  return ($k -cmatch '^-[^-=]*R')
}
function GhSeg([string[]]$a, [bool]$repoEnv) {
  $pre = $false; $i = 0
  while ($i -lt $a.Count) {
    $t = $a[$i]
    if ($t.StartsWith('-', [StringComparison]::Ordinal)) { if (GhRepoFlag $t) { $pre = $true }; $i++; continue }
    if ($t -ceq 'pr') { break }
    if (-not $pre) { return }
    $i++   # after gh -R: its value
  }
  if ($i -ge $a.Count -or $a[$i] -cne 'pr') { return }
  $i++
  while ($i -lt $a.Count) {   # flags between pr and its subcommand: gh pr -R x create
    $t = $a[$i]
    if ($t.StartsWith('-', [StringComparison]::Ordinal)) { if (GhRepoFlag $t) { $pre = $true }; $i++; continue }
    if ($t -ceq 'create') { break }
    if (-not $pre) { return }
    $i++
  }
  if ($i -ge $a.Count -or $a[$i] -cne 'create') { return }
  $i--   # the scan below skips pr and create: here, the word before create
  if ($repoEnv) { Block 'a pull request into another repository (gh pr create with GH_REPO): only into the current one (#261)' }
  if ($pre) { Block 'a pull request into another repository (gh -R before pr create): only into the current one (#261)' }
  foreach ($t in @($a | Select-Object -Skip ($i + 2))) {
    if (GhRepoFlag $t) { Block "a pull request into another repository (gh pr create $(($t -split '=', 2)[0])): only into the current one (#261)" }
  }
}
function ClaudeSeg([string[]]$a) {
  $verb = ''; $nx = $false
  foreach ($t in $a) {
    if ($nx) { $nx = $false; SessionCheck 'claude --resume' $t 'id'; continue }
    if ($t -eq '--resume' -or $t -eq '-r') { $nx = $true }
    elseif ($t -like '--resume=*') { SessionCheck 'claude --resume' $t.Substring(9) 'id' }
    elseif ($t -cmatch '^-r(.+)$') { SessionCheck 'claude --resume' $Matches[1] 'id' }   # -r<id>: the value glued to the short flag
    elseif ($t.StartsWith('-')) { }
    elseif (-not $verb) { $verb = if ($t -match '^(stop|rm|respawn|attach)$') { $t } else { '-' } }
    elseif ($verb -ne '-') { SessionCheck "claude $verb" $t 'id' }
  }
}

# --- the assistant mode (#281): with COORD_ASSISTANT_DIR set, an assistant edits only inside that folder,
# and writes nothing to git or GitHub (AsstGit, AsstGh below). An edit tool passes for a path that lies, as
# it lies on disk (links resolved, #121; as written when none of it is known), in the folder or is the
# folder, in either of the folder's forms (as written, as on disk) - also under COORD_PROTECTED_ROOT, whose
# check below is then skipped; every other path, or none, is refused. A folder set but not absolute (or /,
# or a drive) refuses every edit: a broken mode never fails open. Unset or empty changes nothing. ---
$asst = [string]$env:COORD_ASSISTANT_DIR
if ($asst -and $tool -cmatch '^(Edit|Write|MultiEdit|NotebookEdit)$') {
  function ABlock([string]$why) { [Console]::Error.WriteLine("Blocked by safety-guard: an assistant edits only inside its own folder, COORD_ASSISTANT_DIR ($asst)$why. If this is a false positive, ask the owner."); exit 2 }
  if ($asst -notmatch '^([/\\]|[A-Za-z]:[/\\])') { ABlock ", which is not an absolute path: every edit is refused until it names the assistant's folder" }
  $keep = -not (($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows -or $IsMacOS)
  $aroots = @(Canon $asst -Keep:$keep)
  $ph = Physical $asst -Keep:$keep; if ($null -ne $ph) { $aroots += $ph }
  foreach ($r in $aroots) { if ($r -match '^([A-Za-z]:)?$') { ABlock ", which is / or a drive: every edit is refused until it names the assistant's folder" } }
  $any = $false
  foreach ($p in @($d.tool_input.file_path, $d.tool_input.notebook_path)) {
    if ($p -isnot [string] -or -not $p) { continue }
    $any = $true
    # a path holding a line break or a carriage return is refused (as in safety-guard.sh, whose reader
    # splits its fields at line breaks)
    if ($p.IndexOfAny([char[]]@("`n", "`r")) -ge 0) { ABlock ': a path that holds a line break or a carriage return is refused' }
    $full = $p
    if ($full -notmatch '^([/\\]|[A-Za-z]:)') {
      $base = if ($cwd) { $cwd } elseif ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { (Get-Location).Path }
      $full = "$base/$full"
    }
    $f = Physical $full -Keep:$keep; if ($null -eq $f) { $f = Canon $full -Keep:$keep }
    $ok = $false
    foreach ($r in $aroots) { if ("$f/".StartsWith("$r/", [StringComparison]::Ordinal)) { $ok = $true } }
    if (-not $ok) { ABlock ", not $p" }
  }
  if (-not $any) { ABlock ': this call names no path' }
}
# --- the owner's working copy: no edit tool under COORD_PROTECTED_ROOT outside its .claude/worktrees/ ---
# Opt-in: unset or empty changes nothing. A relative path counts from the call's cwd; whole path segments
# are compared (<root>-old is another folder), letter case ignored on Windows and macOS only.
if ($env:COORD_PROTECTED_ROOT -and -not $asst -and $tool -cmatch '^(Edit|Write|MultiEdit|NotebookEdit)$') {
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
# a message to another session (CORE section 1.17): its address looked up in the listing
if ($tool -ceq 'SendMessage') { SessionCheck 'a message to' $to 'send' }
# Line continuations: backslash-newline (bash) and backtick-newline (PowerShell) join the lines.
$cmd = $cmd.Replace("`r`n", "`n").Replace("\`n", '').Replace('`' + "`n", ' ')
# Comment lines (a "#" at the start of a line) do not count for the project patterns.
$lines = @($cmd -split "`n" | Where-Object { $_ -notmatch '^\s*#' })
if (-not ($lines -join '')) { exit 0 }

function Block([string]$why) {
  [Console]::Error.WriteLine("Blocked by safety-guard: $why. If this is a false positive, ask the owner.")
  exit 2
}
# --- the self-test's probe (SELFTEST step 2a, #259): `selftest probes` writes a random token into the
# project's .claude/coordinator-probe.txt for the length of its run and starts sessions told to run
# `echo <token>`; a Bash / PowerShell command holding the token is blocked. That block in a probe's
# transcript shows Claude Code runs this hook from that session's settings and honours exit 2, with
# nothing in the probe a classifier could refuse (sessions told to push to main were refused, #218,
# #235). A file that is missing, unreadable or holds no token of 16+ letters, digits and - is ignored. ---
$probePd = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { '.' }
$probeFile = Join-Path (Join-Path $probePd '.claude') 'coordinator-probe.txt'
if ($cmd -and (Test-Path -LiteralPath $probeFile -PathType Leaf)) {
  $probeTok = ''
  try { $probeTok = [string](Get-Content -LiteralPath $probeFile -TotalCount 1 -ErrorAction Stop) } catch { $probeTok = '' }
  if ($probeTok.Length -ge 16 -and $probeTok -cmatch '^[A-Za-z0-9-]+$' -and $cmd.Contains($probeTok)) { Block "the self-test's probe token (.claude/coordinator-probe.txt): this hook runs and its block holds" }
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
$WRAP = '^([{}!]|then|do|else|elif|if|while|until|time|nohup|command|exec|builtin|noglob)$'
$ASSIGN = '^[A-Za-z_][A-Za-z0-9_]*='
# wrappers with options of their own: the options that take a value
function OptArg([string]$t) {
  switch ($t) { 'sudo' { '^-[ugpcdrt]$' } 'env' { '^-[usc]$' } 'timeout' { '^-[sk]$' } 'nice' { '^-n$' } 'stdbuf' { '^-[ioe]$' }
    # macOS: caffeinate -i, arch -arm64, script -q <file> <command>
    'caffeinate' { '^-[tw]$' } 'arch' { '^-(arch|e|d)$' } 'script' { '^-[tTc]$' }
    # xargs -I {} -n 1 ... (not -i: its value is glued)
    'xargs' { '^-[InPLdEsa]$' } default { '' } }
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
function BaseName([string]$t) { $b = ($t.ToLowerInvariant().TrimStart('=') -split '[/\\]')[-1]; if ($b.EndsWith('.exe')) { $b = $b.Substring(0, $b.Length - 4) }; $b }
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
# Unesc: a word with each backslash taken as the shell takes an unquoted one (ma\in is main)
function Unesc([string]$t) { [regex]::Replace($t, '\\(.?)', '$1') }
# StartProc: Start-Process / saps / start <program> [-ArgumentList] <arguments> as one command line
# (PowerShell runs the program with them), or '' for another command
function StartProc($toks) {
  $j = CmdIdx $toks; if ($j -ge $toks.Count) { return '' }
  $b = BaseName $toks[$j]; if ($b -ne 'start-process' -and $b -ne 'saps' -and $b -ne 'start') { return '' }
  $prog = ''; $args0 = ''
  for ($k = $j + 1; $k -lt $toks.Count; $k++) {
    $lt = $toks[$k].ToLowerInvariant()
    if ($lt -match '^-f(i(l(e(p(a(t(h)?)?)?)?)?)?)?$') { $k++; if ($k -lt $toks.Count) { $prog = $toks[$k] }; continue }
    if ($lt -match '^-a(r(g(u(m(e(n(t(l(i(s(t)?)?)?)?)?)?)?)?)?)?)?$' -or $lt -eq '-args') { $k++; if ($k -lt $toks.Count) { $args0 += ' ' + $toks[$k] }; continue }
    # parameters with a value (-WorkingDirectory, -Verb, -WindowStyle, -Credential, -Environment,
    # -RedirectStandard...), by their unambiguous prefixes; -Wait, -NoNewWindow, -PassThru take none
    if ($lt -match '^-(wo|v|wi|c|e|r)') { $k++; continue }
    if ($lt.StartsWith('-')) { continue }
    if (-not $prog) { $prog = $toks[$k] } else { $args0 += ' ' + $toks[$k] }
  }
  if (-not $prog) { return '' }
  $prog + $args0.Replace(',', ' ')   # -ArgumentList push,origin,main
}
# --- brace expansion as bash does it (#345): Scan keeps the unquoted braces of a word as [char]2 and
# [char]3 (a Bash command only: PowerShell has none) ---
$B1 = [string][char]2; $B2 = [string][char]3; $BMAX = 64
function IsRange([string]$x) { $x -match '^(-?[0-9]+\.\.-?[0-9]+|[A-Za-z]\.\.[A-Za-z])(\.\.-?[0-9]+)?$' }
# BWord: the { at i, at the start of a word, opens an expansion: a comma at its top level or a range,
# closed before the word ends (else it is a group: { git push; })
function BWord([string]$s, [int]$i) {
  $dep = 0; $q = ''; $cm = $false
  for ($j = $i; $j -lt $s.Length; $j++) {
    $c = [string]$s[$j]
    if ($q) { if ($c -eq $q) { $q = '' } elseif ($c -eq '\' -and $q -eq '"') { $j++ }; continue }
    if ($c -eq '\') { $j++; continue }
    if ($c -eq "'" -or $c -eq '"') { $q = $c; continue }
    if (" `t`r`n;|&()<>".Contains($c)) { return $false }
    if ($c -eq '{') { $dep++ }
    elseif ($c -eq '}') { $dep--; if ($dep -eq 0) { return ($cm -or (IsRange $s.Substring($i + 1, $j - $i - 1))) } }
    elseif ($c -eq ',' -and $dep -eq 1) { $cm = $true }
  }
  $false
}
# InFind: the words so far are a find command (its {} and \; are words)
function InFind($toks) { if ($toks.Count -eq 0) { return $false }; $j = CmdIdx $toks; ($j -lt $toks.Count) -and ((BaseName $toks[$j]) -eq 'find') }
# BExp: the words bash makes of w into $script:bxw, as bash does it: the first brace with a comma at its
# top level or a range, each alternative with the text before and after it, again; returns their number,
# or -1 for more than BMAX words (or too much work)
function BExp([string]$w) {
  $script:bxw = New-Object System.Collections.Generic.List[string]
  $todo = New-Object System.Collections.Generic.List[string]; $todo.Add($w); $it = 0
  while ($todo.Count -gt 0) {
    $x = $todo[$todo.Count - 1]; $todo.RemoveAt($todo.Count - 1); $it++; if ($it -gt 4096) { return -1 }
    $found = $false
    for ($a = 0; $a -lt $x.Length; $a++) {
      if ($x[$a] -ne [char]2) { continue }
      $dep = 0; $cm = $false
      for ($b = $a; $b -lt $x.Length; $b++) {
        $c = $x[$b]
        if ($c -eq [char]2) { $dep++ } elseif ($c -eq [char]3) { $dep--; if ($dep -eq 0) { break } }
        elseif ($c -eq [char]'\') { $b++ }   # an escaped character (\, ) is text
        elseif ($c -eq [char]',' -and $dep -eq 1) { $cm = $true }
      }
      if ($b -lt $x.Length -and ($cm -or (IsRange $x.Substring($a + 1, $b - $a - 1)))) { $found = $true; break }
    }
    if (-not $found) { if ($script:bxw.Count -ge $BMAX) { return -1 }; $script:bxw.Add($x.Replace($B1, '{').Replace($B2, '}')); continue }
    $body = $x.Substring($a + 1, $b - $a - 1); $al = New-Object System.Collections.Generic.List[string]
    if ($cm) {
      $dep = 0; $cur = ''
      for ($k = 0; $k -lt $body.Length; $k++) {
        $c = $body[$k]
        if ($c -eq [char]'\') { $cur += $c; $k++; if ($k -lt $body.Length) { $cur += $body[$k] }; continue }
        if ($c -eq [char]2) { $dep++ } elseif ($c -eq [char]3) { $dep-- }
        if ($c -eq [char]',' -and $dep -eq 0) { $al.Add($cur); $cur = '' } else { $cur += $c }
      }
      $al.Add($cur)
    } else {
      $R = $body -split '\.\.'; $lt = $R[0] -match '^[A-Za-z]$'
      if ($lt) { $lo = [double][int][char]$R[0]; $hi = [double][int][char]$R[1] } else { $lo = [double]$R[0]; $hi = [double]$R[1] }
      $st = 1; if ($R.Count -gt 2) { $st = [Math]::Abs([double]$R[2]) }; if ($st -eq 0) { $st = 1 }
      if ([Math]::Abs($hi - $lo) / $st -ge $BMAX) { return -1 }
      $wd = 0; if ($R[0] -match '^-?0[0-9]' -or $R[1] -match '^-?0[0-9]') { $wd = [Math]::Max($R[0].Length, $R[1].Length) }
      for ($v = $lo; ($lo -le $hi -and $v -le $hi) -or ($lo -gt $hi -and $v -ge $hi); $v += $(if ($lo -le $hi) { $st } else { -$st })) {
        if ($lt) { $al.Add([string][char][int]$v); continue }
        # as the .sh: %d, or %0<wd>d (the sign counts in the width)
        $n = ([long][Math]::Abs($v)).ToString([Globalization.CultureInfo]::InvariantCulture)
        if ($v -lt 0) { $n = '-' + $n.PadLeft([Math]::Max($wd - 1, 0), [char]'0') } else { $n = $n.PadLeft($wd, [char]'0') }
        $al.Add($n)
      }
    }
    for ($k = $al.Count - 1; $k -ge 0; $k--) { $todo.Add($x.Substring(0, $a) + $al[$k] + $x.Substring($b + 1)) }
  }
  $script:bxw.Count
}
# the commands the guard reads (and the shells and Start-Process, which run others)
function Judged([string]$b) { $b -match '^(git|gh|claude|cd|pushd|chdir|set-location|sl|push-location|rm|remove-item|ri|del|erase|rd|rmdir|find|get-childitem|gci|ls|dir|get-item|gi|bash|sh|zsh|dash|ksh|pwsh|powershell|start-process|saps|start)$' }
function Seg($list, [int]$depth, [bool]$qm, [bool]$pp, [bool]$bx) {
  # each word with [char]2 [char]3 as the words bash makes of it (an empty one dropped); a word of more
  # than BMAX words stays as written, and the command is refused when that word is its command word (or
  # before it) or the command is one the guard reads
  $ex = New-Object System.Collections.Generic.List[string]; $big = -1
  foreach ($t in @($list)) {
    if ($t.IndexOf([char]2) -lt 0 -and $t.IndexOf([char]3) -lt 0) { $ex.Add($t); continue }
    $r = BExp $t
    if ($r -lt 0) { if ($big -lt 0) { $big = $ex.Count }; $ex.Add($t.Replace($B1, '{').Replace($B2, '}')); continue }
    foreach ($w in $script:bxw) { if ($w) { $ex.Add($w) } }
  }
  $toks = $ex.ToArray()
  if ($big -ge 0) {
    $j = CmdIdx $toks
    if ($big -le $j -or ($j -lt $toks.Count -and (Judged (BaseName $toks[$j])))) { Block 'a brace expansion to more than 64 words in a command the guard reads (#345): write the words out' }
  }
  if ($toks.Count -eq 0) { return }
  $clean = New-Object string[] $toks.Count
  for ($j = 0; $j -lt $toks.Count; $j++) { $clean[$j] = $toks[$j] -replace '[\t\r\n]', ' ' }
  $script:segs.Add($clean); $script:pipes.Add($pp)
  # a word with a backslash is also checked as the shell reads it unquoted (git push origin ma\in);
  # the command as written is checked too, so this only adds a check
  # (the Bash tool only: in PowerShell a backslash separates folders, its escape is the backtick)
  if ($qm -and $tool -ne 'PowerShell') {
    $un = New-Object string[] $clean.Count; $diff = $false
    for ($j = 0; $j -lt $clean.Count; $j++) { $un[$j] = Unesc $clean[$j]; if ($un[$j] -cne $clean[$j]) { $diff = $true } }
    if ($diff) { $script:segs.Add($un); $script:pipes.Add($pp) }
  }
  # find -exec / -execdir / -ok / -okdir (#345): the command up to ; (\;) or {} + is a command of its own
  $j = CmdIdx $toks
  if ($j -lt $toks.Count -and (BaseName $toks[$j]) -eq 'find') {
    for ($k = $j + 1; $k -lt $toks.Count; $k++) {
      if ($toks[$k] -notmatch '^-(exec|execdir|ok|okdir)$') { continue }
      $fx = New-Object System.Collections.Generic.List[string]
      for ($k++; $k -lt $toks.Count; $k++) {
        $t = $toks[$k]; if ($t -eq ';' -or $t -eq '\;' -or $t -eq '\' -or ($t -eq '+' -and $fx.Count -gt 0 -and $fx[$fx.Count - 1] -eq '{}')) { break }
        $fx.Add($t)
      }
      if ($fx.Count -gt 0) { Seg $fx $depth $qm $false $bx }
    }
  }
  # Start-Process runs the program itself, with no shell to expand braces
  $inner = StartProc $toks; if ($inner) { Scan $inner ($depth + 1) $qm $false }
  if (-not (IsShell $toks)) { return }
  $sbx = (BaseName $toks[$script:shJ]) -notmatch '^(pwsh|powershell)$'
  for ($k = $script:shJ + 1; $k -lt $toks.Count; $k++) { $lt = $toks[$k].ToLowerInvariant(); if ($lt -match '^-[a-z]*c$' -or $lt -match '^-com(m(a(n(d)?)?)?)?$') { break } }
  if ($k -lt $toks.Count - 1 -and $toks[$k + 1] -eq '--') { $k++ }
  if ($k -ge $toks.Count - 1) { return }
  Scan ($toks[($k + 1)..($toks.Count - 1)] -join ' ') ($depth + 1) $qm $sbx
}
function Scan([string]$s, [int]$depth, [bool]$qm, [bool]$bx) {
  if ($depth -gt 8) { return }
  $n = $s.Length; $q = ''; $tok = ''; $st = $false; $hd = ''; $hdd = $false; $hdsh = $false; $bd = 0; $bm = ''; $hbx = $false; $pp = $false
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
      if ($c -eq '$' -and $d -eq '(') { $k = ClosePar $s ($i + 2); Scan $s.Substring($i + 2, $k - $i - 2) ($depth + 1) $qm $bx; $tok += '$SUBST'; $i = $k; continue }
      if ($c -eq '`') { $k = CloseTick $s ($i + 1); Scan $s.Substring($i + 1, $k - $i - 1) ($depth + 1) $qm $bx; $tok += '$SUBST'; $i = $k; continue }
      $tok += $c; continue
    }
    if ($bx -and $c -eq '\' -and $d -eq ';' -and (InFind $toks)) { $tok += $c + $d; $st = $true; $i++; continue }   # \; of find is a word
    # inside a brace of a word an escaped character is text: no brace, no word end ({main,x\}}, {main,\;})
    if ($bx -and $c -eq '\' -and $bd -gt 0 -and $d) { $tok += $c + $d; $st = $true; $i++; continue }
    if ($qm -and $c -eq '\' -and ($d -eq '"' -or $d -eq "'" -or $d -eq '\')) { $tok += $d; $st = $true; $i++; continue }
    if ($qm -and $c -eq '$' -and $d -eq "'") { continue }   # $'...' (ANSI-C quoting): its text, as '...'
    if ($c -eq "'" -or $c -eq '"') { if ($qm) { $q = $c; $st = $true }; continue }
    if ($c -eq '$' -and $d -eq '(') { $k = ClosePar $s ($i + 2); Scan $s.Substring($i + 2, $k - $i - 2) ($depth + 1) $qm $bx; $tok += '$SUBST'; $st = $true; $i = $k; continue }
    if ($c -eq '`') { $k = CloseTick $s ($i + 1); Scan $s.Substring($i + 1, $k - $i - 1) ($depth + 1) $qm $bx; $tok += '$SUBST'; $st = $true; $i = $k; continue }
    if ($c -eq ' ' -or $c -eq "`t" -or $c -eq "`r") { if ($tok) { $toks.Add($tok) }; $tok = ''; $st = $false; $bd = 0; $bm = ''; continue }
    if ($c -eq '#' -and -not $tok -and -not $st) { while ($i -lt $n - 1 -and (Ch $s ($i + 1)) -ne "`n") { $i++ }; continue }
    if ($c -eq '<' -and $d -eq '<' -and (Ch $s ($i + 2)) -ne '<') {
      if ($tok) { $toks.Add($tok) }; $tok = ''; $st = $false; $bd = 0; $bm = ''
      $hdsh = IsShell $toks; $hbx = $hdsh -and ((BaseName $toks[$script:shJ]) -notmatch '^(pwsh|powershell)$'); $hd = HereWord $s ($i + 2); $hdd = $script:hdDash; $i = $script:hdJ; continue
    }
    if ($c -eq '>' -or $c -eq '<') {
      if ($tok -and $tok -notmatch '^[0-9]+$' -and $tok -ne '&' -and $tok -ne '*' -and $tok -notmatch '[<>]$') { $toks.Add($tok); $tok = ''; $bd = 0; $bm = '' }
      $tok += $c; $st = $true; continue
    }
    if ($c -eq '&' -and ($p -eq '>' -or $p -eq '<' -or $d -eq '>')) { $tok += $c; $st = $true; continue }
    # { and } around words are groups and script blocks (& {git push}, % { ... }); inside a word they
    # are data (${HOME}, @{0}, refs/heads/main^{}). In a Bash command a brace in a word, one opening an
    # expansion ({main,} , {1..3}) and {} of a find command belong to the word; kept as [char]2 [char]3 for
    # Seg, but not ${ or an escaped one (bm: which of the open braces are kept so)
    if ($bx -and $c -eq '{' -and ($tok -or (InFind $toks) -or (BWord $s $i))) {
      $bd++; $bk = if ($p -eq '$' -or $p -eq '\') { '0' } else { '1' }; $bm += $bk; $tok += $(if ($bk -eq '1') { $B1 } else { $c }); continue
    }
    if ($bx -and $c -eq '}' -and $bd -gt 0) {
      $bd--; $bk = '0'; if ($bm) { $bk = $bm.Substring($bm.Length - 1); $bm = $bm.Substring(0, $bm.Length - 1) }
      $tok += $(if ($bk -eq '1' -and $p -ne '\') { $B2 } else { $c }); continue
    }
    if ($c -eq '{' -and $tok) { $bd++; $tok += $c; continue }
    if ($c -eq '}' -and $bd -gt 0) { $bd--; $tok += $c; continue }
    if ($c -eq "`n" -or $c -eq ';' -or $c -eq '|' -or $c -eq '&' -or $c -eq '(' -or $c -eq ')' -or $c -eq '{' -or $c -eq '}') {
      if ($tok) { $toks.Add($tok) }; $tok = ''; $st = $false; $bd = 0; $bm = ''; $e = ($toks.Count -eq 0)
      Seg $toks $depth $qm $pp $bx; $toks = New-Object System.Collections.Generic.List[string]
      $pp = ($c -eq '|' -and $d -ne '|' -and $p -ne '|') -or ($e -and $pp)
      if ($c -eq "`n" -and $hd) { $k = HereEnd $s ($i + 1) $hd $hdd; $body = $script:hdBody; $hd = ''; if ($hdsh) { Scan $body ($depth + 1) $false $hbx }; $i = $k }
      continue
    }
    $tok += $c
  }
  if ($q) { $script:fail = $true }
  if ($tok) { $toks.Add($tok) }
  Seg $toks $depth $qm $pp $bx
}
$joined = $cmd
$bx0 = $tool -ne 'PowerShell'; Scan $joined 0 $true $bx0
if ($script:fail) { $script:segs.Clear(); $script:pipes.Clear(); Scan $joined 0 $false $bx0 }

# --- helpers (case-insensitive matching: GIT PUSH ORIGIN MAIN counts) ---
$REDIR = '^[0-9*]*&?[<>]'
$REDIR_OP = '^[0-9*]*&?[<>]+[&|]?$'
$RMREC = '^-[rfvidp]*r[rfvidp]*$'
$PSREC = '^-r(e(c(u(r(se?)?)?)?)?)?(:\$?true)?$'
$WT = '(^|[/\\])\.claude([/\\]worktrees([/\\][^/\\]+)?)?$'   # a worktree, the worktrees' folder, .claude

$script:dir = if ($cwd) { $cwd } elseif ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { '.' }
$script:ovDir = ''; $script:ovBranch = ''   # a checkout / switch earlier in this command: dir and branch

# one of the protected branches ($PROT, above): the whole name, literally, letter case ignored
function IsProtected([string]$x) { foreach ($b in $PROT) { if ($x -ieq $b) { return $true } }; $false }
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
    if (IsProtected $dst) { Block "push to a protected branch ($dst)" }
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
  foreach ($t in $names) { $n = NormRef $t; if (IsProtected $n) { Block "deleting a protected branch ($n)" } }
}
function UpdRefSeg([string[]]$a) {
  $del = $false; $names = @()
  foreach ($t in $a) { if ($t -eq '-d' -or $t -eq '--delete') { $del = $true } elseif (-not $t.StartsWith('-')) { $names += $t } }
  if (-not $del) { return }
  foreach ($t in $names) { $n = NormRef $t; if (IsProtected $n) { Block "deleting a protected branch ($n)" } }
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
function GitSeg([string[]]$a, [bool]$redir = $false) {
  $eff = $script:dir; $i = 0
  while ($i -lt $a.Count) {
    $t = $a[$i]
    if ($t -ceq '-C') { $v = if ($i + 1 -lt $a.Count) { $a[$i + 1] } else { '' }; $eff = Compose $eff $v; $i += 2; continue }
    if ($asst) { AsstGopt $t }
    if ($t -match '^(--git-dir|--work-tree)$') { $redir = $true; $i += 2; continue }
    if ($t -match '^(--git-dir|--work-tree)=') { $redir = $true; $i++; continue }
    if ($t -match '^(-c|--namespace|--config-env|--super-prefix)$') { $i += 2; continue }
    if ($t.StartsWith('-')) { $i++; continue }
    break
  }
  if ($i -ge $a.Count) { return }
  # --git-dir / --work-tree (or GIT_DIR= / GIT_WORK_TREE= before git) point git elsewhere: the folder a
  # discarding command acts on is not known
  $deff = if ($redir) { '?' } else { $eff }
  $sub = $a[$i]; $rest = @(if ($i + 1 -lt $a.Count) { $a[($i + 1)..($a.Count - 1)] })
  if ($asst) { AsstGit $sub $rest }
  switch ($sub.ToLowerInvariant()) {
    'push' { PushSeg $eff $rest }
    'branch' { BranchSeg $rest }
    'update-ref' { UpdRefSeg $rest }
    'checkout' { DiscardSeg $deff 'checkout' $rest; CheckoutSeg $eff $rest }
    'switch' { DiscardSeg $deff 'switch' $rest; CheckoutSeg $eff $rest }
    'worktree' { WorktreeSeg $rest }
    'clean' { DiscardSeg $deff 'clean' $rest }
    'reset' { DiscardSeg $deff 'reset' $rest }
    'restore' { DiscardSeg $deff 'restore' $rest }
    'stash' { DiscardSeg $deff 'stash' $rest }
  }
}
# --- discarding files in a repository's main checkout (#263): git clean -f, reset --hard, checkout -- <paths>
# (also <ref> -- <paths>, ., -f), switch -f / --discard-changes, restore of the working tree, stash drop /
# clear. A linked worktree is free (workers and verifiers wipe their own throwaway copies), and so is a
# folder under .claude/worktrees/ or under a declared worktree root (a worker's own copy); a folder that
# cannot be known (a variable, not a repository) is not. COORD_PROTECTED_ROOT plays no part: a subagent
# under the coordinator's own settings has none.
function DiscardSeg([string]$dd, [string]$sub, [string[]]$a) {
  $what = ''; $nx = $false; $dash = $false; $f = $false; $n = $false; $s = $false; $w = $false
  foreach ($t in $a) {
    if ($nx) { $nx = $false; continue }
    if ($dash) { if ($sub -ceq 'checkout') { $what = 'checkout' }; break }   # checkout [<ref>] -- <paths>
    $st = $sub + ':' + $t   # compared with letter case: -f is not -F, -s (a source) is not -S (staged)
    if ($t -ceq '--') { $dash = $true; if ($sub -cne 'checkout') { break }; continue }
    if ($st -ceq 'clean:--force') { $f = $true }
    elseif ($st -ceq 'clean:--dry-run') { $n = $true }
    elseif ($st -cmatch '^(clean:--exclude|restore:--source|checkout:-[bB]|switch:-[cC]|checkout:--orphan|switch:--(orphan|create|force-create))$') { $nx = $true }
    elseif ($st -cmatch '^(reset:--hard|checkout:--force|switch:--force|switch:--discard-changes)$') { $what = $sub }
    elseif ($st -ceq 'restore:--staged') { $s = $true }
    elseif ($st -ceq 'restore:--worktree') { $w = $true }
    elseif ($st -cmatch '^checkout:(\.|\./|\.\\|\.\.|\.\./|\.\.\\|:/|\*)$') { $what = 'checkout' }
    elseif ($sub -ceq 'stash') {
      if ($t.StartsWith('-')) { continue }
      if ($t -ceq 'drop' -or $t -ceq 'clear') { $what = "stash $t" }
      break
    }
    elseif ($t.StartsWith('--')) { }
    elseif ($t.Length -ge 2 -and $t.StartsWith('-')) {
      # a cluster of short options (-ffdx): its letters; one that takes a value ends it
      for ($k = 1; $k -lt $t.Length; $k++) {
        $c = $sub + ':' + $t[$k]
        if ($c -ceq 'clean:f') { $f = $true }
        elseif ($c -ceq 'clean:n') { $n = $true }
        elseif ($c -cmatch '^(checkout|switch):f$') { $what = $sub }
        elseif ($c -ceq 'restore:S') { $s = $true }
        elseif ($c -ceq 'restore:W') { $w = $true }
        elseif ($c -cmatch '^(clean:e|checkout:[bB]|switch:[cC]|restore:s)$') { if ($k -eq $t.Length - 1) { $nx = $true }; break }
      }
    }
  }
  if ($f -and -not $n) { $what = 'clean' }
  if ($sub -ceq 'restore' -and ($w -or -not $s)) { $what = 'restore' }
  if (-not $what) { return }
  if (FreeCopy $dd) { return }
  Block "discarding files in a repository's main checkout (git $what): only a worktree may be wiped (#263)"
}
# FreeCopy <dir>: a linked worktree (its git dir is not the common one), or a main checkout whose top
# folder (the repository's, not the dir's: a plain or stale folder under .claude/worktrees/ belongs to the
# project) lies, as written and as on disk, under .claude/worktrees/<name> or a declared worktree root
# (OwnForms). rev-parse must print three absolute paths: an older git echoes --path-format back.
function FreeCopy([string]$dd) {
  if ($dd -eq '?') { return $false }
  $out = @(git -C $dd rev-parse --path-format=absolute --git-dir --git-common-dir --show-toplevel 2>$null)
  if ($LASTEXITCODE -ne 0 -or $out.Count -ne 3) { return $false }
  foreach ($l in $out) { if ("$l" -notmatch '^(/|[A-Za-z]:/)') { return $false } }
  if ($out[0] -cne $out[1]) { return $true }
  $top = [string]$out[2]
  OwnForms
  $wr = @()
  foreach ($r in $script:wtRel) {
    $x = Canon $r -Keep:$smKeep; if ($x -and $x -ne '.') { $wr += $x }
    $ph = Physical $r -Keep:$smKeep; if ($ph -and $ph -ne '.') { $wr += $ph }
  }
  $forms = @(Canon $top -Keep:$smKeep); $ph = Physical $top -Keep:$smKeep; if ($null -ne $ph) { $forms += $ph }
  foreach ($x in $forms) {
    if ("$x/" -match '/\.claude/worktrees/[^/]+/') { continue }
    $in = $false
    foreach ($r in $wr) { if ("$x/".Length -gt "$r/".Length -and "$x/".StartsWith("$r/", [StringComparison]::Ordinal)) { $in = $true; break } }
    if (-not $in) { return $false }
  }
  $true
}
# git worktree remove --force throws away what the worktree holds: the cleanup script checks first
function WorktreeSeg([string[]]$a) {
  if ($a.Count -eq 0 -or $a[0] -ne 'remove') { return }
  foreach ($t in $a) { if ($t -match '^(--force|-f|-ff)$') { Block 'removing a worktree by force (use the cleanup script)' } }
}
# --- the assistant mode (#281, COORD_ASSISTANT_DIR set): git and GitHub are read, never written ---
# A git read that can run a command or write a file is refused too: git's settings and programs set on
# its command line (AsstGopt), a variable set before git (AsstGenv) or a GIT_ variable set anywhere in the
# command (AsstGvar), and the read options that run a program or write a file (AsstGarg).
# AsstGopt <a global option of git>: -c, --config-env, --exec-path=, --git-dir, --work-tree (a folder with
# git settings of its own)
function AsstGopt([string]$t) {
  if ($t -match '^(-c.*|--config-env(=.*)?|--exec-path=.*|--git-dir(=.*)?|--work-tree(=.*)?)$') {
    Block "an assistant runs git with no option that sets its settings, its programs or its folder (git $t): a setting can run a command (COORD_ASSISTANT_DIR is set, #281)"
  }
}
# AsstGenv <the words> <the index of git>: a VAR=value before git (also after env) - GIT_PAGER, PAGER,
# HOME, PATH ... can make a read run a command
function AsstGenv([string[]]$w, [int]$n) {
  for ($k = 0; $k -lt $n; $k++) {
    if ($w[$k] -match $ASSIGN) { Block "an assistant runs git with no variable set before it ($($w[$k].Substring(0, $w[$k].IndexOf('=')))=): one can make a read run a command (COORD_ASSISTANT_DIR is set, #281)" }
  }
}
# AsstGvar <the words>: a GIT_ variable set anywhere in a command (export GIT_PAGER=..., $env:GIT_PAGER =
# ..., Set-Item env:GIT_PAGER ...): it would reach a later git
function AsstGvar([string[]]$w) {
  for ($k = 0; $k -lt $w.Count; $k++) {
    $t = $w[$k]
    $set = $t -match '^(GIT_.+=|env:([/\\])?GIT_|\$env:GIT_.*=)'
    if (-not $set -and $t -match '^\$env:GIT_' -and $k + 1 -lt $w.Count -and $w[$k + 1].StartsWith('=')) { $set = $true }
    if ($set) { Block "an assistant sets no GIT_ variable ($t): one can make a git read run a command (COORD_ASSISTANT_DIR is set, #281)" }
  }
}
# AsstGarg <subcommand> <its arguments>: --output (writes a file), --ext-diff, --upload-pack,
# --receive-pack, --exec, --open-files-in-pager (each also abbreviated, as git takes it), grep's -O and
# ls-remote's -u (also in a cluster of short options) - before a -- that ends the options
function AsstGarg([string]$sub, [string[]]$a) {
  $d = ''; $v = ''
  switch -regex ($sub) { '^grep$' { $d = 'O'; $v = 'efABCm' } '^ls-remote$' { $d = 'u'; $v = 'o' } }
  $nx = $false
  foreach ($t in $a) {
    if ($nx) { $nx = $false; continue }
    if ($t -eq '--') { break }
    if ($t.StartsWith('--')) {
      $n = $t.Substring(2); $q = $n.IndexOf('='); if ($q -ge 0) { $n = $n.Substring(0, $q) }
      foreach ($c in @('output', 'ext-diff', 'upload-pack', 'receive-pack', 'exec', 'open-files-in-pager')) {
        if ($c.StartsWith($n, [StringComparison]::Ordinal)) { Block "an assistant runs no git read that runs a program or writes a file (git $sub $t) (COORD_ASSISTANT_DIR is set, #281)" }
      }
    } elseif ($t.Length -gt 1 -and $t.StartsWith('-') -and $d) {   # -O is not -o (grep's --only-matching)
      for ($j = 1; $j -lt $t.Length; $j++) {
        $h = [string]$t[$j]
        if ($h -ceq $d) { Block "an assistant runs no git read that runs a program or writes a file (git $sub $t) (COORD_ASSISTANT_DIR is set, #281)" }
        if ($v.Contains($h)) { if ($j -eq $t.Length - 1) { $nx = $true }; break }   # its value: the rest, or the next word
      }
    }
  }
}
# AsstGit <subcommand> <its arguments>: passes a read - the subcommands below, a branch or tag listing, a
# config read, remote with no subcommand / show / get-url, reflog but expire / delete / drop / write,
# worktree list, symbolic-ref of one name, fetch with no local destination (no <src>:<dst> refspec, no
# --refmap with a :<dst>); refuses the rest (a
# write, an alias, a subcommand not known here). Letter case ignored, as for the other git checks.
$ASST_GIT_READ = '^(log|show|diff|status|blame|annotate|rev-parse|rev-list|ls-files|ls-tree|ls-remote|cat-file|grep|shortlog|describe|merge-base|for-each-ref|show-ref|show-branch|name-rev|count-objects|whatchanged|range-diff|cherry|check-ignore|check-attr|check-mailmap|verify-commit|verify-tag|diff-tree|diff-files|diff-index|var|help|version)$'
function AsstGit([string]$sub, [string[]]$a) {
  AsstGarg $sub $a
  if ($sub -match $ASST_GIT_READ) { return }
  $w = $false; $l = $false; $np = 0; $nx = $false; $rm = $false; $fst = ''
  foreach ($t in $a) {
    if ($nx) { $nx = $false; continue }
    if ($rm) { $rm = $false; if ($t -match ':.') { $w = $true }; continue }   # --refmap's value
    $st = "${sub}:$t"
    if ($st -match '^fetch:--refmap$') { $rm = $true }   # a refmap with a :<dst> updates local refs, as a <src>:<dst> refspec does
    elseif ($st -match '^fetch:--refmap=') { if ($t.Substring($t.IndexOf('=') + 1) -match ':.') { $w = $true } }
    elseif ($st -match '^fetch:-') { }
    elseif ($st -match '^fetch:') { $np++; if ($np -gt 1 -and $t.Contains(':')) { $w = $true } }   # a refspec after the repository
    elseif ($st -match '^(branch:--list|tag:--list|tag:--verify|config:--list|config:--get|config:--get-all|config:--get-regexp|config:--get-urlmatch|config:--get-color|config:--get-colorbool)$') { $l = $true }
    elseif ($st -match '^(branch|tag):--(contains|no-contains|merged|no-merged|points-at)$') { $l = $true; $nx = $true }
    elseif ($st -match '^(branch|tag):--(contains|no-contains|merged|no-merged|points-at)=') { $l = $true }
    elseif ($st -match '^(branch:--sort|branch:--format|tag:--sort|tag:--format|config:--file|config:-f|config:--blob|config:--type|config:--default|config:--comment)$') { $nx = $true }
    elseif ($st -match '^branch:(--delete|--move|--copy|--force|--set-upstream-to.*|--unset-upstream|--edit-description|--track.*|--no-track|--create-reflog|--recurse-submodules)$') { $w = $true }
    elseif ($st -match '^tag:(--annotate|--sign|--local-user.*|--force|--delete|--message.*|--file.*|--edit|--create-reflog|--cleanup.*|--trailer.*)$') { $w = $true }
    elseif ($st -match '^(config:--unset|config:--unset-all|config:--add|config:--replace-all|config:--rename-section|config:--remove-section|config:--edit|config:-e|symbolic-ref:-d|symbolic-ref:--delete|symbolic-ref:-m)$') { $w = $true }
    elseif ($st -match '^config:-l$') { $l = $true }
    elseif ($st -match '^[^:]*:--') { }
    elseif ($st -match '^branch:-') { if ($t -match '[dmcfut]') { $w = $true }; if ($t -match 'l') { $l = $true } }
    elseif ($st -match '^tag:-') { if ($t -match '[dfasmeu]') { $w = $true }; if ($t -match '[lvn]') { $l = $true } }
    elseif ($t.StartsWith('-')) { }
    else { $np++; if (-not $fst) { $fst = $t } }
  }
  switch -regex ($sub) {
    '^fetch$' { if (-not $w) { return } }
    '^(branch|tag)$' { if (-not $w -and ($np -eq 0 -or $l)) { return } }
    '^config$' {
      if (-not $w) {
        if ($fst -match '^(get|list)$') { return }
        if ($fst -notmatch '^(set|unset|rename-section|remove-section|edit)$' -and ($l -or $np -eq 1)) { return }
      }
    }
    '^remote$' { if ($fst -match '^(|show|get-url)$') { return } }
    '^reflog$' { if ($fst -notmatch '^(expire|delete|drop|write)$') { return } }   # no subcommand: reflog show
    '^worktree$' { if ($fst -ceq 'list') { return } }
    '^symbolic-ref$' { if (-not $w -and $np -eq 1) { return } }
  }
  Block "an assistant writes nothing to git (git $sub): it reads only (COORD_ASSISTANT_DIR is set, #281)"
}
# AsstGh <gh's arguments>: an allowlist (281.5) - passes a read, refuses every other gh command (an alias
# and its call, an extension, auth, config, agent-task, an unknown group ...). gh's command line is read
# exactly (281.6): before the group and before the subcommand only -R / --repo / --hostname with its value
# (also --repo= / --hostname=) may stand, any other flag there refuses (gh may take the next word as its
# value) - but gh --version alone, and gh --help / -h with only words after it (it prints help); names match
# case-sensitively and whole, as gh matches them. Reads: no group (gh), help, version, status, browse (opens
# a URL; these four take no subcommand), search; auth status, alias list, config get / list, org list; pr |
# issue | release | repo | label | gist | workflow | secret | variable | run | cache | ruleset | project |
# codespace | ssh-key | gpg-key with no subcommand or list / view / status / diff / checks / watch; gh api:
# AsstApi
function AsstGh([string[]]$a) {
  if ($a.Count -eq 1 -and $a[0] -ceq '--version') { return }
  if ($a.Count -ge 1 -and ($a[0] -ceq '--help' -or $a[0] -ceq '-h') -and -not @($a | Select-Object -Skip 1 | Where-Object { $_.StartsWith('-') }).Count) { return }
  $grp = ''; $sub = ''; $nx = $false; $i = 0
  while ($i -lt $a.Count) {
    $t = $a[$i]; $i++
    if ($nx) { $nx = $false; continue }
    if ($t -cin '-R', '--repo', '--hostname') { $nx = $true; continue }
    if ($t -clike '--repo=*' -or $t -clike '--hostname=*') { continue }
    if ($t.StartsWith('-')) {
      $at = if ($grp) { 'subcommand' } else { 'command' }
      Block "an assistant writes nothing to GitHub (gh ... $t before the $at, which gh may take as its value): it reads only, and gh passes only a known read (COORD_ASSISTANT_DIR is set, #281)"
    }
    if (-not $grp) { $grp = $t; if ($grp -cin 'api', 'help', 'version', 'status', 'browse') { break }; continue }
    $sub = $t; break
  }
  if ($grp -ceq 'api') { AsstApi @(if ($i -lt $a.Count) { $a[$i..($a.Count - 1)] }); return }
  if ($grp -cin '', 'help', 'version', 'status', 'browse', 'search') { return }
  if (($grp -ceq 'auth' -and $sub -cin '', 'status') -or ($grp -cin 'alias', 'org' -and $sub -cin '', 'list') -or ($grp -ceq 'config' -and $sub -cin '', 'get', 'list')) { return }
  if ($grp -cin 'pr', 'issue', 'release', 'repo', 'label', 'gist', 'workflow', 'secret', 'variable', 'run', 'cache', 'ruleset', 'project', 'codespace', 'ssh-key', 'gpg-key' -and $sub -cin '', 'list', 'view', 'status', 'diff', 'checks', 'watch') { return }
  $gs = if ($sub) { "$grp $sub" } else { $grp }
  Block "an assistant writes nothing to GitHub (gh $gs): it reads only, and gh passes only a known read (COORD_ASSISTANT_DIR is set, #281)"
}
# AsstApi <gh api's arguments>: refuses a method (-X / --method, also -XPOST, --method=x) other than GET or
# HEAD, and fields or --input (-f / -F / --field / --raw-field, also glued or with =) with no method (gh's
# implicit POST); graphql instead: refused when a word holds "mutation" (letter case ignored) or the query
# comes from a file (--input, a field's =@file), whatever the method; the endpoint folded first (a leading
# /, an http(s)://<host>/ prefix). Flags with letter case: -h is not -H.
function AsstApi([string[]]$a) {
  $m = ''; $fl = $false; $ep = ''; $mu = $false; $at = $false; $i = 0
  foreach ($t in $a) { if ($t -match 'mutation') { $mu = $true } }
  while ($i -lt $a.Count) {
    $t = $a[$i]; $i++; $v = ''
    $nv = if ($i -lt $a.Count) { $a[$i] } else { '' }
    if ($t -ceq '-X' -or $t -ceq '--method') { $m = $nv; $i++ }
    elseif ($t.StartsWith('--method=', [StringComparison]::Ordinal)) { $m = $t.Substring(9) }
    elseif ($t.StartsWith('-X', [StringComparison]::Ordinal)) { $m = $t.Substring(2); if ($m.StartsWith('=')) { $m = $m.Substring(1) } }
    elseif ($t -cmatch '^(-f|-F|--field|--raw-field)$') { $fl = $true; $v = $nv; $i++ }
    elseif ($t -cmatch '^--(field|raw-field)=') { $fl = $true; $v = $t.Substring($t.IndexOf('=') + 1) }
    elseif ($t -cmatch '^-[fF]') { $fl = $true; $v = $t.Substring(2); if ($v.StartsWith('=')) { $v = $v.Substring(1) } }
    elseif ($t -ceq '--input') { $fl = $true; $at = $true; $i++ }
    elseif ($t.StartsWith('--input=', [StringComparison]::Ordinal)) { $fl = $true; $at = $true }
    elseif ($t -cmatch '^(-H|--header|-p|--preview|-q|--jq|-t|--template|--cache|--hostname)$') { $i++ }
    elseif ($t.StartsWith('-')) { }
    elseif (-not $ep) { $ep = $t }
    if ($v -like '*=@*') { $at = $true }
  }
  if ($ep -match '^https?://') { $ep = $ep -replace '^https?://[^/]*/?', '' }
  $ep = $ep.TrimStart('/')   # /graphql and https://<host>/graphql are graphql
  if ($ep -ceq 'graphql') {
    if ($mu) { Block 'an assistant writes nothing to GitHub (gh api graphql with a mutation): it reads only (COORD_ASSISTANT_DIR is set, #281)' }
    if ($at) { Block 'an assistant writes nothing to GitHub (gh api graphql with its query from a file, which may be a mutation): it reads only (COORD_ASSISTANT_DIR is set, #281)' }
    return
  }
  if (-not $m) { if ($fl) { Block 'an assistant writes nothing to GitHub (gh api with fields and no -X GET, which is a POST): it reads only (COORD_ASSISTANT_DIR is set, #281)' }; return }
  if ($m -notmatch '^(get|head)$') { Block "an assistant writes nothing to GitHub (gh api -X $m): it reads only (COORD_ASSISTANT_DIR is set, #281)" }
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
  if ($asst) { AsstGvar $words }
  # the command word: after wrappers ({ ( ! then do sudo env ...), their options (sudo -E,
  # timeout -k 5 30, nice -n 5, stdbuf -oL ...) and VAR=value assignments
  $i = CmdIdx $words
  if ($i -ge $words.Count) { continue }
  $cw = BaseName $words[$i]
  $rest = @(if ($i + 1 -lt $words.Count) { $words[($i + 1)..($words.Count - 1)] })
  switch -regex ($cw) {
    '^git$' {
      # GIT_DIR= / GIT_WORK_TREE= before git (also after env): see GitSeg
      $redir = $false; for ($k = 0; $k -lt $i; $k++) { if ($words[$k] -match '^(GIT_DIR|GIT_WORK_TREE)=') { $redir = $true } }
      if ($asst) { AsstGenv $words $i }
      GitSeg $rest $redir
    }
    '^(cd|pushd|chdir|set-location|sl|push-location)$' { CdSeg $rest }
    '^(rm|remove-item|ri|del|erase|rd|rmdir)$' { RmSeg $cw $rest }
    '^find$' { FindSeg $rest }
    '^(get-childitem|gci|ls|dir|get-item|gi)$' { ListSeg $rest }
    '^claude$' { ClaudeSeg $rest }
    '^gh$' {
      # GH_REPO= before gh (also after env): see GhSeg
      $ghEnv = $false; for ($k = 0; $k -lt $i; $k++) { if ($words[$k] -match '^GH_REPO=') { $ghEnv = $true } }
      if ($asst) { AsstGh $rest }
      GhSeg $rest $ghEnv
    }
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
