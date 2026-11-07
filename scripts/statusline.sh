#!/usr/bin/env bash
# Status line for coordinator machines (macOS / Linux; Windows: statusline.ps1). Prints bars with their text inside
#   Opus 5.5 high · 837k/1M 83% · 5h limit 14% · week 92% · reset 50% · #449 W 7/12$
# - model effort, context used against the threshold set · 5-hour and weekly limits (claude.ai Pro / Max only); in a
# coordinator's session also a newer core and the tasks at work - and saves Claude Code's status JSON to
# ~/.claude/coordinator/statusline.json for the coordinator.
#   statusline.sh --install    copies this script to <config>/coordinator/statusline/, unless the same or a newer version is there
#   statusline.sh --session-start    a coordinator's SessionStart hook: records the window this session starts with (TOOLKIT *Usage*)
# statusline-version: 6
script_version() { tr -d '\r' 2>/dev/null < "$1" | sed -n 's/^# statusline-version: \([0-9][0-9]*\)$/\1/p' | head -n 1; }
if [ "${1:-}" = --install ]; then
  to="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/coordinator/statusline"; copy="$to/$(basename "$0")"; have="$(script_version "$copy")"
  if [ -z "$have" ] || [ "$have" -lt "$(script_version "$0")" ]; then
    mkdir -p "$to" && cp "$0" "$copy.$$" && mv -f "$copy.$$" "$copy"   # a running bash reads its script as it goes: never overwritten in place
  fi
  exit 0
fi
input="$(cat)"
case "$input" in '{'*) ;; *'{'*) input="{${input#*\{}" ;; esac   # a BOM before the JSON breaks it
dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/coordinator"
# Each file is written to a temp file and renamed over (mv in one folder tree: atomic), so a reader -
# or another status line drawn at the same moment - never sees half a file or an empty one; the temp
# file is removed whatever happened (one left by a kill mid-write is deleted by session-tokens --prune
# after an hour).
tmp="$dir/statusline.$$.tmp"
save() { printf '%s' "$input" > "$tmp" && mv -f "$tmp" "$1" 2>/dev/null; rm -f "$tmp"; }
sid="$(printf '%s' "$input" | sed -n 's/.*"session_id" *: *"\([^"]*\)".*/\1/p' | head -n 1)"
if [ "${1:-}" != --session-start ]; then
  mkdir -p "$dir" 2>/dev/null && save "$dir/statusline.json"
  # A copy per session, so the coordinator reads each worker's own numbers (the file above is the last
  # session to draw its status line, whichever that was).
  [ -n "$sid" ] && mkdir -p "$dir/sessions" 2>/dev/null && save "$dir/sessions/$sid.json"
  command -v jq >/dev/null 2>&1 || { echo "Claude · install jq for the full status line"; exit 0; }
else
  command -v jq >/dev/null 2>&1 || exit 0
fi

# The core's public home (the same value as README, procedures/CORE-FINDINGS.md): this copy lives outside any repository.
core_url=https://github.com/Arziburst/claude-coordinator
tab="$(printf '\t')"
{ read -r name; read -r root; read -r src; } <<LINES
$(printf '%s' "$input" | jq -r '(.session_name // ""), (.workspace.project_dir // .cwd // ""), (.source // "")' 2>/dev/null)
LINES
[ "${1:-}" != --session-start ] || root="${CLAUDE_PROJECT_DIR:-$root}"

# The threshold actually set: local project settings, project settings, the account's; else the model's window.
limit=""
for f in "$root/.claude/settings.local.json" "$root/.claude/settings.json" "${dir%/*}/settings.json"; do
  [ -f "$f" ] || continue
  limit="$(jq -r '.autoCompactWindow | select(type == "number" and . > 0)' "$f" 2>/dev/null)"
  [ -z "$limit" ] || break
done

# A session keeps the window it started with (measured, #499): a process's start reads the file, a start and a resume;
# an edit, /clear and a compaction do not. So only those two write the record, and /clear, which changes the id, leaves none.
windows="$dir/windows"
if [ "${1:-}" = --session-start ]; then
  case "$sid" in *[!0-9a-zA-Z-]*|'') exit 0 ;; esac
  case "$src" in startup|resume)
    mkdir -p "$windows" 2>/dev/null && printf '%s' "$limit" > "$windows/$sid.$$" && mv -f "$windows/$sid.$$" "$windows/$sid"
    rm -f "$windows/$sid.$$"
    find "$windows" -maxdepth 1 -type f -mtime +30 -delete 2>/dev/null ;;
  esac
  exit 0
fi
# Does this session need a restart for the window? The record differs from the file; or none is there and the project has
# the hook: the session started before it. No hook in the project: an older core, a restart would change nothing.
window_stale() {
  if [ -f "$windows/$sid" ]; then [ "$(cat "$windows/$sid" 2>/dev/null)" != "$limit" ]
  else cat "$root/.claude/settings.local.json" "$root/.claude/settings.json" 2>/dev/null | grep -Eq 'statusline\.(sh|ps1).*(--session-start|-SessionStart)'; fi
}

# A newer core: upstream's tag stable, else main, read at most once in 12 hours by a detached git ls-remote into a file (the status line
# itself never waits for the network), against the commit PROJECT.md records. Line 2 of the file: the record it was read
# against; line 4: earlier reads' records, any project's on this machine (#541). A record in neither (an update) hides the
# mark and the file is read again, at most every 10 minutes (#516).
core_behind() {
  local file="$dir/core-upstream.txt" sha rec had seen= keep refs
  rec="$(sed -n 's/^| Core (CORE .*commit `\([0-9a-f]\{7,40\}\)`.*/\1/p' "$root/coordinator/PROJECT.md" 2>/dev/null | head -n 1)"
  had="$(sed -n '2p;4p' "$file" 2>/dev/null | tr -d '\r' | tr '\n' ' ')"
  case " $had " in *" $rec "*) seen=1 ;; esac
  keep="$(printf '%s\n' $had | grep -vx "$rec" | head -n 8 | tr '\n' ' ')"   # line 4 of the next read
  if [ ! -f "$file" ] || [ -z "$(find "$file" -mmin -720 2>/dev/null)" ] || { [ -z "$seen" ] && [ -z "$(find "$file" -mmin -10 2>/dev/null)" ]; }; then
    touch "$file"   # one reader at a time
    refs="refs/heads/main refs/tags/stable"   # the tag stable when upstream has it, else main; a project's row Core source `main`: main (#495)
    ! grep -q '^| Core source[^|]*| `main` |' "$root/coordinator/PROJECT.md" 2>/dev/null || refs=refs/heads/main
    ( r="$(git ls-remote "$core_url" $refs 2>/dev/null)"; m="$(printf '%s\n' "$r" | grep 'refs/heads/main$')"; r="$(printf '%s\n' "$r" | grep 'refs/tags/stable$' || printf '%s' "$m")"
      [ -z "$r" ] || printf '%s\n%s\n%s\n%s' "$r" "$rec" "$m" "$keep" > "$file" ) </dev/null >/dev/null 2>&1 &   # line 3: main's, a core at its head is not behind
  fi
  [ -n "$seen" ] || return 1
  sha="$(head -n 1 "$file" 2>/dev/null | cut -c1-40)"
  case "$sha" in *[!0-9a-f]*|'') return 1 ;; esac
  [ "${#sha}" = 40 ] || return 1
  [ -n "$rec" ] || return 1
  case "$sha" in "$rec"*) return 1 ;; esac
  case "$(sed -n 3p "$file" 2>/dev/null | cut -c1-40)" in "$rec"*) return 1 ;; esac
  return 0
}

# The tasks at work, as JSON for the bars: only this project's folder, only tasks with a session at work now.
# Spent = the task's rows of RUNS.tsv + what its live sessions spent, idle ones too. A live session and its finished row
# count once, the live value: a row is that session's when its start cell equals the transcript's first timestamp (`runs check`).
agents_prog='($root | gsub("\\\\"; "/") | rtrimstr("/")) as $b
  | sort_by(.startedAt // 0)[]
  | ((.cwd // "") | gsub("\\\\"; "/") | rtrimstr("/")) as $c | select($c == $b or ($c | startswith($b + "/")))
  | ((.name // "") | capture("^#(?<n>[0-9]+)(?<s>\\.[0-9]+)?\\s+(?<r>\\w+):")) as $m
  | [$m.n, $m.r, (if .state == "working" or .state == "blocked" then "1" else "0" end), (if .status then "1" else "0" end), (.sessionId // "-"), (if $m.s then "1" else "0" end)] | @tsv'
tasks_prog='($items | split("\n") | map(select(. != "") | split("\t"))) as $a
  | (split("\n") | map(rtrimstr("\r"))) as $rows
  | (($rows[0] // "") | split("\t")) as $h | ($h | index("cost")) as $ci | ($h | index("task")) as $ti | ($h | index("role")) as $ri | ($h | index("start")) as $si
  | {tester: "T", worker: "W", verifier: "V", lead: "L", researcher: "R"} as $letters
  | reduce $a[] as $r ({}; .[$r[0]] = ((.[$r[0]] // {n: ($r[0] | tonumber), spent: 0, stage: "?", lead: false, working: false, live: {}, budget: 0})
      | (if .budget > 0 then . else .budget = (($r[6] | tonumber?) // 0) end)
      | .spent += (($r[4] | tonumber?) // 0)
      | if $r[5] != "" then .live[$r[5]] = true else . end
      | if $r[1] == "lead" then .lead = true else . end
      | if $r[2] == "1" then .working = true | .stage = ($letters[$r[1]] // ($r[1][0:1] | ascii_upcase)) else . end))
  | with_entries(select(.value.working))
  | if $ci == null or $ti == null or $ri == null then . else
      reduce ($rows[1:][] | split("\t")) as $c (.;
        ((($c[$ti] // "") | split("."))[0] // "") as $n
        | if .[$n] == null or ($c | length) <= $ci or $c[$ri] == "task" or ($si != null and (.[$n].live[$c[$si] // ""] // false)) then .
          else .[$n].spent += (($c[$ci] | capture("^(?<v>[0-9.]+)").v | tonumber?) // 0) end) end
  | [.[]] | sort_by(.n)'
task_json() {
  local list items="" n role work live id sub cost tp start budget state="$root/coordinator"
  list="$(claude agents --json 2>/dev/null | jq -r --arg root "$root" "$agents_prog" 2>/dev/null)"
  [ -n "$list" ] || return
  while IFS="$tab" read -r n role work live id sub; do
    cost=0; start=""
    if [ "$live" = 1 ] && [ -f "$dir/sessions/$id.json" ]; then
      { read -r cost; read -r tp; } <<LINES
$(jq -r '(.cost.total_cost_usd // 0), (.transcript_path // "")' "$dir/sessions/$id.json" 2>/dev/null)
LINES
      [ ! -f "$tp" ] || start="$(LC_ALL=C grep -a -m 1 -o '"timestamp": *"[0-9T:-]*' "$tp" 2>/dev/null | head -n 1 | sed 's/.*"//' | cut -c1-19)"
      [ -z "$start" ] || start="${start}Z"
    fi
    budget="$(sed -n 's/^[[:space:]]\{1,\}cost:[[:space:]]*\([0-9.]\{1,\}\).*/\1/p' "$state/briefs/$n-contract.md" 2>/dev/null | head -n 1)"
    # else what the session was started with, its kept brief: the first `cost:` under a `budget:` line; a lead's #<task>.<n> session has its own (#505)
    [ -n "$budget" ] || [ "$sub" = 1 ] || budget="$(awk '/^[ \t]*budget:/ { on = 1; next } on && /^[ \t]+cost:/ { if (match($0, /[0-9.]+/)) print substr($0, RSTART, RLENGTH); exit } on && /^[^ \t\r]/ { on = 0 }' "$dir/briefs/$id.md" 2>/dev/null)"
    items="$items$n$tab$role$tab$work$tab$live$tab$cost$tab$start$tab$budget
"
  done <<LINES
$list
LINES
  cat "$state/RUNS.tsv" 2>/dev/null | jq -Rsc --arg items "$items" "$tasks_prog" 2>/dev/null
}

behind=0; tasks='[]'; restart=""
case "$name" in *Coordinator*)
  if [ -n "$root" ]; then
    if core_behind; then behind=1; fi
    if window_stale; then restart=1; else restart=0; fi
    tasks="$(task_json)"; [ -n "$tasks" ] || tasks='[]'
  fi ;;
esac

line_prog='
  def rnd: (. + 0.5) | floor;
  def mag: if . < 0 then -. else . end;
  def fm($m): . - $m * ((. / $m) | floor);
  def tok: if . >= 1000000 then "\((. / 100000 | floor) / 10)M" elif . >= 1000 then "\(. / 1000 | floor)k" else "\(floor)" end;
  def spaces($n): [range(0; $n) | " "] | join("");
  def cells($t; $w): (($w - ($t | length)) | if . < 0 then 0 else . end) as $p | spaces($p / 2 | floor) + $t + spaces($p / 2 | ceil);
  def base($c): {green: "63;185;80", yellow: "227;179;65", red: "248;81;73"}[$c] // "88;166;255";
  def on($c): "\u001b[48;2;\(base($c))m\u001b[38;2;13;17;23m";
  def off: "\u001b[48;2;48;54;61m\u001b[38;2;201;209;217m";
  def at($l; $pct): [($l | length), (($l | length) * $pct / 100 | rnd)] | min;
  def bar($t; $pct; $w; $c): cells($t; $w) as $l | at($l; $pct) as $f | on($c) + $l[0:$f] + off + $l[$f:] + "\u001b[0m";
  def level: if . < 70 then "green" elif . < 90 then "yellow" else "red" end;
  # The week gone is always blue; the limit is green when it is behind or level with the time, and past the time its excess is yellow, or red over 10 points.
  def weekbar($t; $u; $g; $width): cells($t; $width) as $l | at($l; ([$u, $g] | min)) as $a | at($l; ([$u, $g] | max)) as $b
    | (if $u <= $g then on("green") + $l[0:$a] + on("blue") else on("blue") + $l[0:$a] + (if $u <= $g + 10 then on("yellow") else on("red") end) end) + $l[$a:$b] + off + $l[$b:] + "\u001b[0m";
  # Each letter its own colour, red through orange to yellow, the wave moving with the clock at every refresh.
  def gradient($t): (($now / 5 | fm(8)) / 8) as $s | ($t | length) as $n
    | ([range(0; $n) | . as $k | ((($k / $n + $s) | fm(1)) * 2 - 1 | mag | 1 - .) as $v
        | "\u001b[1;38;2;255;\(80 + 140 * $v | rnd);\(80 - 20 * $v | rnd)m\($t[$k:$k + 1])"] | join("")) + "\u001b[0m";
  # Beside the number: the window in force is not the one shown. Past 100% is itself a sign: a compaction comes before it, or one large turn after.
  def restartmark($over): if $restart == "1" or ($restart != "" and $over) then gradient("restart") else empty end;
  # A working task: a soft lighter wave moves through the fill at every redraw, in the colour its budget has now.
  def wave($t; $pct; $width; $c): cells($t; $width) as $l | at($l; $pct) as $f | (base($c) | split(";") | map(tonumber)) as $b
    | ([range(0; $l | length) | . as $k
        | if $k < $f then (($k - $now / 2) | fm($f) / $f * 2 - 1 | mag | 1 - .) as $v | ($v * $v) as $w
            | "\u001b[48;2;\([$b[] | (. + (255 - .) * 0.45 * $w | rnd)] | map(tostring) | join(";"))m\u001b[38;2;13;17;23m\($l[$k:$k + 1])"
          else off + $l[$k:$k + 1] end] | join("")) + "\u001b[0m";
  def taskbar: (if .lead then "L" else .stage end) as $st | (.spent | rnd) as $sp
    | if .budget > 0 then (.spent * 100 / .budget) as $p | ($p | rnd) as $whole
        | wave("#\(.n) \($st) \($sp)/\(.budget)$"; $p; 17; (if $whole < 80 then "green" elif $whole <= 100 then "yellow" else "red" end))
      else bar("#\(.n) \($st) \($sp)$"; 100; 17; "neutral") end;
  ((.model.display_name // "Claude") + (if .effort.level then " \(.effort.level)" else "" end)) as $model
  | (.context_window | if type == "object" and .used_percentage != null then
       ((.current_usage.input_tokens // 0) + (.current_usage.cache_read_input_tokens // 0) + (.current_usage.cache_creation_input_tokens // 0)) as $u
       | $lim != "" and $u > ($lim | tonumber) else false end) as $over
  | [ (if $behind == "1" then gradient("core ↑") else empty end),
      restartmark($over),
      (.context_window | if type == "object" and .used_percentage != null then
         ((.current_usage.input_tokens // 0) + (.current_usage.cache_read_input_tokens // 0) + (.current_usage.cache_creation_input_tokens // 0)) as $u
         | (if $lim != "" then ($lim | tonumber) else (.context_window_size // 0) end) as $t
         | (if $t > 0 then $u * 100 / $t else 0 end) as $p
         | bar("\($model) · \($u | tok)/\($t | tok) \($p | floor)%"; $p; 34; ($p | level))
       else $model end),
      (.rate_limits.five_hour | if type == "object" and .used_percentage != null then bar("5h limit \(.used_percentage | floor)%"; .used_percentage; 14; (.used_percentage | level)) else empty end),
      (.rate_limits.seven_day | if type == "object" and .used_percentage != null then .used_percentage as $w
         | if (.resets_at | type) == "number" then ((100 - (.resets_at - $now) * 100 / 604800) | if . < 0 then 0 elif . > 100 then 100 else . end) as $g
             | weekbar("week \($w | floor)% · reset \($g | rnd)%"; $w; $g; 26)
           else bar("week \($w | floor)%"; $w; 16; ($w | level)) end
       else empty end),
      ($tasks[] | taskbar) ]
  # One line while it fits; past the width a whole bar moves to the next line, never cut. Claude Code sets COLUMNS for a status line; 4 for its own margins.
  | ($cols | tonumber? // 0) as $c | (if $c > 4 then $c - 4 else 1e18 end) as $room
  | reduce .[] as $p ({lines: [], line: "", used: 0};
      ($p | gsub("\u001b\\[[0-9;]*m"; "") | length) as $w
      | if .used > 0 and .used + 3 + $w > $room then .lines += [.line] | .line = "" | .used = 0 else . end
      | if .used > 0 then .line += " · " | .used += 3 else . end
      | .line += $p | .used += $w)
  | (.lines + [.line])[]'
printf '%s' "$input" | jq -r --arg lim "$limit" --argjson now "$(date +%s)" --arg behind "$behind" --arg restart "$restart" --arg cols "${COLUMNS:-}" --argjson tasks "$tasks" "$line_prog" 2>/dev/null || echo "Claude"
