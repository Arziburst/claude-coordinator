# Optional second PreToolUse hook for an assistant's session (#380, TOOLKIT.md *Assistants*): beside
# safety-guard, connected only in the settings of a session that needs it. Reads the tool call JSON on
# stdin; exit 2 blocks. A command naming a network client (curl, wget, Invoke-WebRequest, iwr,
# Invoke-RestMethod, irm, also .exe) may reach only http(s) hosts listed in COORD_ASSISTANT_HOSTS=
# <host>[:write],... (exact host, any case, port ignored, no user part); data / write forms (-d, --data*,
# -F, -T, -X other than GET, --json, -Method other than Get, -Body, -InFile, --post-*) need :write. An
# address it cannot read (variable, substitution, none), -K / --config: blocked. --help / -h allowed.
# Unset or empty list: every client call blocked. A command with no client word passes at once.
# NOT A WALL: it reads text, no shell parse. A client's name inside a quoted string may block (fails
# closed); .NET, scripts and other tools are out of reach (no wall: #375). Same verdicts as net-guard.sh.
$j = [Console]::In.ReadToEnd()
if ($j -notmatch '(^|[^A-Za-z0-9_.-])(curl|wget|invoke-webrequest|iwr|invoke-restmethod|irm)(\.exe)?([^A-Za-z0-9_-]|$)') { exit 0 }
if ($j -cmatch '(^|\s)(-h|--help)(\s|"|\\|$)') { exit 0 }
function No($m) { [Console]::Error.WriteLine("net-guard: $m (allowed hosts: COORD_ASSISTANT_HOSTS=<host>[:write],...)"); exit 2 }
if ($j -cmatch '(^|\s)(-K|--config)(\s|=|$)') { No 'a config file cannot be read' }
$w = ($j -cmatch '(^|\s)(-d|-F|-T|--data[a-z-]*|--form|--upload-file|--json|--post-[a-z]*)(\s|=|\\|$)') -or ($j -match '(^|\s)(-Body|-InFile)(\s|\\|$)')
$m = [regex]::Match($j, '(^|\s)(-X|-Method|--request)[ =]+([A-Za-z]+)', 'IgnoreCase')
if ($m.Success -and $m.Groups[3].Value -ne 'get') { $w = $true }
$urls = [regex]::Matches($j, '(?i)https?://[^\s"''\\<>|;&)]*')
if ($urls.Count -eq 0) { No 'no address it can read' }
$list = @(([string]$env:COORD_ASSISTANT_HOSTS).ToLower().Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
foreach ($u in $urls) {
  $h = $u.Value -replace '^[^:]*://', ''
  $h = ($h -split '[/?#]')[0]
  if ($h.Contains('@')) { No "user part in $($u.Value)" }
  $h = ($h -split ':')[0].ToLower()
  $ok = $false
  foreach ($e in $list) {
    if (($e -replace ':write$', '') -ne $h) { continue }
    if ($w -and $e -notmatch ':write$') { continue }
    $ok = $true
  }
  if (-not $ok) { No "$($u.Value) is not allowed (a write form needs :write)" }
}
exit 0
