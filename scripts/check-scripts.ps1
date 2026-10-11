# Syntax check of every script under the given folders (Windows; macOS / Linux: check-scripts.sh - same
# output). Catches a script that no longer parses before anything runs it.
#   powershell -File scripts/check-scripts.ps1 [folder ...]      default: this core's own scripts/
# .ps1 files: PowerShell's own parser (run it with `powershell` for Windows PowerShell 5.1's rules); a
# file marked `#Requires -Version 7` (or 6, or `-PSEdition Core`) is parsed by `pwsh`, and is listed as
# skipped, not passed, where there is none. .sh files: `bash -n`, through check-scripts.sh when `bash`
# is installed (Git Bash); without it they are listed as skipped, not passed.
# Prints `<file>:<line>: <message>` per error, then `check-scripts: <n> files, <e> errors`.
# Exit 1 on any error, 2 on a usage error.
param([switch]$OnlyPs1, [Parameter(DontShow)][string]$ParseFile, [Parameter(Position = 0, ValueFromRemainingArguments = $true)][string[]]$Folders)   # -OnlyPs1, -ParseFile: internal
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

# every file as <folder>/<path below it>, sorted the same way on every system
function List([string]$ext) {
  foreach ($d in $Folders) {
    $shown = $d.TrimEnd('/', '\').Replace('\', '/')
    $root = (Resolve-Path -LiteralPath $d).Path.TrimEnd('/', '\')
    $rel = [string[]]@(Get-ChildItem -LiteralPath $root -Recurse -File -Filter "*.$ext" |
      Where-Object { $_.Extension -eq ".$ext" } |
      ForEach-Object { $_.FullName.Substring($root.Length + 1).Replace('\', '/') })
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

$n = 0; $e = 0
$sh = @(List 'sh')
if (-not $OnlyPs1 -and $sh.Count -gt 0) {
  # Git Bash first: on Windows a plain `bash` may be the WSL launcher
  $bash = $null
  if ($env:ProgramFiles) { $bash = Join-Path $env:ProgramFiles 'Git\bin\bash.exe'; if (-not (Test-Path -LiteralPath $bash)) { $bash = $null } }
  if (-not $bash) {
    $c = Get-Command bash -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $bash = if ($c) { $c.Source } else { $null }
  }
  if ($bash) {
    $fw = @($Folders | ForEach-Object { $_.Replace('\', '/') })   # bash reads forward slashes
    $res = @(& $bash ($here.Replace('\', '/') + '/check-scripts.sh') --only-sh @fw)
    foreach ($l in $res) {
      if ($l -match '^#count (\d+) (\d+)$') { $n += [int]$Matches[1]; $e += [int]$Matches[2] } else { $l }
    }
  } else { "skipped $($sh.Count) .sh files: no bash on this machine" }
}
$pwsh = $null
if ($PSVersionTable.PSVersion.Major -lt 6) {
  $c = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c) { $pwsh = $c.Source }
}
foreach ($f in (List 'ps1')) {
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
if ($OnlyPs1) { "#count $n $e"; exit 0 }
"check-scripts: $n files, $e errors"
if ($e -gt 0) { exit 1 }
exit 0
