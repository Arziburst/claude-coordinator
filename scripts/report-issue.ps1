# One path for every issue a project files to claude-coordinator (Windows; macOS / Linux: report-issue.sh -
# the same lines and codes; procedures/CORE-FINDINGS.md section 2): a fixed signature, an existing issue
# found before a new one, a repeat marked with a reaction (#338).
#   powershell -File scripts\report-issue.ps1 signature -Source <script or core file> [-Step <step>] [-Exit <code>]
#                    -ErrorText <text>
#   powershell -File scripts\report-issue.ps1 file -Repo <owner/name> -Title <title> -BodyFile <file>
#                    -Signature <sig> [-Keywords <words>] [-Checked <n,n,...>] [-CommentFile <file>] [-Regression]
#                    [-DryRun]
# signature: one line `<source>: <step>: exit <code>: <words>` (a negative code kept as it is) - the error
# text lower-cased (ASCII), URLs and scp-style remotes, dates and times, paths (absolute, with a drive
# letter, UNC, ~ or ./; a quoted one with its spaces), hex ids (0x..., or 7+ characters) and numbers
# replaced by the tokens URL, DATE, PATH, ID and N, quotes dropped, whitespace (CR, LF, tabs)
# collapsed, at most 120 characters (bytes): the same error from two machines gives the same line.
# file, in this order: (1) the exact signature (a `Signature: <sig>` line in the body) on an open issue ->
# a +1 reaction from this account (none added when it is already there), with -CommentFile that comment
# too, `REPEAT #<n>` - an open issue wins over a closed one; (2) only on a closed issue closed as completed
# -> nothing filed, `FIXED UPSTREAM #<n>` (closed as not planned is no fix: it goes on); with -Regression
# (this core already holds that fix) one new issue instead, its body holding `Regression of #<n>`, nothing
# written on #<n>; (3) the keyword search (-Keywords, else the title; title
# and body, open and closed, updated in the last 90 days, at most 5): a candidate not in -Checked ->
# `CHECK #<a> #<b> ...` and each candidate's title, nothing filed - read them, then run again with them in
# -Checked; (4) none left -> the issue filed, its body ending `Checked: #a, #b` (when any) and
# `Signature: <sig>`, `FILED #<n>`. -DryRun prints what it would do and changes nothing. Every gh call is
# read-only but `issue create`, `issue comment` and the reaction.
# Exit codes: 0 a signature, REPEAT, FILED or a dry run of them; 1 usage error or gh failed; 3 FIXED
# UPSTREAM; 4 CHECK. -ErrorText, not -Error: $Error is PowerShell's own.
param([Parameter(Position = 0)][string]$Mode, [string]$Source, [string]$Step, [string]$Exit, [string]$ErrorText,
      [string]$Repo, [string]$Title, [string]$BodyFile, [string]$Signature, [string]$Keywords, [string]$Checked,
      [string]$CommentFile, [switch]$Regression, [switch]$DryRun)
# native output (gh) is read and this script's own output written as UTF-8, whatever the console's code
# page; the caller's console gets its own encoding back on every way out
$enc0 = $null; try { $enc0 = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
try {
$usage = 'usage: signature -Source <s> [-Step <s>] [-Exit <code>] -ErrorText <text> | file -Repo <owner/name> -Title <t> -BodyFile <f> -Signature <sig> [-Keywords <words>] [-Checked <n,n,...>] [-CommentFile <f>] [-Regression] [-DryRun]'
function Usage([string]$m) { [Console]::Error.WriteLine($(if ($m) { "$m; $usage" } else { $usage })); exit 1 }
if ($Mode -cne 'signature' -and $Mode -cne 'file') { Usage '' }

# OneLine <text>: CR, LF and tabs to spaces, runs of spaces to one, trimmed
function OneLine([string]$s) { (($s -creplace "[`r`n`t`f`v]", ' ') -creplace ' +', ' ').Trim(' ') }
function Lower([string]$s) { -join @($s.ToCharArray() | ForEach-Object { if ($_ -ge [char]'A' -and $_ -le [char]'Z') { [char]([int]$_ + 32) } else { $_ } }) }

if ($Mode -ceq 'signature') {
  if (-not $Source -or -not $PSBoundParameters.ContainsKey('ErrorText')) { Usage 'signature needs -Source and -ErrorText' }
  if ($Exit -cnotmatch '^(-?[0-9]+)?$') { Usage '-Exit takes a whole number' }
  # the words: lower-cased, then each kind replaced by its token, quotes dropped; a rule that needs the
  # character after a match runs twice, as in report-issue.sh. A quoted path is one PATH with its spaces
  # (the quotes still there to bound it), then the quotes go; an unquoted Windows or UNC path takes the next
  # words that hold a backslash; an scp-style remote (`git@host:owner/repo`, `user@host:/path`) is one URL
  $w = Lower (OneLine $ErrorText)
  foreach ($r in @(
      @('[a-z][a-z0-9+.-]*://[^ ]*', 'URL'),
      @('(^|[^a-z0-9_.-])[a-z0-9_.-]+@[a-z0-9_.-]+:[^ ]*', '${1}URL'),
      @('[0-9]{4}[-/][0-9]{2}[-/][0-9]{2}([t ][0-9]{2}:[0-9]{2}(:[0-9]{2}([.,][0-9]+)?)?)?(z|[+-][0-9]{2}:?[0-9]{2})?', 'DATE'),
      @('(^|[^a-z0-9])[0-9]{1,2}:[0-9]{2}(:[0-9]{2}([.,][0-9]+)?)?', '${1}DATE'),
      @('"([a-z]:[\\/]|\\\\|~/|\.{1,2}/|/)[^"]*"', 'PATH'),
      @('''([a-z]:[\\/]|\\\\|~/|\.{1,2}/|/)[^'']*''', 'PATH'),
      @('["''`]', ''),
      @('(^|[^a-z0-9_.\\-])[a-z]:[\\/][^ ]*( [^ ]*\\[^ ]*)*', '${1}PATH'),
      @('(^|[^a-z0-9_.\\-])\\\\[^ ]+( [^ ]*\\[^ ]*)*', '${1}PATH'),
      @('(^|[^a-z0-9_.~/\\-])(~|\.{1,2})?/[^ ]+', '${1}PATH'),
      @('(^|[^a-z0-9])0x[0-9a-f]+', '${1}ID'),
      @('(^|[^a-z0-9])[0-9a-f]{7,}([^a-z0-9]|$)', '${1}ID${2}'),
      @('(^|[^a-z0-9])[0-9a-f]{7,}([^a-z0-9]|$)', '${1}ID${2}'),
      @('(^|[^a-z0-9])[0-9]+', '${1}N'))) { $w = $w -creplace $r[0], $r[1] }
  $w = ($w -creplace ' +', ' ').Trim(' ')
  $line = (OneLine $Source) -creplace '\\', '/'
  if ($Step) { $line += ": $(OneLine $Step)" }
  if ($Exit) { $line += ": exit $Exit" }
  if ($w) { $line += ": $w" }
  # at most 120 bytes: a longer line is cut, the non-ASCII bytes (a cut character's leftover) and the
  # spaces at its new end dropped
  $b = [Text.Encoding]::UTF8.GetBytes($line)
  if ($b.Length -gt 120) {
    $n = 120; while ($n -gt 0 -and ($b[$n - 1] -lt 0x20 -or $b[$n - 1] -gt 0x7E)) { $n-- }
    $line = [Text.Encoding]::UTF8.GetString($b, 0, $n).TrimEnd(' ')
  }
  $line
  exit 0
}

# --- file ---
if ($Repo -notmatch '/') { Usage '-Repo takes <owner/name>' }
if (-not $Title) { Usage 'file needs -Title' }
if (-not $BodyFile -or -not (Test-Path -LiteralPath $BodyFile -PathType Leaf)) { Usage "no such body file: $BodyFile" }
if ($CommentFile -and -not (Test-Path -LiteralPath $CommentFile -PathType Leaf)) { Usage "no such comment file: $CommentFile" }
$sig = OneLine $Signature
if (-not $sig) { Usage 'file needs -Signature' }
$nums = @()   # the -Checked numbers, "#" and spaces allowed, in their order, each once
foreach ($n in @($Checked -split '[,#\s]+' | Where-Object { $_ })) {
  if ($n -cnotmatch '^[0-9]+$') { Usage "-Checked takes issue numbers: $Checked" }
  if ($nums -notcontains $n) { $nums += $n }
}
$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) { [Console]::Error.WriteLine('gh: command not found'); exit 1 }
# Windows PowerShell 5.1 (and 7 before 7.3, or 'Legacy' passing) hands a native program an argument's
# double quotes unescaped: gh would get the exact phrase without them. Arg escapes them for gh.exe.
$v = $PSVersionTable.PSVersion
$legacy = $gh.CommandType -eq 'Application' -and ($v.Major -lt 7 -or ($v.Major -eq 7 -and $v.Minor -lt 3) -or
  "$(Get-Variable PSNativeCommandArgumentPassing -ValueOnly -ErrorAction SilentlyContinue)" -eq 'Legacy')
function Arg([string]$s) {
  if (-not $legacy) { return $s }
  if ($s.Contains('"')) { $s = $s -creplace '(\\*)"', '$1$1\"' }
  # an argument with a space is put in quotes: a backslash at its end would escape the closing one
  if ($s -match '\s') { $s = $s -creplace '(\\+)$', '$1$1' }
  $s
}
# Q <gh args>: gh's non-empty output lines; a failed gh stops the run (exit 1)
function Q([string[]]$a) {
  $x = @($a | ForEach-Object { Arg $_ })
  $o = @(& gh @x 2>&1)
  $err = @($o | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
  $out = @($o | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
  if ($LASTEXITCODE -ne 0) { [Console]::Error.WriteLine("gh $($a[0]) $($a[1]) failed: $(($err + $out) -join ' ')"); exit 1 }
  @($out | ForEach-Object { $_ -split "`r?`n" } | Where-Object { $_ -ne '' })
}
# JStr <text>: a JSON string literal
function JStr([string]$s) { '"' + ($s -creplace '\\', '\\' -creplace '"', '\"') + '"' }
$ROW = '[.number, .state, .stateReason, .title] | @tsv'

# (1) and (2): the exact phrase finds the candidates, a body line equal to `Signature: <sig>` decides
$phrase = $sig -creplace '"', ''
$jq = '.[] | select(any((.body // "") | split("\n")[]; rtrimstr("\r") | rtrimstr(" ") == ' + (JStr "Signature: $sig") + ')) | ' + $ROW
$open = $null; $fixed = $null
foreach ($l in @(Q @('issue', 'list', '--repo', $Repo, '--state', 'all', '--search', "`"$phrase`" in:body", '--json', 'number,state,stateReason,title,body', '--limit', '20', '--jq', $jq))) {
  $f = $l -split "`t", 4; if ($f.Count -lt 4) { continue }
  if ($f[1] -ceq 'OPEN' -and -not $open) { $open = $f }
  elseif ($f[1] -ceq 'CLOSED' -and $f[2] -ceq 'COMPLETED' -and -not $fixed) { $fixed = $f }
}

if ($open) {
  $n = $open[0]; $t = $open[3]
  $login = (@(Q @('api', 'user', '--jq', '.login')) -join '').Trim()
  $mine = @(Q @('api', "repos/$Repo/issues/$n/reactions?per_page=100", '--paginate', '--jq', '.[] | [.content, .user.login] | @tsv'))
  $react = -not ($mine -ceq "+1`t$login")
  if ($DryRun) {
    $todo = ''; if ($react) { $todo = 'a +1 reaction' }
    if ($CommentFile) { $todo = $(if ($todo) { "$todo and " } else { '' }) + "the comment from $CommentFile" }
    "REPEAT #${n}: $t (dry run: $(if ($todo) { "would add $todo" } else { 'nothing to add' }))"
    exit 0
  }
  if ($react) { $null = Q @('api', '--method', 'POST', "repos/$Repo/issues/$n/reactions", '-f', 'content=+1') }
  if ($CommentFile) { $null = Q @('issue', 'comment', $n, '--repo', $Repo, '--body-file', $CommentFile) }
  "REPEAT #${n}: $t"
  exit 0
}
$reg = ''
if ($fixed) {
  # -Regression: this core already holds the fix, the bug came back - a new issue naming the old one
  if ($Regression) { $reg = $fixed[0] } else {
    "FIXED UPSTREAM #$($fixed[0]): $($fixed[3])"
    exit 3
  }
}

# (3): the keyword search over the last 90 days; candidates not read yet stop the filing (a regression
# has its issue already: the closed one it names)
if (-not $reg) {
  $since = [DateTime]::UtcNow.AddDays(-90).ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
  $words = (OneLine $(if ($Keywords) { $Keywords } else { $Title })) -creplace '"', ''
  $new = @(); $lines = @()
  foreach ($l in @(Q @('issue', 'list', '--repo', $Repo, '--state', 'all', '--search', "$words in:title,body updated:>=$since", '--json', 'number,state,stateReason,title', '--limit', '5', '--jq', ".[] | $ROW"))) {
    $f = $l -split "`t", 4; if ($f.Count -lt 4) { continue }
    if ($nums -contains $f[0]) { continue }
    $new += "#$($f[0])"; $lines += "#$($f[0]) $($f[1])$(if ($f[2]) { " $($f[2])" }): $($f[3])"
  }
  if ($new.Count) {
    $all = @($nums) + @($new | ForEach-Object { $_.TrimStart('#') })
    "CHECK $($new -join ' ')"
    $lines
    "read each: the same problem -> a +1 reaction there (gh api --method POST repos/$Repo/issues/<n>/reactions -f content=+1), a comment only with something new; none -> run again with -Checked $($all -join ',')"
    exit 4
  }
}

# (4): file it, the body's own Regression, Signature and Checked lines replaced by the script's
$text = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $BodyFile).ProviderPath) -creplace "`r", ''
$kept = [Collections.Generic.List[string]]@($text -split "`n")
if ($kept.Count -and $kept[$kept.Count - 1] -eq '') { $kept.RemoveAt($kept.Count - 1) }
$kept = [Collections.Generic.List[string]]@($kept | Where-Object { $_ -cnotmatch '^(Signature|Checked):|^Regression of #' })
while ($kept.Count -and $kept[$kept.Count - 1] -eq '') { $kept.RemoveAt($kept.Count - 1) }
$body = (-join @($kept | ForEach-Object { "$_`n" })) + "`n"
if ($reg) { $body += "Regression of #$reg`n" }
if ($nums.Count) { $body += "Checked: #$($nums -join ', #')`n" }
$body += "Signature: $sig`n"
if ($DryRun) {
  "WOULD FILE in $Repo (dry run): $Title"
  if ($reg) { "Regression of #$reg" }
  if ($nums.Count) { "Checked: #$($nums -join ', #')" }
  "Signature: $sig"
  exit 0
}
$tmp = [IO.Path]::GetTempFileName()
try {
  [IO.File]::WriteAllText($tmp, $body, (New-Object Text.UTF8Encoding $false))
  $url = (@(Q @('issue', 'create', '--repo', $Repo, '--title', $Title, '--body-file', $tmp)) -join "`n")
} finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
$m = [regex]::Matches($url, '/issues/([0-9]+)')
"FILED #$(if ($m.Count) { $m[$m.Count - 1].Groups[1].Value } else { '?' }): $Title"
exit 0
} finally { if ($enc0) { try { [Console]::OutputEncoding = $enc0 } catch { } } }
