#!/usr/bin/env bash
# Claude Code's internal formats against the fields the core reads (#559; macOS / Linux; Windows: cc-formats.ps1 - the same
# line and codes, the table below read from this file): a moved or renamed field is a FAIL naming it and its readers.
#   scripts/cc-formats.sh [--if-changed] [--transcript <file.jsonl>] [--payload <file.json>]
# Reads `claude agents --json --all` (5 s at most), the last 2000 lines of the newest transcript <config>/projects/*/*.jsonl
# holding an assistant message (or --transcript), and a recorded payload: <config>/coordinator/statusline.json, the status
# line's input as Claude Code last drew it, with the hooks' common fields (or --payload: a hook's recorded input).
# <config>: CLAUDE_CONFIG_DIR, else ~/.claude. Writes only in its scratch folder <config>/coordinator/cc-formats/: the
# listing, and `version` - `claude --version` at the last PASS. --if-changed: nothing at all (exit 0) when that version is
# today's or claude answers no version; else the probe. One line: `cc-formats: PASS claude <version>, <n> fields` or
# `cc-formats: FAIL claude <version>: <format> <field> (read by <scripts>); ...` - a field missing, or an input unread.
# No status line here (that file absent, no --payload): first `cc-formats: SKIP payload: ...`; the rest decides.
# Exit 0 PASS, 1 FAIL (the version stays unrecorded: the next run probes again), 2 usage.
# The table: `#F <format> <field> <when> <pattern> <readers>`. <when> and <pattern> are extended regular expressions on the
# input's text after `"<key>" : ` is written `"<key>":` and `, "` as `,"` (- in <when>: always); a row is checked only when
# its input matches <when>. agents: the listing (rows checked when it lists a session); transcript; payload.
#F agents id [{] "id":" runs,watch-sessions,cleanup-worker,start-worker,hooks/safety-guard,hooks/before-compact
#F agents sessionId [{] "sessionId":" runs,watch-sessions,cleanup-worker,start-worker,hooks/safety-guard,statusline
#F agents cwd [{] "cwd":" runs,watch-sessions,cleanup-worker,hooks/before-compact,hooks/safety-guard,statusline
#F agents name [{] "name":" runs,watch-sessions,cleanup-worker,start-worker,hooks/safety-guard,hooks/before-compact,statusline
#F agents state [{] "state":" runs,watch-sessions,start-worker,hooks/before-compact,statusline
#F agents startedAt [{] "startedAt": statusline
#F agents status "pid":[0-9] "status":" statusline
#F transcript type - "type":"assistant" session-tokens,session-insights
#F transcript timestamp - "timestamp":" session-tokens,session-insights
#F transcript cwd - "cwd":" session-insights
#F transcript message - "message":[{] session-tokens,session-insights
#F transcript message.id - "id":"msg_ session-tokens,session-insights
#F transcript model - "model":" session-tokens,session-insights
#F transcript usage - "usage":[{] session-tokens,session-insights
#F transcript input_tokens - "input_tokens":[0-9] session-tokens,session-insights
#F transcript output_tokens - "output_tokens":[0-9] session-tokens,session-insights
#F transcript cache_read_input_tokens - "cache_read_input_tokens":[0-9] session-tokens,session-insights
#F transcript cache_creation_input_tokens - "cache_creation_input_tokens":[0-9] session-tokens,session-insights
#F transcript stop_reason - "stop_reason": session-insights
#F transcript turnOrigin "type":"user" "turnOrigin":" session-insights
#F transcript tool_use.id "tool_use" "type":"tool_use","id":" session-tokens,session-insights
#F transcript tool_use_id "tool_result" "tool_use_id":" session-tokens,session-insights
#F payload session_id - "session_id":" statusline,hooks/before-compact,hooks/after-compact
#F payload cwd - "cwd":" statusline,hooks/safety-guard,hooks/before-compact,hooks/after-compact
#F payload transcript_path - "transcript_path":" statusline
#F payload workspace.project_dir "workspace":[{] "project_dir":" statusline
#F payload model.display_name "workspace":[{] "display_name":" statusline
#F payload cost.total_cost_usd "workspace":[{] "total_cost_usd":[0-9] statusline,session-tokens
#F payload context_window.context_window_size "workspace":[{] "context_window_size":[0-9] statusline
#F payload effort.level "effort":[{] "effort":[{][^}]*"level":" statusline
#F payload context_window.used_percentage "current_usage":[{] "context_window":[{]([^{}]|[{][^{}]*[}])*"used_percentage":[0-9] statusline
#F payload context_window.current_usage.input_tokens "context_window":[{]([^{}]|[{][^{}]*[}])*"used_percentage":[0-9] "current_usage":[{][^}]*"input_tokens":[0-9] statusline
#F payload context_window.current_usage.cache_read_input_tokens "context_window":[{]([^{}]|[{][^{}]*[}])*"used_percentage":[0-9] "current_usage":[{][^}]*"cache_read_input_tokens":[0-9] statusline
#F payload context_window.current_usage.cache_creation_input_tokens "context_window":[{]([^{}]|[{][^{}]*[}])*"used_percentage":[0-9] "current_usage":[{][^}]*"cache_creation_input_tokens":[0-9] statusline
#F payload rate_limits.five_hour.used_percentage "five_hour":[{] "five_hour":[{][^}]*"used_percentage":[0-9] statusline
#F payload rate_limits.seven_day.used_percentage "rate_limits":[{] "seven_day":[{][^}]*"used_percentage":[0-9] statusline
#F payload rate_limits.seven_day.resets_at "rate_limits":[{] "seven_day":[{][^}]*"resets_at":[0-9] statusline
#F payload source "hook_event_name":"SessionStart" "source":" statusline
#F payload tool_input.command "tool_name":"Bash" "tool_input":[{][^}]*"command":" hooks/safety-guard
set -u
usage() { sed -n '2,13s/^# \{0,1\}//p' "$0" >&2; exit 2; }
ifc=""; tr=""; pl=""
while [ $# -gt 0 ]; do case "$1" in
  --if-changed) ifc=1 ;; --transcript) [ $# -ge 2 ] || usage; tr="$2"; shift ;; --payload) [ $# -ge 2 ] || usage; pl="$2"; shift ;;
  *) usage ;; esac; shift; done
cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; sd="$cfg/coordinator/cc-formats"
ver="$(claude --version 2>/dev/null </dev/null | head -n 1 | sed 's/ .*//')" || ver=""
if [ -n "$ifc" ]; then [ -n "$ver" ] || exit 0; [ "$(cat "$sd/version" 2>/dev/null)" != "$ver" ] || exit 0; fi
mkdir -p "$sd" || { echo "cc-formats: FAIL claude ${ver:-?}: cannot create $sd"; exit 1; }
bad=""; n=0
# the listing, 5 s at most (past that its whole process group is killed: set -m gives it one of its own)
set -m; claude agents --json --all > "$sd/agents.json" 2>/dev/null </dev/null & pid=$!; set +m
t0=$SECONDS; while kill -0 "$pid" 2>/dev/null && [ $((SECONDS - t0)) -lt 5 ]; do sleep 0.1; done   # by the clock: a slow machine's loop is slower
if kill -0 "$pid" 2>/dev/null; then { kill -- "-$pid" || kill "$pid"; wait "$pid"; } 2>/dev/null; bad="$bad; agents: claude agents --json --all did not answer in 5 s"
elif ! wait "$pid" || ! tr -d ' \t\r\n' < "$sd/agents.json" | grep -q '^\[.*\]$'; then bad="$bad; agents: claude agents --json --all printed no JSON list"; fi
if [ -z "$tr" ]; then
  for f in $(ls -t "$cfg"/projects/*/*.jsonl 2>/dev/null | head -n 50); do
    tail -n 2000 "$f" | grep -q '"role": *"assistant"' && { tr="$f"; break; }
  done
  [ -n "$tr" ] || bad="$bad; transcript: none under $cfg/projects holds an assistant message"
fi
fms="agents transcript payload"   # no status line here (its file absent, no --payload): the payload part one SKIP line
if [ -z "$pl" ] && [ ! -e "$cfg/coordinator/statusline.json" ]; then fms="agents transcript"
  echo "cc-formats: SKIP payload: no status line here ($cfg/coordinator/statusline.json absent)"; else pl="${pl:-$cfg/coordinator/statusline.json}"; fi
[ -z "$tr" ] || [ -r "$tr" ] || bad="$bad; transcript: cannot read $tr"
[ "$fms" = "agents transcript" ] || [ -r "$pl" ] || bad="$bad; payload: cannot read $pl"
# text <format>: the input, `": ` and `, "` closed up
text() { case "$1" in agents) cat "$sd/agents.json" ;; transcript) [ -z "$tr" ] || tail -n 2000 "$tr" ;; payload) cat "$pl" ;; esac 2>/dev/null |
  sed -E 's/"[[:space:]]*:[[:space:]]*/":/g; s/,[[:space:]]*"/,"/g'; }
for fm in $fms; do
  case "$bad" in *"; $fm: "*) continue ;; esac
  t="$(text "$fm")"
  while read -r _ f fld when pat who; do
    [ "$f" = "$fm" ] || continue
    [ "$when" = - ] || printf '%s\n' "$t" | grep -Eq -- "$when" || continue
    n=$((n + 1)); printf '%s\n' "$t" | grep -Eq -- "$pat" || bad="$bad; $fm $fld (read by ${who//,/, })"
  done < <(grep '^#F ' "$0")
done
if [ -n "$bad" ]; then echo "cc-formats: FAIL claude ${ver:-?}: ${bad#; }"; exit 1; fi
[ -z "$ver" ] || printf '%s\n' "$ver" > "$sd/version"
echo "cc-formats: PASS claude ${ver:-?}, $n fields"
