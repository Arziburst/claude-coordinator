# Syntax check of every script under the given folders (Windows; macOS / Linux: check-scripts.sh - same
# output). Catches a script that no longer parses before anything runs it.
#   powershell -File scripts/check-scripts.ps1 [folder ...]      default: this core's own scripts/
# .ps1 files: PowerShell's own parser, Windows PowerShell 5.1's where it exists (run with pwsh too); a
# file marked `#Requires -Version 7` (or 6, or `-PSEdition Core`) is parsed by `pwsh`, and is listed as
# skipped, not passed, where there is none. .sh files: `bash -n`, through check-scripts.sh with Git Bash
# (the bash next to git); no bash: listed as skipped, not passed; a bash that does not run: an error.
# Prints `<file>:<line>: <message>` per error, then `check-scripts: <n> files, <e> errors`.
# Exit 1 on any error, 2 on a usage error.
param([switch]$OnlyPs1, [Parameter(DontShow)][string]$ParseFile, [Parameter(Position = 0, ValueFromRemainingArguments = $true)][string[]]$Folders)   # -OnlyPs1, -ParseFile: internal
# native output (git, bash) is read and this script's own output written as UTF-8, whatever the console's
# code page (cp866 on a Russian Windows garbles a non-ASCII path or a section sign); no console: left as is
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
if ($Folders -and ($Folders[0] -eq '-h' -or $Folders[0] -eq '--help')) {
  Get-Content -LiteralPath $PSCommandPath -TotalCount 9 | ForEach-Object { $_ -replace '^# ?', '' }; exit 2
}
$ErrorActionPreference = 'Stop'

# `<line>: <message>` per parse error of one file
function Parse([string]$path) {
  $tokens = $null; $errs = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errs)
  foreach ($x in @($errs)) { if ($x) { "{0}: {1}" -f $x.Extent.StartLineNumber, $x.Message } }
}
if ($ParseFile) { Parse $ParseFile; exit 0 }   # called under pwsh for a file that needs PowerShell 7

$here = Split-Path -Parent $PSCommandPath
if (-not $Folders) { $Folders = @($here) }
foreach ($d in $Folders) { if (-not (Test-Path -LiteralPath $d -PathType Container)) { [Console]::Error.WriteLine("not a folder: $d"); exit 2 } }

# every file as <folder>/<path below it>, sorted the same way on every system; the extension in any letter
# case (Foo.SH), on every system, as check-scripts.sh matches it. The core's deliberately broken fixtures
# (tests/check-scripts/broken/) are left out unless the folder given is that folder or inside it: a whole
# core copy passes, and their own check still sees them fail.
function List([string]$ext) {
  $p = '/tests/check-scripts/broken/'
  foreach ($d in $Folders) {
    $shown = $d.TrimEnd('/', '\').Replace('\', '/')
    # Get-Item's FullName is in the form the listing's FullNames take (a root given as C:\Users\RUNNER~1\...
    # comes back long), so the relative paths are cut at the right place
    $root = (Get-Item -LiteralPath $d -Force).FullName.TrimEnd('/', '\')
    $a = $root.Replace('\', '/') + '/'
    # no -Filter: it is case-sensitive under PowerShell 7 on Linux and macOS
    $rel = [string[]]@(Get-ChildItem -LiteralPath $root -Recurse -File |
      Where-Object { $_.Extension -eq ".$ext" } |
      ForEach-Object { $_.FullName.Substring($root.Length + 1).Replace('\', '/') } |
      Where-Object { $a.Contains($p) -or -not ($a + $_).Contains($p) })
    [Array]::Sort($rel, [StringComparer]::Ordinal)   # as LC_ALL=C sort
    foreach ($r in $rel) { if ($r) { [pscustomobject]@{ Show = "$shown/$r"; Path = (Join-Path $root $r) } } }
  }
}

# a script that declares it runs only on PowerShell 6+ (#Requires -Version 7, -PSEdition Core)
function Needs7([string]$path) {
  foreach ($l in [IO.File]::ReadAllLines($path)) {
    if ($l -match '^\s*#requires\b.*-psedition\s+core\b') { return $true }
    if ($l -match '^\s*#requires\b.*-version\s+(\d+)' -and [int]$Matches[1] -ge 6) { return $true }
  }
  return $false
}

# runs another shell's part of the check (check-scripts.sh --only-sh, or this script -OnlyPs1 under
# Windows PowerShell 5.1): passes its error lines on and adds its `#count <n> <e>` line to the totals.
# A shell that does not run (the WSL launcher without a distribution, a broken install) prints no count
# line: its files are listed as skipped and counted as an error, never dropped from the count silently.
function Hand([string]$what, [string]$name, [int]$count, [string]$exe, [string[]]$a) {
  $res = @(& { $ErrorActionPreference = 'Continue'; & $exe @a 2>$null })
  $c = @($res | Where-Object { $_ -match '^#count \d+ \d+$' })
  if ($c.Count -eq 0) { "skipped $count $what files: $name did not run ($exe)"; $script:e++; return }
  $res | Where-Object { $_ -notmatch '^#count \d+ \d+$' }
  $w = "$($c[-1])".Split(' '); $script:n += [int]$w[1]; $script:e += [int]$w[2]
}

$n = 0; $e = 0
$sh = @(List 'sh')
if (-not $OnlyPs1 -and $sh.Count -gt 0) {
  # On Windows the bash next to git (Git Bash) first: a plain `bash` on PATH may be the WSL launcher
  # (C:\Windows\System32\bash.exe), which checks nothing
  $bash = $null
  if ($env:OS -eq 'Windows_NT') {
    $git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($git) {
      $gd = Split-Path -Parent $git.Source
      foreach ($b in @((Join-Path $gd '..\bin\bash.exe'), (Join-Path $gd '..\..\bin\bash.exe'))) {
        if (Test-Path -LiteralPath $b -PathType Leaf) { $bash = [IO.Path]::GetFullPath($b); break }
      }
    }
    if (-not $bash -and $env:ProgramFiles) {
      $b = Join-Path $env:ProgramFiles 'Git\bin\bash.exe'; if (Test-Path -LiteralPath $b -PathType Leaf) { $bash = $b }
    }
  }
  if (-not $bash) {
    $c = Get-Command bash -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $bash = if ($c) { $c.Source } else { $null }
  }
  if ($bash) {
    $fw = @($Folders | ForEach-Object { $_.Replace('\', '/') })   # bash reads forward slashes
    Hand '.sh' 'bash' $sh.Count $bash (@(($here.Replace('\', '/') + '/check-scripts.sh'), '--only-sh') + $fw)
  } else { "skipped $($sh.Count) .sh files: no bash on this machine" }
}
$ps1 = @(List 'ps1')
# Under PowerShell 7 on Windows, where Windows PowerShell 5.1 exists, the .ps1 files are parsed by 5.1
# (its rules, as check-scripts.sh does): the mirror of the hand-off of a #Requires -Version 7 file to pwsh
$ps51 = $null
if ($PSVersionTable.PSVersion.Major -ge 6 -and $env:OS -eq 'Windows_NT') {
  $c = Get-Command powershell -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c) { $ps51 = $c.Source }
}
$pwsh = $null
if ($PSVersionTable.PSVersion.Major -lt 6) {
  $c = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c) { $pwsh = $c.Source }
}
if ($ps51 -and $ps1.Count -gt 0) {
  Hand '.ps1' 'powershell' $ps1.Count $ps51 (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-OnlyPs1') + $Folders)
} else {
  foreach ($f in $ps1) {
    if ($PSVersionTable.PSVersion.Major -lt 6 -and (Needs7 $f.Path)) {
      if (-not $pwsh) { "skipped $($f.Show): needs PowerShell 7, no pwsh on this machine"; continue }
      $errs = @(& $pwsh -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -ParseFile $f.Path)
    } else {
      $errs = @(Parse $f.Path)
    }
    $n++
    if ($errs.Count -gt 0) {
      $e++
      foreach ($x in $errs) { "{0}:{1}" -f $f.Show, $x }
    }
  }
}
if ($OnlyPs1) { "#count $n $e"; exit 0 }
"check-scripts: $n files, $e errors"
if ($e -gt 0) { exit 1 }
exit 0
