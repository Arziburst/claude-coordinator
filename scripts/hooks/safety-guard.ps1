# PreToolUse safety hook for coordinator projects (Windows; macOS / Linux: safety-guard.sh - the same
# rules, checked against the same cases: tests/safety-guard/cases.txt).
# With COORD_ASSISTANT_DIR set (the assistant mode, #281): the edit tools only inside that folder, git and
# gh only a known read (an allowlist); the deliberate-evasion routes and the network closed too (#345).
# With COORD_NO_PUSH=1 (a never-push project, #367): every git push it reads is blocked, on any branch.
# Reads the tool call JSON on stdin; exit 2 blocks the call and shows the reason to Claude.
# A safety net only - the real enforcement is branch protection on the code host (CORE section 2);
# deliberate obfuscation (iex, cmd /c, quoting tricks ...) is out of scope but in the assistant mode (TOOLKIT.md *Safety*).
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
  # assistant's session (#281) also its own: a commit blocks, a log passes. COORD_NO_PUSH is cleared
  # (#367: it refuses every push too)
  $exe = (Get-Process -Id $PID).Path
  $env:COORD_NO_PUSH = $null
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
    # from / : git in the assistant's own folder is refused (#345), and a session may start there
    '{"tool_input":{"command":"git log -1"},"cwd":"/"}' |
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
$RUN_SQB = [char[]]@([char]39, [char]92)
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
# INorm: a whole number as digits, its sign kept, no leading zeros; IBig: past 2^53 - 1, where adding to a number
# no longer moves it, so such a number is compared as text and never counted
function INorm([string]$x) { $g = ''; if ($x.StartsWith('-')) { $g = '-'; $x = $x.Substring(1) }; $g + $x.TrimStart('0') }
function IBig([string]$x) { $d = (INorm $x).TrimStart('-'); ($d.Length -gt 16) -or ($d.Length -eq 16 -and [string]::CompareOrdinal($d, '9007199254740991') -gt 0) }
# BWord: the { at i, at the start of a word, opens an expansion: a comma at its top level or a range,
# closed before the word ends (else it is a group: { git push; })
function BWord([string]$s, [int]$i) {
  $dep = 0; $q = ''; $cm = $false
  for ($j = $i; $j -lt $s.Length; $j++) {
    $c = [string]$s[$j]
    if ($q -eq 'A') { if ($c -eq "'") { $q = '' } elseif ($c -eq '\') { $j++ }; continue }   # $'...': a backslash escapes there
    if ($q) { if ($c -eq $q) { $q = '' } elseif ($c -eq '\' -and $q -eq '"') { $j++ }; continue }
    if ($c -eq '\') { $j++; continue }
    if ($c -eq '$' -and $j + 1 -lt $s.Length -and $s[$j + 1] -eq [char]39) { $q = 'A'; $j++; continue }
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
# or -1 for more than BMAX words (or too much work). A range with a bound past 2^53 - 1 is never counted: its
# two bounds the same number make one word, that number; any other is too big, the same -1
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
        if ($c -eq [char]',' -and $dep -eq 0) { if ($al.Count + 1 -ge $BMAX) { return -1 }; $al.Add($cur); $cur = '' } else { $cur += $c }   # counted before its words are pushed (#345)
      }
      $al.Add($cur)
    } else {
      $R = $body -split '\.\.'; $lt = $R[0] -match '^[A-Za-z]$'
      if (-not $lt -and ((IBig $R[0]) -or (IBig $R[1]))) {
        if ((INorm $R[0]) -cne (INorm $R[1])) { return -1 }
        $todo.Add($x.Substring(0, $a) + $(if ($R[1].Length -gt $R[0].Length) { $R[1] } else { $R[0] }) + $x.Substring($b + 1))
        continue
      }
      if ($lt) { $lo = [double][int][char]$R[0]; $hi = [double][int][char]$R[1] } else { $lo = [double]$R[0]; $hi = [double]$R[1] }
      $st = 1
      if ($R.Count -gt 2) { if (IBig $R[2]) { $st = 4e16 } else { $st = [Math]::Abs([double]$R[2]) } }   # 4e16: above any span of two bounds that are not big, the first word only
      if ($st -eq 0) { $st = 1 }
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
# PsStrip $w $qw: a PowerShell line (#374): the index of the first word of the command an assignment or a
# dot-source runs ($x = git ..., $x += ..., $x=git ..., [string]$x = ..., $a = $b = ..., . git ...), 0 for none.
# A glued right side is cut out of its word. $qw: the first word opened by a quote, or by one right after a = :
# a quoted right side is a string, never a command, and the line stays as written; after a dot it is the command.
# return runs the command after it (#345), and a target may be more than one word: PsTarget.
function PsStrip([string[]]$w, [int]$qw) {
  $j = 0; $n = $w.Count
  while ($j -lt $n) {
    $t = $w[$j]; $o = if ($j + 1 -lt $n) { $w[$j + 1] } else { '' }
    if ($t -eq '.') { $j++ }
    elseif ($t -eq 'return') { if ($j + 1 -eq $qw) { return 0 }; $j++ }
    elseif ($t -match '^(\[[^\]]+\]+)+$' -and $o.StartsWith('$')) { $j++ }
    elseif ($t -match '^(\[|\$|]|,|\.[A-Za-z_]|([-+*/%]|\?\?)?=|[-+*%]|/([0-9$]|$))') {
      $r = PsTarget $w $j $qw; if ($r -eq -1) { return 0 }; if ($r -eq -2) { break }; $j = $r
    }
    else { break }
  }
  if ($j -ge $n) { 0 } else { $j }
}
# PsTarget $w $j $qw: the words from j are the target of an assignment ($x, $y; $x , $y; $x[$i + 1]; $x[ 0 ]; the
# rest of $x[(1)] or $x.y().z after their parentheses, which end a command here: ] , .z , + 1] ; the = of
# ${a b}): the index of the first word of the right side, a glued one cut out of its word; -2 when they are no
# target, -1 when the right side is quoted. Inside [ ] any word belongs; outside, only a list goes on to a next word.
function PsTarget([string[]]$w, [int]$j, [int]$qw) {
  $n = $w.Count
  $dep = if ($w[$j] -match '^([-+*%]|/)' -and $w[$j] -notmatch '^[-+*/%]=') { 1 } else { 0 }   # the rest of an index: + 1] , -1]
  for (; $j -lt $n; $j++) {
    $t = $w[$j]; $m = $t.Length
    for ($i = 0; $i -lt $m; $i++) {
      $c = $t[$i]
      if ($c -eq [char]'[') { $dep++ }
      elseif ($c -eq [char]']') { if ($dep -gt 0) { $dep-- } }
      elseif ($c -eq [char]'=' -and $dep -eq 0) {
        if ($j -eq $qw) { return -1 }
        if ($i -eq $m - 1) { if ($j + 1 -eq $qw) { return -1 }; return ($j + 1) }
        $w[$j] = $t.Substring($i + 1); return $j
      }
    }
    if ($dep -gt 0) { continue }
    $o = if ($j + 1 -lt $n) { $w[$j + 1] } else { '' }
    if ($o -match '^([-+*/%]|\?\?)?=') { continue }
    if (($t.EndsWith(',') -or $o.StartsWith(',')) -and $o -match '^(\[|\$|,)') { continue }
    if ($t -match '^(\[[^\]]+\]+)+$' -and $o.StartsWith('$')) { continue }
    return -2
  }
  -2
}
function Seg($list, [int]$depth, [bool]$qm, [bool]$pp, [bool]$bx, [int]$qw = -1) {
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
  # bx off: PowerShell reads this line (the PowerShell tool, pwsh -c); a Bash line keeps its own words
  if (-not $bx) { $j = PsStrip $toks $qw; if ($j -gt 0) { $toks = [string[]]@($toks[$j..($toks.Count - 1)]) } }
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
  $n = $s.Length; $q = ''; $tok = ''; $st = $false; $hd = ''; $hdd = $false; $hdsh = $false; $bd = 0; $bm = ''; $hbx = $false; $pp = $false; $qw = -1
  $toks = New-Object System.Collections.Generic.List[string]
  for ($i = 0; $i -lt $n; $i++) {
    # in a brace word ($ib) a backslash stays an escape for BExp, so a quoted one goes in doubled: {'a\',main}
    $ib = $bx -and ($bd -gt 0 -or $tok.Contains($B1))
    $set = if ($q -eq "'") { if ($ib) { $RUN_SQB } else { $RUN_SQ } } elseif ($q -ceq 'A') { $RUN_SQB } elseif ($q) { $RUN_DQ } else { $RUN_UQ }
    $k = RunTo $s $i $set
    if ($k -gt 0) { $tok += $s.Substring($i, $k); $i += $k - 1; continue }
    $c = [string]$s[$i]; $d = if ($i + 1 -lt $n) { [string]$s[$i + 1] } else { '' }; $p = if ($i -gt 0) { [string]$s[$i - 1] } else { '' }
    if ($q -eq "'") { if ($c -eq "'") { $q = '' } else { $tok += $c; if ($c -eq '\') { $tok += $c } }; continue }
    if ($q -ceq 'A') { if ($c -eq "'") { $q = '' } else { $tok += $c + $d; $i++ }; continue }   # $'...' in a brace word: \x stays an escape for BExp
    if ($q -eq '"') {
      if ($ib -and $c -eq '\' -and $d -eq '\') { $tok += $c + $d; $i++; continue }
      if ($c -eq '\' -and ($d -eq '"' -or $d -eq '\' -or $d -eq '$' -or $d -eq '`')) { $tok += $d; $i++; continue }
      if ($c -eq '"') { $q = ''; continue }
      if ($c -eq '$' -and $d -eq '(') { $k = ClosePar $s ($i + 2); Scan $s.Substring($i + 2, $k - $i - 2) ($depth + 1) $qm $bx; $tok += '$SUBST'; $i = $k; continue }
      if ($c -eq '`') { $k = CloseTick $s ($i + 1); Scan $s.Substring($i + 1, $k - $i - 1) ($depth + 1) $qm $bx; $tok += '$SUBST'; $i = $k; continue }
      $tok += $c; continue
    }
    if ($bx -and $c -eq '\' -and $d -eq ';' -and (InFind $toks)) { $tok += $c + $d; $st = $true; $i++; continue }   # \; of find is a word
    # inside a brace of a word, or later in a word that holds one, an escaped character is text: no brace, no word
    # end ({main,x\}}, {main,\;}, {main,x}\}, {main,x}\ y), and a backslash before a line end is no character at all
    if ($bx -and $c -eq '\' -and $d -and ($bd -gt 0 -or ($ib -and $d -ne '{'))) { if ($d -ne "`n") { $tok += $c + $d }; $st = $true; $i++; continue }
    if ($qm -and $c -eq '\' -and ($d -eq '"' -or $d -eq "'" -or $d -eq '\')) { $tok += $d; $st = $true; $i++; continue }
    if ($qm -and $c -eq '$' -and $d -eq "'") { if ($ib) { $q = 'A'; $st = $true; $i++ }; continue }   # $'...' (ANSI-C quoting): its text, as '...'
    if ($c -eq "'" -or $c -eq '"') { if ($qm) { if (-not $bx -and $qw -lt 0 -and ($tok -eq '' -or $tok.EndsWith('='))) { $qw = $toks.Count }; $q = $c; $st = $true }; continue }
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
      $tok += $(if ($bk -eq '1') { $B2 } else { $c }); continue
    }
    if ($c -eq '{' -and $tok) { $bd++; $tok += $c; continue }
    if ($c -eq '}' -and $bd -gt 0) { $bd--; $tok += $c; continue }
    if ($c -eq "`n" -or $c -eq ';' -or $c -eq '|' -or $c -eq '&' -or $c -eq '(' -or $c -eq ')' -or $c -eq '{' -or $c -eq '}') {
      if ($tok) { $toks.Add($tok) }; $tok = ''; $st = $false; $bd = 0; $bm = ''; $e = ($toks.Count -eq 0)
      Seg $toks $depth $qm $pp $bx $qw; $qw = -1; $toks = New-Object System.Collections.Generic.List[string]
      $pp = ($c -eq '|' -and $d -ne '|' -and $p -ne '|') -or ($e -and $pp)
      if ($c -eq "`n" -and $hd) { $k = HereEnd $s ($i + 1) $hd $hdd; $body = $script:hdBody; $hd = ''; if ($hdsh) { Scan $body ($depth + 1) $false $hbx }; $i = $k }
      continue
    }
    $tok += $c
  }
  if ($q) { $script:fail = $true }
  if ($tok) { $toks.Add($tok) }
  Seg $toks $depth $qm $pp $bx $qw
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
# a never-push project (#367): every push the guard reads comes through here; only the value 1 turns it on
function NoPush {
  if ($env:COORD_NO_PUSH -ceq '1') { Block 'this project allows no push (COORD_NO_PUSH): every git push is blocked, on any branch' }
}
function PushSeg([string]$dd, [string[]]$a) {
  NoPush
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
  $script:pushBare = $remote -and $refs -eq 0
  if ($refs -eq 0 -and $tags) { return }   # tags only: not a branch push
  if ($refs -eq 0 -or $cur) {
    $br = BranchIn $dd
    if (IsProtected $br) { Block "push while on $br" }
  }
}
# --- what else pushes (#374). git subtree push <remote> <ref> pushes that ref; its other commands do not ---
function SubtreeSeg([string]$dd, [string[]]$a) {
  $what = ''; $skip = $false; $r = New-Object System.Collections.Generic.List[string]
  foreach ($t in $a) {
    if ($skip) { $skip = $false; continue }
    if ($t -match '^(-P|--prefix|-m|--message|--onto|--annotate|-b|--branch)$') { $skip = $true; continue }
    if ($t.StartsWith('-')) { continue }
    if ($what -eq '') { $what = $t } else { $r.Add($t) }
  }
  if ($what -ceq 'push') { PushSeg $dd ($r.ToArray()) }   # git is case-sensitive: subtree PUSH is refused, as in the .sh
}
# git send-pack: judged as a push, after PushSeg; with no ref it updates every branch both sides have, and
# --stdin takes its refs where the guard does not read them
function SendPackSeg([string[]]$a) {
  foreach ($t in $a) { if ($t -ceq '--stdin') { Block 'git send-pack --stdin (the refs it pushes cannot be read here)' } }
  if ($script:pushBare) { Block 'git send-pack without a ref (updates every branch both sides have, incl. protected ones)' }
}
# git lfs push sends objects and names no ref: only a never-push project stops it
function LfsSeg([string[]]$a) {
  foreach ($t in $a) { if ($t.StartsWith('-')) { continue }; if ($t -ceq 'push') { NoPush }; return }
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
    if ($asst) { AsstGopt $t ($a.Count - $i) }
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
  if ($asst) {
    if (AsstOwn $eff) { Block "an assistant runs git in no repository in its own folder, or in one it cannot name ($eff): a .git there could be crafted $ASST_M" }
    AsstGit $sub $rest
  }
  switch ($sub.ToLowerInvariant()) {
    'push' { PushSeg $eff $rest }
    'subtree' { SubtreeSeg $eff $rest }
    'send-pack' { PushSeg $eff $rest; SendPackSeg $rest }
    'lfs' { LfsSeg $rest }
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
function AsstGopt([string]$t, [int]$left) {
  $m = "an assistant runs git with no option that sets its settings, its programs or its folder (git $t): a setting can run a command (COORD_ASSISTANT_DIR is set, #281)"
  if ($t -match '^-c') { Block $m }
  if ($t -eq '--help') { if ($left -gt 1) { Block "an assistant reads git's help with git <command> -h: git --help <command> opens a browser on Windows $ASST_M" }; return }
  if ($t.Length -gt 2 -and $t.StartsWith('--')) {
    $q = $t.IndexOf('='); $nm = if ($q -ge 0) { $t.Substring(0, $q) } else { $t }
    foreach ($c in @('--git-dir', '--work-tree', '--config-env')) { if ($c.StartsWith($nm, [StringComparison]::OrdinalIgnoreCase)) { Block $m } }   # also abbreviated: read as their full form
    if ('--exec-path'.StartsWith($nm, [StringComparison]::OrdinalIgnoreCase) -and $q -ge 0) { Block $m }
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
# write, an alias, a subcommand not known here). Letter case ignored, as for the other git checks. Long options read
# as their full form, as git takes a unique start (#345). <command> -h alone is the terminal help, also of a write;
# --help before a -- and git help <command> open a browser on Windows. fetch and ls-remote read no repository in the
# assistant's folder.
$ASST_GIT_OPTS = @{
  branch = @('verbose', 'quiet', 'track', 'no-track', 'set-upstream-to', 'unset-upstream', 'color', 'no-color', 'remotes', 'contains', 'no-contains', 'column', 'no-column', 'abbrev', 'no-abbrev', 'all', 'delete', 'move', 'copy', 'list', 'create-reflog', 'edit-description', 'force', 'merged', 'no-merged', 'sort', 'points-at', 'ignore-case', 'recurse-submodules', 'format', 'show-current', 'omit-empty')
  tag = @('force', 'annotate', 'sign', 'no-sign', 'local-user', 'delete', 'verify', 'list', 'column', 'no-column', 'contains', 'no-contains', 'merged', 'no-merged', 'points-at', 'message', 'file', 'trailer', 'cleanup', 'create-reflog', 'sort', 'format', 'color', 'no-color', 'ignore-case', 'omit-empty', 'edit', 'no-edit')
  config = @('global', 'system', 'local', 'worktree', 'file', 'blob', 'get', 'get-all', 'get-regexp', 'get-urlmatch', 'replace-all', 'add', 'unset', 'unset-all', 'rename-section', 'remove-section', 'list', 'fixed-value', 'edit', 'get-color', 'get-colorbool', 'type', 'bool', 'int', 'bool-or-int', 'bool-or-str', 'path', 'expiry-date', 'no-type', 'null', 'name-only', 'show-origin', 'show-scope', 'includes', 'no-includes', 'default', 'comment', 'all', 'regexp', 'value', 'url')
  'symbolic-ref' = @('delete', 'quiet', 'short', 'no-recurse', 'recurse')
  fetch = @('refmap')
}
$ASST_GIT_READ = '^(log|show|diff|status|blame|annotate|rev-parse|rev-list|ls-files|ls-tree|ls-remote|cat-file|grep|shortlog|describe|merge-base|for-each-ref|show-ref|show-branch|name-rev|count-objects|whatchanged|range-diff|cherry|check-ignore|check-attr|check-mailmap|verify-commit|verify-tag|diff-tree|diff-files|diff-index|var|help|version)$'
function AsstGit([string]$sub, [string[]]$a) {
  foreach ($t in $a) {
    if ($t -eq '--') { break }
    if ($t -eq '--help') { Block "an assistant reads git's help with git $sub -h: --help opens a browser on Windows $ASST_M" }
  }
  if ($sub -eq 'help' -and -not ($a.Count -eq 0 -or ($a.Count -eq 1 -and $a[0] -match '^(-a|--all|-g|--guides)$'))) {
    Block "an assistant reads git's help with git <command> -h: git help <command> opens a browser on Windows $ASST_M"
  }
  if ($sub -match '^(fetch|ls-remote)$') {
    foreach ($t in $a) {
      if ($t.StartsWith('-')) { continue }
      $u = $t; if ($u -like 'file://*') { $u = $u.Substring(7) }
      if (AsstOwn $u) { Block "an assistant runs git on no repository in its own folder, or one it cannot name (git $sub $u): a .git there could be crafted $ASST_M" }
    }
  }
  if ($a.Count -eq 1 -and $a[0] -ceq '-h') { return }
  AsstGarg $sub $a
  if ($sub -match $ASST_GIT_READ) { return }
  $w = $false; $l = $false; $np = 0; $nx = $false; $rm = $false; $fst = ''
  $gl = $ASST_GIT_OPTS[$sub.ToLowerInvariant()]
  foreach ($t0 in $a) {
    $t = $t0
    if ($nx) { $nx = $false; continue }
    if ($rm) { $rm = $false; if ($t -match ':.') { $w = $true }; continue }   # --refmap's value
    if ($gl -and $t.Length -gt 2 -and $t.StartsWith('--')) { AsstGfull $t $gl; $t = $script:GF; if ($script:GA) { $w = $true } }
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
# value) - but gh --version alone, and gh --help / -h with only words after it, the first a name gh knows (it
# prints help; an extension's name runs the extension, #345); names match
# case-sensitively and whole, as gh matches them. Reads: no group (gh), help, version, status, search; browse only
# with -n / --no-browser, which prints the URL (AsstBrowse); auth status, alias list, config get / list, org list;
# pr | issue | release | repo | label | gist | workflow | secret | variable | run | cache | ruleset | project |
# codespace | ssh-key | gpg-key with no subcommand or list / view / status / diff / checks / watch; project item-list;
# gh api: AsstApi. --web and -w (in a cluster too; gh run list's -w is --workflow) open a browser, on any of them.
function AsstBrowse([string[]]$a) {
  $nb = $false; $nx = $false
  foreach ($t in $a) {
    if ($nx) { $nx = $false; continue }
    if ($t -ceq '--') { break }
    if ($t -cin '-n', '--no-browser', '--no-browser=true') { $nb = $true }
    elseif ($t -cin '-b', '--branch', '-R', '--repo') { $nx = $true }   # its value
  }
  if (-not $nb) { Block "an assistant opens no browser (gh browse): only gh browse --no-browser prints the URL $ASST_M" }
}
function AsstGh([string[]]$a) {
  if ($a.Count -eq 1 -and $a[0] -ceq '--version') { return }
  if ($a.Count -ge 1 -and ($a[0] -ceq '--help' -or $a[0] -ceq '-h') -and -not @($a | Select-Object -Skip 1 | Where-Object { $_.StartsWith('-') }).Count) {
    if ($a.Count -lt 2 -or $a[1] -cin 'pr', 'issue', 'repo', 'release', 'run', 'workflow', 'auth', 'config', 'gist', 'label', 'cache', 'secret', 'variable', 'search', 'status', 'browse', 'codespace', 'project', 'ruleset', 'org', 'alias', 'api', 'attestation', 'extension', 'gpg-key', 'ssh-key', 'completion', 'help', 'preview', 'agent-task') { return }
  }
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
  foreach ($t in $a) {
    if ($t -ceq '--web' -or $t.StartsWith('--web=', [StringComparison]::Ordinal)) { Block "an assistant opens no browser (gh ... $t) $ASST_M" }
    if ($t.StartsWith('--')) { continue }
    if ($t.StartsWith('-') -and $t.Contains('w') -and $grp -cne 'api' -and -not ($grp -ceq 'run' -and $sub -ceq 'list')) { Block "an assistant opens no browser (gh ... $t) $ASST_M" }
  }
  if ($grp -ceq 'api') { AsstApi @(if ($i -lt $a.Count) { $a[$i..($a.Count - 1)] }); return }
  if ($grp -ceq 'browse') { AsstBrowse @(if ($i -lt $a.Count) { $a[$i..($a.Count - 1)] }); return }
  if ($grp -cin '', 'help', 'version', 'status', 'search') { return }
  if ($grp -ceq 'project' -and $sub -ceq 'item-list') { return }
  if (($grp -ceq 'auth' -and $sub -cin '', 'status') -or ($grp -cin 'alias', 'org' -and $sub -cin '', 'list') -or ($grp -ceq 'config' -and $sub -cin '', 'get', 'list')) { return }
  if ($grp -cin 'pr', 'issue', 'release', 'repo', 'label', 'gist', 'workflow', 'secret', 'variable', 'run', 'cache', 'ruleset', 'project', 'codespace', 'ssh-key', 'gpg-key' -and $sub -cin '', 'list', 'view', 'status', 'diff', 'checks', 'watch') { return }
  $gs = if ($sub) { "$grp $sub" } else { $grp }
  Block "an assistant writes nothing to GitHub (gh $gs): it reads only, and gh passes only a known read (COORD_ASSISTANT_DIR is set, #281)"
}
# AsstApi <gh api's arguments>: refuses a method (-X / --method, also -XPOST, --method=x) other than GET or
# HEAD, and fields or --input (-f / -F / --field / --raw-field, also glued or with =) with no method (gh's
# implicit POST); graphql is refused whatever it holds (the owner's decision, 2026-11-02: a board is read by gh
# project view / item-list); the endpoint folded first (a leading /, an http(s)://<host>/ prefix). Flags with letter
# case: -h is not -H.
function AsstApi([string[]]$a) {
  $m = ''; $fl = $false; $ep = ''; $i = 0
  while ($i -lt $a.Count) {
    $t = $a[$i]; $i++
    $nv = if ($i -lt $a.Count) { $a[$i] } else { '' }
    if ($t -ceq '-X' -or $t -ceq '--method') { $m = $nv; $i++ }
    elseif ($t.StartsWith('--method=', [StringComparison]::Ordinal)) { $m = $t.Substring(9) }
    elseif ($t.StartsWith('-X', [StringComparison]::Ordinal)) { $m = $t.Substring(2); if ($m.StartsWith('=')) { $m = $m.Substring(1) } }
    elseif ($t -cmatch '^(-f|-F|--field|--raw-field)$') { $fl = $true; $i++ }
    elseif ($t -cmatch '^--(field|raw-field)=') { $fl = $true }
    elseif ($t -cmatch '^-[fF]') { $fl = $true }
    elseif ($t -ceq '--input') { $fl = $true; $i++ }
    elseif ($t.StartsWith('--input=', [StringComparison]::Ordinal)) { $fl = $true }
    elseif ($t -cmatch '^(-H|--header|-p|--preview|-q|--jq|-t|--template|--cache|--hostname)$') { $i++ }
    elseif ($t.StartsWith('-')) { }
    elseif (-not $ep) { $ep = $t }
  }
  if ($ep -match '^https?://') { $ep = $ep -replace '^https?://[^/]*/?', '' }
  $ep = $ep.TrimStart('/')   # /graphql and https://<host>/graphql are graphql
  if ($ep -ceq 'graphql') { Block "an assistant reads no gh api graphql (a board: gh project view or item-list) $ASST_M" }
  if (-not $m) { if ($fl) { Block 'an assistant writes nothing to GitHub (gh api with fields and no -X GET, which is a POST): it reads only (COORD_ASSISTANT_DIR is set, #281)' }; return }
  if ($m -notmatch '^(get|head)$') { Block "an assistant writes nothing to GitHub (gh api -X $m): it reads only (COORD_ASSISTANT_DIR is set, #281)" }
}
# --- the assistant mode closes the deliberate-evasion routes (#345; the owner's choice, 2026-10-30): an assistant
# reads outside data, so text it reads can try to steer it. One call per simple command (AsstRedir, AsstGvar,
# AsstCmd below). Reading commands is no wall: the routes not named here stay open (TOOLKIT.md *Safety*). ---
$ASST_M = '(COORD_ASSISTANT_DIR is set, #345)'
$script:asr = $null
# AsstIn <a full path>: it lies in the assistant's folder, as written or as on disk (links resolved), whole path
# segments compared, letter case as the system takes it. A folder not absolute, / or a drive holds nothing.
function AsstIn([string]$x) {
  if ($null -eq $script:asr) {
    $script:asr = @()
    if ($asst -match '^([/\\]|[A-Za-z]:[/\\])') {
      $r0 = @(Canon $asst -Keep:$smKeep)
      $ph = Physical $asst -Keep:$smKeep; if ($null -ne $ph) { $r0 += $ph }
      $bad = $false; foreach ($e in $r0) { if ($e -match '^([A-Za-z]:)?$') { $bad = $true } }
      if (-not $bad) { $script:asr = $r0 }
    }
  }
  if ($script:asr.Count -eq 0) { return $false }
  $f = Physical $x -Keep:$smKeep; if ($null -eq $f) { $f = Canon $x -Keep:$smKeep }
  foreach ($r in $script:asr) { if ("$f/".StartsWith("$r/", [StringComparison]::Ordinal)) { return $true } }
  $false
}
# AsstOwn <a folder as written>: git would run there: in the assistant's folder, or a folder that cannot be known
function AsstOwn([string]$p) {
  if ($p -ceq '?') { return $true }
  $f = Compose $script:dir $p
  if ($f -ceq '?') { return $true }
  AsstIn $f
}
# AsstWr <a path as written>: refused unless it lies in the assistant's folder. /dev/null ($null, nul) is no write.
# Unknown: a variable, {} of find, ~name, and in PowerShell a list (a,b) or a drive that is no folder (env:, HKCU:)
function AsstWr([string]$p) {
  $t = $p
  if ($tool -ceq 'PowerShell') {
    if ($t -eq '$null' -or $t -eq 'nul') { return }
    if ($t.Contains(',') -or $t -match '^[A-Za-z][A-Za-z0-9_]+:') { $t = '$' }
  } elseif ($t -match '^/dev/(null|stdout|stderr)$') { return }
  if (-not $t -or $t.Contains('{}') -or $t -match '^~[^/\\]') { $t = '$' }
  $f = Compose $script:dir $t
  if ($f -cne '?' -and (AsstIn $f)) { return }
  $shown = if ($p) { $p } else { '(no path)' }
  Block "an assistant writes only inside its own folder, not to $shown $ASST_M"
}
# AsstRedir: the targets of the redirections of this command (as written): > >> 2> &> <> ; a duplicated stream
# (2>&1) and a read (< , <<<) are no write; a redirection with no word after it (>| ends the command here) is refused
function AsstRedir([string[]]$w) {
  $k = 0
  while ($k -lt $w.Count) {
    $t = $w[$k]; $k++
    $m = [regex]::Match($t, '^([0-9*]*&?[<>]+&?)(.*)$', [Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $m.Success) { continue }
    $op = $m.Groups[1].Value; $rest = $m.Groups[2].Value
    if (-not $rest -and $k -lt $w.Count) { $rest = $w[$k]; $k++ }
    if (-not $op.Contains('>')) { continue }
    if ($op.EndsWith('&') -and $rest -match '^(-|[0-9]+)$') { continue }
    AsstWr $rest
  }
}
# The variables an assistant sets for nothing: one can make a read run a command or reach another host. GH_REPO and
# GH_HOST only name what gh reads. AsstVar <name>: it is one of them
function AsstVar([string]$v) {
  if ($v -match '^(GH_REPO|GH_HOST)$') { return $false }
  $v -match '^(GIT_.*|GH_.*|BROWSER|PAGER|HTTP_PROXY|HTTPS_PROXY|ALL_PROXY|NO_PROXY|CURL_HOME|WGETRC|PATH|HOME|USERPROFILE|XDG_CONFIG_HOME)$'
}
$ASST_ENV_RE = '\$\{?env:(GIT_[A-Za-z0-9_]*|GH_[A-Za-z0-9_]*|BROWSER|PAGER|HTTP_PROXY|HTTPS_PROXY|ALL_PROXY|NO_PROXY|CURL_HOME|WGETRC|PATH|HOME|USERPROFILE|XDG_CONFIG_HOME)\}?[\s]*[-+*/]?='
# AsstGvar <the words> <the index of the command word> <its base name, or empty>: one of them set: before the command
# (GIT_DIR= before git is AsstGenv's), or by export, declare, Set-Item env:... (the word env:X is refused unless a read of it)
function AsstGvar([string[]]$w, [int]$ix, [string]$c) {
  $m = 'an assistant sets no such variable: one can make a read run a command or reach another host'
  for ($k = 0; $k -lt $ix; $k++) {
    if ($w[$k] -notmatch $ASSIGN) { continue }
    $v = $w[$k].Substring(0, $w[$k].IndexOf('='))
    if ($c -eq 'git' -and $v -eq 'GIT_DIR') { continue }
    if (AsstVar $v) { Block "$m ($v=) $ASST_M" }
  }
  if ($c -match '^(export|declare|typeset|readonly|local|set|setenv)$') {
    for ($k = $ix + 1; $k -lt $w.Count; $k++) {
      $t = $w[$k]; $q = $t.IndexOf('='); $v = if ($q -ge 0) { $t.Substring(0, $q) } else { $t }
      if ((AsstVar $v) -and ($c -eq 'setenv' -or $q -ge 0)) { Block "$m ($v) $ASST_M" }
    }
  } elseif ($c -notmatch '^(ls|dir|gci|get-childitem|gi|get-item|gc|get-content|cat|type|test-path|echo|write-output|write-host|select-string|sls|grep)$') {
    for ($k = $ix + 1; $k -lt $w.Count; $k++) {
      if ($w[$k] -notmatch '^env:[/\\]?(.*)$') { continue }
      $v = $Matches[1]
      if (AsstVar $v) { Block "$m (env:$v) $ASST_M" }
    }
  }
}
# AsstGenv <the words> <the index of git>: a VAR=value before git (also after env) - GIT_PAGER, PAGER, HOME, PATH ... can
# make a read run a command; GIT_DIR= with a known path outside the assistant's folder is judged as the read it is
function AsstGenv([string[]]$w, [int]$ix) {
  for ($k = 0; $k -lt $ix; $k++) {
    $t = $w[$k]
    if ($t -notmatch $ASSIGN) { continue }
    if ($t -match '^GIT_DIR=.') {
      if (-not (AsstOwn $t.Substring($t.IndexOf('=') + 1))) { continue }
      Block "an assistant runs git on no repository in its own folder, or one it cannot name ($t): a .git there could be crafted $ASST_M"
    }
    Block "an assistant runs git with no variable set before it ($($t.Substring(0, $t.IndexOf('=')))=): one can make a read run a command (COORD_ASSISTANT_DIR is set, #281)"
  }
}
# AsstGfull <a long option> <the subcommand's long options>: GF its full form as git takes it (a unique start, its
# =value kept); the start of several: git refuses it, GA true
function AsstGfull([string]$t, [string[]]$list) {
  $script:GF = $t; $script:GA = $false
  $n = $t.Substring(2); $v = ''; $q = $n.IndexOf('='); if ($q -ge 0) { $v = $n.Substring($q); $n = $n.Substring(0, $q) }
  $h = ''; $k = 0
  foreach ($c in $list) {
    if ($c -eq $n) { return }
    if ($c.StartsWith($n, [StringComparison]::OrdinalIgnoreCase)) { $h = $c; $k++ }
  }
  if ($k -eq 1) { $script:GF = "--$h$v" }
  if ($k -gt 1) { $script:GA = $true }
}
# AsstPfx <a name> <full names>: the name is one of them or the start of one
function AsstPfx([string]$n, [string[]]$list) {
  if (-not $n) { return $false }
  foreach ($c in $list) { if ($c.StartsWith($n, [StringComparison]::OrdinalIgnoreCase)) { return $true } }
  $false
}
# AsstPsArgs <the arguments of a PowerShell file command>: POS the positional ones, NMD the values of its path
# parameters, DST of -Destination; parameters by their prefixes, -Name:value too; the values of others skipped
function AsstPsArgs([string[]]$a) {
  $script:POS = @(); $script:NMD = @(); $script:DST = ''
  $k = 0
  while ($k -lt $a.Count) {
    $t = $a[$k]; $k++
    if ($t.Length -lt 2 -or -not $t.StartsWith('-')) { $script:POS += $t; continue }
    $n = $t.Substring(1); $v = ''; $hv = $false; $q = $n.IndexOf(':')
    if ($q -ge 0) { $v = $n.Substring($q + 1); $n = $n.Substring(0, $q); $hv = $true }
    $nv = if ($k -lt $a.Count) { $a[$k] } else { '' }
    if (AsstPfx $n @('destination')) { if (-not $hv) { $v = $nv; $k++ }; $script:DST = $v }
    elseif (AsstPfx $n @('path', 'literalpath', 'pspath', 'filepath', 'name')) { if (-not $hv) { $v = $nv; $k++ }; $script:NMD += $v }
    elseif (AsstPfx $n @('value', 'encoding', 'filter', 'include', 'exclude', 'stream', 'itemtype', 'type', 'inputobject', 'credential', 'width', 'variable', 'delimiter', 'erroraction', 'warningaction', 'informationaction', 'errorvariable')) { if (-not $hv) { $k++ } }
  }
}
# AsstWrite <the command word> <its arguments>: the paths a file command writes, each inside the folder: cp only its
# destination (reading anywhere is allowed), mv all, Set-Content / Out-File / New-Item the path, not the value
function AsstWrite([string]$w, [string[]]$a) {
  if ($tool -ceq 'PowerShell') {
    AsstPsArgs $a
    if ($w -match '^(cp|copy|cpi|copy-item)$') {
      if ($script:DST) { AsstWr $script:DST } elseif ($script:POS.Count -gt 1) { AsstWr $script:POS[1] } else { AsstWr '.' }
    } elseif ($w -match '^(mv|move|mi|move-item|rename|ren|rni|rename-item)$') {
      foreach ($t in @($script:NMD) + @($script:POS)) { AsstWr $t }
      if ($script:DST) { AsstWr $script:DST } elseif ($script:POS.Count -lt 2) { AsstWr '.' }
    } elseif ($w -match '^(rm|rmdir|rd|del|erase|ri|remove-item|touch|truncate|ln)$') {
      foreach ($t in @($script:NMD) + @($script:POS)) { AsstWr $t }
    } else {
      foreach ($t in $script:NMD) { AsstWr $t }
      if ($script:POS.Count -gt 0) { AsstWr $script:POS[0] }
    }
    return
  }
  $p = @(); $d = ''; $e = $false; $k = 0; $ct = $w -match '^(cp|copy|mv)$'
  while ($k -lt $a.Count) {
    $t = $a[$k]; $k++
    if ($e) { $p += $t; continue }
    if ($t -ceq '--') { $e = $true }
    elseif ($t -clike '--t*=*') { $d = $t.Substring($t.IndexOf('=') + 1) }
    elseif ($t -clike '--t*') { if ($ct) { $d = if ($k -lt $a.Count) { $a[$k] } else { '' }; $k++ } }
    elseif ($t.StartsWith('--')) { }
    elseif ($t.Length -ge 2 -and $t.StartsWith('-')) {
      if ($ct) {
        $q = $t.IndexOf('t')   # cp -t, not -T
        if ($q -ge 0) { if ($q -eq $t.Length - 1) { $d = if ($k -lt $a.Count) { $a[$k] } else { '' }; $k++ } else { $d = $t.Substring($q + 1) } }
      }
    }
    else { $p += $t }
  }
  if ($w -match '^(cp|copy|cpi|copy-item)$') {
    if ($d) { AsstWr $d } elseif ($p.Count -gt 0) { AsstWr $p[$p.Count - 1] }
  } else {
    if ($d) { AsstWr $d }
    foreach ($t in $p) { AsstWr $t }
  }
}
# AsstSed <its arguments>: sed -i (also -i.bak, -Ei, --in-place, -I): the files it names, the script not among them
function AsstSed([string[]]$a) {
  $ip = $false; $sc = $false; $e = $false; $nx = $false; $p = @()
  foreach ($t in $a) {
    if ($nx) { $nx = $false; continue }
    if ($e) { $p += $t; continue }
    if ($t -ceq '--') { $e = $true }
    elseif ($t -clike '--in*' -or $t -ceq '--i') { $ip = $true }
    elseif ($t -clike '--expression=*' -or $t -clike '--file=*') { $sc = $true }
    elseif ($t -clike '--e*' -or $t -clike '--f*') { $sc = $true; $nx = $true }
    elseif ($t.StartsWith('--')) { }
    elseif ($t.Length -ge 2 -and $t.StartsWith('-')) {
      for ($j = 1; $j -lt $t.Length; $j++) {
        $h = [string]$t[$j]; $last = $j -eq $t.Length - 1
        if ($h -ceq 'i' -or $h -ceq 'I') { $ip = $true; break }
        if ($h -ceq 'e' -or $h -ceq 'f') { $sc = $true; if ($last) { $nx = $true }; break }
        if ($h -ceq 'l') { if ($last) { $nx = $true }; break }
      }
    }
    else { $p += $t }
  }
  if (-not $ip) { return }
  if (-not $sc -and $p.Count -gt 0) { $p = @($p | Select-Object -Skip 1) }
  foreach ($t in $p) { AsstWr $t }
}
# AsstFind <its arguments>: -delete deletes under the paths before the first expression; -fprint* -fls write a file
function AsstFind([string[]]$a) {
  $del = $false; $on = $true; $p = @()
  foreach ($t in $a) {
    if ($t -eq '-delete') { $del = $true; $on = $false }
    elseif ($t -match '^-(fprint|fprint0|fprintf|fls)$') { Block "an assistant writes no file with find $t $ASST_M" }
    elseif ($t.StartsWith('-') -or $t -ceq '!') { $on = $false }
    elseif ($on) { $p += $t }
  }
  if (-not $del) { return }
  if ($p.Count -eq 0) { $p = @('.') }
  foreach ($t in $p) { AsstWr $t }
}
# AsstUrl <a URL as written>: AH its host as the client reads it: an http or https URL or no scheme (read as a
# host), a port dropped; returns false for what cannot be read: a variable, a glob or a list, a backslash, a user (@
# before the host), another scheme, no host. No decoding: a %2e in a host is no listed host.
function AsstUrl([string]$u) {
  if (-not $u -or $u -match '[$`\\{}\[\]<>|^"'' ]') { return $false }
  $q = $u.IndexOf('://')
  if ($q -ge 0) {
    if ($u.Substring(0, $q) -notmatch '^https?$') { return $false }
    $u = $u.Substring($q + 3)
  }
  $r = ($u -split '[/?#]', 2)[0]
  if (-not $r -or $r.Contains('@') -or $r -match ':.*:') { return $false }
  $q = $r.LastIndexOf(':')
  if ($q -ge 0) {
    if ($r.Substring($q + 1) -notmatch '^[0-9]+$') { return $false }
    $r = $r.Substring(0, $q)
  }
  if (-not $r) { return $false }
  $script:AH = $r
  $true
}
# AsstHost <host>: true listed in COORD_ASSISTANT_HOSTS (<host>[:write],...: the same name whole, any letter case),
# AW true with :write. An entry of another form lists nothing.
function AsstHost([string]$hn) {
  $script:AW = $false; $ok = $false
  foreach ($e0 in ("$env:COORD_ASSISTANT_HOSTS" -split ',')) {
    $e = $e0.Trim(); $q = $e.IndexOf(':'); $h = if ($q -ge 0) { $e.Substring(0, $q) } else { $e }
    if (-not $h) { continue }
    if ($e -ine $h -and $e -ine "${h}:write") { continue }
    if ($hn -ieq $h) { $ok = $true; if ($e -ine $h) { $script:AW = $true } }
  }
  $ok
}
# curl's long options the guard reads; any other, or the start of one that is no write, is refused
$CURL_RS = @('silent', 'show-error', 'no-show-error', 'fail', 'fail-with-body', 'fail-early', 'include', 'head', 'verbose', 'compressed', 'globoff', 'get', 'http1.0', 'http1.1', 'http2', 'ipv4', 'ipv6', 'insecure', 'no-progress-meter', 'progress-bar')
$CURL_RV = @('header', 'user-agent', 'referer', 'user', 'cookie', 'max-time', 'connect-timeout', 'retry', 'retry-delay', 'retry-max-time', 'range')
$CURL_W = @('data', 'data-ascii', 'data-binary', 'data-raw', 'data-urlencode', 'form', 'form-string', 'upload-file', 'json')
function AsstMethod([string]$v) { if ($v -cnotmatch '^(GET|HEAD)$') { $script:NW = $true } }
# AsstCurl <its arguments>: fills NU (URLs), NO (outputs), NW (a write), NL (follows a redirect), NR (a file named from the URL)
function AsstCurl([string[]]$a) {
  $k = 0; $e = $false
  while ($k -lt $a.Count) {
    $t = $a[$k]; $k++
    if ($e) { $script:NU += $t; continue }
    if ($t -ceq '--') { $e = $true; continue }
    $nv = if ($k -lt $a.Count) { $a[$k] } else { '' }
    if ($t.Length -gt 2 -and $t.StartsWith('--')) {
      $n = $t.Substring(2); $v = ''; $hv = $false; $q = $n.IndexOf('=')
      if ($q -ge 0) { $v = $n.Substring($q + 1); $n = $n.Substring(0, $q); $hv = $true }
      if ($n -ceq 'next') { continue }
      if ($n -ceq 'url') { if (-not $hv) { $v = $nv; $k++ }; $script:NU += $v; continue }
      if ($n -ceq 'output') { if (-not $hv) { $v = $nv; $k++ }; $script:NO += $v; continue }
      if ($n -cin 'remote-name', 'remote-name-all') { $script:NR = $true; continue }
      if ($n -cin 'location', 'location-trusted') { $script:NL = $true; continue }
      if ($n -ceq 'request') { if (-not $hv) { $v = $nv; $k++ }; AsstMethod $v; continue }
      if ($CURL_W -ccontains $n) { $script:NW = $true; if (-not $hv) { $k++ }; continue }
      if ($CURL_RS -ccontains $n) { continue }
      if ($CURL_RV -ccontains $n) { if (-not $hv) { $k++ }; continue }
      # an abbreviated option as its full form: the start of the write options only
      $rd = $false; foreach ($c in @($CURL_RS) + @($CURL_RV)) { if ($c.StartsWith($n, [StringComparison]::Ordinal)) { $rd = $true } }
      $wr = $false; foreach ($c in @($CURL_W) + @('request')) { if ($c.StartsWith($n, [StringComparison]::Ordinal)) { $wr = $true } }
      if ($rd -or -not $wr) { Block "an assistant runs curl only with options the guard reads, not $t $ASST_M" }
      $script:NW = $true; if (-not $hv) { $k++ }
      continue
    }
    if ($t.Length -ge 2 -and $t.StartsWith('-')) {
      for ($j = 1; $j -lt $t.Length; $j++) {
        $h = [string]$t[$j]; $c = $t.Substring($j + 1)
        if ('sSfiIvkgGq012346#:'.Contains($h)) { continue }
        if ($h -ceq 'L') { $script:NL = $true; continue }
        if ($h -ceq 'O') { $script:NR = $true; continue }
        if ('HAeubmr'.Contains($h)) { if (-not $c) { $k++ }; break }
        if ('dFT'.Contains($h)) { $script:NW = $true; if (-not $c) { $k++ }; break }
        if ($h -ceq 'X') { $v = $c; if (-not $c) { $v = $nv; $k++ }; AsstMethod $v; break }
        if ($h -ceq 'o') { $v = $c; if (-not $c) { $v = $nv; $k++ }; $script:NO += $v; break }
        Block "an assistant runs curl only with options the guard reads, not $t $ASST_M"
      }
      continue
    }
    $script:NU += $t
  }
}
# AsstWget <its arguments>: the same fills; with no -O the file is named from the URL
function AsstWget([string[]]$a) {
  $k = 0; $e = $false; $oo = $false
  while ($k -lt $a.Count) {
    $t = $a[$k]; $k++
    if ($e) { $script:NU += $t; continue }
    if ($t -ceq '--') { $e = $true; continue }
    $nv = if ($k -lt $a.Count) { $a[$k] } else { '' }
    if ($t.Length -gt 2 -and $t.StartsWith('--')) {
      $n = $t.Substring(2); $v = ''; $hv = $false; $q = $n.IndexOf('=')
      if ($q -ge 0) { $v = $n.Substring($q + 1); $n = $n.Substring(0, $q); $hv = $true }
      if ($n -cin 'quiet', 'server-response', 'no-verbose') { continue }
      if ($n -cin 'header', 'user-agent', 'timeout', 'tries') { if (-not $hv) { $k++ }; continue }
      if ($n -ceq 'output-document') { if (-not $hv) { $v = $nv; $k++ }; $script:NO += $v; $oo = $true; continue }
      if ($n -ceq 'method') { if (-not $hv) { $v = $nv; $k++ }; AsstMethod $v; continue }
      $wr = $false; foreach ($c in @('post-data', 'post-file', 'body-data', 'body-file')) { if ($c.StartsWith($n, [StringComparison]::Ordinal)) { $wr = $true } }
      if (-not $wr) { Block "an assistant runs wget only with options the guard reads, not $t $ASST_M" }
      $script:NW = $true; if (-not $hv) { $k++ }
      continue
    }
    if ($t -ceq '-nv') { continue }
    if ($t.Length -ge 2 -and $t.StartsWith('-')) {
      for ($j = 1; $j -lt $t.Length; $j++) {
        $h = [string]$t[$j]; $c = $t.Substring($j + 1)
        if ($h -ceq 'q' -or $h -ceq 'S') { continue }
        if ('TtU'.Contains($h)) { if (-not $c) { $k++ }; break }
        if ($h -ceq 'O') { $v = $c; if (-not $c) { $v = $nv; $k++ }; $script:NO += $v; $oo = $true; break }
        Block "an assistant runs wget only with options the guard reads, not $t $ASST_M"
      }
      continue
    }
    $script:NU += $t
  }
  if (-not $oo) { $script:NR = $true }
}
# AsstIwr <the command word> <its arguments>: Invoke-WebRequest / Invoke-RestMethod, parameters by their prefixes,
# -Name:value too
function AsstIwr([string]$c, [string[]]$a) {
  $k = 0
  while ($k -lt $a.Count) {
    $t = $a[$k]; $k++
    if ($t.Length -lt 2 -or -not $t.StartsWith('-')) { $script:NU += $t; continue }
    $n = $t.Substring(1); $v = ''; $hv = $false; $q = $n.IndexOf(':')
    if ($q -ge 0) { $v = $n.Substring($q + 1); $n = $n.Substring(0, $q); $hv = $true }
    if (AsstPfx $n @('usebasicparsing', 'disablekeepalive')) { continue }
    if (-not $hv) { $v = if ($k -lt $a.Count) { $a[$k] } else { '' }; $k++ }
    if (AsstPfx $n @('uri')) { $script:NU += $v }
    elseif (AsstPfx $n @('method')) { if ($v -notmatch '^(get|head)$') { $script:NW = $true } }
    elseif (AsstPfx $n @('body', 'infile', 'form', 'custommethod')) { $script:NW = $true }
    elseif (AsstPfx $n @('outfile')) { $script:NO += $v }
    elseif (AsstPfx $n @('headers', 'timeoutsec', 'maximumredirection', 'useragent', 'contenttype')) { }
    else { Block "an assistant runs $c only with parameters the guard reads, not $t $ASST_M" }
  }
}
# AsstNet <the words> <the index of the command word> <the command word> <its arguments>: closed by default; each URL a
# listed host; a write only on one with :write; a redirect only from one without it (it must not carry data
# elsewhere); an output inside the folder
function AsstNet([string[]]$w, [int]$ix, [string]$c, [string[]]$a) {
  if ($a.Count -eq 1 -and $c -match '^(curl|wget)$' -and $a[0] -match '^(--help|-h|--version)$') { return }
  for ($k = 0; $k -lt $ix; $k++) {
    if ($w[$k] -match $ASSIGN) { Block "an assistant runs $c with no variable set before it ($($w[$k].Substring(0, $w[$k].IndexOf('=')))=): one can reach another host or read another config $ASST_M" }
  }
  $script:NU = @(); $script:NO = @(); $script:NW = $false; $script:NL = $false; $script:NR = $false
  if ($c -eq 'curl') { AsstCurl $a } elseif ($c -eq 'wget') { AsstWget $a } else { AsstIwr $c $a }
  if ($script:NU.Count -eq 0) { Block "an assistant reaches the network only at a URL the guard can read ($c): none named $ASST_M" }
  foreach ($t in $script:NU) {
    if (-not (AsstUrl $t)) { Block "an assistant reaches the network only at a URL the guard can read, not $t $ASST_M" }
    if (-not (AsstHost $script:AH)) { Block "an assistant reaches only the hosts in COORD_ASSISTANT_HOSTS, not $($script:AH) $ASST_M" }
    if ($script:NW -and -not $script:AW) { Block "an assistant writes only to a host listed with :write in COORD_ASSISTANT_HOSTS, not $($script:AH) $ASST_M" }
    if ($script:NL -and $script:AW) { Block "an assistant follows no redirect from a host with :write ($($script:AH)): it must not carry data elsewhere $ASST_M" }
  }
  foreach ($t in $script:NO) { if ($t -cne '-') { AsstWr $t } }
  if ($script:NR) { AsstWr '.' }
}
# AsstPath <a command word with a folder>: only an absolute path outside the assistant's folder, to a program known
# here (/usr/bin/git, C:\x\git.exe); ./x.sh, its own folder and any other program by a path run what a file says
function AsstPath([string]$t) {
  $b = BaseName $t
  if ($t -match '^([/\\]|[A-Za-z]:)' -and $b -match '^(git|gh|curl|wget|env|ls|cat|grep|egrep|fgrep|head|tail|wc|sort|uniq|cut|tr|find|sed|awk|jq|date|echo|printf|timeout|nice|sudo|stdbuf|xargs|dirname|basename|pwd|which|where|tee|rm|cp|mv|mkdir|touch|dd)$') {
    $f = Compose $script:dir $t
    if ($f -cne '?' -and -not (AsstIn $f)) { return }
  }
  Block "an assistant runs no script or program by its path ($t) $ASST_M"
}
# AsstCmd <the words> <the index of the command word> <its base name>: one simple command
function AsstCmd([string[]]$w, [int]$ix, [string]$c) {
  $xa = $false
  for ($k = 0; $k -le $ix; $k++) {
    $t = $w[$k]
    if ($t -match $ASSIGN -or $t.StartsWith('-')) { continue }
    if ($t -match '[/\\]') { AsstPath $t }
    if ((BaseName $t) -eq 'xargs') { $xa = $true }
  }
  $t = $w[$ix]; $a = @(if ($ix + 1 -lt $w.Count) { $w[($ix + 1)..($w.Count - 1)] })
  # a variable or a command's output as the command word; in PowerShell $x = 'a' (kept as written) is no command
  if ($t.Contains('$')) {
    $asg = ($tool -ceq 'PowerShell') -and ($t.Contains('=') -or ($a.Count -gt 0 -and $a[0] -match '^([-+*/%]|\?\?)?='))
    if (-not $asg) { Block "an assistant runs no command from a variable ($t) $ASST_M" }
  }
  if ($c -eq 'setx' -or $c.Contains('[environment]::setenvironmentvariable') -or $c.Contains('[system.environment]::setenvironmentvariable')) { Block "an assistant sets no variable for good ($c) $ASST_M" }
  $net = 'an assistant reaches the network only by curl, wget or Invoke-WebRequest, at a listed host'
  if ($c.Contains('[net.') -or $c.Contains('[system.net.')) { Block "$net ($c) $ASST_M" }
  if ($c -eq 'new-object') { foreach ($x in $a) { if ($x -match '^(system\.)?net\.') { Block "$net (New-Object $x) $ASST_M" } } }
  if ($c -match '^(bash|sh|zsh|dash|ksh|ash|fish|csh|tcsh|pwsh|powershell|python|python[0-9].*|py|pypy.*|node|nodejs|deno|bun|perl|ruby|php|lua|cmd|wscript|cscript|mshta|rundll32|regsvr32|eval|source|\.|iex|invoke-expression|invoke-command|icm|start-process|saps|start|invoke-item|ii|start-job|sajb)$') { Block "an assistant runs no script and no inline code ($c) $ASST_M" }
  if ($c -match '\.(sh|bash|ps1|psm1|py|js|mjs|rb|pl|php|bat|cmd|vbs)$') { Block "an assistant runs no script ($c) $ASST_M" }
  if ($c -match '^(nc|ncat|netcat|socat|ssh|scp|sftp|ftp|telnet|rsync|certutil|bitsadmin|start-bitstransfer)$') { Block "$net ($c) $ASST_M" }
  if ($c -match '^(curl|wget|iwr|irm|invoke-webrequest|invoke-restmethod)$') { AsstNet $w $ix $c $a }
  if ($c -match '^(tee|tee-object|cp|copy|cpi|copy-item|mv|move|mi|move-item|rename|ren|rni|rename-item|rm|rmdir|rd|del|erase|ri|remove-item|touch|truncate|ln|mkdir|md|new-item|ni|set-content|sc|add-content|ac|clear-content|clc|out-file)$') {
    if ($xa) { Block "an assistant writes no file through xargs ($c): the paths come from its input $ASST_M" }
    AsstWrite $c $a
  }
  if ($c -eq 'sed') { AsstSed $a }
  if ($c -eq 'dd') { foreach ($x in $a) { if ($x -like 'of=*') { AsstWr $x.Substring(3) } } }
  if ($c -eq 'find') { AsstFind $a }
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
# what the words of a command no longer show: an environment variable set in PowerShell (its right side is cut off as
# a command, #374) and a script block run by the call operator; as text, so a quoted one is refused too
if ($asst) {
  if ($cmd -match $ASST_ENV_RE) { Block "an assistant sets no such variable ($($Matches[0])): one can make a read run a command or reach another host $ASST_M" }
  if ($tool -ceq 'PowerShell' -and $cmd -match '(^|[^&])&\s*\{') { Block "an assistant runs no script block (& { ... }) $ASST_M" }
}
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
  if ($asst) { AsstRedir $segT }
  # the command word: after wrappers ({ ( ! then do sudo env ...), their options (sudo -E,
  # timeout -k 5 30, nice -n 5, stdbuf -oL ...) and VAR=value assignments
  $i = CmdIdx $words
  if ($i -ge $words.Count) { if ($asst) { AsstGvar $words $i '' }; continue }
  $cw = BaseName $words[$i]
  if ($asst) { AsstGvar $words $i $cw; AsstCmd $words $i $cw }
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
