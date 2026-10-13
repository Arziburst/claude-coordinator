# Check a contract against CONTRACT.md before it is delegated (Windows; macOS / Linux: check-contract.sh -
# same checks, same output).
#   pwsh -File scripts/check-contract.ps1 <contract.md|contract.yaml> ...      (or: powershell -File ...)
# The contract is the YAML header between `---` lines, or a top-level `contract:` block.
# ERROR (exit 1): a required key missing, id / title / intent empty, an acceptance item not led by `criterion:`,
# a criterion without a valid check, an oracle without `how`, non_goals without the two default lines; a file
# that cannot be read (`<file>: cannot read`). WARN: budget.model, .escalate_to, .cost or touches missing; no
# oracle criterion. Reads line by line (no YAML parser), so keep the CONTRACT.md layout; values may be quoted.
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Files)
if (-not $Files) { Get-Content -LiteralPath $PSCommandPath -TotalCount 8 | ForEach-Object { $_ -creplace '^# ?', '' }; exit 2 }

$sect = [string][char]0x00A7   # not a literal: Windows PowerShell 5.1 reads a BOM-less script as ANSI
# a value without its comment, blanks and surrounding quotes (double or single)
function Val([string]$s) {
  $s = ($s -creplace '[ \t]+#.*$', '').Trim(' ', "`t")
  if ($s.Length -ge 2 -and ($s[0] -eq '"' -or $s[0] -eq "'") -and $s[$s.Length - 1] -eq $s[0]) { $s = $s.Substring(1, $s.Length - 2) }
  $s
}
# a top-level value that holds nothing: comments, block markers, blanks or empty quotes only
function Blank([string]$t) { $t = $t -creplace '#[^\n]*', '' -creplace '[>|\n \t]', ''; $t -eq '' -or $t -eq '""' -or $t -eq "''" }

$failed = 0
foreach ($f in $Files) {
  $L = $null
  try { if (Test-Path -LiteralPath $f -PathType Leaf) { $L = @([IO.File]::ReadAllLines((Resolve-Path -LiteralPath $f).Path)) } } catch { }
  if ($null -eq $L) { "${f}: cannot read"; $failed = 1; continue }
  $ne = 0; $nw = 0
  $out = New-Object System.Collections.Generic.List[string]
  # the contract block: front matter, or the body of a top-level "contract:", else the whole file
  $s = 0; $e = $L.Count - 1
  if ($L.Count -and $L[0] -cmatch '^---[ \t]*$') {
    $s = 1
    for ($i = 1; $i -lt $L.Count; $i++) { if ($L[$i] -cmatch '^---[ \t]*$') { $e = $i - 1; break } }
  } else {
    for ($i = 0; $i -lt $L.Count; $i++) {
      if ($L[$i] -cmatch '^contract:[ \t]*$') {
        $s = $i + 1; $e = $L.Count - 1; $ind = 1000
        for ($j = $s; $j -lt $L.Count; $j++) {
          if ($L[$j] -cmatch '^[^ \t]') { $e = $j - 1; break }
          if ($L[$j] -cmatch '[^ \t]') { $w = ([regex]::Match($L[$j], '^[ \t]*')).Length; if ($w -lt $ind) { $ind = $w } }
        }
        for ($j = $s; $j -le $e; $j++) { $L[$j] = if ($L[$j].Length -gt $ind) { $L[$j].Substring($ind) } else { '' } }
        break
      }
    }
  }
  # top-level keys and the text of each
  $txt = @{}; $key = ''
  for ($i = $s; $i -le $e; $i++) {
    if ($L[$i] -cmatch '^([a-z_]+):') { $key = $Matches[1]; $txt[$key] = $L[$i].Substring($Matches[0].Length) }
    elseif ($key) { $txt[$key] += "`n" + $L[$i] }
  }
  foreach ($k in 'id', 'title', 'intent', 'acceptance', 'non_goals', 'do_not_decide') {
    if (-not $txt.ContainsKey($k)) { $out.Add("ERROR missing ``$k``"); $ne++ }
  }
  foreach ($k in 'id', 'title', 'intent') {
    if ($txt.ContainsKey($k) -and (Blank $txt[$k])) { $out.Add("ERROR ``$k`` is empty"); $ne++ }
  }

  # acceptance criteria; each item starts with `- criterion:` (the first `-` line sets the items indent)
  if ($txt.ContainsKey('acceptance')) {
    $crit = @(); $chk = @(); $how = @(); $ii = -1; $mis = $false
    foreach ($line in ($txt['acceptance'] -split "`n")) {
      if ($line -cmatch '^([ \t]*)-([ \t]|$)') {
        $w = $Matches[1].Length; if ($ii -lt 0) { $ii = $w }
        if ($w -eq $ii -and $line -cnotmatch '^[ \t]*-[ \t]*[{]?[ \t]*criterion:') { $mis = $true }
      }
      if ($line -cmatch '^[ \t]*criterion:') { $mis = $true }
      if ($line -cmatch '^[ \t]*-[ \t]*[{]?[ \t]*criterion:[ \t]*(.*)$') {
        $crit += $Matches[1]; $c = ''; $h = ''
        # check: and how: on the same line only in a flow item - { criterion: ..., check: ..., how: ... }
        if ($line -cmatch '^[ \t]*-[ \t]*[{]') {
          if ($line -cmatch 'check:[ \t]*([^ \t,}]+)') { $c = Val $Matches[1] }
          if ($line -cmatch 'how:([^,}]*)') { if ((Val $Matches[1]) -ne '') { $h = 'y' } }
        }
        $chk += $c; $how += $h
      } elseif ($crit.Count -and $line -cmatch '^[ \t]+check:(.*)$') { $chk[$crit.Count - 1] = Val $Matches[1] }
      elseif ($crit.Count -and $line -cmatch '^[ \t]+how:(.*)$') { if ((Val $Matches[1]) -ne '') { $how[$crit.Count - 1] = 'y' } }
    }
    if ($mis) { $out.Add('ERROR criterion must be the first key of each acceptance item'); $ne++ }
    elseif (-not $crit.Count) { $out.Add('ERROR `acceptance` has no criteria'); $ne++ }
    $oracle = $false
    for ($i = 0; $i -lt $crit.Count; $i++) {
      $n = $i + 1; $short = if ($crit[$i].Length -gt 60) { $crit[$i].Substring(0, 60) } else { $crit[$i] }
      if ($chk[$i] -eq '') { $out.Add("ERROR criterion $n has no ``check`` ($short)"); $ne++ }
      elseif ($chk[$i] -cnotmatch '^(oracle|review|owner)$') { $out.Add("ERROR criterion ${n}: check ``$($chk[$i])`` is not oracle / review / owner"); $ne++ }
      elseif ($chk[$i] -ceq 'oracle' -and $how[$i] -eq '') { $out.Add("ERROR criterion ${n}: oracle check without ``how``"); $ne++ }
      if ($chk[$i] -ceq 'oracle') { $oracle = $true }
    }
    if ($crit.Count -and -not $oracle) { $out.Add('WARN  no criterion has an oracle check: everything rests on opinion'); $nw++ }
  }
  if ($txt.ContainsKey('non_goals')) {
    $ng = $txt['non_goals'].ToLower()
    if (-not $ng.Contains('beyond the fix')) { $out.Add('ERROR non_goals lacks the default (no changes beyond the fix, its diagnostics and its test)'); $ne++ }
    if (-not $ng.Contains('weaken')) { $out.Add('ERROR non_goals lacks the default (do not weaken or loosen tests, timeouts or tolerances)'); $ne++ }
  }
  $b = "`n" + $txt['budget']
  if ($b -cnotmatch '\n[ \t]+model:[ \t]*[^ \t\n]') { $out.Add("WARN  budget.model missing (CORE ${sect}7)"); $nw++ }
  if ($b -cnotmatch '\n[ \t]+escalate_to:[ \t]*[^ \t\n]') { $out.Add('WARN  budget.escalate_to missing (no stronger model to retry on)'); $nw++ }
  else {
    # the fixed model names in order of strength (0: a name not on this list)
    $rank = { param($m) $m = "$m".ToLower(); if ($m -match 'fable') { 4 } elseif ($m -match 'opus') { 3 } elseif ($m -match 'sonnet') { 2 } elseif ($m -match 'haiku') { 1 } else { 0 } }
    $bm = if ($b -cmatch '\n[ \t]+model:[ \t]*([^ \t\n#]+)') { $Matches[1] } else { '' }
    $be = if ($b -cmatch '\n[ \t]+escalate_to:[ \t]*([^ \t\n#]+)') { $Matches[1] } else { '' }
    $rm = & $rank $bm; $re = & $rank $be
    if ($rm -and $re -and $re -le $rm) { $out.Add("WARN  budget.escalate_to ($be) is not stronger than budget.model ($bm): its one retry gains nothing"); $nw++ }
  }
  if ($b -cnotmatch '\n[ \t]+cost:[ \t]*[0-9]') {
    if ($b -cmatch '\n[ \t]+tokens:[ \t]*[0-9]') { $out.Add("WARN  budget.tokens is now budget.cost, in USD at list price (CORE ${sect}7a)") }
    else { $out.Add("WARN  budget.cost missing (no spend forecast, CORE ${sect}7a)") }
    $nw++
  }
  if ((($txt['touches'] + '') -creplace '#[^\n]*', '' -creplace '[ \t\n\[\]-]', '') -eq '') {
    $out.Add("WARN  touches missing or empty (no conflict foresight, CORE ${sect}4a)"); $nw++
  }
  # errors first, then warnings, as check-contract.sh prints them in order of the checks
  foreach ($m in $out) { "${f}: $m" }
  "${f}: $(if ($ne) { 'FAIL' } else { 'OK' }) ($ne errors, $nw warnings)"
  if ($ne) { $failed = 1 }
}
exit $failed
