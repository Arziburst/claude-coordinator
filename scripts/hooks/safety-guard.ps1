# The safety guard for a settings file that still names safety-guard.ps1 (written before #564): a thin shim.
# The guard is one script, safety-guard.sh, on every OS (Windows: Git Bash, which Claude Code runs hooks
# through); this hands it the tool call unchanged - stdin's bytes in, its stdout, stderr and exit code back -
# so an older project's settings keep a working guard after "update the core" with no hand edit. New
# settings name the .sh itself (settings.example.windows.json): one process less a call.
# Fails closed: no Git Bash, no safety-guard.sh beside this file, or a .sh that ends in neither 0 nor 2
# blocks the call (exit 2 with the reason); the self-test then prints NOT WORKING.
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/hooks/safety-guard.ps1 [-SelfTest]
# Windows PowerShell 5.1 or PowerShell 7; nothing to install. No rule lives here: a rule goes into the .sh.
param([switch]$SelfTest)

function Stop-Guard([string]$why) {
  if ($SelfTest) { "safety-guard: NOT WORKING - STOP: do not start workers until it is fixed (TOOLKIT.md): $why"; exit 0 }
  [Console]::Error.WriteLine("Blocked by safety-guard: the guard cannot run ($why). If this is a false positive, ask the owner.")
  exit 2
}

# Git Bash: Claude Code's own setting, else the one beside git, else bash on PATH (as start-worker finds it, #465) -
# never WSL's launcher (System32\bash.exe) or its store alias, which cannot read a Windows path
$cand = @()
if ($env:CLAUDE_CODE_GIT_BASH_PATH) { $cand += $env:CLAUDE_CODE_GIT_BASH_PATH }
foreach ($g in @(Get-Command git -CommandType Application -All -ErrorAction SilentlyContinue | ForEach-Object { $_.Source })) {
  $cand += (Join-Path (Split-Path $g) '..\bin\bash.exe'), (Join-Path (Split-Path $g) '..\..\bin\bash.exe')
}
$cand += @(Get-Command bash -CommandType Application -All -ErrorAction SilentlyContinue | ForEach-Object { $_.Source })
$bash = $null
foreach ($b in $cand) {
  if (-not $b -or -not (Test-Path -LiteralPath $b -PathType Leaf)) { continue }
  if ($env:OS -eq 'Windows_NT' -and $b -match '\\(system32|sysnative|WindowsApps)\\bash\.exe$') { continue }
  $bash = [IO.Path]::GetFullPath($b); break
}
if (-not $bash) { Stop-Guard 'no Git Bash found: install Git for Windows, or set CLAUDE_CODE_GIT_BASH_PATH' }
$sh = Join-Path $PSScriptRoot 'safety-guard.sh'
if (-not (Test-Path -LiteralPath $sh -PathType Leaf)) { Stop-Guard "no $sh" }

$psi = New-Object Diagnostics.ProcessStartInfo
$psi.FileName = $bash
$psi.Arguments = '"' + $sh.Replace('\', '/') + '"' + $(if ($SelfTest) { ' --self-test' } else { '' })
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
# the .sh runs sed, awk and the like: Git's usr\bin on the child's PATH, whichever bash was found
$sep = [IO.Path]::PathSeparator
foreach ($d in @((Split-Path $bash), (Join-Path (Split-Path (Split-Path $bash)) 'usr\bin'))) {
  if ($env:OS -eq 'Windows_NT' -and (Test-Path -LiteralPath $d -PathType Container)) { $psi.EnvironmentVariables['PATH'] = $d + $sep + $psi.EnvironmentVariables['PATH'] }
}
try { $p = [Diagnostics.Process]::Start($psi) } catch { Stop-Guard "$bash did not start: $($_.Exception.Message)" }
$out = New-Object IO.MemoryStream; $err = New-Object IO.MemoryStream
$to = $p.StandardOutput.BaseStream.CopyToAsync($out); $te = $p.StandardError.BaseStream.CopyToAsync($err)
# the tool call's bytes as they came (no decoding: a non-ASCII path reaches the .sh as Claude Code wrote it)
$in = [Console]::OpenStandardInput()
if (-not $SelfTest) { try { $in.CopyTo($p.StandardInput.BaseStream) } catch { } }
try { $p.StandardInput.Close() } catch { }
$p.WaitForExit(); $to.Wait(); $te.Wait()
$rc = $p.ExitCode
if ($rc -ne 0 -and $rc -ne 2) { Stop-Guard "safety-guard.sh ended with exit $rc" }
$so = [Console]::OpenStandardOutput(); $out.WriteTo($so); $so.Flush()
$se = [Console]::OpenStandardError(); $err.WriteTo($se); $se.Flush()
exit $rc
