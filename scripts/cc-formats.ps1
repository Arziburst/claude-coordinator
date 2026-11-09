# Claude Code's internal formats against the fields the core reads (#559; Windows; macOS / Linux: cc-formats.sh - the same
# line and codes). The table of fields (`#F` lines) and what each part means: cc-formats.sh, beside this file.
#   scripts/cc-formats.ps1 [-IfChanged] [-Transcript <file.jsonl>] [-Payload <file.json>]
# No status line here (that file absent, no -Payload): first `cc-formats: SKIP payload: ...`; the rest decides.
# Exit 0 PASS, 1 FAIL, 2 usage.
param([switch]$IfChanged, [string]$Transcript = '', [string]$Payload = '')
if ($args.Count -gt 0) { [Console]::Error.WriteLine('usage: cc-formats.ps1 [-IfChanged] [-Transcript <file.jsonl>] [-Payload <file.json>]'); exit 2 }
$ErrorActionPreference = 'Continue'
$cfg = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } elseif ($env:USERPROFILE) { "$env:USERPROFILE/.claude" } else { "$env:HOME/.claude" }
$sd = "$cfg/coordinator/cc-formats"
$cm = Get-Command claude -ErrorAction SilentlyContinue | Select-Object -First 1
$ver = ''; if ($cm) { try { $ver = "$(& claude --version 2>$null | Select-Object -First 1)" -replace ' .*', '' } catch { $ver = '' } }
$v = if ($ver) { $ver } else { '?' }
if ($IfChanged) { if (-not $ver) { exit 0 }; if ("$(Get-Content -LiteralPath "$sd/version" -ErrorAction SilentlyContinue | Select-Object -First 1)" -eq $ver) { exit 0 } }
try { $null = New-Item -ItemType Directory -Force -Path $sd -ErrorAction Stop } catch { "cc-formats: FAIL claude ${v}: cannot create $sd"; exit 1 }
$bad = @(); $n = 0
# the listing, 5 s at most, into the scratch folder (claude as PATH gives it: a .ps1 through this PowerShell, a .cmd / .bat through cmd)
$ao = "$sd/agents.json"; $ae = "$sd/agents.err"
try {
  if (-not $cm) { throw 'no claude' }
  $a = 'agents --json --all'
  if ($cm.CommandType -eq 'ExternalScript') { $exe = (Get-Process -Id $PID).Path; $a = '-NoProfile -ExecutionPolicy Bypass -File "' + $cm.Path + '" ' + $a }
  elseif ($cm.Path -match '\.(cmd|bat)$') { $exe = $env:ComSpec; $a = '/d /s /c ""' + $cm.Path + '" ' + $a + '"' } else { $exe = $cm.Path }
  # its whole tree in a job object: a child whose Windows parent is gone (an msys exec leaves one) is out of reach of
  # taskkill /T and Kill($true), which follow parent ids, and holds the caller's inherited pipe open until it ends (#559)
  $win = $env:OS -eq 'Windows_NT'; $job = [IntPtr]::Zero; if ($win) { try { Add-Type -Namespace CcFormats -Name Job -ErrorAction Stop -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr CreateJobObject(IntPtr a, IntPtr n);
[DllImport("kernel32.dll")] public static extern bool AssignProcessToJobObject(IntPtr j, IntPtr p);
[DllImport("kernel32.dll")] public static extern bool TerminateJobObject(IntPtr j, uint c);
'@; $job = [CcFormats.Job]::CreateJobObject([IntPtr]::Zero, [IntPtr]::Zero) } catch { } }
  $p = Start-Process -FilePath $exe -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput $ao -RedirectStandardError $ae -ErrorAction Stop
  $null = $p.Handle   # keeps its exit code readable after it ends
  $inJob = $job -ne [IntPtr]::Zero -and [CcFormats.Job]::AssignProcessToJobObject($job, $p.Handle)
  if (-not $p.WaitForExit(5000)) {   # the job ended; without one: taskkill /T (Windows), else Kill($true) (.NET Core)
    if (-not ($inJob -and [CcFormats.Job]::TerminateJobObject($job, 1))) { $tk = $false
      if ($win) { $null = & taskkill.exe /T /F /PID $p.Id 2>&1; $tk = $LASTEXITCODE -eq 0 }
      if (-not $tk) { try { $p.Kill($true) } catch { } } }
    $bad += 'agents: claude agents --json --all did not answer in 5 s' }
  else { $p.WaitForExit(); $j = [IO.File]::ReadAllText($ao) -replace '\s', ''
    if ($p.ExitCode -ne 0 -or $j -notmatch '^\[.*\]$') { $bad += 'agents: claude agents --json --all printed no JSON list' } }
} catch { $bad += 'agents: claude agents --json --all printed no JSON list' }
Remove-Item -LiteralPath $ae -Force -ErrorAction SilentlyContinue
# Tail2000 <file>: its last 2000 lines, the file read once whole (Get-Content -Tail took 18 s on 51 MB on Windows), shared
# with its writer; @() when unreadable
function Tail2000([string]$p) {
  try { $s = [IO.FileStream]::new($p, 'Open', 'Read', 'ReadWrite'); $r = [IO.StreamReader]::new($s, [Text.Encoding]::UTF8)
    try { $l = $r.ReadToEnd().TrimEnd([char]10).Split([char]10) } finally { $r.Dispose() }
    if ($l.Count -gt 2000) { $l[($l.Count - 2000)..($l.Count - 1)] } else { $l } } catch { @() }
}
$tl = $null   # the transcript's last 2000 lines, read once: the search below and Text
if (-not $Transcript) {
  foreach ($f in @(Get-ChildItem -Path "$cfg/projects/*/*.jsonl" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 50)) {
    $l = @(Tail2000 $f.FullName); if (@($l -match '"role": *"assistant"').Count) { $Transcript = $f.FullName; $tl = $l; break } }
  if (-not $Transcript) { $bad += "transcript: none under $cfg/projects holds an assistant message" }
}
$fms = 'agents', 'transcript', 'payload'   # no status line here (its file absent, no -Payload): the payload part one SKIP line
if (-not $Payload) { $Payload = "$cfg/coordinator/statusline.json"
  if (-not (Test-Path -LiteralPath $Payload)) { $fms = 'agents', 'transcript'; "cc-formats: SKIP payload: no status line here ($Payload absent)" } }
if ($Transcript -and -not (Test-Path -LiteralPath $Transcript -PathType Leaf)) { $bad += "transcript: cannot read $Transcript" }
if ($fms.Count -eq 3 -and -not (Test-Path -LiteralPath $Payload -PathType Leaf)) { $bad += "payload: cannot read $Payload" }
# the input's lines, `": ` and `, "` closed up
function Text([string]$fm) {
  $l = switch ($fm) { 'agents' { Get-Content -LiteralPath $ao -Encoding UTF8 } 'transcript' { if ($null -ne $tl) { $tl } elseif ($Transcript) { Tail2000 $Transcript } }
    'payload' { Get-Content -LiteralPath $Payload -Encoding UTF8 } }
  @($l | ForEach-Object { $_ -replace '"\s*:\s*', '":' -replace ',\s*"', ',"' })
}
$rows = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'cc-formats.sh') | Where-Object { $_ -like '#F *' })
foreach ($fm in $fms) {
  if (@($bad | Where-Object { $_ -like "${fm}: *" }).Count) { continue }
  $t = @(Text $fm)   # one line stays a list: -match on a list filters it
  foreach ($r in $rows) {
    $x = $r -split ' +'; if ($x[1] -ne $fm) { continue }
    if ($x[3] -ne '-' -and -not @($t -match $x[3]).Count) { continue }
    $n++; if (-not @($t -match $x[4]).Count) { $bad += "$fm $($x[2]) (read by $($x[5].Replace(',', ', ')))" }
  }
}
if ($bad.Count) { "cc-formats: FAIL claude ${v}: $($bad -join '; ')"; exit 1 }
if ($ver) { [IO.File]::WriteAllText("$sd/version", "$ver`n") }
"cc-formats: PASS claude $v, $n fields"
exit 0
