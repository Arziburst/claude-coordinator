# Check a contract against CONTRACT.md before it is delegated (Windows; macOS / Linux: check-contract.sh -
# same checks, same output).
#   pwsh -File scripts/check-contract.ps1 <contract.md|contract.yaml> ...      (or: powershell -File ...)
# The contract is the YAML header between `---` lines, or a top-level `contract:` block.
# ERROR (exit 1): a required key missing, id / title / intent empty, an acceptance item not led by `criterion:`,
# a criterion without a valid check, an oracle without `how` (empty, blank or null is none), `tests_first`
# missing or neither yes nor no with its reason (CORE section 4 step 3), non_goals without
# the two default lines (a line commented out does not count); a file
# that cannot be read (`<file>: cannot read`). WARN: budget.model, .escalate_to, .cost or touches missing; no
# oracle criterion; budget.time (optional) present but not minutes or a range (25, 18-40).
# Reads line by line (no YAML parser), so keep the CONTRACT.md layout; values may be quoted.
#   -Field <key> <contract>: read-only - the same checks, and when the contract passes only the key's
#   value as they read it (its text with continuation lines, comment and quotes removed) on one line,
#   exit 0; else the usual ERROR and FAIL lines and exit 1 (start-worker's tests_first gate, #276).
#   <contract> ... -Runs <RUNS.tsv> [-Kind <k>]: after its own checks, the budget against the run log (CORE
#   section 7a, #333) - the kind from the contract's `kind:` field (it wins over -Kind), else -Kind; the
#   model as run-stats lists it, or the longest listed name budget.model holds (claude-opus-5-5 is opus);
#   4+ tasks: a WARN when budget.cost or budget.time (a range by its middle) is outside run-stats' low..high;
#   fewer (by cost): `thin history: <n> tasks; this model's runs came in at <R>x their estimates` (R: run-stats
#   -Ratio's cost_ratio, - for none; the sign is U+00D7 as in the .sh); an unreadable log or no kind: a WARN.
#   WARN lines count as warnings; never an ERROR, the exit code unchanged; not with -Field (check-contract.sh).
# the arguments are read here, not by a param() binding: -Field with no key, or an empty one, prints the
# usage and exits 2 as check-contract.sh does (a binding would stop with its own error, #288)
$Field = ''; $Files = @($args | ForEach-Object { "$_" }); $usage = -not $Files
if ($Files.Count -gt 0 -and $Files[0] -match '^-field:?$') {
  if ($Files.Count -lt 3 -or -not $Files[1]) { $usage = $true } else { $Field = $Files[1]; $Files = @($Files[2..($Files.Count - 1)]) }
}
$Runs = ''; $RKind = ''; $HasRuns = $false; $rest = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $Files.Count; $i++) {
  if ($Files[$i] -match '^-(runs|kind):?$') {
    if ($i + 1 -ge $Files.Count -or -not $Files[$i + 1]) { $usage = $true; break }
    if ($Matches[1] -eq 'runs') { $Runs = $Files[$i + 1]; $HasRuns = $true } else { $RKind = $Files[$i + 1] }
    $i++
  } else { $rest.Add($Files[$i]) }
}
$Files = @($rest.ToArray())
if (-not $Files.Count -or ($RKind -and -not $HasRuns) -or ($HasRuns -and $Field)) { $usage = $true }
# native output (git, bash) is read and this script's own output written as UTF-8, whatever the console's
# code page (cp866 on a Russian Windows garbles a non-ASCII path or a section sign); no console: left as is.
# The caller's console gets its own encoding back on every way out (the end, any exit N, a terminating
# error): the body below runs inside try, the encoding is restored in finally.
$enc0 = $null; try { $enc0 = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
try {
if ($usage) { Get-Content -LiteralPath $PSCommandPath -TotalCount 21 | ForEach-Object { $_ -creplace '^# ?', '' }; exit 2 }

$sect = [string][char]0x00A7   # not a literal: Windows PowerShell 5.1 reads a BOM-less script as ANSI
# a value without its comment, blanks and surrounding quotes (double or single)
function Val([string]$s) {
  $s = ($s -creplace '[ \t]+#.*$', '').Trim(' ', "`t")
  if ($s.Length -ge 2 -and ($s[0] -eq '"' -or $s[0] -eq "'") -and $s[$s.Length - 1] -eq $s[0]) { $s = $s.Substring(1, $s.Length - 2) }
  $s
}
# a value that says something: not empty, not blanks inside quotes, not null (~)
function Filled([string]$s) { $s = (Val $s).Trim(' ', "`t"); $s -ne '' -and $s -ne '~' -and $s.ToLower() -ne 'null' }
# a top-level value that holds nothing: comments, block markers, blanks or empty quotes only
function Blank([string]$t) { $t = $t -creplace '#[^\n]*', '' -creplace '[>|\n \t]', ''; $t -eq '' -or $t -eq '""' -or $t -eq "''" }

# the budget against the run log: lines `W<tab><warning>` and `I<tab><line>` (the header: -Runs)
$inv = [Globalization.CultureInfo]::InvariantCulture
$RunStats = Join-Path $PSScriptRoot 'run-stats.ps1'
function Forecast([string]$k, [string]$bm, [string]$c, [string]$t) {
  if (-not (Test-Path -LiteralPath $Runs -PathType Leaf)) { return "W`tcannot read the run log ${Runs}: the budget is not checked against run-stats (CORE ${sect}7a)" }
  if (-not $k) { return "W`t--runs without a kind (no ``kind:`` field, no --kind): the budget is not checked against run-stats" }
  if (-not $bm) { return }   # budget.model missing: warned above
  $tbl = @(& $RunStats $Runs)
  if ($LASTEXITCODE) { return "W`trun-stats failed on ${Runs}" }
  # the model as run-stats lists it: the same name, else the longest listed name budget.model holds
  $m = ''; $exact = $false; $y = $bm.ToLowerInvariant()
  foreach ($ln in @($tbl | Select-Object -Skip 1)) {
    $x = "$ln".Split("`t"); if ($x.Count -lt 2) { continue }; $xm = $x[1].ToLowerInvariant()
    if ($xm -ceq $y) { $m = $x[1]; $exact = $true }
    elseif (-not $exact -and $xm -ne '' -and $y.Contains($xm) -and $x[1].Length -gt $m.Length) { $m = $x[1] }
  }
  if (-not $m) { $m = $bm }
  $p = $null
  foreach ($ln in @($tbl | Select-Object -Skip 1)) { $x = "$ln".Split("`t"); if ($x.Count -ge 10 -and $x[0] -ceq $k -and $x[1] -ceq $m) { $p = $x; break } }
  $n = if ($p) { [int]$p[2] } else { 0 }
  if ($n -lt 4) {
    $rt = @(& $RunStats $Runs -Ratio -Model $m 2>$null); $r = '-'
    if ($rt.Count -ge 1) { $q = "$($rt[0])".Split("`t"); if ($q.Count -ge 3 -and $q[2]) { $r = $q[2] } }
    "I`tthin history: $n tasks; this model's runs came in at $r$([char]0x00D7) their estimates"
  }
  if (-not $p) { return }
  # the WARN lines from the pair's line (cost from 4 tasks on; the time likewise)
  $num = '^[0-9]+([.][0-9]+)?\z'; $pair = "$k/$m"
  $v = $c -creplace '^[$]', ''
  if ($n -ge 4 -and $v -cmatch $num) {
    $d = [decimal]::Parse($v, $inv)
    if ($d -lt [decimal]::Parse($p[4], $inv) -or $d -gt [decimal]::Parse($p[5], $inv)) { "W`tbudget.cost $c is outside run-stats ${pair}: median $($p[3]), range $($p[4])-$($p[5]), $($p[2]) tasks" }
  }
  $v = $t -creplace '[ \t]', ''; $d = $null
  if ($v -cmatch '^([0-9]+(?:[.][0-9]+)?)-([0-9]+(?:[.][0-9]+)?)\z') { $d = ([decimal]::Parse($Matches[1], $inv) + [decimal]::Parse($Matches[2], $inv)) / 2 }
  elseif ($v -cmatch $num) { $d = [decimal]::Parse($v, $inv) }
  if ([int]$p[6] -ge 4 -and $null -ne $d) {
    if ($d -lt [decimal]::Parse($p[8], $inv) -or $d -gt [decimal]::Parse($p[9], $inv)) { "W`tbudget.time $t is outside run-stats ${pair}: median $($p[7]), range $($p[8])-$($p[9]), $($p[6]) tasks" }
  }
}
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
  # tests first (CORE section 4 step 3): yes, or no with its reason - never left undecided
  if (-not $txt.ContainsKey('tests_first')) { $out.Add("ERROR missing ``tests_first`` (yes, or no with the reason: CORE ${sect}4 step 3)"); $ne++ }
  else {
    $tf = (Val $txt['tests_first']).ToLower()
    if ($tf -cnotmatch '^yes([ \t,:;(]|$)' -and $tf -cnotmatch ('^no[ \t]*(' + [char]0x2014 + '|-|:|,|[(])[ \t]*[^ \t)]')) {
      $out.Add("ERROR ``tests_first`` is neither yes nor no with its reason ($(Val $txt['tests_first'])): write ``tests_first: yes`` or ``tests_first: no - <why>``"); $ne++
    }
  }

  # acceptance criteria; each item starts with `- criterion:` (the first `-` line sets the items indent)
  if ($txt.ContainsKey('acceptance')) {
    $crit = @(); $chk = @(); $how = @(); $ii = -1; $mis = $false
    $AL = @($txt['acceptance'] -split "`n")
    for ($li = 0; $li -lt $AL.Count; $li++) {
      $line = $AL[$li]
      if ($line -cmatch '^([ \t]*)-([ \t]|$)') {
        $w = $Matches[1].Length; if ($ii -lt 0) { $ii = $w }
        if ($w -eq $ii -and $line -cnotmatch '^[ \t]*-[ \t]*[{]?[ \t]*criterion:') { $mis = $true }
      }
      if ($line -cmatch '^[ \t]*criterion:') { $mis = $true }
      if ($line -cmatch '^[ \t]*-[ \t]*[{]?[ \t]*criterion:[ \t]*(.*)$') {
        $crit += $Matches[1]; $c = ''; $h = ''
        # check: and how: on the same line only in a flow item - { criterion: ..., check: ..., how: ... } -
        # each key after the brace or a comma, so a criterion whose text holds "how:" names no how
        if ($line -cmatch '^[ \t]*-[ \t]*[{]') {
          if ($line -cmatch '[{,][ \t]*check:[ \t]*([^ \t,}]+)') { $c = Val $Matches[1] }
          if ($line -cmatch '[{,][ \t]*how:([^,}]*)') { if (Filled $Matches[1]) { $h = 'y' } }
        }
        $chk += $c; $how += $h
      } elseif ($crit.Count -and $line -cmatch '^[ \t]+check:(.*)$') { $chk[$crit.Count - 1] = Val $Matches[1] }
      elseif ($crit.Count -and $line -cmatch '^([ \t]+)how:(.*)$') {
        $hi = $Matches[1].Length; $raw = $Matches[2]
        # a block scalar (how: > or how: |) holds the lines below that are indented deeper than the key
        if ((Val $raw) -cmatch '^[>|][-+0-9]*$') {
          for ($j = $li + 1; $j -lt $AL.Count; $j++) {
            if ($AL[$j] -cmatch '^[ \t]*(#.*)?$') { continue }
            if (([regex]::Match($AL[$j], '^[ \t]*')).Length -gt $hi) { $how[$crit.Count - 1] = 'y' }
            break
          }
        } elseif (Filled $raw) { $how[$crit.Count - 1] = 'y' }
      }
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
    # its text without comments: a default line commented out (# - no changes ...) is missing
    $ng = (@($txt['non_goals'] -split "`n" | Where-Object { $_ -cnotmatch '^[ \t]*#' } | ForEach-Object { $_ -creplace '[ \t]+#.*$', '' }) -join "`n").ToLower()
    if (-not $ng.Contains('no changes beyond')) { $out.Add('ERROR non_goals lacks the default (no changes beyond this contract''s acceptance, its diagnostics and its tests)'); $ne++ }
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
  # the time estimate is optional: checked only when it is there
  if ($b -cmatch '\n[ \t]+time:([^\n]*)') {
    $tv = Val $Matches[1]
    if ($tv -cnotmatch '^[0-9]+([.][0-9]+)?([ \t]*-[ \t]*[0-9]+([.][0-9]+)?)?\z') { $out.Add("WARN  budget.time ($tv) is not minutes or a range of minutes (25 or 18-40, CORE ${sect}7a)"); $nw++ }
  }
  if ((($txt['touches'] + '') -creplace '#[^\n]*', '' -creplace '[ \t\n\[\]-]', '') -eq '') {
    $out.Add("WARN  touches missing or empty (no conflict foresight, CORE ${sect}4a)"); $nw++
  }
  # -Runs: the budget against the run log, after the checks above; a `kind:` field wins over -Kind
  if ($HasRuns) {
    $ck = if ($txt.ContainsKey('kind')) { Val (($txt['kind'] -split "`n")[0]) } else { '' }
    if (-not $ck) { $ck = $RKind }
    $cm = if ($b -cmatch '\n[ \t]+model:[ \t]*([^ \t\n#]+)') { $Matches[1] } else { '' }
    $cc = if ($b -cmatch '\n[ \t]+cost:[ \t]*([^ \t\n#]+)') { $Matches[1] } else { '' }
    $ctm = if ($b -cmatch '\n[ \t]+time:([^\n]*)') { Val $Matches[1] } else { '' }
    foreach ($w in @(Forecast $ck $cm $cc $ctm)) {
      if ($w.StartsWith("W`t")) { $out.Add('WARN  ' + $w.Substring(2)); $nw++ } elseif ($w.StartsWith("I`t")) { $out.Add($w.Substring(2)) }
    }
  }
  # errors first, then warnings, as check-contract.sh prints them in order of the checks
  # -Field: the key's value as read above, its lines joined into one; warnings left out
  if ($Field -and -not $ne) { ((Val $txt[$Field]) -creplace '[ \t]*\r?\n[ \t]*', ' ').Trim(' ', "`t"); continue }
  foreach ($m in $out) { if (-not $Field -or $m.StartsWith('ERROR')) { "${f}: $m" } }
  "${f}: $(if ($ne) { 'FAIL' } else { 'OK' }) ($ne errors, $nw warnings)"
  if ($ne) { $failed = 1 }
}
exit $failed
} finally { if ($enc0) { try { [Console]::OutputEncoding = $enc0 } catch { } } }
