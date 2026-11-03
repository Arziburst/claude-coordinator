# A PreCompact hook for a coordinator (#342; Windows - macOS / Linux: before-compact.sh, the same file): before
# Claude Code compacts the conversation it writes <cwd>/coordinator/CHECKPOINT.md - the moment, the journal's
# open questions, the watch list, this project's sessions (claude agents --json, 10 s at most: past that only
# the process this hook started is killed, by its own handle) and the files to re-read - which after-compact.ps1
# coordinator puts back into the context: a summary is precomputed hours before the swap and never holds it.
# Never blocks a compaction: exit 0 on any failure, one line on stderr; silent without <cwd>/coordinator, in a
# worktree, with a kept brief (a worker) or COORD_ASSISTANT_DIR (an assistant). At most 8000 bytes: a section
# over its share keeps its first lines and says truncated.
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/hooks/before-compact.ps1   (the hook's JSON on stdin)
$in = ''; try { $in = [Console]::In.ReadToEnd() } catch { }
function Str([string]$k) { $m = [regex]::Match(($in -replace "[`r`n]", ''), '"' + $k + '" *: *"([^"]*)"'); if ($m.Success) { $m.Groups[1].Value } else { '' } }
$sid = Str 'session_id'; $wd = (Str 'cwd').Replace('\\', '\').Replace('\', '/')
$cfg = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
if (-not $wd -or $env:COORD_ASSISTANT_DIR -or $wd -like '*/.claude/worktrees/*' -or $wd -like '*/.claude/worktrees') { exit 0 }
if ($sid -match '^[0-9a-fA-F-]+$' -and (Test-Path -LiteralPath (Join-Path $cfg "coordinator/briefs/$sid.md") -PathType Leaf)) { exit 0 }
$c = "$wd/coordinator"; if (-not (Test-Path -LiteralPath $c -PathType Container)) { exit 0 }
function Fail([string]$m) { [Console]::Error.WriteLine("before-compact: $m") }
$U = New-Object System.Text.UTF8Encoding $false
# the lines under LOG.md's "## Open questions" up to its next heading
$q = 'could not read coordinator/LOG.md'
try { $on = $false; $q = (@(foreach ($l in [IO.File]::ReadAllLines("$c/LOG.md", $U)) { if ($l -clike '## *') { $on = $l -clike '## Open questions*'; continue }; if ($on) { $l } }) -join "`n").TrimEnd("`n") } catch { Fail "cannot read $c/LOG.md" }
$w = ''; try { $w = [IO.File]::ReadAllText("$c/watch.txt", $U).TrimEnd("`r", "`n") } catch { }
# the sessions whose cwd is the project or inside it: `<id> <state> <name>`; the listing to a file, never a pipe (a
# process left under a killed claude would hold it); claude as PATH gives it: a .ps1 through this PowerShell, a .cmd / .bat through cmd
function G([string]$o, [string]$k) { $m = [regex]::Match($o, '"' + $k + '" *: *"([^"]*)"'); if ($m.Success) { $m.Groups[1].Value.Replace('\\', '\') } else { '' } }
$r = "coordinator/core/CORE.md`ncoordinator/PROJECT.md`ncoordinator/BINDINGS.md`ncoordinator/LOG.md"; $s = ''; $o = $null; $e = $null
try {
  $cm = Get-Command claude -ErrorAction Stop | Select-Object -First 1; $a = 'agents --json'
  if ($cm.CommandType -eq 'ExternalScript') { $exe = (Get-Process -Id $PID).Path; $a = '-NoProfile -ExecutionPolicy Bypass -File "' + $cm.Path + '" ' + $a }
  elseif ($cm.Path -match '\.(cmd|bat)$') { $exe = $env:ComSpec; $a = '/d /s /c ""' + $cm.Path + '" ' + $a + '"' } else { $exe = $cm.Path }
  $o = [IO.Path]::GetTempFileName(); $e = [IO.Path]::GetTempFileName()
  $p = Start-Process -FilePath $exe -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e -ErrorAction Stop
  $null = $p.Handle   # keeps its exit code readable after it ends
  if (-not $p.WaitForExit(10000)) { try { $p.Kill() } catch { }; throw 'claude agents --json did not answer in 10 s' }
  $p.WaitForExit(); if ($p.ExitCode -ne 0) { throw "claude agents --json exited with $($p.ExitCode)" }
  $s = @(foreach ($m in [regex]::Matches([IO.File]::ReadAllText($o, $U), '\{[^{}]*\}')) { $d = (G $m.Value 'cwd').Replace('\', '/')
    if ($d -ieq $wd -or $d.StartsWith("$wd/", [StringComparison]::OrdinalIgnoreCase)) { (G $m.Value 'id') + ' ' + (G $m.Value 'state') + ' ' + (G $m.Value 'name') } }) -join "`n"
} catch { $s = 'could not list the sessions'; Fail ('no session listing (' + ($_.Exception.Message -split "`r?`n")[0] + ')') }
finally { foreach ($f in @($o, $e)) { if ($f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } } }
# Sec <heading> <share in bytes> <text>: the text's first lines within the share, then `truncated`
function Sec([string]$h, [int]$max, [string]$t) { $x = "## $h`n"; $n = 0
  foreach ($l in ($t -replace "`r", '') -split "`n") { $n += $U.GetByteCount($l) + 1; if ($n -gt $max) { return $x + "truncated`n" }; $x += "$l`n" }; $x }
$out = 'written: ' + [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ') + "`n" + (Sec 'Open questions' 3200 $q) + (Sec 'Watch list' 1600 $w) + (Sec 'Sessions' 2400 $s) + (Sec 'Re-read' 400 $r)
try { [IO.File]::WriteAllText("$c/CHECKPOINT.md", $out, $U) } catch { Fail "cannot write $c/CHECKPOINT.md" }
exit 0
