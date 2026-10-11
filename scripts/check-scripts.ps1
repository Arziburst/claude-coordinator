# Syntax check of every script under the given folders (Windows; macOS / Linux: check-scripts.sh - same
# output). Catches a script that no longer parses before anything runs it.
#   powershell -File scripts/check-scripts.ps1 [folder ...]      default: this core's own scripts/
# .ps1 files: PowerShell's own parser (run it with `powershell` for Windows PowerShell 5.1's rules).
# .sh files: `bash -n`, through check-scripts.sh when `bash` is installed (Git Bash); without it they
# are listed as skipped, not passed.
# Prints `<file>:<line>: <message>` per error, then `check-scripts: <n> files, <e> errors`.
# Exit 1 on any error, 2 on a usage error.
param([switch]$OnlyPs1, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Folders)   # -OnlyPs1: used by check-scripts.sh
if ($Folders -and ($Folders[0] -eq '-h' -or $Folders[0] -eq '--help')) {
  Get-Content -LiteralPath $PSCommandPath -TotalCount 8 | ForEach-Object { $_ -replace '^# ?', '' }; exit 2
}
$ErrorActionPreference = 'Stop'
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
foreach ($f in (List 'ps1')) {
  $n++
  $tokens = $null; $errs = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($f.Path, [ref]$tokens, [ref]$errs)
  if ($errs -and $errs.Count -gt 0) {
    $e++
    foreach ($x in $errs) { "{0}:{1}: {2}" -f $f.Show, $x.Extent.StartLineNumber, $x.Message }
  }
}
if ($OnlyPs1) { "#count $n $e"; exit 0 }
"check-scripts: $n files, $e errors"
if ($e -gt 0) { exit 1 }
exit 0
