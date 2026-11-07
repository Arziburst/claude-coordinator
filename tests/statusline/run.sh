#!/usr/bin/env bash
# The status line cases on tests/selftest/status.json: the line, statusline.json and the session's copy
# saved and no statusline.*.tmp left - on a plain run, a config path with [ ] in it, 20 runs at once, and
# (PowerShell) statusline.json held open by a reader, which fails the move on Windows.
#   tests/statusline/run.sh sh              # scripts/statusline.sh, with the bash running this file
#   tests/statusline/run.sh ps pwsh         # scripts/statusline.ps1 (or: ps powershell)
# The .sh draws its line only with jq: without it the line is not compared. Exit 1 if any case fails.
# Access points the scripts implement as written here (#449):
#   Install: `statusline.sh --install` / `statusline.ps1 -Install` copies the script itself to
#     <config>/coordinator/statusline/<its file name>, unless a copy there holds the same or a newer version; exit 0.
#   Version: a line `# statusline-version: <whole number>` in each script, raised with a change.
#   Upstream's head: <config>/coordinator/core-upstream.txt, its first 40 characters the sha (the `git ls-remote` line):
#     the tag stable's when upstream has it, else main's; main's alone when PROJECT.md's row `| Core source ...` holds `main` (#495).
#   The recorded commit: <project>/coordinator/PROJECT.md, the row `| Core (CORE ...` holding commit `<sha>`, a prefix.
#   The project: workspace.project_dir of the status JSON. A task's budget: `  cost: <n>` in its briefs/<task>-contract.md, else
#     (#505) under a `budget:` line in <config>/coordinator/briefs/<sessionId>.md, the first of its sessions in start order that holds one, a `#<task>.<n>` one never.
#   Sessions: `claude agents --json`: name, cwd, state, status, sessionId. A live one has a status; at work: state `working`.
#   Live spend: <config>/coordinator/sessions/<sessionId>.json, cost.total_cost_usd. A row in coordinator/RUNS.tsv is that
#     session's when its start cell equals the session's start, as `runs check` reads it: the first timestamp in the
#     transcript (transcript_path in that file), to the second, with Z.
set -u
[ $# -gt 0 ] || { sed -n '2,7s/^# \{0,1\}//p' "$0"; exit 2; }
kind="$1"; shift
[ "$kind" = sh ] || [ "$kind" = ps ] || { sed -n '2,7s/^# \{0,1\}//p' "$0"; exit 2; }
PS=("$@")
[ "$kind" = sh ] || [ ${#PS[@]} -gt 0 ] || { echo "ps needs the PowerShell command" >&2; exit 2; }
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -r "$tmp"' EXIT
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }   # Git Bash -> C:/...
fixture="$core/tests/selftest/status.json"; in="$fixture"; script="$core/scripts/statusline"; unset COLUMNS CLAUDE_PROJECT_DIR
want='Opus 5.5 high · 837k/1M 83% · 5h limit 14% · week 92%'
line=yes; [ "$kind" = ps ] || command -v jq >/dev/null 2>&1 || line=no
bom="$(printf '\357\273\277')"

# one run with CLAUDE_CONFIG_DIR=$1 and the fixture on stdin; stdout to $tmp/out (\r removed), exit code in rc
run() {
  local cfg; cfg="$(winpath "$1")"
  if [ "$kind" = ps ]; then
    CLAUDE_CONFIG_DIR="$cfg" "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$(winpath "$script.ps1")" < "$in" 2> "$tmp/err" | cat > "$tmp/out.raw"
  else
    CLAUDE_CONFIG_DIR="$cfg" bash "$script.sh" < "$in" 2> "$tmp/err" | cat > "$tmp/out.raw"
  fi
  rc=${PIPESTATUS[0]}
  tr -d '\r' < "$tmp/out.raw" > "$tmp/out"
}
# what the line says: no colour codes, a bar's padding gone
plain() { sed "s/$(printf '\033')\[[0-9;]*m//g" "$tmp/out" | tr -s ' ' | sed 's/^ //; s/ $//'; }
# is $1 the fixture, a BOM (Windows PowerShell 5.1's utf8) aside?
same() { local c; [ -f "$1" ] || return 1; c="$(cat "$1")"; [ "${c#"$bom"}" = "$(cat "$fixture")" ]; }
# the statusline.*.tmp files left in $1/coordinator
temps() { ls "$1/coordinator" | grep '^statusline\..*\.tmp$' | tr '\n' ' '; }
fail=0; n=0
bad() { echo "FAIL $*"; fail=1; }
# check <name> <config dir> <compare statusline.json: yes | no>: the run's exit, line, files and temp files
check() {
  local name="$1" cfg="$2" json="$3" t
  n=$((n + 1))
  [ "$rc" = 0 ] || { bad "$name: exit $rc"; sed 's/^/  err: /' "$tmp/err"; return; }
  [ "$line" = no ] || [ "$(plain)" = "$want" ] || { bad "$name: wants '$want', printed '$(plain)'"; return; }
  t="$(temps "$cfg")"; [ -z "$t" ] || { bad "$name: left $t"; return; }
  [ "$json" = no ] || same "$cfg/coordinator/statusline.json" || { bad "$name: statusline.json is not the status JSON"; return; }
  same "$cfg/coordinator/sessions/selftest-fixture.json" || { bad "$name: no session copy"; return; }
  echo "ok   $name"
}

run "$tmp/one"; check "the fixture: the line, statusline.json, the session's copy, no temp file" "$tmp/one" yes
mkdir -p "$tmp/cfg[1]"; run "$tmp/cfg[1]"; check "a config path with [ ]" "$tmp/cfg[1]" yes

# 20 at once, as Claude Code draws several sessions' status lines: Move-Item -Force deletes the target,
# then moves, so another run's move in between failed this one's and left its temp file; and Set-Content
# straight on the session copy emptied it, then lost the write to another run holding it (about 1 round
# in 10 under Windows PowerShell 5.1): the copy must be whole after every round
m="$tmp/many"; mkdir -p "$m"; cm="$(winpath "$m")"; i=0
while [ $i -lt 20 ]; do
  if [ "$kind" = ps ]; then
    CLAUDE_CONFIG_DIR="$cm" "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$(winpath "$core/scripts/statusline.ps1")" < "$fixture" > /dev/null 2>&1 &
  else
    CLAUDE_CONFIG_DIR="$cm" bash "$core/scripts/statusline.sh" < "$fixture" > /dev/null 2>&1 &
  fi
  i=$((i + 1))
done
wait
rc=0; printf '%s\n' "$want" > "$tmp/out"; check "20 runs at once" "$m" yes

# statusline.json held open by a reader (FileShare.ReadWrite, no Delete): on Windows the move fails, the
# temp file goes and the old statusline.json stays for this tick; elsewhere the move succeeds
if [ "$kind" = ps ]; then
  cat > "$tmp/hold.ps1" <<'EOF'
param([string]$Target, [string]$Script, [string]$In, [string]$Out)
$h = [IO.File]::Open($Target, 'Open', 'Read', 'ReadWrite')
try {
  $exe = (Get-Process -Id $PID).Path
  $p = Start-Process -FilePath $exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $Script)) -RedirectStandardInput $In -RedirectStandardOutput $Out -NoNewWindow -PassThru
  $null = $p.Handle; $p.WaitForExit(); exit $p.ExitCode
} finally { $h.Close() }
EOF
  hd="$tmp/held"; mkdir -p "$hd/coordinator"; printf '{}' > "$hd/coordinator/statusline.json"
  CLAUDE_CONFIG_DIR="$(winpath "$hd")" "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$(winpath "$tmp/hold.ps1")" \
    -Target "$(winpath "$hd/coordinator/statusline.json")" -Script "$(winpath "$core/scripts/statusline.ps1")" \
    -In "$(winpath "$fixture")" -Out "$(winpath "$tmp/out.raw")" 2> "$tmp/err"
  rc=$?; tr -d '\r' < "$tmp/out.raw" > "$tmp/out"
  check "statusline.json held open by a reader" "$hd" no
fi
# ---- The bars (#449). `| cat` in run: a status line's stdout is a pipe. $tmp/bars, read cell by cell from the codes: a row per bar: line, text (trimmed;
# . the middle dot, ^ the up arrow), width, colours (`green:8 grey:13`; `!` = not dark text on a colour; a lighter wave cell is its base colour), text colours, fill colours.
E="$(printf '\033')"; dot="$(printf '\302\267')"; arrow="$(printf '\342\206\221')"
bars() { tr -d '\r' < "$tmp/out.raw" | LC_ALL=C sed "s/$dot/./g; s/$arrow/^/g" | LC_ALL=C awk -v E="$E" '
  function rgb(p, key, i, a) { i = index(";" p ";", ";" key ";2;"); if (!i) return ""; split(substr(p, i + length(key) + 3), a, ";"); return a[1] ";" a[2] ";" a[3] }
  function col(c, a) { if (c == "") return "none"; if (c == "48;54;61") return "grey"; split(c, a, ";"); if (a[3] >= a[2]) return "blue"; if (a[1] < a[2]) return "green"; return a[2] >= 179 ? "yellow" : "red" }
  function cell(ch, k) { k = col(bg); if (bg != "" && k != "grey" && fg != "13;17;23") k = k "!"; if (k != ck) { if (ck != "") segs = segs ck ":" cn " "; ck = k; cn = 0 } cn++; txt = txt ch; fgs = fgs " " fg; bgs = bgs " " bg }
  function flush(t) { if (txt != "") { segs = segs ck ":" cn; t = txt; gsub(/^ +| +$/, "", t); printf "%d\t%s\t%d\t%s\t%s\t%s\n", NR, t, length(txt), segs, fgs, bgs } txt = segs = fgs = bgs = ck = ""; cn = 0 }
  { s = $0; bg = fg = ""
    while (s != "") {
      if (substr(s, 1, 2) == E "[") { i = index(s, "m"); p = substr(s, 3, i - 3); s = substr(s, i + 1)
        if (p == "0" || p == "") { flush(); bg = fg = "" } else { x = rgb(p, 48); if (x != "") bg = x; x = rgb(p, 38); if (x != "") fg = x }
      } else { if (bg != "" || fg != "") cell(substr(s, 1, 1)); s = substr(s, 2) } }
    flush() }' > "$tmp/bars"; }
cname=""; cfail=0
finish() { [ -z "$cname" ] || [ "$cfail" != 0 ] || echo "ok   $cname"; cname=""; }
begin() { finish; cname="$1"; cfail=0; n=$((n + 1)); }
no() { echo "FAIL $cname: $*"; fail=1; cfail=1; }
draw() { run "$cfg"; [ "$rc" = 0 ] || no "wants exit 0, got $rc: $(head -n 2 "$tmp/err")"; bars; }
is() { [ "$(plain)" = "$1" ] || no "wants the text '$1', printed '$(plain)'"; }
bar() { local g; g="$(awk -F'\t' -v t="$1" '$2 == t { print $3 " " $4 }' "$tmp/bars" | head -n 1)"; [ "$g" = "$2 $3" ] || no "wants the bar '$1' width $2 colours '$3', got '${g:-no such bar}'; printed '$(plain)'"; }
lines() { local g; g="$(cut -f1 "$tmp/bars" | tr '\n' ' ')"; [ "$g" = "$1" ] || no "wants the bars on lines '$1', got '$g'; printed '$(plain)'"; }
first() { head -n 1 "$tmp/bars" | cut -f2; }
nat() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }   # the form Claude Code hands over
jp() { nat "$1" | sed 's/\\/\\\\/g'; }
cfg="$tmp/c"; root="$tmp/proj"; other="$tmp/proj-other"; wt="$root/.claude/worktrees/w"; up="$cfg/coordinator/core-upstream.txt"
mkdir -p "$cfg/coordinator/sessions" "$cfg/projects/p" "$root/.claude" "$root/coordinator/briefs" "$other" "$tmp/bin" "$tmp/stub"
# fx <session name> <model> <effort> <used tokens> <window> [,more top-level JSON]: the status JSON of the next draw
fx() { printf '{"session_id":"t1","session_name":"%s","cwd":"%s","workspace":{"project_dir":"%s"},"model":{"display_name":"%s"},"effort":{"level":"%s"},"context_window":{"used_percentage":1,"context_window_size":%s,"current_usage":{"input_tokens":%s,"cache_read_input_tokens":0}}%s}\n' \
    "$1" "$(jp "$root")" "$(jp "$root")" "$2" "$3" "$5" "$4" "${6:-}" > "$tmp/in.json"; in="$tmp/in.json"; }
export STUB_D; STUB_D="$(winpath "$tmp/stub")"
printf '#!/usr/bin/env bash\ncat "$STUB_D/agents.json" 2>/dev/null || echo "[]"\n' > "$tmp/bin/claude"
cat > "$tmp/bin/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_D/git.log"
case "$*" in *ls-remote*) sleep "$(cat "$STUB_D/git.sleep")"; case "$*" in *refs/heads/main*) printf '%s\trefs/heads/main\n' "$(cat "$STUB_D/git.head")" ;; esac
  case "$*" in *refs/tags/stable*) [ ! -f "$STUB_D/git.stable" ] || printf '%s\trefs/tags/stable\n' "$(cat "$STUB_D/git.stable")" ;; esac; printf x >> "$STUB_D/git.done" ;; esac
EOF
for s in claude git; do chmod +x "$tmp/bin/$s"; printf '& bash (Join-Path $PSScriptRoot %s) @args\nexit $LASTEXITCODE\n' "$s" > "$tmp/bin/$s.ps1"; printf '@bash "%%~dp0%s" %%*\r\n' "$s" > "$tmp/bin/$s.cmd"; done
export PATH="$tmp/bin:$PATH"
# agent <id> <name> <state> <status|-> <cwd> <cost> <start>: in the stub's list (no status field for -), with its status copy and its transcript
ag=0
agent() { local st=""; [ "$4" = - ] || st=",\"status\":\"$4\""; ag=$((ag + 1))
  printf ',{"id":"%s","sessionId":"%s","name":"%s","cwd":"%s","state":"%s","startedAt":%s%s}' "$1" "$1" "$2" "$(jp "$5")" "$3" "$((1793786400000 + ag * 1000))" "$st" >> "$tmp/agents.body"
  printf '[%s]\n' "$(cut -c2- "$tmp/agents.body")" > "$tmp/stub/agents.json"
  printf '{"timestamp":"%s.000Z","type":"user"}\n' "${7%Z}" > "$cfg/projects/p/$1.jsonl"
  printf '{"session_id":"%s","transcript_path":"%s","cost":{"total_cost_usd":%s}}\n' "$1" "$(jp "$cfg/projects/p/$1.jsonl")" "$6" > "$cfg/coordinator/sessions/$1.json"; }
row() { printf '2026-11-04\t%s\t%s\thard\tm\thigh\t-\t1\t%s\tdone\t%s\t1\t1\t\t\n' "$1" "$2" "$3" "$4" >> "$root/coordinator/RUNS.tsv"; }
tasks_reset() { rm -f "$tmp/agents.body" "$tmp/stub/agents.json"; printf 'date\ttask\trole\tkind\tmodel\teffort\testimate\ttokens\tcost\tresult\tstart\twall\tactive\twait\testimate_time\n' > "$root/coordinator/RUNS.tsv"; }
budget() { printf -- '---\nid: %s\nbudget:\n  model: opus\n  cost: 10\n---\n' "$1" > "$root/coordinator/briefs/$1-contract.md"; }
A=aaaaaaa000000000000000000000000000000000; B=bbbbbbb000000000000000000000000000000000
core_row() { printf '| Core (CORE \302\2472) | a | b | 2026-11-04 | a local copy in `coordinator/core/` at claude-coordinator commit `%s`; local edits: none |\n' "$(printf '%s' "$B" | cut -c1-7)" > "$root/coordinator/PROJECT.md"; }
upstream() { printf '%s\trefs/heads/main\n%s' "$1" "${2-$(printf '%s' "$B" | cut -c1-7)}" > "$up"; }   # line 2: the commit PROJECT.md recorded when the file was read (#516)
waitfor() { local i=0; while [ $i -lt 20 ]; do grep -q "^$1" "$up" 2>/dev/null && return 0; sleep 1; i=$((i + 1)); done; return 1; }
stamp() { local s=$(( $(date +%s) - $1 )); if date --version >/dev/null 2>&1; then date -d "@$s" +%Y%m%d%H%M.%S; else date -r "$s" +%Y%m%d%H%M.%S; fi; }
gitcalls() { grep -c ls-remote "$tmp/stub/git.log" 2>/dev/null; }
wk() { printf '"seven_day":{"used_percentage":%s,"resets_at":%s}' "$1" "$(( $(date +%s) + (1000 - $2) * 6048 / 10 ))"; }   # $2: the week gone, in tenths of a point
C="CORE Coordinator"; M="Opus 5.5"; W400="400000 1000000"; L400="Opus 5.5 high $dot 400k/1M 40%"
# the coordinator's SessionStart hook on $tmp/hook.json: stdout in $tmp/out, exit in rc; hk <source> <session id> writes that JSON first
hkrun() { if [ "$kind" = ps ]; then CLAUDE_CONFIG_DIR="$(winpath "$cfg")" "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$(winpath "$script.ps1")" -SessionStart; else CLAUDE_CONFIG_DIR="$cfg" bash "$script.sh" --session-start; fi < "$tmp/hook.json" > "$tmp/out" 2> "$tmp/err"; rc=$?; }
hk() { printf '{"session_id":"%s","cwd":"%s","hook_event_name":"SessionStart","source":"%s"}\n' "$2" "$(jp "$root")" "$1" > "$tmp/hook.json"; hkrun; }

bar_cases() {
  local m e u t s g
  begin "the context bar: the four models at high and medium, one width"
  for m in "Opus 5.5" "Sonnet 5.5" "Haiku 5.5" "Fable 5.1"; do for e in high medium; do fx x "$m" "$e" $W400; draw; bar "$m $e . 400k/1M 40%" 34 "green:14 grey:20"; done; done
  begin "the threshold: the project's local settings, the project's, the account's, else the model's window"
  printf '{"autoCompactWindow":100000}' > "$root/.claude/settings.local.json"; printf '{"autoCompactWindow":200000}' > "$root/.claude/settings.json"; printf '{"autoCompactWindow":300000}' > "$cfg/settings.json"
  fx x "$M" high 60000 1000000
  draw; bar "$M high . 60k/100k 60%" 34 "green:20 grey:14"; rm "$root/.claude/settings.local.json"
  draw; bar "$M high . 60k/200k 30%" 34 "green:10 grey:24"; rm "$root/.claude/settings.json"
  draw; bar "$M high . 60k/300k 20%" 34 "green:7 grey:27"; rm "$cfg/settings.json"
  draw; bar "$M high . 60k/1M 6%" 34 "green:2 grey:32"
  begin "the longest context bar holds its width, red and full past the threshold"; printf '{"autoCompactWindow":500000}' > "$cfg/settings.json"; fx x "Sonnet 5.5" medium 999000 1000000; draw; bar "Sonnet 5.5 medium . 999k/500k 199%" 34 "red:34"; rm "$cfg/settings.json"
  begin "the context's colours at their edges: 70 and 90"
  fx x "$M" high 699999 1000000; draw; bar "$M high . 699k/1M 69%" 34 "green:24 grey:10"; fx x "$M" high 700000 1000000; draw; bar "$M high . 700k/1M 70%" 34 "yellow:24 grey:10"
  fx x "$M" high 899999 1000000; draw; bar "$M high . 899k/1M 89%" 34 "yellow:31 grey:3"; fx x "$M" high 900000 1000000; draw; bar "$M high . 900k/1M 90%" 34 "red:31 grey:3"
  begin "the 5-hour bar by the context's levels, only where it is passed"
  fx x "$M" high $W400 ",\"rate_limits\":{\"five_hour\":{\"used_percentage\":85},$(wk 30 502)}"; draw; bar "5h limit 85%" 14 "yellow:12 grey:2"
  fx x "$M" high $W400 ",\"rate_limits\":{$(wk 30 502)}"; draw; is "$L400 $dot week 30% $dot reset 50%"
  begin "the week behind time: green to the limit, blue to the time, then grey"; fx x "$M" high $W400 ",\"rate_limits\":{$(wk 30 502)}"; draw; bar "week 30% . reset 50%" 26 "green:8 blue:5 grey:13"
  begin "the week level with time: green to the limit, then grey"; fx x "$M" high $W400 ",\"rate_limits\":{$(wk 50 500)}"; draw; bar "week 50% . reset 50%" 26 "green:13 grey:13"
  begin "the week ahead up to 10 points: blue to the time, the excess yellow"; fx x "$M" high $W400 ",\"rate_limits\":{$(wk 60 502)}"; draw; bar "week 60% . reset 50%" 26 "blue:13 yellow:3 grey:10"
  begin "the week ahead past 10 points: blue to the time, the excess red"; fx x "$M" high $W400 ",\"rate_limits\":{$(wk 61 502)}"; draw; bar "week 61% . reset 50%" 26 "blue:13 red:3 grey:10"

  # no fetch while the tasks are drawn: a fresh file, the commit PROJECT.md records
  core_row; upstream "$B"; for t in 7 11 12 13 14 20 21; do budget "$t"; done
  begin "a lead's task: stage L, its #<task>.<n> sessions and rows count"; tasks_reset; agent l1 "#7 lead: x" idle idle "$root" 2 2026-11-04T09:00:00Z; agent l2 "#7.1 worker: x" working busy "$wt" 1 2026-11-04T09:10:00Z; row 7.1 tester 1.0000 2026-11-04T09:05:00Z
  fx "$C" "$M" high $W400; draw; bar "#7 L 4/10\$" 17 "green:7 grey:10"
  begin "tasks at work: stage, spent/budget, green, yellow from 80%, yellow at 100%, red past; a live session and its row count once; idle, another folder, self: no bar"; tasks_reset; s=2026-11-04T10:00
  agent a1 "$C" working busy "$root" 1 "$s:00Z"
  agent b1 "#11 tester: x" done - "$wt" 2 "$s:01Z"; row 11 tester 2.0000 "$s:01Z"; agent b2 "#11 worker: x" working busy "$wt" 5 "$s:02Z"; row 11 verifier "in coordinator" ""; row 11 task - "$s:01Z"
  agent c1 "#12 tester: x" working busy "$wt" 8 "$s:03Z"
  agent d1 "#13 verifier: x" working busy "$wt" 3 "$s:04Z"; row 13 verifier 3.0000 "$s:04Z"; row 13 worker 8.0000 "$s:05Z"
  agent e1 "#14 researcher: x" working busy "$wt" 10 "$s:06Z"
  agent f1 "#20 worker: x" idle idle "$wt" 1 "$s:07Z"
  agent g1 "#21 worker: x" working busy "$other" 1 "$s:08Z"
  fx "$C" "$M" high $W400; draw
  is "$L400 $dot #11 W 7/10\$ $dot #12 T 8/10\$ $dot #13 V 11/10\$ $dot #14 R 10/10\$"
  bar "#11 W 7/10\$" 17 "green:12 grey:5"; bar "#12 T 8/10\$" 17 "yellow:14 grey:3"; bar "#13 V 11/10\$" 17 "red:17"; bar "#14 R 10/10\$" 17 "yellow:17"
  # #505: <config>/coordinator/briefs/<sessionId>.md, what a session was started with; `  cost:` counts only under `budget:`
  kept() { mkdir -p "$cfg/coordinator/briefs"; printf '# %s\nprice:\n  cost: 3\n---\nid: x\nbudget:\n  model: opus\n  cost: %s\n---\n' "$1" "$2" > "$cfg/coordinator/briefs/$1.md"; }
  begin "no coordinator/briefs, the contract at another path: the budget from the session's kept brief"; tasks_reset; mv "$root/coordinator/briefs" "$tmp/briefs.away"; mkdir -p "$root/coordinator/contracts"; printf -- '---\nbudget:\n  cost: 99\n---\n' > "$root/coordinator/contracts/c30.md"
  agent k1 "#30 worker: x" working busy "$wt" 7 2026-11-04T12:00:00Z; kept k1 10; fx "$C" "$M" high $W400; draw; bar "#30 W 7/10\$" 17 "green:12 grey:5"
  begin "an earlier session of the task holds no budget: the next one's counts"; tasks_reset; agent k2 "#31 tester: x" done - "$wt" 0 2026-11-04T12:01:00Z; printf 'no contract here\n' > "$cfg/coordinator/briefs/k2.md"; agent k3 "#31 worker: x" working busy "$wt" 7 2026-11-04T12:02:00Z; kept k3 10; draw; bar "#31 W 7/10\$" 17 "green:12 grey:5"
  begin "nothing found, no kept brief or one without a budget: the bar as before, exit 0"; tasks_reset; agent k4 "#32 worker: x" working busy "$wt" 3 2026-11-04T12:03:00Z; draw; bar "#32 W 3\$" 17 "blue:17"; printf 'no contract here\n' > "$cfg/coordinator/briefs/k4.md"; draw; bar "#32 W 3\$" 17 "blue:17"
  begin "a lead's sub-session does not replace the lead's budget, nor stand in for one"; tasks_reset; agent k5 "#33.1 worker: x" working busy "$wt" 1 2026-11-04T12:04:00Z; kept k5 1; agent k6 "#33 lead: x" idle idle "$root" 2 2026-11-04T12:05:00Z; kept k6 10; draw; bar "#33 L 3/10\$" 17 "green:5 grey:12"
  rm "$cfg/coordinator/briefs/k6.md"; draw; bar "#33 L 3\$" 17 "blue:17"
  begin "briefs/<task>-contract.md first, where it exists"; tasks_reset; mv "$tmp/briefs.away" "$root/coordinator/briefs"; budget 34; agent k7 "#34 worker: x" working busy "$wt" 7 2026-11-04T12:06:00Z; kept k7 20; draw; bar "#34 W 7/10\$" 17 "green:12 grey:5"
  begin "not a coordinator: no task bars and no core mark"; upstream "$A"; fx "#11 worker: x" "$M" high $W400; draw; is "$L400"; [ ! -s "$tmp/stub/git.log" ] || no "wants no git call in a session that is not a coordinator"

  tasks_reset; printf 6 > "$tmp/stub/git.sleep"; printf '%s' "$A" > "$tmp/stub/git.head"; rm -f "$up" "$tmp/stub/git.log"; fx "$C" "$M" high $W400
  begin "the core mark: the first read detached, the script does not wait for git ls-remote, nothing shown"; draw; [ ! -f "$tmp/stub/git.done" ] || no "wants the script done before the stub git (6 s) answered"
  is "$L400"
  if waitfor "$A"; then
    grep -Eq 'ls-remote .*claude-coordinator.* refs/heads/main' "$tmp/stub/git.log" || no "wants 'git ls-remote <the core's address> refs/heads/main', got '$(cat "$tmp/stub/git.log")'"
    begin "the core mark shown, first, letters red to yellow; git not read again inside 12 hours"; draw; [ "$(first)" = "core ^" ] || no "wants 'core <up arrow>' as the first bar, printed '$(plain)'"
    g="$(awk -F'\t' 'NR == 1 { n = split($5, a, " "); for (i = 1; i <= n; i++) { split(a[i], c, ";"); if (c[1] != 255 || c[2] < 80 || c[2] > 220 || c[3] < 60 || c[3] > 80) { print "bad"; exit } if (!(a[i] in d)) { d[a[i]] = 1; k++ } } print k + 0 }' "$tmp/bars")"
    [ "$g" -ge 3 ] 2>/dev/null || no "wants its letters in at least 3 colours, each 255;80-220;60-80, got '$g'"
    [ "$(gitcalls)" = 1 ] || no "wants one git ls-remote inside 12 hours, got $(gitcalls)"
    begin "past 12 hours: the old file drawn, git read once more; upstream's main at the recorded commit: no mark"; printf 0 > "$tmp/stub/git.sleep"; printf '%s' "$B" > "$tmp/stub/git.head"; touch -t "$(stamp 46800)" "$up"
    draw; [ "$(first)" = "core ^" ] || no "wants the mark from the old file, printed '$(plain)'"
    waitfor "$B" || no "wants the file read again after 13 hours"
    [ "$(gitcalls)" = 2 ] || no "wants a second git ls-remote, got $(gitcalls)"
    draw; is "$L400"
  else no "wants the detached git ls-remote's answer in core-upstream.txt"; fi
  begin "an update (#516): the core changed since the file was read: no mark at once, read again, and still none when the core is the newest"
  printf 0 > "$tmp/stub/git.sleep"; printf '%s' "$B" > "$tmp/stub/git.head"; rm -f "$tmp/stub/git.log"; core_row; upstream "$A" 1111111; touch -t "$(stamp 3600)" "$up"
  draw; is "$L400"; waitfor "$B" || no "wants the file read again after the core changed"; [ "$(gitcalls)" = 1 ] || no "wants one git ls-remote after the change, got $(gitcalls)"
  [ "$(sed -n 2p "$up" | tr -d '\r\n')" = "$(printf '%s' "$B" | cut -c1-7)" ] || no "wants line 2 of the file to hold the recorded commit, got '$(sed -n 2p "$up")'"
  draw; is "$L400"; [ "$(gitcalls)" = 1 ] || no "wants no further read, got $(gitcalls)"
  begin "an update (#516): the core changed, upstream moved on meanwhile: the mark once the file is read against the new record"
  printf '%s' "$A" > "$tmp/stub/git.head"; upstream "$A" 1111111; touch -t "$(stamp 3600)" "$up"; draw; is "$L400"; waitfor "$A" || no "wants the file read again"; draw; [ "$(first)" = "core ^" ] || no "wants the mark for a core behind, printed '$(plain)'"
  begin "the same record, upstream equal: no mark, no read"; upstream "$B"; rm -f "$tmp/stub/git.log"; draw; is "$L400"; [ ! -s "$tmp/stub/git.log" ] || no "wants no git call, got $(gitcalls)"
  # #541: two projects on one machine, one config, on different cores; the file read once for each record, not again inside 12 hours
  H=ccccccc000000000000000000000000000000000; r0="$root"; mkdir -p "$other/coordinator"
  as() { root="$1"; fx "$C" "$M" high $W400; }
  line2() { local i=0; while [ $i -lt 20 ]; do [ "$(sed -n 2p "$up" | tr -d '\r')" = "$1" ] && return 0; sleep 1; i=$((i + 1)); done; return 1; }
  orow() { printf '| Core (CORE \302\2472) | a | b | 2026-11-04 | a local copy in `coordinator/core/` at claude-coordinator commit `%s`; local edits: none |\n' "$1" > "$other/coordinator/PROJECT.md"; }
  begin "two projects, different cores, both behind (#541): the other's first draw hides its mark and reads; then each shows its own"
  printf '%s' "$H" > "$tmp/stub/git.head"; rm -f "$tmp/stub/git.log"; orow aaaaaaa; upstream "$H"; touch -t "$(stamp 3600)" "$up"
  draw; [ "$(first)" = "core ^" ] || no "wants the mark in the first project, printed '$(plain)'"
  as "$other"; draw; is "$L400"; line2 aaaaaaa || no "wants the file read against the other project's record"; draw; [ "$(first)" = "core ^" ] || no "wants the mark in the other project, printed '$(plain)'"
  begin "two projects (#541): neither hides the other's mark, and no read again past 10 minutes"; touch -t "$(stamp 3600)" "$up"
  as "$r0"; draw; [ "$(first)" = "core ^" ] || no "wants the first project's mark after the other's read, printed '$(plain)'"
  as "$other"; draw; [ "$(first)" = "core ^" ] || no "wants the other project's mark, printed '$(plain)'"; [ "$(gitcalls)" = 1 ] || no "wants one git ls-remote for both, got $(gitcalls)"
  begin "two projects (#541): the other updated to main's head: no mark there, read again; the first keeps its mark"
  orow ccccccc; as "$other"; draw; is "$L400"; line2 ccccccc || no "wants the file read against the new record"; draw; is "$L400"
  as "$r0"; draw; [ "$(first)" = "core ^" ] || no "wants the first project's mark kept, printed '$(plain)'"; [ "$(gitcalls)" = 2 ] || no "wants two git ls-remote, got $(gitcalls)"
  upstream "$B"; rm -f "$tmp/stub/git.log"
  begin "the tag stable (#495): upstream holds it at the core's commit, main ahead: no mark, one ls-remote for both"; printf '%s' "$B" > "$tmp/stub/git.stable"; printf '%s' "$A" > "$tmp/stub/git.head"; rm -f "$up"; draw; waitfor "$B" || no "wants stable's commit in the file"
  draw; is "$L400"; [ "$(gitcalls)" = 1 ] || no "wants one git ls-remote, got $(gitcalls)"; grep -q 'refs/tags/stable' "$tmp/stub/git.log" || no "wants the tag asked, got '$(cat "$tmp/stub/git.log")'"
  begin "the tag stable behind main, the core at main's head: no mark (a core ahead of stable)"; printf '%s' "$A" > "$tmp/stub/git.stable"; printf '%s' "$B" > "$tmp/stub/git.head"; rm -f "$up"; draw; waitfor "$A" || no "wants stable's commit in the file"; draw; is "$L400"
  begin "the tag stable and main elsewhere, the core behind: the mark, against stable"; printf '%s' "$A" > "$tmp/stub/git.head"; rm -f "$up"; draw; waitfor "$A" || no "wants stable's commit in the file"; draw; [ "$(first)" = "core ^" ] || no "wants the mark against stable, printed '$(plain)'"
  begin "a project that asks for main (PROJECT.md row Core source): main, not the tag"; printf '| Core source (CORE \302\2472) | `main` | owner, 2026-11-06 | 2026-11-06 | stable, main |\n' >> "$root/coordinator/PROJECT.md"; printf '%s' "$B" > "$tmp/stub/git.head"; rm -f "$up" "$tmp/stub/git.log"; draw; waitfor "$B" || no "wants main's commit in the file"
  draw; is "$L400"; ! grep -q 'refs/tags/stable' "$tmp/stub/git.log" || no "wants only main asked, got '$(cat "$tmp/stub/git.log")'"; rm -f "$tmp/stub/git.stable"; core_row
  begin "the core mark with no PROJECT.md: nothing"; upstream "$A"; rm "$root/coordinator/PROJECT.md"; draw; is "$L400"; core_row
  begin "the wave: a task's fill has lighter cells, it and the core mark move with the clock"; agent w1 "#11 worker: x" working busy "$wt" 7 2026-11-04T11:00:00Z; draw
  u="$(awk -F'\t' '$2 ~ /^#11/ { print $6 }' "$tmp/bars")"; m="$(awk -F'\t' '$2 ~ /^core/ { print $5 }' "$tmp/bars")"
  if [ -n "$u" ] && [ -n "$m" ]; then
    [ "$(printf '%s' "$u" | tr ' ' '\n' | grep -v '^48;54;61$' | sort -u | grep -c .)" -ge 2 ] || no "wants at least 2 fill colours in the task's bar, got '$u'"
    sleep 6; draw
    [ "$(awk -F'\t' '$2 ~ /^#11/ { print $6 }' "$tmp/bars")" != "$u" ] || no "wants the task's fill changed after 6 s"
    [ "$(awk -F'\t' '$2 ~ /^core/ { print $5 }' "$tmp/bars")" != "$m" ] || no "wants the core mark's colours changed after 6 s"
  else no "wants a task bar and a core mark to read, printed '$(plain)'"; fi
  tasks_reset

  # The window mark (#499). The hook entry named in the project's settings; the record: <config>/coordinator/windows/<session id>.
  local HOOK='{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"bash /core/scripts/statusline.sh --session-start"}]}]}}'
  local WIN="$root/.claude/settings.local.json" R="$cfg/coordinator/windows/t1" LR="restart $dot $L400"
  upstream "$B"; rm -f "$root/.claude/settings.json" "$WIN"; rm -rf "$cfg/coordinator/windows"
  L6="$M high $dot 400k/600k 66%"
  begin "the mark: no record and no hook in the project: none, an older core's restart changes nothing"; fx "$C" "$M" high $W400; draw; is "$L400"
  begin "the mark: no record, the hook in the project: the session started before it, beside the number"; printf '%s' "$HOOK" > "$root/.claude/settings.json"; draw; is "$LR"
  bar "$M high . 400k/1M 40%" 34 "green:14 grey:20"; g="$(sed -n 1p "$tmp/bars" | cut -f2)"; [ "$g" = restart ] || no "wants the mark first, before the context bar, got '$g'"
  begin "the mark right after core ^ where that shows: restart second, the context bar third"; upstream "$A"; draw; g="$(cut -f2 "$tmp/bars" | head -n 3 | tr '\n' '|')"; [ "$g" = "core ^|restart|$M high . 400k/1M 40%|" ] || no "wants core ^, restart, the context bar, got '$g'"; upstream "$B"
  begin "the hook on a start: the window recorded, prints nothing, no status file; the same window: no mark"; printf '{"autoCompactWindow":600000}' > "$WIN"; rm -f "$cfg/coordinator/statusline.json"
  hk startup t1; [ "$rc" = 0 ] && [ ! -s "$tmp/out" ] || no "wants exit 0 and no output, got $rc '$(cat "$tmp/out")'"; [ "$(tr -d '\r\n' < "$R" 2>/dev/null)" = 600000 ] || no "wants 600000 recorded, got '$(cat "$R" 2>/dev/null)'"
  [ ! -f "$cfg/coordinator/statusline.json" ] || no "wants no statusline.json from the hook"; draw; is "$L6"
  begin "the file edited: the bar shows the file's number, the mark says restart"; printf '{"autoCompactWindow":800000}' > "$WIN"; draw; is "restart $dot $M high $dot 400k/800k 50%"
  begin "a compaction and /clear do not record: the mark stays, /clear's new id has no record"; hk compact t1; hk clear t1; draw; is "restart $dot $M high $dot 400k/800k 50%"; hk clear t2; [ ! -f "$cfg/coordinator/windows/t2" ] || no "wants no record on /clear"
  begin "a resume records: the mark goes"; hk resume t1; [ "$(tr -d '\r\n' < "$R" 2>/dev/null)" = 800000 ] || no "wants 800000 recorded on a resume, got '$(cat "$R" 2>/dev/null)'"; draw; is "$M high $dot 400k/800k 50%"
  begin "the window removed from the file, then none at the start and one added: the mark"; rm "$WIN"; draw; is "$LR"; hk startup t1; [ ! -s "$R" ] || no "wants an empty record with no window set"; draw; is "$L400"; printf '{"autoCompactWindow":800000}' > "$WIN"; draw; is "restart $dot $M high $dot 400k/800k 50%"
  begin "past 100% with the record equal: the mark; not a coordinator: none, with a differing record too"; printf '{"autoCompactWindow":300000}' > "$WIN"; hk startup t1; draw; is "restart $dot $M high $dot 400k/300k 133%"; fx "#11 worker: x" "$M" high $W400; draw; is "$M high $dot 400k/300k 133%"; printf 1 > "$R"; draw; is "$M high $dot 400k/300k 133%"
  begin "before the first response: the mark beside the model"; printf '{"session_id":"t1","session_name":"%s","workspace":{"project_dir":"%s"},"model":{"display_name":"%s"},"effort":{"level":"high"}}\n' "$C" "$(jp "$root")" "$M" > "$tmp/in.json"; draw; is "restart $dot $M high"
  begin "the hook's root: CLAUDE_PROJECT_DIR over a cwd in a subfolder; a session id that is no plain name writes nothing"; printf '{"autoCompactWindow":700000}' > "$WIN"; mkdir -p "$root/sub"; printf '{"session_id":"t3","cwd":"%s","source":"startup"}\n' "$(jp "$root/sub")" > "$tmp/hook.json"; CLAUDE_PROJECT_DIR="$(nat "$root")" hkrun; [ "$(tr -d '\r\n' < "$cfg/coordinator/windows/t3" 2>/dev/null)" = 700000 ] || no "wants 700000 recorded from the project's settings, got '$(cat "$cfg/coordinator/windows/t3" 2>/dev/null)'"; hk startup '../../evil'; [ ! -e "$cfg/evil" ] && [ ! -e "$cfg/coordinator/evil" ] || no "wants nothing written outside the folder"
  begin "the hook removes a record older than 30 days, keeps a newer one"; printf x > "$cfg/coordinator/windows/old"; touch -t "$(stamp 2678400)" "$cfg/coordinator/windows/old"; hk startup t1; [ ! -e "$cfg/coordinator/windows/old" ] || no "wants the old record gone"; [ -e "$cfg/coordinator/windows/t3" ] || no "wants a newer record kept"
  rm -f "$root/.claude/settings.json" "$WIN"

  fx x "$M" high $W400 ",\"rate_limits\":{\"five_hour\":{\"used_percentage\":14},$(wk 30 502)}"
  for t in "140|1 1 1 " "66|1 1 2 " "40|1 2 3 " "|1 1 1 "; do
    begin "the width '${t%%|*}': whole bars, on lines ${t#*|}"
    if [ -n "${t%%|*}" ]; then COLUMNS="${t%%|*}" draw; else draw; fi
    lines "${t#*|}"; bar "$M high . 400k/1M 40%" 34 "green:14 grey:20"; bar "5h limit 14%" 14 "green:2 grey:12"; bar "week 30% . reset 50%" 26 "green:8 blue:5 grey:13"
  done
}
if [ "$line" = yes ]; then bar_cases; else echo "skip the bars: no jq here (the .sh needs it for its line)"; fi

begin "refreshInterval 5 on TOOLKIT's statusLine, no other"; grep -q '"statusLine".*"refreshInterval": 5}' "$core/TOOLKIT.md" || no "wants '\"refreshInterval\": 5' on the statusLine lines in TOOLKIT.md"
! grep '"statusLine"' "$core/TOOLKIT.md" | grep -q '"refreshInterval": 10' || no "wants no \"refreshInterval\": 10 on a statusLine line in TOOLKIT.md"

# the install's version rule: a copy in <config>/coordinator/statusline/ is replaced only by a newer script
i="$tmp/inst"; if [ "$kind" = ps ]; then f=statusline.ps1; else f=statusline.sh; fi; src="$core/scripts/$f"; to="$i/coordinator/statusline/$f"
inst() { if [ "$kind" = ps ]; then CLAUDE_CONFIG_DIR="$(winpath "$i")" "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$(winpath "$src")" -Install; else CLAUDE_CONFIG_DIR="$i" bash "$src" --install; fi < /dev/null > /dev/null 2> "$tmp/err"; }
begin "the install: none there: copied; a newer copy stays; an older one replaced; the copy draws by itself"
v="$(tr -d '\r' < "$src" | sed -n 's/^# statusline-version: \([0-9][0-9]*\)$/\1/p' | head -n 1)"
if [ -z "$v" ]; then no "wants a line '# statusline-version: <whole number>' in scripts/$f"
else
  inst; cmp -s "$src" "$to" || no "wants $f copied whole to <config>/coordinator/statusline/"
  printf '# statusline-version: %s\nnewer\n' "$((v + 1))" > "$to"; cp "$to" "$tmp/newer"; inst; cmp -s "$tmp/newer" "$to" || no "wants a newer copy kept byte for byte"
  printf '# statusline-version: %s\nolder\n' "$((v - 1))" > "$to"; inst; cmp -s "$src" "$to" || no "wants an older copy replaced by the script"
  in="$fixture"; script="$i/coordinator/statusline/statusline"; run "$tmp/copy"; [ "$line" = no ] || is "$want"; [ -f "$tmp/copy/coordinator/statusline.json" ] || no "wants the copy to save statusline.json"; script="$core/scripts/statusline"
fi
finish
[ "$fail" = 0 ] && echo "statusline: $n cases passed" || echo "statusline: failures above ($n cases)"
exit "$fail"
