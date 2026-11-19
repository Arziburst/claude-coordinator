# A contract's bounds against the real diff (#381; Windows; macOS / Linux: check-bounds.sh - the rules in its header).
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check-bounds.ps1 <contract> <base>...<head>
# Lines: `<glob> <added>/<max>` per bound, `binary: <path> counts as 0`, `check-bounds: WARN <glob> matches no file` (#586;
# a glob's one pair of surrounding quotes dropped), `check-bounds: OK`, `check-bounds: OVER <glob>
# <added>/<max>`, `check-bounds: no bounds`. Exit 0 OK or no bounds, 1 OVER, 2 usage, unreadable, a malformed bound
# (also a max too large for a long, or a `[` not closed: refused before the diff is read, the line naming the bound), the #615 refusal (touches found nowhere, or another repository's origin; with touches found nowhere an OVER is still reported, exit 1).
$enc0 = $null; try { $enc0 = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
try {
function Stop2([string]$m) { $m; exit 2 }
# the glob matches the path (-clike); each `**/` from $from on: none, or `*/` (one or more folders) (#529)
function GlobMatch([string]$p, [string]$g, [int]$from = 0) { $i = $g.IndexOf('**/', $from, [StringComparison]::Ordinal); if ($i -lt 0) { return ($p -clike $g) }
  $a = $g.Substring(0, $i); $r = $g.Substring($i + 3); (GlobMatch $p ($a + $r) $i) -or (GlobMatch $p ($a + '*/' + $r) ($i + 2)) }
if ($args.Count -ne 2 -or -not "$($args[1])".Contains('...')) { Get-Content -LiteralPath $PSCommandPath -TotalCount 2 | ForEach-Object { [Console]::Error.WriteLine(($_ -creplace '^# ?', '')) }; exit 2 }
$c = "$($args[0])"; $range = "$($args[1])"; $L = $null
try { if (Test-Path -LiteralPath $c -PathType Leaf) { $L = @([IO.File]::ReadAllLines((Resolve-Path -LiteralPath $c).Path)) } } catch { }
if ($null -eq $L) { Stop2 "check-bounds: cannot read $c" }
$s = 0; $e = $L.Count - 1; $b = @()
if ($L.Count -and $L[0] -cmatch '^---[ \t]*$') { $s = 1; for ($i = 1; $i -lt $L.Count; $i++) { if ($L[$i] -cmatch '^---[ \t]*$') { $e = $i - 1; break } } }
else { for ($i = 0; $i -lt $L.Count; $i++) { if ($L[$i] -cmatch '^contract:[ \t]*$') { $s = $i + 1
  for ($j = $s; $j -lt $L.Count; $j++) { if ($L[$j] -cmatch '^[^ \t]') { $e = $j - 1; break } }
  for ($j = $s; $j -le $e; $j++) { $L[$j] = $L[$j].TrimStart(' ', "`t") }; break } } }
$on = $false; $tk = $false; $tch = @(); $repo = ''
# the items of touches (inline or a block list), one with `**/` also without it (#615)
function Tks([string]$v) { (($v -creplace '[ \t]#.*$', '') -creplace '[\[\],"'']', ' ') -creplace '^[ \t]*-[ \t]', ' ' -split '[ \t]+' | Where-Object { $_ } | ForEach-Object { $_; if ($_.Contains('**/')) { $_.Replace('**/', '') } } }
for ($i = $s; $i -le $e; $i++) { $t = $L[$i]
  if ($t -cmatch '^[a-z_]+:') { $tk = $t -cmatch '^touches:(.*)$'; if ($tk) { $tch += @(Tks $Matches[1]) }
    if ($t -cmatch '^repository:(.*)$') { $repo = ($Matches[1] -creplace '[ \t]#.*$', '') -creplace '[ \t"'']', '' } }
  elseif ($tk) { $tch += @(Tks $t) }
  if ($tk) { continue }
  if ($t -cmatch '^[a-z_]+:') { $on = $false; if ($t -cmatch '^bounds:[ \t]*(.*)$') { $on = $true; if ($Matches[1] -cnotmatch '^(#.*)?$') { Stop2 "check-bounds: a malformed bound (- <glob> <max added lines>): $t" } }; continue }
  if (-not $on -or $t -cmatch '^[ \t]*(#.*)?$') { continue }
  if ($t -cnotmatch '^[ \t]*-[ \t]+([^ \t]+)[ \t]+([0-9]+)([ \t]+#.*)?[ \t]*$') { Stop2 "check-bounds: a malformed bound (- <glob> <max added lines>): $t" }
  $mx = [long]0; if (-not [long]::TryParse($Matches[2], [ref]$mx) -or ($Matches[1] -creplace '\[[^\]]+\]', '').Contains('[')) { Stop2 "check-bounds: a malformed bound (- <glob> <max added lines>): $t" }
  $gl = $Matches[1]; if ($gl.Length -gt 2 -and ($gl[0] -ceq '"' -or $gl[0] -ceq "'") -and $gl[-1] -ceq $gl[0]) { $gl = $gl.Substring(1, $gl.Length - 2) }   # #586
  $b += , @($gl, $Matches[2]) }
if (-not $b.Count) { 'check-bounds: no bounds'; exit 0 }
$nums = @(& { $ErrorActionPreference = 'Continue'; & git -c core.quotePath=false diff --numstat --no-renames $range 2>&1 } | ForEach-Object { "$_" })
if ($LASTEXITCODE -ne 0) { $top = @(& { $ErrorActionPreference = 'Continue'; & git rev-parse --show-toplevel 2>$null } | ForEach-Object { "$_" }); $top = if ($LASTEXITCODE -eq 0 -and $top.Count) { $top[0] } else { '(none)' }; Stop2 "check-bounds: cannot read $range in the repository ${top}: $($nums | Select-Object -First 1); run it from the project's root" }
# #615: a folder that is not the contract's repository counts 0 for every bound, so it is refused, never OK
function GitOut { $a = $args; $o = @(& { $ErrorActionPreference = 'Continue'; & git @a 2>$null } | ForEach-Object { "$_" }); if ($LASTEXITCODE -eq 0) { $o } }
$top = "$(GitOut rev-parse --show-toplevel | Select-Object -First 1)"
if ($repo) { $o = "$(GitOut remote get-url origin | Select-Object -First 1)"; $u = $o.TrimEnd('/') -replace '\.git$', ''
  if (-not ("/$u").EndsWith('/' + ($repo -replace '\.git$', ''), [StringComparison]::OrdinalIgnoreCase) -and -not $u.EndsWith(':' + ($repo -replace '\.git$', ''), [StringComparison]::OrdinalIgnoreCase)) {
    Stop2 "check-bounds: the origin of the repository $top ($(if ($o) { $o } else { 'none' })) is not the contract's repository ${repo}: run it inside that repository" } }
$wrong = ''; if ($tch.Count -and -not (@(GitOut -C $top ls-files '--' @tch).Count + @(GitOut -C $top diff --name-only --no-renames $range '--' @tch).Count)) {
  $wrong = "check-bounds: none of the contract's touches ($($tch -join ' ')) is in the repository $top or in ${range}: run it inside the contract's repository" }
$over = @(); $hd = $range.Substring($range.IndexOf('...') + 3); if (-not $hd) { $hd = 'HEAD' }; $trk = $null
$outl = @(foreach ($x in $b) { $g = $x[0]; $a = [long]0; $hit = $false
  foreach ($n in $nums) { $f = $n -split "`t", 3; if ($f.Count -lt 3 -or -not (GlobMatch ($f[2]) $g)) { continue }
    $hit = $true
    if ($f[0] -ceq '-') { "binary: $($f[2]) counts as 0" } else { $a += [long]$f[0] } }
  # #586: a glob matching no path of the diff nor a file tracked at the head (an empty head: HEAD) is named
  if (-not $hit) { if ($null -eq $trk) { $trk = @(GitOut -c core.quotePath=false ls-tree -r --full-tree --name-only $hd) }
    foreach ($p in $trk) { if ($p -and (GlobMatch $p $g)) { $hit = $true; break } }
    if (-not $hit) { "check-bounds: WARN $g matches no file" } }
  "$g $a/$($x[1])"; if ($a -gt [long]$x[1]) { $over += "check-bounds: OVER $g $a/$($x[1])" } })
if ($wrong -and -not $over.Count) { Stop2 $wrong }; $outl   # the OK of a wrong folder is refused; an OVER is still said
if ($over.Count) { $over; exit 1 }
'check-bounds: OK'
} catch { "check-bounds: $_"; exit 2 } finally { if ($enc0) { try { [Console]::OutputEncoding = $enc0 } catch { } } }
