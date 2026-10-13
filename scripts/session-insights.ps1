# Where a Claude Code session lost money, time, quality or stability (Windows; macOS / Linux: session-insights.sh -
# the same lines, see its top comment for each). The input of the weekly retro (CORE section 7a); reads only, sends nothing.
#   powershell -File scripts/session-insights.ps1 <session-id | id prefix | a subagent's agentId | transcript.jsonl> [-Detail]   (or: pwsh -File ...)
#   powershell -File scripts/session-insights.ps1 -Since 2026-10-05T17:00:00Z [-Detail]   every transcript from then on (UTC; or Unix seconds)
#     [-Until <UTC time>] [-SkipTests] [-Project <folder>]   the retro's filters: records before -Until only; no probe or
#     self-test sessions; only sessions whose first cwd is the folder or inside it (the rules: session-insights.sh's top comment)
# Tab-separated lines, no header, nothing for a session without messages: "block <reason> count= changed= retried= around= stopped="
# per safety-guard reason and "deny rule", "refusal <source>" the same for other refusals (what the next tool call did);
# "tool_error <tool> count= repeated= exit_only=" (exit_only: errors that are only "Exit code <n>", left out of count);
# "waiting minutes= calls=" (calls over 2 minutes that waited on a person: a permission the user decided, an *AskUserQuestion);
# "cache write= read= rewrites=" (a message writing over half its input to the cache, a transcript's first aside);
# "reread files= reads=" (files the Read tool read 3+ times in one transcript; -Detail adds "reread_file <path> reads=",
# file names for this machine only); "turns assistant= tool_calls=". One session is its transcript and its subagents'.
# Exit 1 when no transcript is found or a prefix is ambiguous, 2 on a usage error. Reads the JSON as text, as the .sh.
param([string]$Session, [string]$Since, [switch]$Detail, [string]$Until, [switch]$SkipTests, [string]$Project)
# this script's output is written as UTF-8, whatever the console's code page; the caller's console gets its own
# encoding back on every way out (the body runs inside try, the encoding is restored in finally)
$enc0 = $null; try { $enc0 = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
try {
if ((-not $Session -and -not $Since) -or ($Session -and $Since) -or (-not $Since -and ($Until -or $SkipTests -or $Project))) {
  Get-Content -LiteralPath $PSCommandPath -TotalCount 14 | ForEach-Object { $_ -replace '^# ?', '' }; exit 2
}
$ErrorActionPreference = 'Stop'
$cfg = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }   # Claude Code's override
$projects = Join-Path $cfg 'projects'
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture
# a -Since / -Until value as YYYY-MM-DDTHH:MM:SS in UTC, or the usage error
function Utc([string]$name, [string]$v) {
  $bad = "$name needs YYYY-MM-DDTHH:MM:SS in UTC (Z or nothing after it) or Unix seconds, got $v"
  if ($v -cmatch '^[0-9]+\z') {
    # Unix seconds (the status line's resets_at)
    if ($v.Length -gt 10) { [Console]::Error.WriteLine($bad); exit 2 }
    return [DateTimeOffset]::FromUnixTimeSeconds([long]$v).UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ss')
  } elseif ($v -cmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]+)?Z?\z') {   # no other offset
    return $v.Substring(0, 19)
  }
  [Console]::Error.WriteLine($bad); exit 2
}
$cut = ''; $upto = ''
if ($Since) { $cut = Utc '-Since' $Since }
if ($Until) { $upto = Utc '-Until' $Until }

$ORD = [StringComparison]::Ordinal
$reTime = [regex]'"timestamp":[ \t]*"([^"]*)"'
# the record's own timestamp, outside "message" (as session-tokens): the first on the line when it comes before
# "message", else the last; $null when the line has none
function RecTime([string]$line) {
  $i = $line.IndexOf('"timestamp":', $ORD); if ($i -lt 0) { return $null }
  $p = $line.IndexOf('"message":', $ORD)
  if ($p -ge 0) {
    $fi = -1; $fv = $null; $e = if ($line.Length -gt $i + 12 -and $line[$i + 12] -eq '"') { $line.IndexOf('"', $i + 13) } else { -1 }
    if ($e -ge 0) { $fi = $i; $fv = $line.Substring($i + 13, $e - $i - 13) }
    else { $f = $reTime.Match($line); if ($f.Success) { $fi = $f.Index; $fv = $f.Groups[1].Value } }
    if ($fi -ge 0 -and $fi -lt $p) { return $fv }
  }
  $a = $line.LastIndexOf('"timestamp":"', $ORD); $e = if ($a -ge 0) { $line.IndexOf('"', $a + 13) } else { -1 }
  if ($a -ge 0 -and $e -ge 0 -and $line.LastIndexOf('"timestamp":', $ORD) -eq $a) { return $line.Substring($a + 13, $e - $a - 13) }
  $all = $reTime.Matches($line); if ($all.Count) { return $all[$all.Count - 1].Groups[1].Value }
  $null
}
function Days([long]$y, [long]$m, [long]$d) {
  if ($m -le 2) { $y-- }
  $e = [Math]::Floor($y / 400); $yoe = $y - $e * 400
  $mp = if ($m -gt 2) { $m - 3 } else { $m + 9 }
  [long]($e * 146097 + $yoe * 365 + [Math]::Floor($yoe / 4) - [Math]::Floor($yoe / 100) + [Math]::Floor((153 * $mp + 2) / 5) + $d - 1 - 719468)
}
# milliseconds since 1970 of a timestamp read as UTC, -1 when it is none
$reStamp = [regex]'^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(?:[.]([0-9]+))?'
function Tms([string]$ts) {
  if (-not $ts) { return [long]-1 }
  $m = $reStamp.Match($ts); if (-not $m.Success) { return [long]-1 }
  $n = $m.Groups
  ((((Days $n[1].Value $n[2].Value $n[3].Value) * 24 + [long]$n[4].Value) * 60 + [long]$n[5].Value) * 60 + [long]$n[6].Value) * 1000 + [long](($n[7].Value + '000').Substring(0, 3))
}
$QB = [char[]]@('"', '\')
$BR = [char[]]@('{', '}', '"')
# $s[$p] is '"': the index of the string's closing quote, -1 when it is unterminated
function StrEnd([string]$s, [int]$p) {
  $j = $p + 1
  while ($j -lt $s.Length) {
    $k = $s.IndexOfAny($QB, $j); if ($k -lt 0) { return -1 }
    if ($s[$k] -eq '"') { return $k }
    $j = $k + 2
  }
  -1
}
# $s[$p] is '"': the string's body as written (escapes kept); unterminated: the rest
function JBody([string]$s, [int]$p) { $e = StrEnd $s $p; if ($e -ge 0) { $s.Substring($p + 1, $e - $p - 1) } else { $s.Substring($p + 1) } }
# the escapes \\ \" \/ \n \r \t read; any other (\u...) kept as written
$reEsc = [regex]'(?s)\\(.)'
$unEsc = [Text.RegularExpressions.MatchEvaluator] { param($m)
  switch -CaseSensitive ($m.Groups[1].Value) { 'n' { "`n" } 'r' { "`r" } 't' { "`t" } '\' { '\' } '"' { '"' } '/' { '/' } default { $m.Value } } }
function Unesc([string]$s) { if ($s.IndexOf('\') -lt 0) { return $s }; $reEsc.Replace($s, $unEsc) }
# lower case for ASCII letters only (as awk under LC_ALL=C), \ read as /
$reUpper = [regex]'[A-Z]+'
$lower = [Text.RegularExpressions.MatchEvaluator] { param($m) $m.Value.ToLowerInvariant() }
function Lower([string]$s) { $reUpper.Replace($s, $lower) }
function Norm([string]$s) { (Lower $s).Replace('\', '/') }
# $s[$p] is '{': the index of its closing '}', -1 when there is none
function ObjEnd([string]$s, [int]$p) {
  $d = 0
  while ($true) {
    $p = $s.IndexOfAny($BR, $p); if ($p -lt 0) { return -1 }
    $c = $s[$p]
    if ($c -eq '"') { $e = StrEnd $s $p; if ($e -lt 0) { return -1 }; $p = $e + 1; continue }
    if ($c -eq '{') { $d++ } else { $d--; if ($d -eq 0) { return $p } }
    $p++
  }
}
# $t in $x as a whole word: no letter, digit or _ . - right before or after it
$reWordChar = [regex]'^[a-z0-9_.-]$'
function HasWord([string]$x, [string]$t) {
  $p = 0
  while ($true) {
    $i = $x.IndexOf($t, $p, $ORD); if ($i -lt 0) { return $false }
    $b = if ($i -gt 0) { [string]$x[$i - 1] } else { '' }
    $a = if ($i + $t.Length -lt $x.Length) { [string]$x[$i + $t.Length] } else { '' }
    if (-not $reWordChar.IsMatch($b) -and -not $reWordChar.IsMatch($a)) { return $true }
    $p = $i + 1
  }
}
# what a blocked call names: its file_path; in its command main, master and the words with a / and 2 letters or
# digits (not /dev/...); the branch of "push while on <b>"
$reSep = [regex]"[ \t\n\r;&|()<>'""``,=]+"
$reAlnum = [regex]'[a-z0-9]'
$reSlashEnd = [regex]'/+\z'
function Targets($c, $f, [string]$reason) {
  $o = New-Object 'System.Collections.Generic.List[string]'
  if ($null -ne $f) { $w = $reSlashEnd.Replace((Norm (Unesc $f)), ''); if ($w) { $o.Add($w) } }
  if ($null -ne $c) {
    foreach ($w in $reSep.Split((Norm (Unesc $c)))) {
      if (-not $w) { continue }
      if ($w -ceq 'main' -or $w -ceq 'master') { $o.Add($w) }
      elseif ($w.Contains('/') -and -not $w.StartsWith('-', $ORD)) {
        $w = $reSlashEnd.Replace($w, '')
        if ($reAlnum.Matches($w).Count -ge 2 -and -not $w.StartsWith('/dev/', $ORD)) { $o.Add($w) }
      }
    }
  }
  if ($reason.StartsWith('push while on ', $ORD)) { $o.Add((Lower $reason.Substring(14))) }
  , $o.ToArray()
}
# the guard's reason from the text after the marker
$reTrail = [regex]'[. ]+\z'
function Why([string]$s) {
  $s = Unesc $s
  $i = $s.IndexOf('. If this is a false positive', $ORD); if ($i -ge 0) { $s = $s.Substring(0, $i) }
  $i = $s.IndexOf("`n", $ORD); if ($i -ge 0) { $s = $s.Substring(0, $i) }
  $i = $s.IndexOf("`r", $ORD); if ($i -ge 0) { $s = $s.Substring(0, $i) }
  $o = ''
  while ($true) {
    $i = $s.IndexOf('(', $ORD); if ($i -lt 0) { break }
    $j = $s.IndexOf(')', $i, $ORD); if ($j -lt 0) { break }
    $pin = $s.Substring($i + 1, $j - $i - 1)
    $o += $s.Substring(0, $i) + $(if ($pin.Contains('/') -or $pin.Contains('\')) { '(<path>)' } else { "($pin)" })
    $s = $s.Substring($j + 1)
  }
  $s = $reTrail.Replace(($o + $s).Replace("`t", ' '), '')
  if ($s) { $s } else { '?' }
}
function NewMap { New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal) }

$reAssistant = [regex]'"type":[ \t]*"assistant"'
$reResultT = [regex]'"type":[ \t]*"tool_result"'
$reMsgId = [regex]'"id":[ \t]*"(msg_[^"]*)"'
$reModel = [regex]'"model":[ \t]*"([^"]*)"'
$reUsage = [regex]'"usage":[ \t]*[{]'
$reUse = [regex]'"type":[ \t]*"tool_use",[ \t]*"id":[ \t]*"([^"]*)",[ \t]*"name":[ \t]*"([^"]*)"'
$reInput = [regex]'\G,[ \t]*"input":[ \t]*[{]'
$reCommand = [regex]'"command":[ \t]*"'
$reFilePath = [regex]'"file_path":[ \t]*"'
$reEndTurn = [regex]'"stop_reason":[ \t]*"end_turn"'
$reUseId = [regex]'"tool_use_id":[ \t]*"([^"]*)"'
$reIsError = [regex]'"is_error":[ \t]*true'
$reByUser = [regex]'"permissionDecision":[ \t]*[{][^}]*"source":[ \t]*"user'
$reReject = [regex]'"permissionDecision":[ \t]*[{][^}]*"decision":[ \t]*"reject"'
$reByUserNo = [regex]'"permissionDecision":[ \t]*[{][^}]*"decision":[ \t]*"reject"[^}]*"source":[ \t]*"user'
$reClassifier = [regex]'"permissionDecision":[ \t]*[{][^}]*"decision":[ \t]*"reject"[^}]*"reasonType":[ \t]*"classifier"'
$reSafety = [regex]'"permissionDecision":[ \t]*[{][^}]*"decision":[ \t]*"reject"[^}]*"reasonType":[ \t]*"safetyCheck"'
# the hook a hook error names: the last word of its command holding a / \ or . (the script), else its first
# word, without folders; "hook" when the command is not shown
$reWs = [regex]'[ \t\n]+'
function HookName([string]$b) {
  $i = $b.IndexOf('hook error: [', $ORD); if ($i -lt 0) { return 'hook' }
  $s = $b.Substring($i + 13); $i = $s.IndexOf(']: ', $ORD); if ($i -lt 0) { return 'hook' }
  $s = $s.Substring(0, $i).Replace('"', '').Replace("'", '')
  $words = @($reWs.Split($s) | Where-Object { $_ }); $w = ''
  for ($k = $words.Count - 1; $k -ge 0; $k--) { if ($words[$k].IndexOfAny([char[]]@('/', '\', '.')) -ge 0) { $w = $words[$k]; break } }
  if (-not $w -and $words.Count) { $w = $words[0] }
  $w = $w.Replace('\', '/'); $i = $w.LastIndexOf('/'); if ($i -ge 0) { $w = $w.Substring($i + 1) }
  $w = $w -replace "[`t`n`r]", ' '
  if ($w) { "hook $w" } else { 'hook' }
}
$reContent = [regex]'"content":[ \t]*'
$reText = [regex]'"text":[ \t]*"'
$MK = 'Blocked by safety-guard: '
function Num([string]$u, [string]$k) { $g = [regex]::Match($u, '"' + $k + '":[ \t]*([0-9]+)'); if ($g.Success) { [long]$g.Groups[1].Value } else { [long]0 } }

# the state over every file read
$seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$used = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$first = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$rep = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$usage = NewMap; $calls = NewMap; $BC = NewMap; $TE = NewMap; $TR = NewMap; $TX = NewMap
$ErrTools = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
function Get0($map, [string]$k) { if ($map.ContainsKey($k)) { $map[$k] } else { 0 } }
$S = @{ na = 0; nc = 0; wt = [long]0; wn = 0; rf = 0; rr = 0 }
$detailLines = New-Object 'System.Collections.Generic.List[string]'
function Add($map, [string]$k, $n) { if ($map.ContainsKey($k)) { $map[$k] += $n } else { $map[$k] = $n } }
function Counts([string]$reason) { if (-not $BC.ContainsKey($reason)) { $BC[$reason] = @{ n = 0; changed = 0; retried = 0; around = 0; stopped = 0 } }; $BC[$reason] }

function Insights([string[]]$Files) {
  foreach ($file in $Files) {
    # per transcript: the open blocks, the last error per tool, the reads, its first message
    $pend = New-Object 'System.Collections.Generic.List[object]'
    $perr = NewMap; $RD = NewMap; $first1 = $false
    foreach ($line in [IO.File]::ReadLines($file)) {
      if (-not $line) { continue }
      if (-not $line.Contains('"tool_result"') -and -not $line.Contains('"assistant"')) { continue }
      $isR = $reResultT.IsMatch($line)
      if (-not $isR -and -not $reAssistant.IsMatch($line)) { continue }
      $ts = RecTime $line
      if ($cut) {
        if (-not $ts) { continue }
        $t19 = if ($ts.Length -gt 19) { $ts.Substring(0, 19) } else { $ts }
        if ([string]::CompareOrdinal($t19, $cut) -lt 0) { continue }
        if ($upto -and [string]::CompareOrdinal($t19, $upto) -ge 0) { continue }
      }
      $ms = Tms $ts
      if ($isR) {
        $g = $reUseId.Match($line); if (-not $g.Success) { continue }
        $st = $g.Index; $id = $g.Groups[1].Value
        if (-not $calls.ContainsKey($id)) { continue }
        $call = $calls[$id]; $nm = $call.N
        if ($ms -ge 0 -and $call.T -ge 0 -and $ms - $call.T -gt 120000 -and ($nm.EndsWith('AskUserQuestion', $ORD) -or $reByUser.IsMatch($line))) { $S.wt += $ms - $call.T; $S.wn++ }
        if ($reIsError.IsMatch($line)) {
          $g = $reResultT.Match($line); if ($g.Success -and $g.Index -lt $st) { $st = $g.Index }
          $body = ''; $r = $line.Substring($st)
          $g = $reContent.Match($r)
          if ($g.Success) {
            $r = $r.Substring($g.Index + $g.Length)
            if ($r.StartsWith('[', $ORD)) { $g = $reText.Match($r); $r = if ($g.Success) { $r.Substring($g.Index + $g.Length - 1) } else { '' } }
            if ($r.StartsWith('"', $ORD)) { $body = JBody $r 0 }
          }
          $k = -1
          if ($body.StartsWith('PreToolUse:', $ORD)) { $k = $body.IndexOf($MK, $ORD) } elseif ($body.StartsWith($MK, $ORD)) { $k = 0 }
          # a block or a refusal: counted under its kind and reason, open until the transcript's next call
          $kind = 'block'; $reason = $null
          if ($k -ge 0) { $reason = Why $body.Substring($k + $MK.Length) }
          elseif ($body.StartsWith('Permission to use ', $ORD) -and $body.Contains(' has been denied')) { $reason = 'deny rule' }
          else {
            $kind = 'refusal'
            if ($body.StartsWith('PreToolUse:', $ORD)) { $reason = HookName (Unesc $body) }
            elseif ($body.StartsWith("The user doesn't want to proceed", $ORD) -or $reByUserNo.IsMatch($line)) { $reason = 'user' }
            elseif ($body.StartsWith('Permission for this action was denied by the Claude Code auto mode classifier', $ORD) -or $reClassifier.IsMatch($line)) { $reason = 'classifier' }
            elseif ($body.StartsWith('Permission for this command was denied by a built-in', $ORD) -or $reSafety.IsMatch($line)) { $reason = 'safety check' }
            elseif ($body.StartsWith('[Request interrupted', $ORD)) { $kind = '' }
            elseif ($body.StartsWith('Permission ', $ORD) -or $reReject.IsMatch($line)) { $reason = 'other' }
          }
          if ($null -ne $reason) {
            (Counts ($kind + "`t" + $reason)).n++
            $key = if ($null -ne $call.C) { $call.C } elseif ($null -ne $call.F) { $call.F } else { $call.I }
            $pend.Add(@{ R = ($kind + "`t" + $reason); N = $nm; K = $key; T = (Targets $call.C $call.F $reason) })
          } elseif ($kind) {
            [void]$ErrTools.Add($nm)
            if ((Unesc $body).TrimEnd(' ', "`t", "`r", "`n") -cmatch '^Exit code -?[0-9]+\z') { Add $TX $nm 1 }   # nothing but the exit code: no failure shown
            else {
              Add $TE $nm 1; if ($rep.Contains($id)) { Add $TR $nm 1 }
              $perr[$nm] = if ($null -ne $call.C) { $call.C } else { $call.I }
            }
          }
        }
        [void]$calls.Remove($id); [void]$rep.Remove($id)
        continue
      }
      # an assistant record: its message once, its usage the largest output's
      $g = $reMsgId.Match($line)
      if ($g.Success) {
        $id = $g.Groups[1].Value
        $m = $reModel.Match($line)
        if (-not ($m.Success -and $m.Groups[1].Value -ceq '<synthetic>')) {
          if ($seen.Add($id)) { $S.na++ }
          $all = $reUsage.Matches($line)
          if ($all.Count) {
            # the message usage is the last on the line (a tool input may hold another)
            $u = $line.Substring($all[$all.Count - 1].Index)
            $o = Num $u 'output_tokens'
            if (-not $usage.ContainsKey($id) -or $o -gt $usage[$id].o) {
              $usage[$id] = @{ o = $o; i = (Num $u 'input_tokens'); r = (Num $u 'cache_read_input_tokens'); w = (Num $u 'cache_creation_input_tokens') }
            }
            if (-not $first1) { $first1 = $true; [void]$first.Add($id) }
          }
        }
      }
      if ($line.Contains('"tool_use"')) {
        foreach ($u in $reUse.Matches($line)) {
          $tid = $u.Groups[1].Value; $nm = $u.Groups[2].Value
          if (-not $used.Add($tid)) { continue }
          $S.nc++
          $inp = ''
          $g = $reInput.Match($line, $u.Index + $u.Length)
          if ($g.Success) { $p = $g.Index + $g.Length - 1; $e = ObjEnd $line $p; $inp = if ($e -ge 0) { $line.Substring($p, $e - $p + 1) } else { $line.Substring($p) } }
          $c = $null; $f = $null
          $g = $reCommand.Match($inp); if ($g.Success) { $c = JBody $inp ($g.Index + $g.Length - 1) }
          $g = $reFilePath.Match($inp); if ($g.Success) { $f = JBody $inp ($g.Index + $g.Length - 1) }
          $calls[$tid] = @{ N = $nm; T = $ms; C = $c; F = $f; I = $inp }
          # the open blocks of this transcript: what this call does after them
          if ($pend.Count) {
            $key = if ($null -ne $c) { $c } elseif ($null -ne $f) { $f } else { $inp }
            $x = Norm (Unesc $key)
            foreach ($b in $pend) {
              if ($nm -ceq $b.N -and $key -ceq $b.K) { $kind = 'retried' }
              else { $kind = 'changed'; foreach ($t in $b.T) { if ($t -and (HasWord $x $t)) { $kind = 'around'; break } } }
              (Counts $b.R)[$kind]++
            }
            $pend.Clear()
          }
          # the tool's next call after an error: the same command (else input) again?
          if ($perr.ContainsKey($nm)) { $ek = if ($null -ne $c) { $c } else { $inp }; if ($perr[$nm] -ceq $ek) { [void]$rep.Add($tid) }; [void]$perr.Remove($nm) }
          if ($nm -ceq 'Read' -and $null -ne $f) { Add $RD (Unesc $f) 1 }
        }
      }
      if ($reEndTurn.IsMatch($line)) { foreach ($b in $pend) { (Counts $b.R).stopped++ }; $pend.Clear() }
    }
    # the transcript ends: open blocks stopped, its rereads counted
    foreach ($b in $pend) { (Counts $b.R).stopped++ }
    foreach ($k in $RD.Keys) {
      if ($RD[$k] -ge 3) { $S.rf++; $S.rr += $RD[$k]; if ($Detail) { $detailLines.Add("reread_file`t" + ($k -replace "[`t`n`r]", ' ') + "`treads=" + $RD[$k]) } }
    }
  }
  if (-not $S.na -and -not $S.nc) { return }
  $lines = [string[]]@(foreach ($r in $BC.Keys) { $b = $BC[$r]; "{0}`tcount={1} changed={2} retried={3} around={4} stopped={5}" -f $r, $b.n, $b.changed, $b.retried, $b.around, $b.stopped })
  [Array]::Sort($lines, [StringComparer]::Ordinal); $lines
  $lines = [string[]]@(foreach ($t in $ErrTools) { "tool_error`t{0}`tcount={1} repeated={2} exit_only={3}" -f $t, (Get0 $TE $t), (Get0 $TR $t), (Get0 $TX $t) })
  [Array]::Sort($lines, [StringComparer]::Ordinal); $lines
  "waiting`tminutes={0} calls={1}" -f [long][Math]::Floor(($S.wt + 30000) / 60000), $S.wn
  $W = [long]0; $R = [long]0; $rw = 0
  foreach ($id in $usage.Keys) { $v = $usage[$id]; $W += $v.w; $R += $v.r; if (-not $first.Contains($id) -and $v.w * 2 -gt $v.i + $v.w + $v.r) { $rw++ } }
  "cache`twrite={0} read={1} rewrites={2}" -f $W, $R, $rw
  "reread`tfiles={0} reads={1}" -f $S.rf, $S.rr
  $lines = $detailLines.ToArray(); [Array]::Sort($lines, [StringComparer]::Ordinal); $lines
  "turns`tassistant={0} tool_calls={1}" -f $S.na, $S.nc
}

# -SkipTests / -Project: of the files (in order, $keys their paths under projects/ with /), those of the sessions
# kept. Per file its first cwd and its last name (customTitle / agentName); a subagent's file is judged by its
# parent's transcript when that is listed (its own cwd also counts for the sandbox) - as the .sh's pick
$reCwd = [regex]'"cwd":"([^"]*)"'
$reName = [regex]'"(?:customTitle|agentName)":"([^"]*)"'
$reSlashes = [regex]'/+'
$reDrive = [regex]'^([a-z]):/'
$reWordC = [regex]'^[a-z0-9_-]$'
$reSt = [regex]'^#st[0-9]'
$reSandbox = [regex]'/coordinator-selftest(/|\z)'
$reSubFile = [regex]'/subagents/[^/]*\.jsonl\z'
# a path compared: \ read as /, repeated / as one, lower case, C:/x as /c/x, no trailing /
function PNorm([string]$p) {
  $p = $reDrive.Replace((Lower $reSlashes.Replace($p.Replace('\', '/'), '/')), '/$1/')
  if ($p.EndsWith('/', $ORD)) { $p = $p.Substring(0, $p.Length - 1) }
  $p
}
# $w in $s as a whole word: no letter, digit, _ or - right before or after it
function PWord([string]$s, [string]$w) {
  $p = 0
  while ($true) {
    $i = $s.IndexOf($w, $p, $ORD); if ($i -lt 0) { return $false }
    $b = if ($i -gt 0) { [string]$s[$i - 1] } else { '' }
    $a = if ($i + $w.Length -lt $s.Length) { [string]$s[$i + $w.Length] } else { '' }
    if (-not $reWordC.IsMatch($b) -and -not $reWordC.IsMatch($a)) { return $true }
    $p = $i + 1
  }
}
# a probe or self-test session by its name: probe, selftest or self-test as a word before the first colon, or a
# task #st<n>; the title after the colon never counts (a task about a self-test is work)
function Tested([string]$n) {
  $v = Lower $n; $i = $v.IndexOf(':')
  $h = if ($i -ge 0) { $v.Substring(0, $i) } else { $v }
  $reSt.IsMatch($v) -or (PWord $h 'probe') -or (PWord $h 'selftest') -or (PWord $h 'self-test')
}
function Pick([string[]]$files, [string[]]$keys) {
  $R = if ($Project) { PNorm $Project } else { $null }
  $cwd = NewMap; $nm = NewMap; $listed = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
  for ($k = 0; $k -lt $files.Count; $k++) {
    [void]$listed.Add($keys[$k]); $c = $null; $n = $null
    foreach ($line in [IO.File]::ReadLines($files[$k])) {
      if ($null -eq $c -and $line.Contains('"cwd":"')) { $m = $reCwd.Match($line); if ($m.Success) { $c = $m.Groups[1].Value } }
      if ($line.Contains('Title":"') -or $line.Contains('"agentName":"')) { $all = $reName.Matches($line); if ($all.Count) { $n = $all[$all.Count - 1].Groups[1].Value } }
    }
    if ($null -ne $c) { $cwd[$keys[$k]] = $c }
    if ($null -ne $n) { $nm[$keys[$k]] = $n }
  }
  $kept = New-Object 'System.Collections.Generic.List[string]'
  for ($k = 0; $k -lt $files.Count; $k++) {
    $p = $keys[$k]; $q = $p
    $m = $reSubFile.Match($p); if ($m.Success -and $listed.Contains($p.Substring(0, $m.Index) + '.jsonl')) { $q = $p.Substring(0, $m.Index) + '.jsonl' }
    $cq = if ($cwd.ContainsKey($q)) { $cwd[$q] } else { '' }; $cp = if ($cwd.ContainsKey($p)) { $cwd[$p] } else { '' }
    $nq = if ($nm.ContainsKey($q)) { $nm[$q] } else { '' }
    if ($SkipTests -and ((Tested $nq) -or $reSandbox.IsMatch((PNorm $cq)) -or $reSandbox.IsMatch((PNorm $cp)))) { continue }
    if ($null -ne $R) {
      $c = if ($cq) { $cq } else { $cp }
      if (-not $c) { continue }
      $c = PNorm $c
      if (-not ($c -ceq $R -or $c.StartsWith($R + '/', $ORD))) { continue }
    }
    $kept.Add($files[$k])
  }
  , $kept.ToArray()
}

if ($Since) {
  if (-not (Test-Path -LiteralPath $projects)) { [Console]::Error.WriteLine("no transcripts in $projects"); exit 1 }
  # in the order of their paths with / (as the .sh sorts them)
  $root = (Get-Item -LiteralPath $projects).FullName
  $files = [string[]]@(Get-ChildItem -LiteralPath $projects -Filter '*.jsonl' -Recurse -File | ForEach-Object { $_.FullName })
  $keys = [string[]]@($files | ForEach-Object { $_.Substring($root.Length).Replace('\', '/') })
  [Array]::Sort($keys, $files, [StringComparer]::Ordinal)
  if ($SkipTests -or $Project) { $files = Pick $files $keys }
  Insights $files
  exit 0
}
$main = $null
if (Test-Path -LiteralPath $Session -PathType Leaf) { $main = $Session } elseif (Test-Path -LiteralPath $projects) {
  # the full id, else a unique prefix (claude --bg and claude agents print 8 characters)
  $main = Get-ChildItem -LiteralPath $projects -Filter "$Session.jsonl" -Recurse -Depth 1 -File |
    Select-Object -First 1 -ExpandProperty FullName
  if (-not $main) {
    $found = @(Get-ChildItem -LiteralPath $projects -Filter "$Session*.jsonl" -Recurse -Depth 1 -File | ForEach-Object { $_.FullName })
    if ($found.Count -gt 1) {
      # ids only: the folder names would show other projects
      $ids = [string[]]@($found | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) }); [Array]::Sort($ids, [StringComparer]::Ordinal)
      [Console]::Error.WriteLine("ambiguous id ${Session}:"); foreach ($x in $ids) { [Console]::Error.WriteLine($x) }; exit 1
    }
    if ($found.Count -eq 1) { $main = $found[0] }
  }
  if (-not $main) {
    # a subagent's agentId (the Agent tool's result): its transcript sits in its parent's subagents/ folder
    $found = @(Get-ChildItem -LiteralPath $projects -Filter "agent-$Session*.jsonl" -Recurse -Depth 3 -File |
      Where-Object { $_.Directory.Name -eq 'subagents' -and $_.Directory.Parent.Parent.Parent.FullName -eq (Get-Item -LiteralPath $projects).FullName } |
      ForEach-Object { $_.FullName })
    if ($found.Count -gt 1) {
      $ids = [string[]]@($found | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) -replace '^agent-', '' }); [Array]::Sort($ids, [StringComparer]::Ordinal)
      [Console]::Error.WriteLine("ambiguous id ${Session}:"); foreach ($x in $ids) { [Console]::Error.WriteLine($x) }; exit 1
    }
    if ($found.Count -eq 1) { $main = $found[0] }
  }
}
if (-not $main) { [Console]::Error.WriteLine("no transcript for $Session"); exit 1 }
# the transcript first, then its subagents' in the order of their names
$main = (Get-Item -LiteralPath $main).FullName
$files = @($main)
$sub = Join-Path ($main -replace '\.jsonl$', '') 'subagents'
if (Test-Path -LiteralPath $sub -PathType Container) {
  $names = [string[]]@(Get-ChildItem -LiteralPath $sub -Filter '*.jsonl' -File | ForEach-Object { $_.Name })
  [Array]::Sort($names, [StringComparer]::Ordinal)
  foreach ($n in $names) { $files += Join-Path $sub $n }
}
Insights $files
} finally { if ($enc0) { try { [Console]::OutputEncoding = $enc0 } catch { } } }
