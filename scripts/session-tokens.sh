#!/usr/bin/env bash
# Tokens a Claude Code session used (macOS / Linux, needs jq).
#   scripts/session-tokens.sh <session-id | transcript.jsonl>
# Prints lines for RUNS.tsv (CORE §7), from two sources when both exist:
#   status      <in+out>  in=<n> out=<n> cost=$<usd>   — the CLI's own totals, from the status line's
#               per-session file ~/.claude/coordinator/sessions/<id>.json (TOOLKIT *Usage*); preferred
#   transcript  <total>   in=<n> out>=<n> cache_read=<n> cache_write=<n>   — summed from the session's
#               transcript and its subagents; input and cache counts are exact, output is a LOWER
#               BOUND (the transcript stores the output count from before a message finished)
set -euo pipefail
arg="${1:?usage: session-tokens.sh <session-id | transcript.jsonl>}"
if [ -f "$arg" ]; then main="$arg"; else
  main="$(find "$HOME/.claude/projects" -maxdepth 2 -name "$arg.jsonl" 2>/dev/null | head -n 1)"
fi
sid="$(basename "${main:-$arg}" .jsonl)"
status="$HOME/.claude/coordinator/sessions/$sid.json"
if [ -f "$status" ]; then
  jq -r '"status\t\((.context_window.total_input_tokens // 0) + (.context_window.total_output_tokens // 0))\tin=\(.context_window.total_input_tokens // "?") out=\(.context_window.total_output_tokens // "?") cost=$\(.cost.total_cost_usd // "?")"' "$status"
fi
if [ -n "${main:-}" ] && [ -f "$main" ]; then
  files=("$main")
  sub="${main%.jsonl}/subagents"
  [ -d "$sub" ] && for f in "$sub"/*.jsonl; do [ -f "$f" ] && files+=("$f"); done
  cat "${files[@]}" | jq -rs '
    map(select(.type == "assistant" and .message.usage != null))
    | group_by(.message.id) | map(map(.message.usage) | max_by(.output_tokens // 0))
    | { i: (map(.input_tokens // 0) | add // 0), o: (map(.output_tokens // 0) | add // 0),
        r: (map(.cache_read_input_tokens // 0) | add // 0), w: (map(.cache_creation_input_tokens // 0) | add // 0) }
    | "transcript\t\(.i + .o + .r + .w)\tin=\(.i) out>=\(.o) cache_read=\(.r) cache_write=\(.w)"'
elif [ ! -f "$status" ]; then
  echo "no transcript or status file for $arg" >&2; exit 1
fi
