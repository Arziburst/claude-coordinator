# Check the coordinator core's own references (Windows; macOS / Linux: check-core.sh - same checks).
#   pwsh -File scripts/check-core.ps1 [repo-root]      (or: powershell -File ...)
# Fails (exit 1) on a relative Markdown link to a missing file, or a section  reference to a section that does
# not exist (the `## <id>. ` headings of CORE.md and procedures/*.md; section 1.N must be an existing hard rule),
# or FEATURES.md out of sync with the files, the scripts, procedures, roles and one-time steps (check-core.sh).
param([string]$Root = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
$sect = [string][char]0x00A7   # not a literal: Windows PowerShell 5.1 reads a BOM-less script as ANSI
$Root = (Resolve-Path -LiteralPath $Root).Path
Set-Location -LiteralPath $Root

$heads = @('CORE.md') + @(Get-ChildItem -Path procedures -Filter '*.md' -File | ForEach-Object { "procedures/$($_.Name)" })
$sections = @{}
foreach ($h in $heads) {
  foreach ($l in [IO.File]::ReadAllLines((Join-Path $Root $h))) {
    if ($l -match '^## (\d+[a-z]?)\. ') { $sections[$Matches[1]] = $true }
  }
}
$rules = 0; $on = $false
foreach ($l in [IO.File]::ReadAllLines((Join-Path $Root 'CORE.md'))) {
  if ($l -match '^## 1\. ') { $on = $true; continue }
  if ($l -match '^## ') { $on = $false }
  if ($on -and $l -match '^\d+\. \*\*') { $rules++ }
}

$errors = 0; $files = 0
# the Markdown files below the root as check-core.sh's find lists them: dot-folders (.github ...) too, but
# not .git, not .claude/ (agent worktrees of a checkout) and not a nested repository or worktree
function MdFiles([string]$dir) {
  foreach ($x in @(Get-ChildItem -LiteralPath $dir -Force)) {
    if ($x.PSIsContainer) {
      if ($x.Name -ceq '.git' -or $x.Name -ceq '.claude' -or ($x.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
          (Test-Path -LiteralPath (Join-Path $x.FullName '.git'))) { continue }
      MdFiles $x.FullName
    } elseif ($x.Name -clike '*.md') { $x }
  }
}
# ordinal order of the relative paths, as LC_ALL=C sort
$all = @(MdFiles $Root)
$rels = [string[]]@($all | ForEach-Object { $_.FullName.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/' })
$byRel = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal); for ($i = 0; $i -lt $all.Count; $i++) { $byRel[$rels[$i]] = $all[$i] }
[Array]::Sort($rels, [StringComparer]::Ordinal)
foreach ($rel in $rels) {
  $file = $byRel[$rel]
  $files++
  $code = $false; $n = 0
  foreach ($line in [IO.File]::ReadAllLines($file.FullName)) {
    $n++
    if ($line -match '^\s*```') { $code = -not $code; continue }
    if ($code) { continue }
    foreach ($m in [regex]::Matches($line, '\]\(([^)\s]+)\)')) {
      $t = $m.Groups[1].Value
      if ($t -match '^[a-z]+:' -or $t.StartsWith('#')) { continue }
      $path = $t.Split('#')[0]
      if ($path -and -not (Test-Path -LiteralPath (Join-Path $file.DirectoryName $path))) {
        "${rel}:${n}: broken link $t"; $errors++
      }
    }
    foreach ($m in [regex]::Matches($line, $sect + '(\d+[a-z]?)(?:\.(\d+))?')) {
      $sec = $m.Groups[1].Value; $sub = $m.Groups[2].Value
      if (-not $sections.ContainsKey($sec)) { "${rel}:${n}: ${sect}$sec does not exist"; $errors++ }
      elseif ($sec -eq '1' -and $sub -and ([int]$sub -lt 1 -or [int]$sub -gt $rules)) {
        "${rel}:${n}: ${sect}1.$sub does not exist (CORE ${sect}1 has $rules hard rules)"; $errors++
      }
    }
  }
}
# FEATURES.md, the feature map: every file a block names exists; every script, procedure, role and
# one-time step is in some feature; IDs are unique; every block has its five fields; the summary table
# and the blocks list the same IDs.
$nfeat = 0
$fm = Join-Path $Root 'FEATURES.md'
if (-not (Test-Path -LiteralPath $fm -PathType Leaf)) { 'FEATURES.md: missing'; $errors++ } else {
  $fnames = @('defined', 'entry', 'promises', 'tested by', 'not covered')
  $row = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal); $rord = New-Object System.Collections.ArrayList
  $blk = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal); $bord = New-Object System.Collections.ArrayList
  $cur = ''; $curn = 0; $have = @($false, $false, $false, $false, $false)
  $out = New-Object System.Collections.ArrayList
  $endblk = {
    if ($script:cur) { for ($k = 0; $k -lt 5; $k++) { if (-not $script:have[$k]) { [void]$script:out.Add("E $($script:curn) $($script:cur) lacks `"- $($fnames[$k]):`"") } } }
    $script:cur = ''; $script:have = @($false, $false, $false, $false, $false)
  }
  $code = $false; $n = 0
  foreach ($line in [IO.File]::ReadAllLines($fm)) {
    $n++
    $line = $line.TrimEnd("`r")
    if ($line -match '^[ \t]*```') { $code = -not $code; continue }
    if ($code) { continue }
    if ($line -match '^\| *(F-[A-Z]+-[0-9]+) *\|') {
      $s = $Matches[1]; if (-not $row.ContainsKey($s)) { $row[$s] = $n; [void]$rord.Add($s) }; continue
    }
    if ($line.StartsWith('### ')) {
      & $endblk
      $w = @($line -split ' +')
      if ($w.Count -gt 1 -and $w[1] -cmatch '^F-[A-Z]+-[0-9]+$') {
        $cur = $w[1]; $curn = $n
        if ($blk.ContainsKey($cur)) { [void]$out.Add("E $n duplicate feature id $cur") } else { $blk[$cur] = $n; [void]$bord.Add($cur) }
      }
      continue
    }
    if ($line.StartsWith('## ')) { & $endblk; continue }
    if ($cur -and $line -cmatch '^- [a-z ]+:') {
      $kk = -1
      for ($k = 0; $k -lt 5; $k++) { if ($line.StartsWith("- $($fnames[$k]):")) { $have[$k] = $true; $kk = $k } }
      if ($kk -eq 0 -or $kk -eq 1 -or $kk -eq 3) {
        $s = $line -creplace '^- [a-z ]+:', '' -replace '[`,;()]', ' '
        foreach ($p in ($s -split ' ' | Where-Object { $_ })) {
          $p = $p -replace '#.*$', '' -replace '[.:]+$', '' -replace '/$', ''
          if ($p -cnotmatch '^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$') { continue }
          if ($p.Contains('/') -or ($p -cmatch '\.(md|sh|ps1|json|yml|txt)$' -and -not $p.StartsWith('.'))) { [void]$out.Add("P $n $p") }
        }
      }
    }
  }
  & $endblk
  foreach ($b in $bord) { if (-not $row.ContainsKey($b)) { [void]$out.Add("E $($blk[$b]) $b is not in the summary table") } }
  foreach ($r in $rord) { if (-not $blk.ContainsKey($r)) { [void]$out.Add("E $($row[$r]) $r has no block") } }
  $nfeat = $bord.Count
  foreach ($o in $out) {
    $kind, $ln, $rest = $o -split ' ', 3
    if ($kind -eq 'E') { "FEATURES.md:${ln}: $rest"; $errors++ }
    # a project's local core copy has no .github/ (CORE section 2): its paths are checked only where it exists
    elseif ($rest.StartsWith('.github/') -and -not (Test-Path -LiteralPath (Join-Path $Root '.github'))) { }
    elseif (-not (Test-Path -LiteralPath (Join-Path $Root $rest))) { "FEATURES.md:${ln}: no such file $rest"; $errors++ }
  }
  $text = [IO.File]::ReadAllText($fm)
  $scripts = [string[]]@(Get-ChildItem -Path scripts -Filter '*.sh' -File -Recurse -Depth 1 | ForEach-Object { $_.FullName.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/' })
  [Array]::Sort($scripts, [StringComparer]::Ordinal)
  $docs = [string[]]@(Get-ChildItem -Path procedures, roles -Filter '*.md' -File | ForEach-Object { $_.FullName.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/' })
  [Array]::Sort($docs, [StringComparer]::Ordinal)
  foreach ($f in @($scripts) + @($docs)) {
    if (-not $text.Contains(($f -replace '\.sh$', ''))) { "FEATURES.md: $f is in no feature"; $errors++ }
  }
  foreach ($l in [IO.File]::ReadAllLines((Join-Path $Root 'ONE-TIME.md'))) {
    if ($l -cmatch '^\| `([a-z0-9-]*)` \|') {
      $id = $Matches[1]
      if (-not $text.Contains('`' + $id + '`')) { "FEATURES.md: one-time step $id is in no feature"; $errors++ }
    }
  }
}
"check-core: $files files, $($sections.Count) sections, $rules hard rules, $nfeat features, $errors errors"
if ($errors) { exit 1 }
